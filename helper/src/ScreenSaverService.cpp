#include "ScreenSaverService.h"

#include "LineChannel.h"

#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QRandomGenerator>
#include <QTimer>

#include <cmath>

namespace {

const QString objectPaths[] = {QStringLiteral("/org/freedesktop/ScreenSaver"), QStringLiteral("/ScreenSaver")};

QString capped(const QString &text, int length)
{
    return text.size() > length ? text.left(length) : text;
}

QJsonObject eventLine(const char *name)
{
    return QJsonObject{{QStringLiteral("event"), QString::fromLatin1(name)}};
}

} // namespace

// ---- One object path ------------------------------------------------------------------

ScreenSaverInterface::ScreenSaverInterface(ScreenSaverService *service)
    : QObject(service)
    , m_service(service)
{
}

uint ScreenSaverInterface::Inhibit(const QString &application, const QString &reason)
{
    const uint cookie = m_service->inhibit(message().service(), application, reason);
    if (cookie == 0)
        sendErrorReply(QDBusError::LimitsExceeded, QStringLiteral("Too many inhibitors"));
    return cookie;
}

void ScreenSaverInterface::UnInhibit(uint cookie)
{
    m_service->unInhibit(message().service(), cookie);
}

void ScreenSaverInterface::SimulateUserActivity()
{
    m_service->simulateActivity();
}

bool ScreenSaverInterface::GetActive()
{
    return m_service->active();
}

uint ScreenSaverInterface::GetActiveTime()
{
    return m_service->activeTime();
}

uint ScreenSaverInterface::GetSessionIdleTime()
{
    // Answered when the shell says how long there has been no input
    setDelayedReply(true);
    m_service->askIdle(message());
    return 0;
}

bool ScreenSaverInterface::SetActive(bool active)
{
    return m_service->setActive(active);
}

// ---- The service ----------------------------------------------------------------------

