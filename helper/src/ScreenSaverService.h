// `h2s-helper screensaver`: org.freedesktop.ScreenSaver on the session bus, for the shell.
//
// The name is asked for without replacing another owner and without letting another
// replace it; taken → the shell is told who holds it (that process's name, capped) and the
// helper stays queued, so it gets the name as soon as it is free. Both object paths apps
// call are served (/ScreenSaver, /org/freedesktop/ScreenSaver).
//
// Inhibit cookies are kept per caller (its unique bus name) and dropped when the caller
// leaves the bus (NameOwnerChanged); UnInhibit removes only the caller's own cookie. I/O
// only: the holders, SimulateUserActivity and SetActive go to the shell as lines, the
// screensaver's state (GetActive, GetActiveTime, ActiveChanged) comes from it, and what an
// inhibitor means is decided there (IdleRules).
//
// Lines to the shell: {"event":"ready","protocol":n}, {"event":"name","owned":true} /
// {"event":"name","owned":false,"owner":"<process name>"}, {"event":"inhibitors","list":
// [{"app","reason","cookie"}]}, {"event":"activity"}, {"event":"setActive","active":b},
// {"event":"askIdle"}, {"event":"error","message":…}. From the shell: {"active":b,
// "since":<epoch s>}, {"idleSeconds":n}.
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
    // App names and reasons are text from outside: cut to this many characters here (the
    // shell caps them again, shorter, for its views)
    static constexpr int maxTextLength = 1000;
    // Cookies one caller may hold, and all callers together
    static constexpr int maxPerCaller = 16;
    static constexpr int maxCookies = 64;
    // GetSessionIdleTime calls waiting for the shell at once, and how long they wait
    static constexpr int maxIdleAsks = 32;
    static constexpr int idleAnswerMs = 2000;

    ScreenSaverService(const QDBusConnection &bus, LineChannel *channel, QObject *parent = nullptr);

    // Registers both paths and asks for the name; false (said on the channel) when the bus
    // will not have the objects
    bool start();

    // For the interfaces: `caller` is the calling connection's unique name. 0 when the
    // caller (or everyone together) holds as many cookies as allowed
    uint inhibit(const QString &caller, const QString &application, const QString &reason);
    void unInhibit(const QString &caller, uint cookie);
    void simulateActivity();
    bool active() const { return m_active; }
    uint activeTime() const;
    void askIdle(const QDBusMessage &call);
    bool setActive(bool active);

private:
    struct Hold {
        QString caller;
        QString application;
        QString reason;
    };

    void shellMessage(const QJsonObject &message);
    void ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void reportName();
    void reportHolders();
    void answerIdle(const QJsonValue &seconds);
    void dropCaller(const QString &caller);
    QString processName(const QString &busName) const;

    QDBusConnection m_bus;
    LineChannel *m_channel;
    QList<ScreenSaverInterface *> m_interfaces;
    QMap<uint, Hold> m_holds;
    uint m_nextCookie;
    bool m_active = false;
    qint64 m_activeSince = 0;
    // The name's state as last told: "" not yet, "owned", or "owner:<name>"
    QString m_nameTold;
    QList<QDBusMessage> m_idleAsks;
    QTimer *m_idleTimer;
};
