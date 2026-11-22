// h2s-helper: one program, subcommands. The shell starts it (Process) and reads it
// (SplitParser), one JSON object per line each way (LineChannel); it ends when its standard
// input closes, so it never outlives the shell. I/O only: what the shell does with what it
// reports is decided in the shell's *Rules.qml.
//
//   h2s-helper --version   {"version":"<the shell's version>","protocol":<n>} and exits
//   h2s-helper ping        {"event":"ready","protocol":<n>}, then answers each
//                          {"ping":<anything>} with {"event":"pong","ping":<the same>}
//   h2s-helper screensaver org.freedesktop.ScreenSaver on the session bus
//                          (ScreenSaverService.h: its lines each way)
//
// The protocol number changes whenever a message changes meaning or goes; the shell
// checks it (HelperRules) and treats a helper with another number as out of date.
#include "LineChannel.h"
#include "ScreenSaverService.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QJsonDocument>
#include <QJsonObject>

#include <csignal>
#include <cstdio>
#include <cstring>

namespace {

constexpr int protocol = 3;

int usage()
{
    std::fputs("usage: h2s-helper --version | ping | screensaver\n", stderr);
    return 2;
}

int printVersion()
{
    const QJsonObject answer{{QStringLiteral("version"), QStringLiteral(H2S_VERSION)},
                             {QStringLiteral("protocol"), protocol}};
    const QByteArray line = QJsonDocument(answer).toJson(QJsonDocument::Compact) + '\n';
    return std::fwrite(line.constData(), 1, size_t(line.size()), stdout) == size_t(line.size())
                   && std::fflush(stdout) == 0
               ? 0
               : 1;
}

int runPing(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    LineChannel channel;
    QObject::connect(&channel, &LineChannel::closed, &application, &QCoreApplication::quit);
    QObject::connect(&channel, &LineChannel::message, &application, [&](const QJsonObject &message) {
        bool delivered;
        if (message.contains(QStringLiteral("ping"))) {
            delivered = channel.send({{QStringLiteral("event"), QStringLiteral("pong")},
                                      {QStringLiteral("ping"), message.value(QStringLiteral("ping"))}});
        } else {
            delivered = channel.send({{QStringLiteral("event"), QStringLiteral("error")},
                                      {QStringLiteral("message"), QStringLiteral("unknown message")}});
        }
        if (!delivered)
            application.quit();
    });
    if (!channel.send({{QStringLiteral("event"), QStringLiteral("ready")},
                       {QStringLiteral("protocol"), protocol}}))
        return 1;
    return application.exec();
}

int runScreenSaver(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    LineChannel channel;
    QObject::connect(&channel, &LineChannel::closed, &application, &QCoreApplication::quit);
    if (!channel.send({{QStringLiteral("event"), QStringLiteral("ready")},
                       {QStringLiteral("protocol"), protocol}}))
        return 1;
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        channel.send({{QStringLiteral("event"), QStringLiteral("error")},
                      {QStringLiteral("message"), QStringLiteral("no session bus: ") + bus.lastError().message()}});
        return 1;
    }
    ScreenSaverService service(bus, &channel);
    if (!service.start())
        return 1;
    return application.exec();
}

} // namespace

int main(int argc, char **argv)
{
    // A shell gone while an answer is written: the write fails and the helper ends,
    // instead of being killed by the signal
    std::signal(SIGPIPE, SIG_IGN);
    if (argc != 2)
        return usage();
    if (std::strcmp(argv[1], "--version") == 0)
        return printVersion();
    if (std::strcmp(argv[1], "ping") == 0)
        return runPing(argc, argv);
    if (std::strcmp(argv[1], "screensaver") == 0)
        return runScreenSaver(argc, argv);
    return usage();
}
