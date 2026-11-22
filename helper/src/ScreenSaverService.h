// `h2s-helper screensaver`: org.freedesktop.ScreenSaver on the session bus, for the shell.
//
// The name is asked for only while the shell says so ({"own":true}: some idle job of the
// shell's is on), without replacing another owner and without letting another replace it;
// taken → the shell is told who holds it (that process's name, capped) and the helper stays
// queued, so it gets the name as soon as it is free. {"own":false} releases the name, or
// leaves the queue, and drops the apps' cookies: another program (an idle daemon doing idle
// instead of the shell) can own it. Until the first {"own":…} the name is not asked for;
// while it is not, Inhibit is refused and {"adopt":…} ignored. An ask the bus refuses is
// said ({"event":"error"}) and tried again, after a growing pause, while the shell wants it.
// Both object paths apps call are served (/ScreenSaver, /org/freedesktop/ScreenSaver).
//
// Inhibit cookies are kept per caller (its unique bus name) and dropped when the caller
// leaves the bus (NameOwnerChanged); UnInhibit removes only the caller's own cookie. A
// caller, and a process over all its connections, holds at most maxPerCaller. I/O only: the
// holders, SimulateUserActivity and SetActive go to the shell as lines, the screensaver's
// state (GetActive, GetActiveTime, ActiveChanged) comes from it, and what an inhibitor or a
// SetActive means is decided there (IdleRules).
//
// Lines to the shell: {"event":"ready","protocol":n}, {"event":"name","owned":true} /
// {"event":"name","owned":false,"owner":"<process name>"} (while asking for it),
// {"event":"name","released":true} (after {"own":false}), {"event":"inhibitors","list":
// [{"app","reason","cookie","caller"}]} (at most one per reportDelayMs: a burst of changes
// is one report), {"event":"activity"}, {"event":"setActive","id":n} (SetActive(true)),
// {"event":"askIdle","id":n}, {"event":"error","message":…}.
// From the shell: {"own":b}; {"active":b,"since":<epoch s>}; the answers {"answer":n,"idleSeconds":s}
// and {"answer":n,"taken":b} to the asks of that id (an answer to an ask no longer waiting
// is dropped: a late one never answers a newer call); {"adopt":[{"caller","app","reason",
// "cookie"}]}: the holders a helper before this one had, taken over where their caller is
// still on the bus (the shell hands them back after a restart).
#pragma once

#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QJsonObject>
#include <QList>
#include <QMap>
#include <QObject>
#include <QString>

class LineChannel;
class QTimer;
class ScreenSaverService;

// One object path's org.freedesktop.ScreenSaver: what apps call, handed to the service
// with the caller's bus name
class ScreenSaverInterface : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.ScreenSaver")

public:
    explicit ScreenSaverInterface(ScreenSaverService *service);

public Q_SLOTS:
    uint Inhibit(const QString &application, const QString &reason);
    void UnInhibit(uint cookie);
    void SimulateUserActivity();
    bool GetActive();
    uint GetActiveTime();
    uint GetSessionIdleTime();
    bool SetActive(bool active);

Q_SIGNALS:
    void ActiveChanged(bool active);

private:
    ScreenSaverService *m_service;
};

class ScreenSaverService : public QObject
{
    Q_OBJECT

public:
    static constexpr const char *serviceName = "org.freedesktop.ScreenSaver";
    // App names and reasons are text from outside: cut to these many characters here (the
    // shell caps them again for its views)
    static constexpr int maxAppLength = 64;
    static constexpr int maxReasonLength = 128;
    // Cookies one caller may hold (by its unique name, and by its process over all its
    // connections), and all callers together
    static constexpr int maxPerCaller = 16;
    static constexpr int maxCookies = 64;
    // Calls waiting for the shell's answer at once, and how long each waits
    static constexpr int maxAsks = 32;
    static constexpr int answerMs = 2000;
    // Changes to the holders within this long go to the shell as one report
    static constexpr int reportDelayMs = 75;

    ScreenSaverService(const QDBusConnection &bus, LineChannel *channel, QObject *parent = nullptr);

    // Registers both paths (the name waits for the shell's {"own":true}); false (said on the
    // channel) when the bus will not have the objects
    bool start();

    // For the interfaces: `caller` is the calling connection's unique name. 0 when the
    // caller (or its process, or everyone together) holds as many cookies as allowed
    uint inhibit(const QString &caller, const QString &application, const QString &reason);
    // Asking for the name (owning it or queued): apps reaching this helper otherwise (by its
    // unique name) are refused
    bool owning() const { return m_owning; }
    void unInhibit(const QString &caller, uint cookie);
    void simulateActivity();
    bool active() const { return m_active; }
    uint activeTime() const;
    // Delayed replies: answered when the shell answers, or at answerMs
    void askIdle(const QDBusMessage &call);
    void askSetActive(const QDBusMessage &call);

private:
    struct Hold {
        QString caller;
        uint pid;
        QString application;
        QString reason;
    };
    enum class AskKind { Idle, SetActive };
    struct Ask {
        AskKind kind;
        QDBusMessage call;
    };

    void ask(AskKind kind, const QDBusMessage &call);
    void answer(const QJsonObject &message);
    void expire(quint64 id);
    void shellMessage(const QJsonObject &message);
    void adopt(const QJsonValue &list);
    bool roomFor(const QString &caller, uint pid) const;
    uint callerPid(const QString &caller) const;
    void ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void setOwning(bool owning);
    void askForName();
    void reportName();
    void reportHolders();
    void sendHolders();
    void dropCaller(const QString &caller);
    void sendError(const QString &text);
    QString processName(const QString &busName) const;

    QDBusConnection m_bus;
    LineChannel *m_channel;
    QList<ScreenSaverInterface *> m_interfaces;
    QMap<uint, Hold> m_holds;
    uint m_nextCookie;
    bool m_active = false;
    qint64 m_activeSince = 0;
    // Asking for the name (owning it or queued for it): the shell's last {"own":…}
    bool m_owning = false;
    // The shell's word: asked for while true (a failed ask is tried again, retryMs doubling)
    bool m_wanted = false;
    int m_retryMs = 0;
    static constexpr int firstRetryMs = 1000;
    static constexpr int maxRetryMs = 30000;
    // The name's state as last told: "" not yet, "owned", "owner:<name>" or "released"
    QString m_nameTold;
    QMap<quint64, Ask> m_asks;
    quint64 m_nextAsk = 1;
    QTimer *m_reportTimer;
    QTimer *m_retryTimer;
};
