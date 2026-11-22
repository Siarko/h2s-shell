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
// All idle times count from the last input, one clock for every monitor (input on any
// monitor is input for all):
//
//   last input ── saverAfter ── screenOffAfter ──┬── lockAfter (one for the session)
//                 (stage 1)     (stage 2)        │
//                 each monitor its own times, or the default's ("Set per monitor")
//   locked ── lockedScreenOffAfter, from the lock or the last input at the lock screen
//
// Each monitor has the same two stages, each switched on or off with its own time: the OLED
// with the screensaver off and screens off after 5 min is a monitor that goes straight to
// off. Without power control a monitor's screen-off is the black screensaver at that time.
//
// A stage reached stays until input, per monitor — an inhibitor arriving, a profile with
// longer times — unless the profile switches it off (a screensaver turned off is hidden, without the end
// command: the user is still away). Inhibitors (Wayland, the screensaver bus interface,
// logind's idle block) hold the next stage while unlocked and are ignored while locked; a
// released inhibitor restarts the counting at its release; an inhibitor holds every
// monitor (none says which monitor it is for). Locking never turns a monitor on; only
// input does. The commands and `active` start once every monitor with a stage on has gone
// dark; a monitor with both stages off is not waited for.
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
    // An idle lock asked for and not taken (no `locked` came: refused, the compositor busy)
    // is asked again while it is due, after a growing pause (ms)
    readonly property var lockRetry: ({ minimum: 5000, maximum: 300000 })
    // A monitor that vanished while dark and is back within this long (ms) is the same
    // monitor coming back (a monitor that drops off and reconnects on its own), not one
    // plugged in; one the shell powered off is that whenever it comes back in the period
    readonly property int replugWindow: 15000
    // A power action the reading after it does not show (the monitor still on after an off,
    // still off after an on) is asked again after a growing pause (ms)
    readonly property var powerRetry: ({ minimum: 2000, maximum: 300000, tries: 8 })

    // The profile's values, by their names in the "lockscreen" group, normalised.
    // `values`: { screensaverEnabled, screensaverTimeout, screenOffEnabled, screenOffTimeout,
    // lockscreenEnabled, lockAfter, lockedScreenOffTimeout, perMonitor, monitorIdle
    // ({ monitorId: { screensaverEnabled, screensaverTimeout, screenOffEnabled,
    // screenOffTimeout } }), screensaverCommands } — times in seconds; `monitors`: the
    // connected monitors' ids (make|model|serial, MonitorRules) or objects with an `id` — as
    // read ({ id, base, connector }), a monitor's entry is found under either form of its key
    // (MonitorRules.overrideFor); `canPowerOff`: a backend can cut a monitor's power. → the
    // config every other function takes: times in seconds, 0 = never; `saverAfter` and
    // `screenOffAfter` the default's, `times` per connected monitor ({ saverAfter,
    // screenOffAfter }: its entry in `monitorIdle` while `perMonitor` is on, else the
    // default's). A screen-off without power control stays a stage: the screensaver at its
    // time (wanted).
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
        // A source's two stages (the profile's own values, or a monitor's entry with the
        // default's values for a field it lacks)
        const stages = (source, fallback) => ({
            saverAfter: flag(source.screensaverEnabled, fallback.screensaverEnabled)
                ? seconds(source.screensaverTimeout, fallback.screensaverTimeout) : 0,
            screenOffAfter: flag(source.screenOffEnabled, fallback.screenOffEnabled)
                ? seconds(source.screenOffTimeout, fallback.screenOffTimeout) : 0
        });
        const own = {
            screensaverEnabled: flag(given.screensaverEnabled, false),
            screensaverTimeout: seconds(given.screensaverTimeout, 300),
            screenOffEnabled: flag(given.screenOffEnabled, false),
            screenOffTimeout: seconds(given.screenOffTimeout, 600)
        };
        const defaults = stages(own, own);
        const ids = [];
        // Each id's monitor as given, for its entry under either form of its key
        const byId = {};
        // Two connected monitors with one id (MonitorRules should have told them apart):
        // kept once, and reported, not merged silently
        const duplicates = [];
        for (const monitor of monitors ?? []) {
            const id = typeof monitor === "string" ? monitor : monitor?.id;
            if (typeof id !== "string" || id === "")
                continue;
            if (!ids.includes(id)) {
                ids.push(id);
                byId[id] = monitor;
            } else if (!duplicates.includes(id)) {
                duplicates.push(id);
            }
        }
        const perMonitor = flag(given.perMonitor, false);
        const entries = perMonitor && _isMap(given.monitorIdle) ? given.monitorIdle : {};
        const times = {};
        // Every key a monitor may have had (MonitorRules.overrideKeys): a monitor coming back
        // under the other form of its id is still the one that went
        const keys = {};
        for (const id of ids) {
            keys[id] = MonitorRules.overrideKeys(byId[id]);
            const entry = MonitorRules.overrideFor(entries, byId[id], monitors);
            times[id] = _isMap(entry) ? stages(entry, own) : Object.assign({}, defaults);
        }
        return {
            saverAfter: defaults.saverAfter,
            screenOffAfter: defaults.screenOffAfter,
            lockAfter: flag(given.lockscreenEnabled, false) ? seconds(given.lockAfter, 600) : 0,
            lockedScreenOffAfter: seconds(given.lockedScreenOffTimeout, 60),
            perMonitor: perMonitor,
            times: times,
            keys: keys,
            canPowerOff: power,
            commands: flag(given.screensaverCommands, false),
            monitors: ids,
            duplicates: duplicates
        };
    }

    function _isMap(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    // A monitor's own times as `monitorIdle` keeps them: its two switches and their times
    // (seconds, within the range of the default's settings — SettingsSchema's
    // screensaverTimeout and screenOffTimeout)
    readonly property var monitorTimeRange: ({ minimum: 5, maximum: 86400 })

    // At most this many entries in `monitorIdle` (connected or not): a new one beyond it is
    // refused; changing or dropping one is always possible
    readonly property int maxMonitorEntries: 32

    // A monitor's times as given (the IPC, the page) → the entry kept, or null when not
    // understood: { screensaverEnabled, screenOffEnabled } booleans, { screensaverTimeout,
    // screenOffTimeout } whole seconds within monitorTimeRange — all four, nothing else
    function monitorTimes(times) {
        if (!_isMap(times))
            return null;
        const fields = ["screensaverEnabled", "screensaverTimeout", "screenOffEnabled", "screenOffTimeout"];
        if (Object.keys(times).some(key => !fields.includes(key)))
            return null;
        const time = value => typeof value === "number" && Number.isInteger(value)
            && value >= monitorTimeRange.minimum && value <= monitorTimeRange.maximum;
        if (typeof times.screensaverEnabled !== "boolean" || typeof times.screenOffEnabled !== "boolean"
                || !time(times.screensaverTimeout) || !time(times.screenOffTimeout))
            return null;
        return {
            screensaverEnabled: times.screensaverEnabled,
            screensaverTimeout: times.screensaverTimeout,
            screenOffEnabled: times.screenOffEnabled,
            screenOffTimeout: times.screenOffTimeout
        };
    }

    // The per-monitor map with one monitor's times set: `map` the current `monitorIdle`;
    // `monitor` a connected monitor as read ({ id, base, connector }: its entry is written
    // under its id, and the other form of its key — the plain `base` of a twin, or a twin's
    // `base|connector` of one alone — dropped, and the one it matches loosely,
    // MonitorRules.looseKey, never another `connected` monitor's key) or a MonitorRules id
    // (a monitor not connected: that key only); `times` its own times (monitorTimes) or
    // "default" — the entry dropped, the monitor follows the default. The other monitors'
    // entries are kept as they are. → the new map, or null when the id or the times are not
    // understood, or a new entry would pass `maxMonitorEntries` (nothing written).
    function withMonitorTimes(map, monitor, times, connected) {
        const id = typeof monitor === "string" ? monitor : monitor?.id;
        if (!MonitorRules.validId(id))
            return null;
        const entry = times === "default" ? null : monitorTimes(times);
        if (times !== "default" && entry === null)
            return null;
        const given = _isMap(map) ? map : {};
        const keys = typeof monitor === "string" ? [id] : MonitorRules.overrideMatches(given, monitor, connected);
        const result = {};
        for (const key of Object.keys(given)) {
            if (!keys.includes(key))
                result[key] = given[key];
        }
        const isNew = !keys.some(key => key in given);
        if (entry !== null) {
            if (isNew && Object.keys(result).length >= maxMonitorEntries)
                return null;
            result[id] = entry;
        }
        return result;
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
            forcedAt: null,          // monotonic ms it was asked for
            dark: false,             // every monitor that goes dark has, in this period (allDark)
            lockedThisPeriod: false, // locked in this idle period: the idle lock is not asked again
            lockAsks: 0,             // the idle lock asked this many times in this period, not taken
            lockAskedAt: -1,         // monotonic ms of the last ask, -1 none
            lockSince: null,         // a profile switch made the lock due: it counts from then (ms)
            lockAfterSeen: null,     // the config's lockAfter at the last step (null: none yet)
            stage: ({}),             // monitor id → 0 none, 1 screensaver, 2 screens off: reached in this period
            commandStarted: false,   // the start command ran in this period
            active: false,           // reported as ActiveChanged
            lockBlack: false,        // the lock surface drawn plain black
            lockAttended: false,     // somebody at the lock screen (the prompt awake, a check under way)
            shown: ({}),             // monitor id → "on" | "saver" | "off": what is in place
            power: ({}),             // monitor id → "on" | "off" | "unknown": as last read
            // monitor id → { on, at, tries, read, gaveUp }: a power action not yet seen in a
            // reading (`read`: what a reading since the last ask said, null for none yet;
            // `gaveUp`: asked powerRetry.tries times, not asked again — kept until a reading
            // shows it, so a monitor left off stays remembered)
            pendingPower: ({}),
            connected: null,         // the monitor ids at the last step (null: no step yet)
            // monitor id → { at, stage, shellOff }: monitors that vanished while dark in this
            // period — one back in time is not a plug-in (replugWindow)
            gone: ({})
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

    // A monitor's times: its own, or the default's for one config does not list
    function _timesOf(config, id) {
        return config.times?.[id] ?? { saverAfter: config.saverAfter, screenOffAfter: config.screenOffAfter };
    }

    // A monitor's stage 1 is on: its screensaver, or the screensaver forced
    function _saverOn(times, state) {
        return times.saverAfter > 0 || state.forced;
    }

    // A monitor's stage 2 is on: its screen-off
    function _offOn(times) {
        return times.screenOffAfter > 0;
    }

    // A monitor goes dark at some point: a stage of its own on (or the screensaver forced)
    function _goesDark(times, state) {
        return _saverOn(times, state) || _offOn(times);
    }

    // The stage one monitor has reached now: what was reached stays unless switched off;
    // held, nothing further; else from the time since the last input, on its own times
    function _monitorStage(state, config, id, now) {
        let reached = state.stage[id] ?? 0;
        if (state.sleeping)
            return reached;
        const times = _timesOf(config, id);
        if (reached === 2 && !_offOn(times))
            reached = 1;
        if (reached === 1 && !_saverOn(times, state))
            reached = 0;
        if (held(state) || !_counting(state))
            return reached;
        let timeline = 0;
        if (state.forced) {
            timeline = 1;
            if (_offOn(times) && now - state.forcedAt >= _forcedOffAfter(times) * 1000)
                timeline = 2;
        } else {
            const idleFor = now - state.idleSince;
            if (times.saverAfter > 0 && idleFor >= times.saverAfter * 1000)
                timeline = 1;
            if (times.screenOffAfter > 0 && idleFor >= times.screenOffAfter * 1000)
                timeline = 2;
        }
        return Math.max(reached, timeline);
    }

    // A forced screensaver shows on every monitor; a monitor's screen-off then comes as long
    // after it as it would after its own screensaver (seconds) — after its whole time where
    // it has no screensaver before the screen-off — never at once
    function _forcedOffAfter(times) {
        return times.saverAfter < times.screenOffAfter ? times.screenOffAfter - times.saverAfter : times.screenOffAfter;
    }

    // → { monitorId: 0 | 1 | 2 } for every connected monitor: the stage each has reached now
    function stage(state, config, now) {
        const result = {};
        for (const id of config.monitors)
            result[id] = _monitorStage(state, config, id, now);
        return result;
    }

    // Every monitor that goes dark has reached its first stage (a monitor with both stages
    // off is not waited for; with none going dark, never): the moment of the commands and
    // of `active`. `reached`: stage()'s answer
    function allDark(state, config, reached) {
        const waited = config.monitors.filter(id => _goesDark(_timesOf(config, id), state));
        return waited.length > 0 && waited.every(id => reached[id] >= 1);
    }

    // The lock screen's own screen-off: no input at the lock for its time (inhibitors ignored)
    // Somebody at the lock screen (`lockAttended`) holds it from starting; once reached, only
    // input undoes it — a check starting under a dark screen turns nothing on
    function lockedDark(state, config, now) {
        if (state.sleeping)
            return state.lockedDark;
        if (!(state.locked && state.inputIdle && config.lockedScreenOffAfter > 0))
            return false;
        if (state.lockedDark)
            return true;
        return !state.lockAttended && now - state.lockQuietSince >= config.lockedScreenOffAfter * 1000;
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
            if (dark || (reached[id] === 2 && config.canPowerOff))
                result[id] = "off";
            else if (reached[id] >= 1)
                result[id] = "saver";
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

    // Where the idle lock counts from: the last input, or a later profile switch that made it
    // due (a switch never locks at once)
    function _lockStart(state) {
        return state.lockSince === null ? state.idleSince : Math.max(state.idleSince, state.lockSince);
    }

    // The pause before asking for the idle lock again after `asks` asks not taken
    // The pause before a power action is asked again after `tries` asks the readings did
    // not show
    function powerRetryDelay(tries) {
        if (tries <= 0)
            return 0;
        return Math.min(powerRetry.maximum, powerRetry.minimum * Math.pow(2, tries - 1));
    }

    // When a pending power action is asked again, or -1: only once a reading since the last
    // ask said otherwise
    function _powerRetryAt(pending) {
        if (pending.gaveUp === true || pending.read === null || pending.read === (pending.on ? "on" : "off"))
            return -1;
        return pending.at + powerRetryDelay(pending.tries);
    }

    // The monitors the shell has turned off and not yet seen on again: what a restarted shell
    // must turn back on (Idle remembers them), and nothing else — a monitor another program
    // turned off is never touched
    function turnedOff(state) {
        const ids = Object.keys(state.shown).filter(id => state.shown[id] === "off");
        for (const id of Object.keys(state.pendingPower)) {
            if (!ids.includes(id))
                ids.push(id);
        }
        return ids.sort();
    }

    // At the start: of the monitors a previous run turned off (`remembered`), those connected
    // and read as off — to turn on again (the `restore` event). `monitors`: [{ id, power }]
    function restoreOnStart(remembered, monitors) {
        const ids = Array.isArray(remembered) ? remembered.map(String) : [];
        return (monitors ?? []).filter(monitor => ids.includes(monitor?.id) && monitor.power === "off")
            .map(monitor => monitor.id);
    }

    function lockRetryDelay(asks) {
        if (asks <= 0)
            return 0;
        return Math.min(lockRetry.maximum, lockRetry.minimum * Math.pow(2, asks - 1));
    }

    // When the idle lock is next due (monotonic ms), or -1: from where it counts, and after an
    // ask not taken, the retry pause
    function _lockAt(state, lockAfter) {
        if (state.sleeping || state.locked || state.lockedThisPeriod || lockAfter <= 0)
            return -1;
        if (held(state) || !_counting(state))
            return -1;
        const due = _lockStart(state) + lockAfter * 1000;
        return state.lockAskedAt < 0 ? due : Math.max(due, state.lockAskedAt + lockRetryDelay(state.lockAsks));
    }

    // The idle lock is due: unlocked, not locked yet in this idle period, not held, from the
    // last input (or a profile switch that made it due), and asked again only after the pause
    function lockDue(state, config, now) {
        const at = _lockAt(state, config.lockAfter);
        return at >= 0 && now >= at;
    }

    // logind's idle block is read before it matters, not on a clock (logind sends no signal
    // when one appears): unlocked and not forced, when a stage or the idle lock is due now,
    // and while a block holds (its re-read, logindRecheck). Idle reads, steps the answer
    // (logindIdleBlock), then the deadline.
    function logindReadDue(state, config, now) {
        if (state.sleeping || state.locked || state.forced)
            return false;
        if (state.logindIdleBlock === true)
            return true;
        const reached = stage(state, config, now);
        return config.monitors.some(id => reached[id] > (state.stage[id] ?? 0)) || lockDue(state, config, now);
    }

    // → the next moment `wanted`, `lockDue` or `lockBlack` changes (monotonic ms, never
    // before `now`), or −1. Idle runs one Timer to it.
    function nextDeadline(state, config, now) {
        if (state.sleeping)
            return -1;
        const due = [];
        if (_counting(state) && !held(state)) {
            for (const id of config.monitors) {
                const times = _timesOf(config, id);
                const reached = state.stage[id] ?? 0;
                if (state.forced) {
                    if (_offOn(times) && reached < 2)
                        due.push(state.forcedAt + _forcedOffAfter(times) * 1000);
                    continue;
                }
                if (times.saverAfter > 0 && reached < 1)
                    due.push(state.idleSince + times.saverAfter * 1000);
                if (times.screenOffAfter > 0 && reached < 2)
                    due.push(state.idleSince + times.screenOffAfter * 1000);
            }
        }
        const lockAt = _lockAt(state, config.lockAfter);
        if (lockAt >= 0)
            due.push(lockAt);
        if (state.locked && state.inputIdle && !state.lockAttended && config.lockedScreenOffAfter > 0 && !state.lockedDark)
            due.push(state.lockQuietSince + config.lockedScreenOffAfter * 1000);
        if (!state.locked && state.logindIdleBlock === true)
            due.push(now + logindRecheck);
        for (const id of Object.keys(state.pendingPower)) {
            const at = _powerRetryAt(state.pendingPower[id]);
            if (at >= 0)
                due.push(at);
        }
        return due.length === 0 ? -1 : Math.max(now, Math.min(...due));
    }

    // ---- The step ----

    function _copy(state) {
        const next = Object.assign({}, state);
        next.shown = Object.assign({}, state.shown);
        next.stage = Object.assign({}, state.stage);
        next.gone = {};
        for (const id of Object.keys(state.gone ?? {}))
            next.gone[id] = Object.assign({}, state.gone[id]);
        next.power = Object.assign({}, state.power);
        next.pendingPower = {};
        for (const id of Object.keys(state.pendingPower ?? {}))
            next.pendingPower[id] = Object.assign({}, state.pendingPower[id]);
        return next;
    }

    // Input (or what counts as input): a new idle period
    function _wake(next, now, actions) {
        next.idleSince = now;
        next.stage = {};
        next.forced = false;
        next.dark = false;
        next.gone = {};
        next.lockedThisPeriod = next.locked;
        next.lockAsks = 0;
        next.lockAskedAt = -1;
        next.lockSince = null;
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

    // Whether an app's SetActive(true) (the busForce event) starts the screensaver now: not
    // while locked, not while going to sleep. Its answer to the app is this
    function busForceTakes(state) {
        return state.locked !== true && state.sleeping !== true;
    }

    function _since(event, now) {
        const since = Number(event.since);
        return event.since !== undefined && isFinite(since) ? Math.min(since, now) : now - baseTime;
    }

    // `event`: { type, … } — inputIdle { idle, since? }, awayIdle { idle, since? },
    // busInhibitors { count }, logindIdleBlock { held: true | false | "unknown" }, power
    // { power: { id: "on" | "off" | other } }, deadline, config, monitors, locked,
    // unlocked, sleep, resumed, force (IPC), busForce (D-Bus SetActive(true): as force, never
    // while locked or going to sleep — busForceTakes), activity (D-Bus SimulateUserActivity, and input on a
    // forced screensaver's surface: before baseTime has passed no inputIdle(true) came, so
    // no inputIdle(false) will — the surface sends `activity`; ignored while locked, where
    // video players send it every ~30 s), lockAttended { attended } (somebody at the lock
    // screen: the prompt awake, a check under way — its screen-off waits), restore { ids }
    // (monitors a previous run turned off: turned on, pending like any power-on). `config`: from config() — passed at every
    // step, so a changed profile or monitor list is the "config"/"monitors" event with the
    // new one. → { state, actions, ignored }. Actions, in this order: powerOn { ids },
    // hideSaver { ids }, showSaver { ids } (a surface for every monitor leaving "on", also
    // one going off: it takes the keys), powerOff { ids }, endCommand, startCommand, power
    // actions asked again { ids: [id], attempt } (a reading since the last ask showed the
    // monitor otherwise; a `restore`'s first with `restore: true`, first of all), powerGaveUp
    // { ids, on } (asked powerRetry.tries times: not asked again), lock, active { active },
    // lockBlack { black }. The start command comes, and `active` turns true unlocked, once
    // every monitor that goes dark has (allDark).
    function step(state, event, config, now) {
        const next = _copy(state);
        const actions = [];
        let wake = false;
        let restored = [];
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
            // A pending action seen done is over; otherwise the reading is kept for its retry
            for (const id of Object.keys(next.pendingPower)) {
                const pending = next.pendingPower[id];
                if (!(id in next.power))
                    continue;
                if (next.power[id] === (pending.on ? "on" : "off"))
                    delete next.pendingPower[id];
                else
                    pending.read = next.power[id];
            }
            break;
        }
        case "lockAttended":
            next.lockAttended = event.attended === true;
            break;
        case "restore": {
            // Monitors a previous run turned off: turned on as any power-on, pending until a
            // reading shows them on (and asked again meanwhile); not one this run wants off
            const ids = (Array.isArray(event.ids) ? event.ids : [])
                .filter(id => config.monitors.includes(id) && next.shown[id] !== "off");
            for (const id of ids)
                next.pendingPower[id] = { on: true, at: now, tries: 1, read: null, gaveUp: false };
            if (ids.length > 0)
                restored = ids;
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
                next.lockAsks = 0;
                next.lockAskedAt = -1;
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
            next.forcedAt = now;
            next.idleSince = now - config.saverAfter * 1000;
            break;
        case "busForce":
            // An app's SetActive(true): only where it takes (busForceTakes); locked, the lock
            // screen's own stages apply and no app starts the screensaver's
            if (busForceTakes(next)) {
                next.forced = true;
                next.forcedAt = now;
                next.idleSince = now - config.saverAfter * 1000;
            }
            break;
        case "activity":
            // Locked: only real input at the lock screen wakes (players keep sending it)
            if (!next.locked)
                wake = true;
            break;
        default:
            return { state: state, actions: [], ignored: "unknown event" };
        }
        if (_pluggedIn(next, config, now))
            wake = true;
        // Input while going to sleep is the hand that closed the lid: the resume wakes
        if (wake && !next.sleeping)
            _wake(next, now, actions);
        _reconcile(next, config, now, actions);
        if (restored.length > 0)
            actions.unshift({ type: "powerOn", ids: restored, restore: true });
        return { state: next, actions: actions, ignored: "" };
    }

    // The monitors that came and went since the last step: a monitor plugged in is somebody
    // at the computer, as input (a new idle period; locked, the lock stays). Not a plug-in:
    // the first step, a change while going to sleep (the resume wakes), and a monitor that
    // vanished while dark in this period and is back — powered off by the shell (some
    // monitors drop off when their power is cut and reconnect), or within replugWindow —
    // which takes back the stage it had. Vanished while dark: remembered for that (`gone`).
    function _pluggedIn(next, config, now) {
        const before = next.connected;
        next.connected = config.monitors.slice();
        if (before === null)
            return false;
        for (const id of before) {
            if (config.monitors.includes(id))
                continue;
            const shown = next.shown[id] ?? "on";
            if (shown !== "on")
                next.gone[id] = { at: now, stage: next.stage[id], shellOff: shown === "off" };
        }
        let plugged = false;
        for (const id of config.monitors) {
            if (before.includes(id))
                continue;
            const key = (config.keys?.[id] ?? [id]).find(candidate => candidate in next.gone);
            const back = key !== undefined ? next.gone[key] : null;
            if (back !== null && (back.shellOff || now - back.at <= replugWindow)) {
                next.stage[id] = back.stage;
                delete next.gone[key];
            } else if (!next.sleeping) {
                plugged = true;
            }
        }
        return plugged;
    }

    function _reconcile(next, config, now, actions) {
        // A changed "Lock after" (a profile switch, the setting) that makes the idle lock due
        // when it was not: it counts from the switch, never locks at once
        if (next.lockAfterSeen !== null && next.lockAfterSeen !== config.lockAfter) {
            const before = _lockAt(next, next.lockAfterSeen);
            const after = _lockAt(next, config.lockAfter);
            if (after >= 0 && after <= now && !(before >= 0 && before <= now))
                next.lockSince = now;
        }
        next.lockAfterSeen = config.lockAfter;
        // Unplugged monitors leave without an action
        for (const id of Object.keys(next.shown)) {
            if (!config.monitors.includes(id))
                delete next.shown[id];
        }
        for (const id of Object.keys(next.power)) {
            if (!config.monitors.includes(id))
                delete next.power[id];
        }

        for (const id of Object.keys(next.pendingPower)) {
            if (!config.monitors.includes(id))
                delete next.pendingPower[id];
        }
        // Only connected monitors keep a stage: one plugged in again starts from the clock
        next.stage = stage(next, config, now);
        next.lockedDark = lockedDark(next, config, now);
        const want = wanted(next, config, now);

        const powerOn = [], hide = [], show = [], powerOff = [];
        for (const id of config.monitors) {
            const from = next.shown[id] ?? "on";
            const to = want[id];
            if (from === "off" && to !== "off")
                powerOn.push(id);
            // The shell changes its power: an earlier read no longer says what it is
            if ((from === "off") !== (to === "off"))
                next.power[id] = "unknown";
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
        for (const id of powerOn)
            next.pendingPower[id] = { on: true, at: now, tries: 1, read: null, gaveUp: false };
        for (const id of powerOff)
            next.pendingPower[id] = { on: false, at: now, tries: 1, read: null, gaveUp: false };
        // Power actions the readings did not show: asked again, after their pause
        // (`attempt`: Idle logs the first ask again)
        if (!next.sleeping) {
            for (const id of Object.keys(next.pendingPower)) {
                const pending = next.pendingPower[id];
                const at = _powerRetryAt(pending);
                if (at < 0 || now < at)
                    continue;
                // Asked often enough: given up, said once (Idle logs it)
                if (pending.tries >= powerRetry.tries) {
                    pending.gaveUp = true;
                    actions.push({ type: "powerGaveUp", ids: [id], on: pending.on });
                    continue;
                }
                pending.tries += 1;
                pending.at = now;
                pending.read = null;
                actions.push({ type: pending.on ? "powerOn" : "powerOff", ids: [id], attempt: pending.tries });
            }
        }

        // Once every monitor that goes dark has, the period stays dark until input, or until
        // no monitor goes dark any more (every stage switched off): a monitor given a stage
        // later, or plugged back, does not take it back
        if (allDark(next, config, next.stage))
            next.dark = true;
        else if (!config.monitors.some(id => _goesDark(_timesOf(config, id), next)))
            next.dark = false;
        const dark = next.dark;
        if (dark && !next.commandStarted && config.commands) {
            actions.push({ type: "startCommand" });
            next.commandStarted = true;
        }
        if (lockDue(next, config, now)) {
            next.lockAsks++;
            next.lockAskedAt = now;
            // `attempt`: 1 the first ask, more for an ask again (Idle logs the first of those)
            actions.push({ type: "lock", attempt: next.lockAsks });
        }
        const active = next.locked || dark;
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