ScreenSaverService::ScreenSaverService(const QDBusConnection &bus, LineChannel *channel, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
    , m_channel(channel)
    // Not from 1: a cookie an app kept from an earlier run of the helper is unlikely to be
    // one handed out again (and UnInhibit takes only the caller's own anyway)
    , m_nextCookie(QRandomGenerator::global()->bounded(1u, 1u << 20))
    , m_idleTimer(new QTimer(this))
{
    m_idleTimer->setSingleShot(true);
    m_idleTimer->setInterval(idleAnswerMs);
    connect(m_idleTimer, &QTimer::timeout, this, [this] {
        for (const QDBusMessage &call : std::as_const(m_idleAsks))
            m_bus.send(call.createErrorReply(QDBusError::Failed, QStringLiteral("The shell did not answer")));
        m_idleAsks.clear();
    });
    connect(channel, &LineChannel::message, this, &ScreenSaverService::shellMessage);
}

bool ScreenSaverService::start()
{
    // Every name's owner changes: the screensaver name's, and callers leaving the bus
    connect(m_bus.interface(), &QDBusConnectionInterface::serviceOwnerChanged, this, &ScreenSaverService::ownerChanged);
    for (const QString &path : objectPaths) {
        auto *interface = new ScreenSaverInterface(this);
        if (!m_bus.registerObject(path, interface, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
            m_channel->send({{QStringLiteral("event"), QStringLiteral("error")},
                             {QStringLiteral("message"), QStringLiteral("could not register ") + path}});
            return false;
        }
        m_interfaces.append(interface);
    }
    const QDBusReply<QDBusConnectionInterface::RegisterServiceReply> reply = m_bus.interface()->registerService(
        QString::fromLatin1(serviceName), QDBusConnectionInterface::QueueService, QDBusConnectionInterface::DontAllowReplacement);
    if (!reply.isValid()) {
        m_channel->send({{QStringLiteral("event"), QStringLiteral("error")},
                         {QStringLiteral("message"), QStringLiteral("could not ask for the name: ") + reply.error().message()}});
        return false;
    }
    reportName();
    return true;
}

uint ScreenSaverService::inhibit(const QString &caller, const QString &application, const QString &reason)
{
    int callerHolds = 0;
    for (const Hold &hold : std::as_const(m_holds))
        callerHolds += hold.caller == caller ? 1 : 0;
    if (callerHolds >= maxPerCaller || m_holds.size() >= maxCookies)
        return 0;
    uint cookie = m_nextCookie;
    while (cookie == 0 || m_holds.contains(cookie))
        ++cookie;
    m_nextCookie = cookie + 1;
    m_holds.insert(cookie, Hold{caller, capped(application, maxTextLength), capped(reason, maxTextLength)});
    reportHolders();
    return cookie;
}

void ScreenSaverService::unInhibit(const QString &caller, uint cookie)
{
    const auto found = m_holds.constFind(cookie);
    // Another caller's cookie stays: only who took it can give it back
    if (found == m_holds.constEnd() || found->caller != caller)
        return;
    m_holds.remove(cookie);
    reportHolders();
}

void ScreenSaverService::simulateActivity()
{
    m_channel->send(eventLine("activity"));
}

uint ScreenSaverService::activeTime() const
{
    if (!m_active || m_activeSince <= 0)
        return 0;
    return uint(qMax<qint64>(0, QDateTime::currentSecsSinceEpoch() - m_activeSince));
}

void ScreenSaverService::askIdle(const QDBusMessage &call)
{
    if (m_idleAsks.size() >= maxIdleAsks) {
        m_bus.send(call.createErrorReply(QDBusError::LimitsExceeded, QStringLiteral("Too many waiting calls")));
        return;
    }
    m_idleAsks.append(call);
    // One question for every call waiting
    if (m_idleAsks.size() == 1) {
        m_channel->send(eventLine("askIdle"));
        m_idleTimer->start();
    }
}

bool ScreenSaverService::setActive(bool active)
{
    QJsonObject message = eventLine("setActive");
    message.insert(QStringLiteral("active"), active);
    m_channel->send(message);
    return true;
}

void ScreenSaverService::shellMessage(const QJsonObject &message)
{
    if (message.value(QStringLiteral("active")).isBool()) {
        const bool active = message.value(QStringLiteral("active")).toBool();
        const double since = message.value(QStringLiteral("since")).toDouble(0);
        m_activeSince = std::isfinite(since) && since > 0 ? qint64(since) : 0;
        if (active != m_active) {
            m_active = active;
            for (ScreenSaverInterface *interface : std::as_const(m_interfaces))
                Q_EMIT interface->ActiveChanged(active);
        }
        return;
    }
    if (message.contains(QStringLiteral("idleSeconds"))) {
        answerIdle(message.value(QStringLiteral("idleSeconds")));
        return;
    }
    m_channel->send({{QStringLiteral("event"), QStringLiteral("error")},
                     {QStringLiteral("message"), QStringLiteral("unknown message")}});
}

void ScreenSaverService::answerIdle(const QJsonValue &seconds)
{
    const double value = seconds.toDouble(-1);
    if (!std::isfinite(value) || value < 0) {
        m_channel->send({{QStringLiteral("event"), QStringLiteral("error")},
                         {QStringLiteral("message"), QStringLiteral("idleSeconds is not a number of seconds")}});
        return;
    }
    const uint answer = uint(qMin(value, 4294967295.0));
    m_idleTimer->stop();
    for (const QDBusMessage &call : std::as_const(m_idleAsks))
        m_bus.send(call.createReply(QVariant::fromValue(answer)));
    m_idleAsks.clear();
}

void ScreenSaverService::ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner)
{
    if (name == QLatin1String(serviceName)) {
        reportName();
        return;
    }
    // A connection gone from the bus: its unique name loses its owner
    if (name.startsWith(QLatin1Char(':')) && !oldOwner.isEmpty() && newOwner.isEmpty())
        dropCaller(name);
}

void ScreenSaverService::dropCaller(const QString &caller)
{
    bool dropped = false;
    for (auto it = m_holds.begin(); it != m_holds.end();) {
        if (it->caller == caller) {
            it = m_holds.erase(it);
            dropped = true;
        } else {
            ++it;
        }
    }
    if (dropped)
        reportHolders();
}

void ScreenSaverService::reportName()
{
    const QDBusReply<QString> owner = m_bus.interface()->serviceOwner(QString::fromLatin1(serviceName));
    // No owner for a moment (between two owners): the next change says who
    if (!owner.isValid() || owner.value().isEmpty())
        return;
    const bool owned = owner.value() == m_bus.baseService();
    const QString name = owned ? QString() : processName(owner.value());
    const QString told = owned ? QStringLiteral("owned") : QStringLiteral("owner:") + name;
    if (told == m_nameTold)
        return;
    m_nameTold = told;
    QJsonObject message = eventLine("name");
    message.insert(QStringLiteral("owned"), owned);
    if (!owned)
        message.insert(QStringLiteral("owner"), name);
    m_channel->send(message);
}

void ScreenSaverService::reportHolders()
{
    QJsonArray list;
    for (auto it = m_holds.constBegin(); it != m_holds.constEnd(); ++it) {
        list.append(QJsonObject{{QStringLiteral("app"), it->application},
                                {QStringLiteral("reason"), it->reason},
                                {QStringLiteral("cookie"), qint64(it.key())}});
    }
    QJsonObject message = eventLine("inhibitors");
    message.insert(QStringLiteral("list"), list);
    m_channel->send(message);
}

// The process behind a bus name, by the name the kernel keeps for it (/proc/<pid>/comm:
// at most 15 characters); "" when the bus or /proc will not say
QString ScreenSaverService::processName(const QString &busName) const
{
    const QDBusReply<uint> pid = m_bus.interface()->servicePid(busName);
    if (!pid.isValid() || pid.value() == 0)
        return QString();
    QFile file(QStringLiteral("/proc/%1/comm").arg(pid.value()));
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    QString name = QString::fromUtf8(file.read(64)).trimmed();
    for (QChar &character : name) {
        if (!character.isPrint())
            character = QLatin1Char(' ');
    }
    return capped(name, 40);
}
