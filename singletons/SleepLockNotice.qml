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
// compositor or logind says (SleepLockState). It reads again every quarter second until
// SleepNoticeRules.look says the look is done — at once when locked, "unlocked" only at its
// deadline (1 s), the shell's own lock on its way waited for — and lets go then. After the
// resume the outcome goes to SleepNoticeRules, whose actions show or withdraw the critical
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

    readonly property int _missedResume: 60000
    readonly property bool _configUsable: Config.ready && !Config.loadFailed

    // "awake" (inhibitor held), "checking" (PrepareForSleep heard, looking), "asleep"
    // (looked, inhibitor let go, waiting for the resume)
    property string _phase: "awake"
    // The sleep being looked at: { generation, at, read (the last answer), outcome }
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
        _sleep = { generation: _generation, at: Date.now(), read: null, outcome: "unknown" };
        _phase = "checking";
        _startRead();
        _tick.restart();
        _evaluate();
    }

    // One read at a time: a read still running (a hung one: hyprctl and gdbus are bounded to
    // a second each, and the end of the look stops it) is left to answer
    function _startRead() {
        if (_reader.running)
            return;
        _reader.generation = _sleep.generation;
        _reader.start();
    }

    // SleepNoticeRules.look decides: done (the outcome final, the inhibitor let go), or look
    // on — a new read at each tick
    function _evaluate(fromTick) {
        if (_phase !== "checking")
            return;
        const result = SleepNoticeRules.look({
            read: _sleep.read, ownLocked: Lockscreen.locked, ownConfirmed: Lockscreen.lockConfirmed,
            elapsed: Date.now() - _sleep.at
        });
        _sleep.outcome = result.outcome;
        if (result.done)
            _finish();
        else if (fromTick === true && result.lookAgain)
            _startRead();
    }

    function _read(outcome) {
        // Late answers lose: a read started for an earlier sleep, or after this one's look ended
        if (_phase !== "checking" || _reader.generation !== _sleep.generation)
            return;
        _sleep.read = outcome;
        _evaluate();
    }

    function _finish() {
        if (_phase !== "checking")
            return;
        _tick.stop();
        _reader.stop();
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
        function onLockConfirmedChanged() { root._evaluate(); }
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
        id: _tick
        interval: SleepNoticeRules.lookEvery
        repeat: true
        onTriggered: root._evaluate(true)
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
