pragma Singleton

import Quickshell
import QtQuick

// What each monitor shows while nobody is at the computer, and when the session locks —
// pure, so tests/IdleRulesTest.qml checks every case without a compositor, a bus or a
// clock. `Idle` (I/O) feeds it the facts and runs the actions.
//
// Declarative: from the facts, `wanted` says what every monitor should show — "on" (the
// desktop), "saver" (the black screensaver surface) or "off" (powered off, under a black
// surface that takes the keys) — and `step` returns the actions as the difference between
// that and what is shown now (`state.shown`). A profile change, a monitor plugged in, a
// deadline, a wake or a resume are then the same step, and no stage is left behind.
//
// All idle times count from the last input:
//
//   last input ── saverAfter ── screenOffAfter ── lockAfter
//                 (stage 1:      (stage 2: every
//                  each monitor   monitor off)
//                  its way)
//   locked ── lockedScreenOffAfter, from the lock or the last input at the lock screen
//
// A stage reached stays until input — an inhibitor arriving, a profile with longer times —
// unless the profile switches it off (a screensaver turned off is hidden, without the end
// command: the user is still away). Inhibitors (Wayland, the screensaver bus interface,
// logind's idle block) hold the next stage while unlocked and are ignored while locked; a
// released inhibitor restarts the counting at its release. Locking never turns a monitor
// on; only input does.
//
// Facts that could not be read are unknown, never the comfortable answer: a monitor's power
// is "off" only when read as off, and logind's block is held only when read as held.
Singleton {
    id: root

    // ext-idle-notify reports idleness after this long without input (Idle's two monitors
    // are made once with it): an `inputIdle` event without its own `since` means the last
    // input was this long before
    readonly property int baseTime: 5000
    // logind sends no signal when an idle block is released: while one holds, Idle reads
    // its inhibitors again this often
    readonly property int logindRecheck: 30000

    // The ways a monitor goes dark at "Screensaver after"
    readonly property var ways: ["screensaver", "off", "slideshow"]

    // The profile's values, by their names in the "lockscreen" group, normalised.
    // `values`: { screensaverEnabled, screensaverTimeout, screenOffEnabled, screenOffTimeout,
    // lockscreenEnabled, lockAfter, lockedScreenOffTimeout, blanking, perMonitor,
    // monitorBlanking ({ monitorId: way }), screensaverCommands } — times in seconds;
    // `monitors`: the connected monitors' ids (make|model|serial, MonitorRules) or objects
    // with an `id`; `canPowerOff`: a backend can cut a monitor's power. → the config every
    // other function takes: times in seconds, 0 = never; `ways` resolved per monitor to
    // "screensaver" or "off" — "off" without power control and "slideshow" (not built)
    // fall back to the screensaver.
    function config(values, monitors, canPowerOff) {
        const given = values ?? {};
        const power = canPowerOff === true;
        const flag = (value, fallback) => typeof value === "boolean" ? value : fallback;
        const seconds = (value, fallback) => {
            const number = Number(value);
            if (value === undefined || value === null || value === "" || !isFinite(number))
                return fallback;
            return Math.max(0, number);
        };
        const ids = [];
        for (const monitor of monitors ?? []) {
            const id = typeof monitor === "string" ? monitor : monitor?.id;
            if (typeof id === "string" && id !== "" && !ids.includes(id))
                ids.push(id);
        }
        const defaultWay = ways.includes(given.blanking) ? given.blanking : "screensaver";
        const perMonitor = flag(given.perMonitor, false);
        const overrides = perMonitor && given.monitorBlanking !== null && typeof given.monitorBlanking === "object"
            ? given.monitorBlanking : {};
        const resolved = {};
        for (const id of ids) {
            const own = overrides[id];
            const way = ways.includes(own) ? own : defaultWay;
            resolved[id] = way === "off" && power ? "off" : "screensaver";
        }
        return {
            saverAfter: flag(given.screensaverEnabled, false) ? seconds(given.screensaverTimeout, 300) : 0,
            // Without power control there is no screen-off stage (the page greys it)
            screenOffAfter: power && flag(given.screenOffEnabled, false) ? seconds(given.screenOffTimeout, 600) : 0,
            lockAfter: flag(given.lockscreenEnabled, false) ? seconds(given.lockAfter, 600) : 0,
            lockedScreenOffAfter: seconds(given.lockedScreenOffTimeout, 60),
            defaultWay: defaultWay,
            perMonitor: perMonitor,
            ways: resolved,
            canPowerOff: power,
            commands: flag(given.screensaverCommands, false),
            monitors: ids
        };
    }

    // The facts at the start: somebody is here, nothing is shown. `now`: monotonic ms.
    function initial(now) {
        return {
            inputIdle: false,        // no input for baseTime (inhibitors ignored)
            awayIdle: false,         // the same, Wayland idle inhibitors respected
            idleSince: now,          // monotonic ms of the last input (moved at a release, a wake)
            busInhibitors: 0,        // org.freedesktop.ScreenSaver inhibits held
            logindIdleBlock: false,  // true, false or "unknown" (a failed read)
            locked: false,
            lockQuietSince: now,     // the later of the lock and the last input at the lock screen
            lockedDark: false,       // the lock screen's own screen-off reached
            sleeping: false,
            forced: false,           // the screensaver asked for (IPC, SetActive(true))
            lockedThisPeriod: false, // the idle lock asked once (or locked) in this idle period
            stage: 0,                // 0 none, 1 screensaver, 2 screens off: reached in this period
            commandStarted: false,   // the start command ran in this period
            active: false,           // reported as ActiveChanged
            lockBlack: false,        // the lock surface drawn plain black
            shown: ({}),             // monitor id → "on" | "saver" | "off": what is in place
            power: ({})              // monitor id → "on" | "off" | "unknown": as last read
        };
    }

    // ---- Queries (pure, from a state, a config and the time) ----

    function _counting(state) {
        return state.inputIdle || state.forced;
    }

    // An inhibitor holds the next stage: only while unlocked, never against a forced start
    function held(state) {
        if (state.locked || state.forced)
            return false;
        return (state.inputIdle && !state.awayIdle) || state.busInhibitors > 0 || state.logindIdleBlock === true;
    }

    function _enabled(stage, state, config) {
        if (stage === 1)
            return config.saverAfter > 0 || state.forced;
        if (stage === 2)
            return config.screenOffAfter > 0;
        return true;
    }

    // The stage idle has reached now: what was reached stays unless switched off; held,
    // nothing further; else from the time since the last input
    function stage(state, config, now) {
        if (state.sleeping)
            return state.stage;
        let reached = state.stage;
        while (reached > 0 && !_enabled(reached, state, config))
            reached--;
        if (held(state) || !_counting(state))
            return reached;
        const idleFor = now - state.idleSince;
        let timeline = state.forced ? 1 : 0;
        if (config.saverAfter > 0 && idleFor >= config.saverAfter * 1000)
            timeline = 1;
        if (config.screenOffAfter > 0 && idleFor >= config.screenOffAfter * 1000)
            timeline = 2;
        return Math.max(reached, timeline);
    }

    // The lock screen's own screen-off: no input at the lock for its time (inhibitors ignored)
    function lockedDark(state, config, now) {
        if (state.sleeping)
            return state.lockedDark;
        return state.locked && state.inputIdle && config.lockedScreenOffAfter > 0
            && now - state.lockQuietSince >= config.lockedScreenOffAfter * 1000;
    }

    // → { monitorId: "on" | "saver" | "off" } for every connected monitor. Sleeping: the
    // picture in place stays.
    function wanted(state, config, now) {
        const result = {};
        if (state.sleeping) {
            for (const id of config.monitors)
                result[id] = state.shown[id] ?? "on";
            return result;
        }
        const reached = stage(state, config, now);
        const dark = lockedDark(state, config, now) && config.canPowerOff;
        for (const id of config.monitors) {
            if (dark || reached === 2)
                result[id] = "off";
            else if (reached === 1)
                result[id] = config.ways[id] === "off" ? "off" : "saver";
            else
                result[id] = "on";
        }
        return result;
    }

    // The lock surface goes plain black at the lock screen's screen-off while any monitor is
    // not known to be off: no power control, a cut that failed, a power read that failed
    function lockBlack(state, config, now) {
        if (!lockedDark(state, config, now))
            return false;
        return config.monitors.some(id => state.power[id] !== "off");
    }

    // The idle lock is due: once per idle period, unlocked, not held, from the last input
    function lockDue(state, config, now) {
        if (state.sleeping || state.locked || state.lockedThisPeriod || config.lockAfter <= 0)
            return false;
        if (held(state) || !_counting(state))
            return false;
        return now - state.idleSince >= config.lockAfter * 1000;
    }

    // → the next moment `wanted`, `lockDue` or `lockBlack` changes (monotonic ms, never
    // before `now`), or −1. Idle runs one Timer to it.
    function nextDeadline(state, config, now) {
        if (state.sleeping)
            return -1;
        const due = [];
        if (_counting(state) && !held(state)) {
            if (config.saverAfter > 0 && state.stage < 1)
                due.push(state.idleSince + config.saverAfter * 1000);
            if (config.screenOffAfter > 0 && state.stage < 2)
                due.push(state.idleSince + config.screenOffAfter * 1000);
            if (config.lockAfter > 0 && !state.locked && !state.lockedThisPeriod)
                due.push(state.idleSince + config.lockAfter * 1000);
        }
        if (state.locked && state.inputIdle && config.lockedScreenOffAfter > 0 && !state.lockedDark)
            due.push(state.lockQuietSince + config.lockedScreenOffAfter * 1000);
        if (!state.locked && state.logindIdleBlock === true)
            due.push(now + logindRecheck);
        return due.length === 0 ? -1 : Math.max(now, Math.min(...due));
    }

    // ---- The step ----

    function _copy(state) {
        const next = Object.assign({}, state);
        next.shown = Object.assign({}, state.shown);
        next.power = Object.assign({}, state.power);
        return next;
    }

    // Input (or what counts as input): a new idle period
    function _wake(next, now, actions) {
        next.idleSince = now;
        next.stage = 0;
        next.forced = false;
        next.lockedThisPeriod = next.locked;
        next.lockedDark = false;
        if (next.locked)
            next.lockQuietSince = now;
        if (next.commandStarted) {
            actions.push({ type: "endCommand" });
            next.commandStarted = false;
        }
    }

    // An inhibitor released while unlocked: the counting starts at the release
    function _released(next, at) {
        if (!next.locked && !next.forced && next.inputIdle)
            next.idleSince = Math.max(next.idleSince, at);
    }

    function _since(event, now) {
        const since = Number(event.since);
        return event.since !== undefined && isFinite(since) ? Math.min(since, now) : now - baseTime;
    }

    // `event`: { type, … } — inputIdle { idle, since? }, awayIdle { idle, since? },
    // busInhibitors { count }, logindIdleBlock { held: true | false | "unknown" }, power
    // { power: { id: "on" | "off" | other } }, deadline, config, monitors, locked,
    // unlocked, sleep, resumed, force, activity. `config`: from config() — passed at every
    // step, so a changed profile or monitor list is the "config"/"monitors" event with the
    // new one. → { state, actions, ignored }. Actions, in this order: powerOn { ids },
    // hideSaver { ids }, showSaver { ids } (a surface for every monitor leaving "on", also
    // one going off: it takes the keys), powerOff { ids }, endCommand, startCommand, lock,
    // active { active }, lockBlack { black }.
    function step(state, event, config, now) {
        const next = _copy(state);
        const actions = [];
        let wake = false;
        switch (event?.type) {
        case "inputIdle":
            if (event.idle === true) {
                if (!next.inputIdle) {
                    next.inputIdle = true;
                    const since = _since(event, now);
                    if (!next.forced)
                        next.idleSince = since;
                    if (next.locked)
                        next.lockQuietSince = Math.max(next.lockQuietSince, since);
                }
            } else if (next.inputIdle) {
                next.inputIdle = false;
                wake = true;
            }
            break;
        case "awayIdle": {
            const away = event.idle === true;
            // A Wayland inhibitor released: away-idle comes baseTime after the release
            if (away && !next.awayIdle)
                _released(next, _since(event, now));
            next.awayIdle = away;
            break;
        }
        case "busInhibitors": {
            const count = Math.max(0, Math.floor(Number(event.count)) || 0);
            if (next.busInhibitors > 0 && count === 0)
                _released(next, now);
            next.busInhibitors = count;
            break;
        }
        case "logindIdleBlock": {
            const value = event.held === true ? true : event.held === false ? false : "unknown";
            if (next.logindIdleBlock === true && value !== true)
                _released(next, now);
            next.logindIdleBlock = value;
            break;
        }
        case "power": {
            const read = event.power ?? {};
            next.power = {};
            for (const id of Object.keys(read))
                next.power[id] = read[id] === "on" || read[id] === "off" ? read[id] : "unknown";
            break;
        }
        case "deadline":
        case "config":
        case "monitors":
            break;
        case "locked":
            if (!next.locked) {
                next.locked = true;
                next.lockQuietSince = now;
                next.lockedThisPeriod = true;
            }
            break;
        case "unlocked":
            if (next.locked) {
                next.locked = false;
                wake = true;
            }
            break;
        case "sleep":
            next.sleeping = true;
            break;
        case "resumed":
            next.sleeping = false;
            wake = true;
            break;
        case "force":
            next.forced = true;
            next.idleSince = now - config.saverAfter * 1000;
            break;
        case "activity":
            wake = true;
            break;
        default:
            return { state: state, actions: [], ignored: "unknown event" };
        }
        // Input while going to sleep is the hand that closed the lid: the resume wakes
        if (wake && !next.sleeping)
            _wake(next, now, actions);
        _reconcile(next, config, now, actions);
        return { state: next, actions: actions, ignored: "" };
    }

    function _reconcile(next, config, now, actions) {
        // Unplugged monitors leave without an action
        for (const id of Object.keys(next.shown)) {
            if (!config.monitors.includes(id))
                delete next.shown[id];
        }
        for (const id of Object.keys(next.power)) {
            if (!config.monitors.includes(id))
                delete next.power[id];
        }
        next.stage = stage(next, config, now);
        next.lockedDark = lockedDark(next, config, now);
        const want = wanted(next, config, now);

        const powerOn = [], hide = [], show = [], powerOff = [];
        for (const id of config.monitors) {
            const from = next.shown[id] ?? "on";
            const to = want[id];
            if (from === "off" && to !== "off")
                powerOn.push(id);
            if (from !== "on" && to === "on")
                hide.push(id);
            if (from === "on" && to !== "on")
                show.push(id);
            if (from !== "off" && to === "off")
                powerOff.push(id);
        }
        // endCommand, from a wake, was pushed first; keep it after the pictures
        const early = actions.splice(0, actions.length);
        if (powerOn.length > 0)
            actions.push({ type: "powerOn", ids: powerOn });
        if (hide.length > 0)
            actions.push({ type: "hideSaver", ids: hide });
        if (show.length > 0)
            actions.push({ type: "showSaver", ids: show });
        if (powerOff.length > 0)
            actions.push({ type: "powerOff", ids: powerOff });
        actions.push(...early);
        next.shown = want;

        if (next.stage >= 1 && !next.commandStarted && config.commands) {
            actions.push({ type: "startCommand" });
            next.commandStarted = true;
        }
        if (lockDue(next, config, now)) {
            actions.push({ type: "lock" });
            next.lockedThisPeriod = true;
        }
        const active = next.locked || config.monitors.some(id => want[id] !== "on");
        if (active !== next.active) {
            actions.push({ type: "active", active: active });
            next.active = active;
        }
        const black = lockBlack(next, config, now);
        if (black !== next.lockBlack) {
            actions.push({ type: "lockBlack", black: black });
            next.lockBlack = black;
        }
    }
}
