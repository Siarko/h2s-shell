pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.helper
import qs.singletons.lock

// Idleness, the screensaver and the idle lock: the I/O around IdleRules. It feeds the rules
// the facts — input idle from two IdleMonitors, the lock from Lockscreen, sleep from
// SystemSleep, the profile's settings, logind's idle block (read before a stage would start,
// LogindIdleBlock) — one event at a time, and carries out the actions they return: the
// screensaver's picture per monitor (`shownFor`, which the screensaver's windows follow), the
// monitors' power (ScreenPower), the lock surface's black fallback (`lockBlack`), the idle
// lock (Lockscreen.lock("idle")), the sleep (logind's Suspend, LogindSleep — only where
// logind answers CanSuspend "yes", read at the start and when the settings page opens), the
// start and end commands. The screensaver interface
// (org.freedesktop.ScreenSaver, the helper's: ScreenSaverClient) brings the apps keeping the
// screen on and their activity, and is told the screensaver's state. One Timer runs to the
// rules' next deadline; nothing here decides when.
//
// Monitors are ScreenPower's (by MonitorRules' ids) where it can cut their power; elsewhere
// the screens, by name, all with the screensaver. Every reading of the monitors is a
// `monitors` and a `power` event: the rules trust a monitor to be off only when read so.
//
// The two IdleMonitors are made once, with the rules' fixed base time, and never remade: a
// new ext-idle notification counts from zero, so remaking one on a settings change ended an
// idle period nobody had come back from. They report "no input for 5 s" — one with Wayland
// idle inhibitors ignored (`inputIdle`), one with them respected (`awayIdle`) — and the
// rules count every stage from the last input.
//
// The clock is monotonic (an ElapsedTimer): it stands still while the machine sleeps, and
// the resume counts as input.
Singleton {
    id: root

    // Some monitor shows the screensaver, locked or not
    readonly property bool saverShown: _anySaver(_state)
    // The screensaver shown and not locked: what the screensaver's windows follow. Both from
    // the one state, so a window never reads a new lock beside an old picture (at an unlock
    // it would map for a moment)
    readonly property bool saverOnScreen: saverShown && !_state.locked
    // The lock surface drawn plain black: the lock screen's screen-off reached while some
    // monitor is not read as off (no power control, a cut that failed)
    readonly property bool lockBlack: _state.lockBlack === true

    // The apps keeping the screen on through org.freedesktop.ScreenSaver: [{ app, reason,
    // cookie }], plain and capped (counted by the rules only while unlocked)
    readonly property var busHolders: _screenSaver.holders
    // The interface as the Screensaver page tells it: { state, line } (HelperRules.serviceStatus)
    readonly property var screenSaverService: HelperRules.serviceStatus(Helper.state, _screenSaver.state, _screenSaver.name)

    // The connected monitors as idle counts them, [{ id, base, connector }] (MonitorRules'
    // ids), and whether their power can be cut (else the screen-off shows the screensaver):
    // what the settings page draws its lanes and cards from
    readonly property var monitors: _monitorEntries
    readonly property bool powerControl: _powerControl
    // The apps keeping the screen on, as the settings page lists them: [{ who, why }] — the
    // screensaver interface's holders, logind's idle blocks as last read, an unnamed Wayland
    // one (AwayViewRules.holders)
    readonly property var holders: AwayViewRules.holders(busHolders, _state.logindIdleBlock === true ? _logindHolders : [],
                                                          IdleRules.waylandHeld(_state))
    // logind's idle blocks at the last read that found them held, listed while the state
    // counts the block held
    property var _logindHolders: []
    // logind's sleep blocks as last read ([{ who, why }]), while the state counts one held:
    // they pause the sleep, locked or not
    readonly property var sleepBlockers: _state.logindSleepBlock === true ? _logindSleepHolders : []
    property var _logindSleepHolders: []
    // What logind allows and does about sleep: { canSuspend: "yes" | "no" | "challenge" |
    // "na" | "unknown", idleAction: { action, after } | null } (LockParseRules.sleepSupport)
    readonly property var sleepSupport: _logindSleep.support
    // The sleep the shell asked for is under way and the settings leave it unlocked (no lock
    // before sleep, no idle lock before it): the sleep notice does not count it
    readonly property bool sleepLeftUnlocked: _state.sleepAsked === true && _state.sleepLeftUnlocked === true

    // Read again what logind allows (the settings page, when it opens)
    function refreshSleepSupport() {
        _logindSleep.refresh();
    }

    // What the screen with this connector name shows unlocked: "on" (the desktop), "saver"
    // (the screensaver) or "off" (powered off, under a plain black surface that takes the
    // keys); "on" while locked, where the lock surface is what shows
    function shownFor(connector) {
        if (_state.locked)
            return "on";
        const entry = _monitorEntries.find(monitor => monitor.connector === connector);
        return entry ? (_state.shown[entry.id] ?? "on") : "on";
    }

    // The backend has listed monitors since it could power off (MonitorRules.backendSeen):
    // from then on its list stands as read, an empty one too
    property bool _backendSeen: false
    // Where the monitors come from (MonitorRules.idleMonitors): { powerControl, entries }
    readonly property var _source: MonitorRules.idleMonitors(ScreenPower.canPowerOff, _backendSeen, ScreenPower.monitors,
                                                             Array.from(Quickshell.screens))
    readonly property bool _powerControl: _source.powerControl
    // [{ id, base, connector }]
    readonly property var _monitorEntries: _source.entries
    readonly property var _monitors: _monitorEntries.map(monitor => monitor.id)
    on_MonitorsChanged: Qt.callLater(root._monitorListChanged)

    // The profile's values, by the rules' names
    readonly property var _values: ({
        screensaverEnabled: Profiles.value("lockscreen.screensaverEnabled"),
        screensaverTimeout: Profiles.value("lockscreen.screensaverTimeout"),
        screenOffEnabled: Profiles.value("lockscreen.screenOffEnabled"),
        screenOffTimeout: Profiles.value("lockscreen.screenOffTimeout"),
        lockscreenEnabled: Profiles.value("lockscreen.lockscreenEnabled"),
        lockAfter: Profiles.value("lockscreen.lockAfter"),
        lockedScreenOffTimeout: Profiles.value("lockscreen.lockedScreenOffTimeout"),
        perMonitor: Profiles.value("lockscreen.perMonitor"),
        monitorIdle: Profiles.value("lockscreen.monitorIdle"),
        screensaverCommands: Profiles.value("lockscreen.screensaverCommands"),
        sleepEnabled: Profiles.value("lockscreen.sleepEnabled"),
        sleepTimeout: Profiles.value("lockscreen.sleepTimeout"),
        lockOnSleep: Profiles.value("lockscreen.lockOnSleep")
    })
    // A profile switch changes several values in one pass: one config event after it
    on_ValuesChanged: Qt.callLater(root._settingsChanged)

    property ElapsedTimer _clock: ElapsedTimer {}
    property var _state: IdleRules.initial(0)
    property var _events: []
    property bool _dispatching: false

    function _now() {
        return Number(_clock.elapsedMs());
    }

    function _config() {
        return IdleRules.config(_values, _monitorEntries, _powerControl, _logindSleep.support.canSuspend);
    }

    function _monitorListChanged() {
        _dispatch({ type: "monitors" });
    }

    // Each reading of ScreenPower's: the power as read ("unknown" for a failed reading)
    function _powerRead() {
        _backendSeen = MonitorRules.backendSeen(_backendSeen, ScreenPower.canPowerOff, ScreenPower.monitors);
        _restoreScreens();
        if (!_powerControl)
            return;
        const power = {};
        for (const monitor of ScreenPower.monitors)
            power[monitor.id] = monitor.power;
        _dispatch({ type: "power", power: power });
    }

    function _anySaver(state) {
        return Object.values(state.shown).some(shown => shown === "saver");
    }

    function _settingsChanged() {
        _dispatch({ type: "config" });
    }

    // Events are taken one at a time, in order, also when an action leads to another (the
    // idle lock sets Lockscreen.locked at once)
    function _dispatch(event) {
        _events.push(event);
        if (_dispatching)
            return;
        _dispatching = true;
        try {
            while (_events.length > 0) {
                const next = _events.shift();
                const result = IdleRules.step(_state, next, _config(), _now());
                if (result.ignored !== "") {
                    _log("warning", "event " + JSON.stringify(next) + " ignored: " + result.ignored);
                    continue;
                }
                _state = result.state;
                for (const action of result.actions)
                    _run(action);
                _remember();
            }
        } finally {
            _dispatching = false;
        }
        _arm();
    }

    function _run(action) {
        switch (action.type) {
        case "showSaver":
            _log("info", "the screensaver shows");
            break;
        case "hideSaver":
            _log("info", "the screensaver goes");
            break;
        case "startCommand":
            _runCommand("lockscreen.screensaverStartCommand");
            break;
        case "endCommand":
            _runCommand("lockscreen.screensaverEndCommand");
            break;
        case "lock":
            // The first ask, and the first ask again (refused, or no lock came); the
            // further ones, after a growing pause, are not logged
            if (action.attempt === 1)
                _log("info", "idle: locking");
            else if (action.attempt === 2)
                _log("warning", "the idle lock was not taken: asking again while it is due, with a growing pause");
            Lockscreen.lock("idle");
            break;
        case "sleep":
            _log("info", "idle: asking logind to suspend" + (action.leftUnlocked ? " (unlocked, as the settings say)" : ""));
            if (!_logindSleep.suspend())
                _dispatch({ type: "sleepFailed" });
            break;
        case "powerOff":
        case "powerOn":
            // The first ask, the first ask again (a reading showed it did not take), and each off
            // asked of a monitor that came back powered; the further asks again, after a
            // growing pause, are not logged
            if (action.restore === true)
                _log("warning", "monitors turned off before the shell restarted, turned on again: " + action.ids.join(", "));
            else if (action.again === true)
                _log("info", "monitor " + action.ids.join(", ") + " read on while off: turned off again");
            else if (action.attempt === undefined)
                _log("info", (action.type === "powerOff" ? "screens off: " : "screens on: ") + action.ids.join(", "));
            else if (action.attempt === 2)
                _log("warning", "monitor " + action.ids.join(", ") + " not turned " + (action.type === "powerOff" ? "off" : "on")
                     + " as asked: asking again, with a growing pause");
            for (const id of action.ids)
                ScreenPower.setPower(id, action.type === "powerOn");
            break;
        case "powerGaveUp":
            _log("warning", "monitor " + action.ids.join(", ") + " still not " + (action.on ? "on" : "off")
                 + " after asking " + IdleRules.powerRetry.tries + " times: not asked again");
            break;
        case "lockBlack":
            _log("info", action.black ? "the lock screen goes black (a monitor not read as off)" : "the lock screen shows again");
            break;
        case "active":
            _busActiveSinceMs = action.active ? Date.now() : 0;
            _busActive = action.active;
            break;
        default:
            break;
        }
    }

    function _runCommand(key) {
        const command = Profiles.value(key) ?? "";
        if (Profiles.value("lockscreen.screensaverCommands") === true && command.trim() !== "")
            Quickshell.execDetached(["sh", "-c", command]);
    }

    function _arm() {
        const now = _now();
        const deadline = IdleRules.nextDeadline(_state, _config(), now);
        if (deadline < 0) {
            _deadline.stop();
            return;
        }
        _deadline.interval = Math.max(0, deadline - now);
        _deadline.restart();
    }

    function _log(level, message) {
        const line = "[Idle] " + message;
        if (level === "warning")
            console.warn(line);
        else
            console.info(line);
    }

    // ---- org.freedesktop.ScreenSaver (the helper's) ----
    property bool _busActive: false
    property real _busActiveSinceMs: 0

    property ScreenSaverClient _screenSaver: ScreenSaverClient {
        path: Helper.available ? Helper.path : ""
        // The name only while an idle job of the shell's is on: left free for an idle daemon
        // otherwise
        own: HelperRules.wantsScreenSaverName(IdleRules.config(root._values, root._monitorEntries, root._powerControl,
                                                                _logindSleep?.support?.canSuspend))
        active: root._busActive
        activeSinceMs: root._busActiveSinceMs
        idleSeconds: () => root._state.inputIdle ? (root._now() - root._state.idleSince) / 1000 : 0
        onHoldersChanged: root._dispatch({ type: "busInhibitors", count: holders.length })
        onActivity: root._dispatch({ type: "activity" })
        // An app's SetActive(true): the screensaver now, where it takes (not while locked)
        setActive: () => {
            const taken = IdleRules.busForceTakes(root._state);
            root._dispatch({ type: "busForce" });
            return taken;
        }
    }

    // "Lock after" replaced `lockscreenTimeout` (counted from the screensaver's start when it
    // was on); the old key is not carried over (unused where it would apply). A profile that
    // still holds it is told once per profile and shell run, naming the new one
    property var _oldKeyTold: ({})
    readonly property var _profilesWithOldKey: (Profiles.profiles ?? [])
        .filter(profile => profile?.set && "lockscreen.lockscreenTimeout" in profile.set)
        .map(profile => String(profile.name ?? ""))
    on_ProfilesWithOldKeyChanged: _tellOldKey()

    function _tellOldKey() {
        for (const name of _profilesWithOldKey) {
            if (_oldKeyTold[name])
                continue;
            _oldKeyTold[name] = true;
            _log("warning", "profile \"" + name + "\" still sets lockscreen.lockscreenTimeout, which is no longer read: "
                + "\"Lock after\" is lockscreen.lockAfter now, counted from the last input");
        }
    }

    Component.onCompleted: {
        _tellOldKey();
        _logindSleep.refresh();
        _restoreScreens();
        if (Lockscreen.attended)
            _dispatch({ type: "lockAttended", attended: true });
        if (_sessionLocked)
            _dispatch({ type: "locked" });
        else
            _arm();
    }

    IdleWatch {
        id: _inputIdle
        enabled: true
        timeout: IdleRules.baseTime / 1000
        respectInhibitors: false
        onIsIdleChanged: root._dispatch({ type: "inputIdle", idle: isIdle })
    }

    IdleWatch {
        id: _awayIdle
        enabled: true
        timeout: IdleRules.baseTime / 1000
        respectInhibitors: true
        onIsIdleChanged: root._dispatch({ type: "awayIdle", idle: isIdle })
    }

    Connections {
        target: ScreenPower
        function onMonitorsChanged() {
            root._powerRead();
        }
        // Set after the monitors of the same reading
        function onMonitorsReadChanged() {
            root._restoreScreens();
        }
    }

    Connections {
        target: Lockscreen
        function onAttendedChanged() {
            root._dispatch({ type: "lockAttended", attended: Lockscreen.attended });
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root._restoreScreens();
        }
    }

    // Monitors a previous run turned off (Config.screensOff): turned on at the first reading
    // once the config is read (the rules' `restore`: pending, asked again, remembered until a
    // reading shows them on) — a restart or a crash while they were off left them so, and
    // Hyprland turns nothing on at input by default. Until then nothing is written over the
    // list; monitors another program turned off are never in it. Config saves a second after
    // a change (its debounce): a crash within that second keeps the list before it
    property bool _screensRestored: false
    readonly property bool _configUsable: Config.ready && !Config.loadFailed

    function _restoreScreens() {
        if (_screensRestored || !_configUsable || !ScreenPower.canPowerOff || !ScreenPower.monitorsRead)
            return;
        _screensRestored = true;
        const ids = IdleRules.restoreOnStart(Array.from(Config.screensOff ?? []), ScreenPower.monitors);
        if (ids.length > 0)
            _dispatch({ type: "restore", ids: ids });
        _remember();
    }

    function _remember() {
        if (!_screensRestored || !_configUsable)
            return;
        const ids = IdleRules.turnedOff(_state);
        if (JSON.stringify(ids) !== JSON.stringify(Array.from(Config.screensOff ?? [])))
            Config.screensOff = ids;
    }

    Timer {
        id: _deadline
        repeat: false
        // An early expiry is harmless: the step finds nothing due and arms again
        onTriggered: root._deadlineReached()
    }

    // A stage or the idle lock due, or a held block's re-read: logind's idle block is read
    // first, and the deadline stepped after its answer. The reader answers within its
    // watchdog; should no answer come even so, the deadline is stepped a second after it
    // with what was known — a read never holds a stage for good
    property bool _deadlineAfterRead: false

    function _deadlineReached() {
        if (_deadlineAfterRead)
            return;
        if (IdleRules.logindReadDue(_state, _config(), _now())) {
            _deadlineAfterRead = true;
            _readGuard.restart();
            _logindIdle.start();
            return;
        }
        _dispatch({ type: "deadline" });
    }

    function _deadlineAfterAnswer() {
        if (!_deadlineAfterRead)
            return;
        _deadlineAfterRead = false;
        _readGuard.stop();
        _dispatch({ type: "deadline" });
    }

    Timer {
        id: _readGuard
        interval: _logindIdle.watchdog + 1000
        repeat: false
        onTriggered: {
            root._log("warning", "logind's idle inhibitors not answered: the deadline taken without them");
            root._deadlineAfterAnswer();
        }
    }

    // The outcome logged when it changes: held (by whom), free again, unreadable
    property string _logindTold: ""

    function _logindRead(block) {
        const told = block.held === true ? "held:" + block.holders.map(holder => holder.who + " (" + holder.why + ")").join(", ")
            : block.held === false ? "free" : "unknown";
        if (told !== _logindTold) {
            if (block.held === true)
                _log("info", "logind: an app keeps the screen on: " + told.slice(5));
            else if (block.held === false && _logindTold !== "")
                _log("info", "logind: no app keeps the screen on");
            else if (block.held !== true && block.held !== false)
                _log("warning", "could not read logind's idle inhibitors: not counted as keeping the screen on");
            _logindTold = told;
        }
        _logindHolders = block.held === true ? block.holders : [];
        const sleep = _logindIdle.sleepBlock;
        const sleepTold = sleep.held === true ? sleep.holders.map(holder => holder.who + " (" + holder.why + ")").join(", ") : "";
        if (sleepTold !== _logindSleepTold) {
            if (sleepTold !== "")
                _log("info", "logind: sleep blocked by " + sleepTold);
            _logindSleepTold = sleepTold;
        }
        _logindSleepHolders = sleep.held === true ? sleep.holders : [];
        _dispatch({ type: "logindIdleBlock", held: block.held, sleepHeld: sleep.held });
        _deadlineAfterAnswer();
    }
    property string _logindSleepTold: ""

    // ---- Sleep: what logind allows, and the call ----

    // The answer logged when it changes
    property string _sleepSupportTold: ""

    function _sleepSupportRead(support) {
        const told = support.canSuspend + " " + JSON.stringify(support.idleAction);
        if (told !== _sleepSupportTold) {
            _log(support.canSuspend === "unknown" ? "warning" : "info", "logind: CanSuspend " + support.canSuspend
                 + (support.idleAction === null ? ", IdleAction not read"
                    : ", IdleAction " + support.idleAction.action + " after " + support.idleAction.after + " s"));
            _sleepSupportTold = told;
        }
        // Not read: read again after a growing pause, so a slow start does not leave the sleep
        // off for the session
        if (support.canSuspend === "unknown") {
            _supportTries++;
            _supportRetry.interval = IdleRules.supportRetryDelay(_supportTries);
            _supportRetry.restart();
        } else {
            _supportTries = 0;
            _supportRetry.stop();
        }
        // The config follows the answer (sleep is a stage only on "yes")
        _dispatch({ type: "config" });
    }
    property int _supportTries: 0

    Timer {
        id: _supportRetry
        repeat: false
        onTriggered: _logindSleep.refresh()
    }

    LogindSleep {
        id: _logindSleep
        toolDirectory: TestSeams.lockTools
        onRead: support => root._sleepSupportRead(support)
        onSuspended: (ok, error) => {
            if (ok)
                return;
            root._log("warning", "logind did not suspend: " + error);
            root._dispatch({ type: "sleepFailed" });
        }
    }

    LogindIdleBlock {
        id: _logindIdle
        toolDirectory: TestSeams.lockTools
        // The lock test bed's `logindIdleWatchdog` timing (H2S_LOCK_TEST_TIMINGS, ms)
        watchdog: {
            const given = TestSeams.timings.logindIdleWatchdog;
            return typeof given === "number" && isFinite(given) && given >= 100 ? given : 7000;
        }
        onRead: block => root._logindRead(block)
    }

    // Locked by the shell, or by another program as read (Lockscreen.foreignLocked): either
    // way no idle lock is asked, and the lock screen's screen-off applies
    readonly property bool _sessionLocked: Lockscreen.locked || Lockscreen.foreignLocked
    on_SessionLockedChanged: root._dispatch({ type: _sessionLocked ? "locked" : "unlocked" })

    Connections {
        target: SystemSleep
        function onGoingToSleep() {
            _missedResume.restart();
            root._dispatch({ type: "sleep" });
        }
        function onResumed() {
            _missedResume.stop();
            root._dispatch({ type: "resumed" });
            // A block may have ended (or begun) over the sleep: read it again
            if (!root._sessionLocked)
                _logindIdle.start();
        }
    }

    // logind's PrepareForSleep(false) never came (its monitor died over the sleep): as
    // Lockscreen does, the machine counts as awake this long after going down — a Qt timer
    // stands still while it sleeps, so this counts from the wake
    Timer {
        id: _missedResume
        interval: LockStepRules.timings.missedResume
        repeat: false
        onTriggered: {
            root._log("warning", "no resume heard " + interval + " ms after going to sleep: taken as awake");
            root._dispatch({ type: "resumed" });
        }
    }

    // h2s-shell ipc call idle state   (JSON, for tests/lock/; Arch: launch.sh ipc call ...)
    IpcHandler {
        target: "idle"

        function state(): string {
            const now = root._now();
            const config = root._config();
            const deadline = IdleRules.nextDeadline(root._state, config, now);
            return JSON.stringify({
                state: root._state,
                config: config,
                monitors: root._monitorEntries,
                saverShown: root.saverShown,
                saverOnScreen: root.saverOnScreen,
                idleFor: now - root._state.idleSince,
                busHolders: root.busHolders,
                screenSaverService: root.screenSaverService,
                sleepSupport: root.sleepSupport,
                sleepBlockers: root.sleepBlockers,
                nextDeadlineIn: deadline < 0 ? -1 : deadline - now
            });
        }

        // h2s-shell ipc call idle setMonitorTimes '<id>' '<times>'   (a MonitorRules id, as
        // `state`'s monitors list them, or one of a monitor not connected; `times` "default" —
        // the monitor follows the default — or JSON: {"screensaverEnabled": false,
        // "screensaverTimeout": 300, "screenOffEnabled": true, "screenOffTimeout": 300}):
        // written where the setting's value comes from now (Profiles.writeInEffect); applies
        // while "Set per monitor" is on. A connected monitor's entry goes under the form of its
        // id it has now (the screens' ids where no backend reads the monitors)
        function setMonitorTimes(id: string, times: string): string {
            let given = times;
            if (times !== "default") {
                try {
                    given = JSON.parse(times);
                } catch (error) {
                    given = null;
                }
            }
            const entries = root._monitorEntries;
            const connected = MonitorRules.connectedFor(id, entries);
            const map = IdleRules.withMonitorTimes(Profiles.value("lockscreen.monitorIdle"), connected ?? id, given, entries);
            if (map === null)
                return "not understood: a monitor id (make|model|serial); \"default\" or {screensaverEnabled, screensaverTimeout, "
                    + "screenOffEnabled, screenOffTimeout} (whole seconds, " + IdleRules.monitorTimeRange.minimum + "–"
                    + IdleRules.monitorTimeRange.maximum + "); at most " + IdleRules.maxMonitorEntries + " monitors";
            return Profiles.writeInEffect("lockscreen.monitorIdle", map) === false ? "not written" : "ok";
        }
    }
}
