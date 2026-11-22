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
    // Ending the screensaver is the user's input, not an app's: false, nothing done
    if (!active)
        return false;
    // Whether it took is the shell's answer (not while locked)
    setDelayedReply(true);
    m_service->askSetActive(message());
    return false;
}

// ---- The service ----------------------------------------------------------------------

ScreenSaverService::ScreenSaverService(const QDBusConnection &bus, LineChannel *channel, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
    , m_channel(channel)
    // Not from 1: a cookie an app kept from an earlier run of the helper is unlikely to be
    // one handed out again (and UnInhibit takes only the caller's own anyway)
    , m_nextCookie(QRandomGenerator::global()->bounded(1u, 1u << 20))
    , m_reportTimer(new QTimer(this))
{
    m_reportTimer->setSingleShot(true);
    m_reportTimer->setInterval(reportDelayMs);
    connect(m_reportTimer, &QTimer::timeout, this, &ScreenSaverService::sendHolders);
    connect(channel, &LineChannel::message, this, &ScreenSaverService::shellMessage);
}

bool ScreenSaverService::start()
{
    // Every name's owner changes: the screensaver name's, and callers leaving the bus
    connect(m_bus.interface(), &QDBusConnectionInterface::serviceOwnerChanged, this, &ScreenSaverService::ownerChanged);
    for (const QString &path : objectPaths) {
        auto *interface = new ScreenSaverInterface(this);
        if (!m_bus.registerObject(path, interface, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
            sendError(QStringLiteral("could not register ") + path);
            return false;
        }
        m_interfaces.append(interface);
    }
    return true;
}

// Asks for the name (queued behind another owner) or gives it up — also its place in the
// queue — with the apps' cookies: they asked the name's owner, which is no longer this
void ScreenSaverService::setOwning(bool owning)
{
    if (owning && !m_owning) {
        const QDBusReply<QDBusConnectionInterface::RegisterServiceReply> reply = m_bus.interface()->registerService(
            QString::fromLatin1(serviceName), QDBusConnectionInterface::QueueService, QDBusConnectionInterface::DontAllowReplacement);
        if (!reply.isValid()) {
            sendError(QStringLiteral("could not ask for the name: ") + reply.error().message());
            return;
        }
        m_owning = true;
        reportName();
    } else if (!owning) {
        if (m_owning) {
            const QDBusReply<bool> reply = m_bus.interface()->unregisterService(QString::fromLatin1(serviceName));
            if (!reply.isValid())
                sendError(QStringLiteral("could not release the name: ") + reply.error().message());
            m_owning = false;
            if (!m_holds.isEmpty()) {
                m_holds.clear();
                reportHolders();
            }
        }
        if (m_nameTold != QLatin1String("released")) {
            m_nameTold = QStringLiteral("released");
            QJsonObject message = eventLine("name");
            message.insert(QStringLiteral("released"), true);
            m_channel->send(message);
        }
    }
}

// The process behind a connection (0 when the bus will not say)
uint ScreenSaverService::callerPid(const QString &caller) const
{
    const QDBusReply<uint> pid = m_bus.interface()->servicePid(caller);
    return pid.isValid() ? pid.value() : 0;
}

bool ScreenSaverService::roomFor(const QString &caller, uint pid) const
{
    if (m_holds.size() >= maxCookies)
        return false;
    int byCaller = 0;
    int byProcess = 0;
    for (const Hold &hold : std::as_const(m_holds)) {
        byCaller += hold.caller == caller ? 1 : 0;
        byProcess += pid != 0 && hold.pid == pid ? 1 : 0;
    }
    return byCaller < maxPerCaller && byProcess < maxPerCaller;
}

uint ScreenSaverService::inhibit(const QString &caller, const QString &application, const QString &reason)
{
    const uint pid = callerPid(caller);
    if (!roomFor(caller, pid))
        return 0;
    uint cookie = m_nextCookie;
    while (cookie == 0 || m_holds.contains(cookie))
        ++cookie;
    m_nextCookie = cookie + 1;
    m_holds.insert(cookie, Hold{caller, pid, capped(application, maxAppLength), capped(reason, maxReasonLength)});
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
    ask(AskKind::Idle, call);
}

void ScreenSaverService::askSetActive(const QDBusMessage &call)
{
    ask(AskKind::SetActive, call);
}

// One question to the shell per call, with an id of its own: its answer replies to that
// call only, and a call not answered in time gets its fallback (expire)
void ScreenSaverService::ask(AskKind kind, const QDBusMessage &call)
{
    if (m_asks.size() >= maxAsks) {
        m_bus.send(call.createErrorReply(QDBusError::LimitsExceeded, QStringLiteral("Too many waiting calls")));
        return;
    }
    const quint64 id = m_nextAsk++;
    m_asks.insert(id, Ask{kind, call});
    QJsonObject message = eventLine(kind == AskKind::Idle ? "askIdle" : "setActive");
    message.insert(QStringLiteral("id"), qint64(id));
    m_channel->send(message);
    QTimer::singleShot(answerMs, this, [this, id] { expire(id); });
}

void ScreenSaverService::expire(quint64 id)
{
    const auto found = m_asks.constFind(id);
    if (found == m_asks.constEnd())
        return;
    if (found->kind == AskKind::Idle)
        m_bus.send(found->call.createErrorReply(QDBusError::Failed, QStringLiteral("The shell did not answer")));
    else
        m_bus.send(found->call.createReply(QVariant::fromValue(false)));
    m_asks.remove(id);
}

void ScreenSaverService::answer(const QJsonObject &message)
{
    const double number = message.value(QStringLiteral("answer")).toDouble(-1);
    const quint64 id = std::isfinite(number) && number > 0 ? quint64(number) : 0;
    const auto found = m_asks.constFind(id);
    // Late (its call already had its fallback) or never asked: dropped
    if (found == m_asks.constEnd())
        return;
    if (found->kind == AskKind::Idle) {
        const double seconds = message.value(QStringLiteral("idleSeconds")).toDouble(-1);
        if (!std::isfinite(seconds) || seconds < 0) {
            sendError(QStringLiteral("idleSeconds is not a number of seconds"));
            return;
        }
        m_bus.send(found->call.createReply(QVariant::fromValue(uint(qMin(seconds, 4294967295.0)))));
    } else {
        m_bus.send(found->call.createReply(QVariant::fromValue(message.value(QStringLiteral("taken")).toBool(false))));
    }
    m_asks.remove(id);
}

void ScreenSaverService::shellMessage(const QJsonObject &message)
{
    if (message.value(QStringLiteral("own")).isBool()) {
        setOwning(message.value(QStringLiteral("own")).toBool());
        return;
    }
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
    if (message.contains(QStringLiteral("answer"))) {
        answer(message);
        return;
    }
    if (message.value(QStringLiteral("adopt")).isArray()) {
        adopt(message.value(QStringLiteral("adopt")));
        return;
    }
    sendError(QStringLiteral("unknown message"));
}

// The holders of the helper before this one (it ended; the shell kept its last list): taken
// over with their cookies where their caller is still on the bus and nothing holds the
// cookie, within the same limits as a new Inhibit
void ScreenSaverService::adopt(const QJsonValue &list)
{
    bool changed = false;
    for (const QJsonValue &value : list.toArray()) {
        const QJsonObject entry = value.toObject();
        const QString caller = entry.value(QStringLiteral("caller")).toString();
        const double number = entry.value(QStringLiteral("cookie")).toDouble(0);
        if (!caller.startsWith(QLatin1Char(':')) || !std::isfinite(number) || number < 1 || number > 4294967295.0)
            continue;
        const uint cookie = uint(number);
        if (m_holds.contains(cookie) || !m_bus.interface()->isServiceRegistered(caller).value())
            continue;
        const uint pid = callerPid(caller);
        if (!roomFor(caller, pid))
            continue;
        m_holds.insert(cookie, Hold{caller, pid, capped(entry.value(QStringLiteral("app")).toString(), maxAppLength),
                                    capped(entry.value(QStringLiteral("reason")).toString(), maxReasonLength)});
        changed = true;
    }
    if (changed)
        reportHolders();
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
    // Not asking: the name's owner is none of this helper's business
    if (!m_owning)
        return;
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

// The list goes when no change has come for a moment: a client inhibiting and releasing in
// a loop makes one report, not one per call
void ScreenSaverService::reportHolders()
{
    if (!m_reportTimer->isActive())
        m_reportTimer->start();
}

void ScreenSaverService::sendHolders()
{
    QJsonArray list;
    for (auto it = m_holds.constBegin(); it != m_holds.constEnd(); ++it) {
        list.append(QJsonObject{{QStringLiteral("app"), it->application},
                                {QStringLiteral("reason"), it->reason},
                                {QStringLiteral("cookie"), qint64(it.key())},
                                {QStringLiteral("caller"), it->caller}});
    }
    QJsonObject message = eventLine("inhibitors");
    message.insert(QStringLiteral("list"), list);
    m_channel->send(message);
}

void ScreenSaverService::sendError(const QString &text)
{
    m_channel->send({{QStringLiteral("event"), QStringLiteral("error")}, {QStringLiteral("message"), text}});
}

// The process behind a bus name, by the name the kernel keeps for it (/proc/<pid>/comm:
// at most 15 characters); "" when the bus or /proc will not say
QString ScreenSaverService::processName(const QString &busName) const
{
    const uint pid = callerPid(busName);
    if (pid == 0)
        return QString();
    QFile file(QStringLiteral("/proc/%1/comm").arg(pid));
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    QString name = QString::fromUtf8(file.read(64)).trimmed();
    for (QChar &character : name) {
        if (!character.isPrint())
            character = QLatin1Char(' ');
    }
    return capped(name, 40);
}
