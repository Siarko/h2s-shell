pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.lock

// Idleness, the screensaver and the idle lock: the I/O around IdleRules
// (notes/plans/idle-lock-flow.md, §8 "Wiring"). It feeds the rules the facts — input idle
// from two IdleMonitors, the lock from Lockscreen, sleep from SystemSleep, the profile's
// settings — one event at a time, and carries out the actions they return: the
// screensaver's picture per monitor (`shownFor`, which the screensaver's windows follow),
// the monitors' power (ScreenPower), the lock surface's black fallback (`lockBlack`), the
// idle lock (Lockscreen.lock("idle")), the start and end commands. One Timer runs to the
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

    // What the screen with this connector name shows unlocked: "on" (the desktop), "saver"
    // (the screensaver) or "off" (powered off, under a plain black surface that takes the
    // keys); "on" while locked, where the lock surface is what shows
    function shownFor(connector) {
        if (_state.locked)
            return "on";
        const entry = _monitorEntries.find(monitor => monitor.connector === connector);
        return entry ? (_state.shown[entry.id] ?? "on") : "on";
    }

    // Power control: a backend, and the monitors read at least once (until then, or with no
    // monitor in its list, the screens with the screensaver: nothing may lose the screensaver
    // or the lock screen's blackout to a reading that failed)
    readonly property bool _powerControl: ScreenPower.canPowerOff && ScreenPower.monitors.length > 0
    // [{ id, connector }]: ScreenPower's monitors with power control, else the screens
    readonly property var _monitorEntries: _powerControl
        ? ScreenPower.monitors.map(monitor => ({ id: monitor.id, connector: monitor.connector }))
        : Quickshell.screens.map(screen => ({ id: screen.name, connector: screen.name }))
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
        blanking: Profiles.value("lockscreen.blanking"),
        screensaverCommands: Profiles.value("lockscreen.screensaverCommands")
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
        return IdleRules.config(_values, _monitors, _powerControl);
    }

    function _monitorListChanged() {
        _dispatch({ type: "monitors" });
    }

    // Each reading of ScreenPower's: the power as read ("unknown" for a failed reading)
    function _powerRead() {
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
        case "powerOff":
        case "powerOn":
            // The first ask, and the first ask again (a reading showed it did not take); the
            // further ones, after a growing pause, are not logged
            if (action.restore === true)
                _log("warning", "monitors turned off before the shell restarted, turned on again: " + action.ids.join(", "));
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
        default:
            // active (no screensaver interface yet): nothing to carry out
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
        _restoreScreens();
        if (Lockscreen.attended)
            _dispatch({ type: "lockAttended", attended: true });
        if (Lockscreen.locked)
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
        onTriggered: root._dispatch({ type: "deadline" })
    }

    Connections {
        target: Lockscreen
        function onLockedChanged() {
            root._dispatch({ type: Lockscreen.locked ? "locked" : "unlocked" });
        }
    }

    Connections {
        target: SystemSleep
        function onGoingToSleep() {
            _missedResume.restart();
            root._dispatch({ type: "sleep" });
        }
        function onResumed() {
            _missedResume.stop();
            root._dispatch({ type: "resumed" });
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
                saverShown: root.saverShown,
                saverOnScreen: root.saverOnScreen,
                idleFor: now - root._state.idleSince,
                nextDeadlineIn: deadline < 0 ? -1 : deadline - now
            });
        }
    }
}
