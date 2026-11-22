pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.lock

// Tells the user when the screen was not locked while the computer slept — by the outcome of
// each sleep, not by guessing which program locks (SleepNoticeRules has the cycle).
//
// The shell holds a sleep delay inhibitor of its own while awake ("Check the screen is
// locked before sleep"), so that at logind's PrepareForSleep it has a moment to look before
// the machine goes down: the shell's own lock confirmed by the compositor, else what the
// compositor or logind says (SleepLockState). Locked: let go at once. Otherwise it looks once
// more after `_lookAgain` (again while the shell's own lock is on its way) and lets go then,
// at the latest `_deadline` after the signal — whatever was read by then is the outcome
// ("unknown" without an answer). After the resume
// the outcome goes to SleepNoticeRules, whose actions show or withdraw the critical
// notification; closing it (× or its action) acknowledges it. The inhibitor is taken again
// after the wake, or when no wake was heard for `_missedResume` of running time.
//
// The state is remembered data (Config.sleepLockNotice, JSON), and kept for the process (a
// PersistentProperties) where the config cannot be written. Each sleep's outcome is logged.
Singleton {
    id: root

    readonly property var noticeState: SleepNoticeRules.restore(LockIoRules.sleepNoticeSaved(_memory.stateText))
    // The time of the unlocked sleep the notice waits on a fix for, or −1 (the Lock screen
    // page reads the same from the config)
    readonly property double waitingSince: SleepNoticeRules.waitingSince(noticeState)

    readonly property string summary: "Not locked while asleep"
    readonly property string body: "The screen was not locked while the computer slept."

    readonly property int _lookAgain: 500
    readonly property int _deadline: 1000
    readonly property int _missedResume: 60000
    readonly property bool _configUsable: Config.ready && !Config.loadFailed

    // "awake" (inhibitor held), "checking" (PrepareForSleep heard, looking), "asleep"
    // (looked, inhibitor let go, waiting for the resume)
    property string _phase: "awake"
    // The sleep being looked at: { generation, at, looks, outcome }
    property var _sleep: null
    property int _generation: 0
    property var _handle: null

    on_ConfigUsableChanged: _load()
    Component.onCompleted: Qt.callLater(_load)

    function _log(message) {
        console.info("[SleepLockNotice] " + message);
    }

    // The remembered state, once the config is read; a notification never closed is shown
    // again (SleepNoticeRules: restarted)
    function _load() {
        if (_memory.loaded || !Config.ready)
            return;
        _memory.loaded = true;
        if (_configUsable)
            _memory.stateText = Config.sleepLockNotice;
        _apply(SleepNoticeRules.step(noticeState, { type: "restarted" }));
    }

    function _apply(result) {
        const text = result.state.phase === "quiet" ? "" : JSON.stringify(result.state);
        const changed = result.state.phase !== noticeState.phase || result.state.at !== noticeState.at;
        _memory.stateText = text;
        if (_configUsable && Config.sleepLockNotice !== text)
            Config.sleepLockNotice = text;
        if (changed)
            _log("notice: " + result.state.phase);
        for (const action of result.actions) {
            if (action.type === "notify")
                _notify(action.at);
            else if (action.type === "withdraw")
                _withdraw();
        }
    }

    function _notify(at) {
        _withdraw();
        // The answer names the sleep it is about: a close of a notification since replaced
        // is ignored by the rules
        const closed = () => root._apply(SleepNoticeRules.step(root.noticeState, { type: "closed", at: at }));
        _handle = Notifier.send(summary, {
            body: body, format: "plain", urgency: "critical", handle: true,
            actions: [{ id: "default", label: "Settings", onTriggered: () => {
                Shell.openSettings("lockscreen");
                closed();
            } }],
            onDismissed: closed
        });
        _log("told the user: " + summary);
    }

    function _withdraw() {
        const handle = _handle;
        _handle = null;
        if (handle && handle.open)
            handle.close();
    }

    // ---- The look at sleep ----

    function _goingToSleep() {
        // A second PrepareForSleep without a wake between: the wake was missed
        if (_phase === "checking")
            _finish();
        if (_phase === "asleep")
            _resumed();
        _generation++;
        _sleep = { generation: _generation, at: Date.now(), looks: 0, outcome: "unknown" };
        _phase = "checking";
        _deadlineTimer.restart();
        _look();
    }

    function _look() {
        if (_phase !== "checking")
            return;
        _sleep.looks++;
        if (Lockscreen.lockConfirmed) {
            _sleep.outcome = "locked";
            _finish();
            return;
        }
        // One read at a time: one still running answers this look if it is this sleep's; an
        // earlier sleep's is ignored, and the deadline ends the look
        if (_reader.running)
            return;
        _reader.generation = _sleep.generation;
        _reader.start();
    }

    function _read(outcome) {
        // Late answers lose: a read started for an earlier sleep, or after this one's look ended
        if (_phase !== "checking" || _reader.generation !== _sleep.generation)
            return;
        _sleep.outcome = LockIoRules.sleepLookOutcome(Lockscreen.lockConfirmed, outcome);
        // The shell's own lock on its way (lock before sleep): looked at again until the
        // deadline, its confirmation ends the look at once (below)
        if (_sleep.outcome === "locked" || (_sleep.looks >= 2 && !Lockscreen.locked))
            _finish();
        else
            _lookAgainTimer.restart();
    }

    // The deadline: whatever was read by then, unless the shell's own lock is confirmed
    function _deadlinePassed() {
        if (_phase === "checking" && Lockscreen.lockConfirmed)
            _sleep.outcome = "locked";
        _finish();
    }

    function _finish() {
        if (_phase !== "checking")
            return;
        _lookAgainTimer.stop();
        _deadlineTimer.stop();
        _phase = "asleep";
        _missedResumeTimer.restart();
        _log("went to sleep " + _sleep.outcome + " (looked for " + (Date.now() - _sleep.at) + " ms)");
    }

    function _resumed() {
        if (_phase === "checking")
            _finish();
        _missedResumeTimer.stop();
        const sleep = _sleep;
        _sleep = null;
        _phase = "awake";
        if (sleep !== null && _memory.loaded)
            _apply(SleepNoticeRules.step(noticeState, { type: "slept", outcome: sleep.outcome, at: sleep.at }));
    }

    Connections {
        target: Lockscreen
        function onLockConfirmedChanged() {
            if (root._phase === "checking" && Lockscreen.lockConfirmed) {
                root._sleep.outcome = "locked";
                root._finish();
            }
        }
    }

    Connections {
        target: SystemSleep
        function onGoingToSleep() { root._goingToSleep(); }
        function onResumed() { root._resumed(); }
    }

    SleepInhibitor {
        id: _inhibitor
        why: "Check the screen is locked before sleep"
        toolDirectory: TestSeams.lockTools
        wanted: root._phase !== "asleep"
        onLogLine: (level, message) => {
            if (level === "warning")
                console.warn("[SleepLockNotice] " + message);
            else
                console.info("[SleepLockNotice] " + message);
        }
    }

    SleepLockState {
        id: _reader
        property int generation: 0
        toolDirectory: TestSeams.lockTools
        sessionPath: Lockscreen.sessionPath
        onRead: outcome => root._read(outcome)
    }

    Timer {
        id: _lookAgainTimer
        interval: root._lookAgain
        onTriggered: root._look()
    }

    Timer {
        id: _deadlineTimer
        interval: root._deadline
        onTriggered: root._deadlinePassed()
    }

    // Running time only (a timer stands still while the machine sleeps): this long awake
    // after going down means the resume signal was lost
    Timer {
        id: _missedResumeTimer
        interval: root._missedResume
        onTriggered: {
            if (root._phase === "asleep") {
                root._log("no resume signal: taken as awake");
                root._resumed();
            }
        }
    }

    // For tests/lock/ (shelltest sleepNotice): the cycle's state, the look
    function describe() {
        return JSON.stringify({ notice: noticeState, waitingSince: waitingSince, phase: _phase });
    }

    // The state for this process (SleepNoticeRules' as JSON, "" for quiet): over a reload,
    // and where the config cannot keep it
    PersistentProperties {
        id: _memory
        property bool loaded: false
        property string stateText: ""
    }
}
