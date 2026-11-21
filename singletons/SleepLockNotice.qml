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
// Given once: the notice's key is kept for the process (over a reload too) and in the
// config (Config.sleepLockNotice) when it can be written, and forgotten only after two reads
// in a row with nothing to say, so the same problem coming back is told again
// (LockIoRules.sleepNoticeStep). A read that fails says nothing. Not while the session is
// locked (nobody would see the toast), and no reads then. The outcome goes to the log when
// it changes.
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
    Component.onCompleted: Qt.callLater(_decide)

    function _timing(name, fallback) {
        const given = TestSeams.timings[name];
        return typeof given === "number" && isFinite(given) && given >= 0 ? given : fallback;
    }

    // `fromRead`: called for a read just answered (counts toward forgetting the key)
    function _decide(fromRead) {
        if (!Config.ready)
            return;
        if (!_memory.loaded) {
            _memory.loaded = true;
            _memory.key = _configUsable ? Config.sleepLockNotice : "";
        }
        if (_reader.reads === 0 || _sessionLocked)
            return;
        const step = LockIoRules.sleepNoticeStep({ key: _memory.key, quiet: _memory.quiet }, _reader.lockers,
                                                 _lockOnSleep, fromRead === true);
        _memory.key = step.memory.key;
        _memory.quiet = step.memory.quiet;
        if (_configUsable && step.memory.key !== Config.sleepLockNotice)
            Config.sleepLockNotice = step.memory.key;
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
            root._decide(true);
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
        onTriggered: {
            if (!root._sessionLocked)
                _reader.start();
        }
    }

    // What was told, for this process: over a reload, and where the config cannot keep it
    PersistentProperties {
        id: _memory
        property bool loaded: false
        property string key: ""
        property int quiet: 0
    }
}
