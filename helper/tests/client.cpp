// An app on the bus, for tests/run-helper.sh: told what to do one line at a time on
// standard input (fields separated by tabs), it answers one line each on standard output,
// and holds its connection — so its inhibitors — until told to leave or its input closes.
//
//   path <object path>         the path later calls go to (/org/freedesktop/ScreenSaver)
//   inhibit <app> <reason>     cookie <n> | error <D-Bus error name>
//   inhibit2 <app> <reason>    the same through a second connection of this process
//   flood <n>                  n Inhibit and UnInhibit pairs at once: flooded
//   uninhibit <cookie>         ok | error <name>
//   activity                   ok | error <name>       (SimulateUserActivity)
//   active                     active true|false | error <name>
//   activetime                 activetime <s> | error <name>
//   idle                       idle <s> | error <name>  (GetSessionIdleTime)
//   setactive true|false       setactive true|false | error <name>
//   own                        owned | not owned        (takes org.freedesktop.ScreenSaver)
//   unique                     unique <its unique bus name>
//   watch                      watching; then `ActiveChanged <path> true|false` per signal
//   exit                       ends (status 0)
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QObject>
#include <QSocketNotifier>
#include <QStringList>

#include <cerrno>
#include <cstdio>
#include <unistd.h>

namespace {

const QString service = QStringLiteral("org.freedesktop.ScreenSaver");

void say(const QString &line)
{
    const QByteArray bytes = line.toUtf8() + '\n';
    std::fwrite(bytes.constData(), 1, size_t(bytes.size()), stdout);
    std::fflush(stdout);
}

} // namespace

class Client : public QObject
{
    Q_OBJECT

public:
    explicit Client(const QDBusConnection &bus)
        : m_bus(bus)
    {
        m_notifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, this);
        connect(m_notifier, &QSocketNotifier::activated, this, &Client::readAvailable);
    }

public Q_SLOTS:
    void activeChanged(const QDBusMessage &message)
    {
        const bool active = message.arguments().value(0).toBool();
        say(QStringLiteral("ActiveChanged ") + message.path() + (active ? QStringLiteral(" true") : QStringLiteral(" false")));
    }

private:
    void readAvailable()
    {
        char chunk[4096];
        const ssize_t got = ::read(STDIN_FILENO, chunk, sizeof chunk);
        if (got < 0 && errno == EINTR)
            return;
        if (got <= 0) {
            QCoreApplication::exit(0);
            return;
        }
        m_buffer.append(chunk, got);
        qsizetype end;
        while ((end = m_buffer.indexOf('\n')) >= 0) {
            const QString line = QString::fromUtf8(m_buffer.left(end));
            m_buffer.remove(0, end + 1);
            take(line.split(QLatin1Char('\t')));
        }
    }

    QDBusMessage call(const QString &method, const QVariantList &arguments = {}, bool second = false)
    {
        QDBusMessage message = QDBusMessage::createMethodCall(service, m_path, service, method);
        message.setArguments(arguments);
        if (second)
            return QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("second")).call(message, QDBus::Block, 5000);
        return m_bus.call(message, QDBus::Block, 5000);
    }

    // `<word> <first argument>`, or `error <name>`
    static QString answer(const QDBusMessage &reply, const QString &word)
    {
        if (reply.type() == QDBusMessage::ErrorMessage)
            return QStringLiteral("error ") + reply.errorName();
        const QVariant value = reply.arguments().value(0);
        if (value.typeId() == QMetaType::Bool)
            return word + (value.toBool() ? QStringLiteral(" true") : QStringLiteral(" false"));
        return word + QLatin1Char(' ') + value.toString();
    }

    void take(const QStringList &fields)
    {
        const QString command = fields.value(0);
        if (command == QLatin1String("path")) {
            m_path = fields.value(1);
            say(QStringLiteral("ok"));
        } else if (command == QLatin1String("inhibit")) {
            say(answer(call(QStringLiteral("Inhibit"), {fields.value(1), fields.value(2)}), QStringLiteral("cookie")));
        } else if (command == QLatin1String("inhibit2")) {
            say(answer(call(QStringLiteral("Inhibit"), {fields.value(1), fields.value(2)}, true), QStringLiteral("cookie")));
        } else if (command == QLatin1String("flood")) {
            const int count = fields.value(1).toInt();
            for (int i = 0; i < count; ++i) {
                const QDBusMessage reply = call(QStringLiteral("Inhibit"), {QStringLiteral("flood"), QString::number(i)});
                call(QStringLiteral("UnInhibit"), {QVariant::fromValue(reply.arguments().value(0).toUInt())});
            }
            say(QStringLiteral("flooded"));
        } else if (command == QLatin1String("uninhibit")) {
            const QDBusMessage reply = call(QStringLiteral("UnInhibit"), {QVariant::fromValue(fields.value(1).toUInt())});
            say(reply.type() == QDBusMessage::ErrorMessage ? answer(reply, QString()) : QStringLiteral("ok"));
        } else if (command == QLatin1String("activity")) {
            const QDBusMessage reply = call(QStringLiteral("SimulateUserActivity"));
            say(reply.type() == QDBusMessage::ErrorMessage ? answer(reply, QString()) : QStringLiteral("ok"));
        } else if (command == QLatin1String("active")) {
            say(answer(call(QStringLiteral("GetActive")), QStringLiteral("active")));
        } else if (command == QLatin1String("activetime")) {
            say(answer(call(QStringLiteral("GetActiveTime")), QStringLiteral("activetime")));
        } else if (command == QLatin1String("idle")) {
            say(answer(call(QStringLiteral("GetSessionIdleTime")), QStringLiteral("idle")));
        } else if (command == QLatin1String("setactive")) {
            say(answer(call(QStringLiteral("SetActive"), {fields.value(1) == QLatin1String("true")}), QStringLiteral("setactive")));
        } else if (command == QLatin1String("own")) {
            const QDBusReply<QDBusConnectionInterface::RegisterServiceReply> reply = m_bus.interface()->registerService(
                service, QDBusConnectionInterface::DontQueueService, QDBusConnectionInterface::DontAllowReplacement);
            say(reply.isValid() && reply.value() == QDBusConnectionInterface::ServiceRegistered ? QStringLiteral("owned")
                                                                                                : QStringLiteral("not owned"));
        } else if (command == QLatin1String("unique")) {
            say(QStringLiteral("unique ") + m_bus.baseService());
        } else if (command == QLatin1String("watch")) {
            for (const QString &path : {QStringLiteral("/org/freedesktop/ScreenSaver"), QStringLiteral("/ScreenSaver")})
                m_bus.connect(QString(), path, service, QStringLiteral("ActiveChanged"), this, SLOT(activeChanged(QDBusMessage)));
            say(QStringLiteral("watching"));
        } else if (command == QLatin1String("exit")) {
            QCoreApplication::exit(0);
        } else {
            say(QStringLiteral("unknown"));
        }
    }

    QDBusConnection m_bus;
    QSocketNotifier *m_notifier = nullptr;
    QByteArray m_buffer;
    QString m_path = QStringLiteral("/org/freedesktop/ScreenSaver");
};

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        std::fputs("no session bus\n", stderr);
        return 1;
    }
    Client client(bus);
    say(QStringLiteral("ready"));
    return application.exec();
}

#include "client.moc"
