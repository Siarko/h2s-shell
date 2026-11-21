pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.lock

// Tells the user, once, when locking before sleep is in conflict with the system
// (LockIoRules.sleepLockNotice): "Lock before the computer sleeps" is on while another
// program locks the screen before sleep too (two lockers racing for the screen), or it is
// off while nothing else does (the screen stays unlocked through sleep). What else locks
// is read from logind's sleep inhibitors (SleepLockers): first a while after the start, so
// that idle daemons started with the session have taken theirs, then every 15 minutes; a
// change of the setting is decided again on the last read.
//
// Given once: the notice's key is kept in the config (Config.sleepLockNotice), and an
// outcome with nothing to say forgets it, so the same problem coming back is told again. A
// read that fails says nothing. Not while the session is locked (nobody would see the
// toast), and not without a config read that can remember. The outcome goes to the log
// when it changes.
Singleton {
    id: root

    readonly property bool _lockOnSleep: Lockscreen.lockOnSleep
    readonly property bool _sessionLocked: !Lockscreen.startChecked || Lockscreen.locked || Lockscreen.restoring
    readonly property bool _configUsable: Config.ready && !Config.loadFailed
    // The first read after the start (30 s) and the pause between reads (15 min), or the lock
    // test bed's `sleepLockers` and `sleepLockersEvery` timings (H2S_LOCK_TEST_TIMINGS, in
    // ms; LockRules ignores those names)
    readonly property int _firstRead: _timing("sleepLockers", 30000)
    readonly property int _readEvery: Math.max(_timing("sleepLockersEvery", 15 * 60 * 1000), 100)
    property string _loggedOutcome: ""

    on_LockOnSleepChanged: _decide()
    on_SessionLockedChanged: _decide()
    on_ConfigUsableChanged: _decide()

    function _timing(name, fallback) {
        const given = TestSeams.timings[name];
        return typeof given === "number" && isFinite(given) && given >= 0 ? given : fallback;
    }

    function _decide() {
        if (_reader.reads === 0 || !_configUsable || _sessionLocked)
            return;
        const step = LockIoRules.sleepNoticeStep(Config.sleepLockNotice, _reader.lockers, _lockOnSleep);
        if (step.remember !== Config.sleepLockNotice)
            Config.sleepLockNotice = step.remember;
        if (step.notice === null)
            return;
        console.info("[SleepLockNotice] telling the user: " + step.notice.summary);
        Notifier.send(step.notice.summary, { body: step.notice.body, format: "plain" });
    }

    SleepLockers {
        id: _reader
        toolDirectory: TestSeams.lockTools
        onRead: lockers => {
            const text = LockIoRules.sleepLockersText(lockers);
            if (text !== root._loggedOutcome) {
                root._loggedOutcome = text;
                console.info("[SleepLockNotice] other lockers before sleep: " + text);
            }
            root._decide();
        }
    }

    Timer {
        interval: root._firstRead
        running: true
        onTriggered: {
            _reader.start();
            _every.start();
        }
    }

    Timer {
        id: _every
        interval: root._readEvery
        repeat: true
        onTriggered: _reader.start()
    }
}
