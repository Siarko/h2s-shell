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
//   last input ── saverAfter ── screenOffAfter ──┬── lockAfter ── sleepAfter (one for the
//                 (stage 1)     (stage 2)        │                 session, the whole machine)
//                 each monitor its own times, or the default's ("Set per monitor")
//   locked ── lockedScreenOffAfter, from the lock or the last input at the lock screen
//
// Hibernation is the whole computer's too. With sleep on it is the sleep's: logind's
// SuspendThenHibernate in place of Suspend, the system waking it to hibernate after its own
// delay (sleep.conf's HibernateDelaySec, one per machine — the shell cannot pass one). With
// sleep off it is a stage of its own on the clock (`hibernateAfter`): logind's Hibernate, as
// long after the last stage switched on before it — the latest screensaver of the connected
// monitors or the idle lock, whichever comes later; neither: the last input — as its time
// says (hibernateBase). Only one of the two whole-computer stages is ever on the clock, so
// they share the sleep's rules: asked once per period, held by the apps keeping the screen
// on while unlocked, after a fresh read of logind's inhibitors found no sleep block, an idle
// lock due no later waited for, only on logind's "yes".
//
// Sleep is the whole computer's: logind's Suspend, asked once per idle period, only where
// logind answers CanSuspend "yes" (never on "challenge": no password from a timer). The
// apps keeping the screen on hold it while unlocked, as every stage (after a forced
// screensaver too); logind's own `sleep` block inhibitors (a backup) hold it locked or not —
// read before the call, which goes only after a read found none. An idle lock due
// at or before it is waited for a moment (sleepLockWait), so a sleep the settings lock
// before goes down locked; "Lock before the computer sleeps" locks at logind's
// PrepareForSleep, as for any sleep.
//
// Each monitor has the same two stages, each switched on or off with its own time: the OLED
// with the screensaver off and screens off after 5 min is a monitor that goes straight to
// off. Without power control a monitor's screen-off is the black screensaver at that time.
//
// A stage reached stays until input, per monitor — an inhibitor arriving, a profile with
// longer times — unless the profile switches it off (a screensaver turned off is hidden, without the
// "back" commands: the user is still away). Inhibitors (Wayland, the screensaver bus interface,
// logind's idle block) hold the next stage while unlocked and are ignored while locked; a
// released inhibitor restarts the counting at its release; an inhibitor holds every
// monitor (none says which monitor it is for). Locking never turns a monitor on; only
// input does. `active` starts once every monitor with a stage on has gone dark; a monitor
// with both stages off is not waited for.
//
// The commands are a list of entries, each with its moment and two commands: "go" when the
// moment comes, "back" at its end — screens dark (the monitors it waits for, by default
// every one that goes dark; the end: input), locked (any lock; the end: the unlock), before
// sleep (any sleep; the end: the resume). An entry's "back" runs only after its "go" ran,
// and the "back" that runs is the one of that "go": a profile switched while away (the
// stage switched off, the list another) still runs it at the return.
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
    // plugged in: replugWindow after it vanished showing the screensaver, shellOffWindow
    // after it vanished powered off by the shell (some monitors drop off at their power cut
    // and come back only later); later than that it is plugged in (a re-plug, its own power
    // button pressed by somebody back)
    readonly property int replugWindow: 15000
    readonly property int shellOffWindow: 60000
    // A power action the reading after it does not show (the monitor still on after an off,
    // still off after an on) is asked again after a growing pause (ms)
    readonly property var powerRetry: ({ minimum: 2000, maximum: 300000, tries: 8 })
    // A sleep due while the idle lock, due at or before it, is not taken yet waits for the
    // lock this long (ms) after the lock fell due, then goes ahead
    readonly property int sleepLockWait: 5000
    // A read of logind's inhibitors for the sleep that could not tell (failed, timed out) is
    // made again after a growing pause (ms); the sleep is never asked without a read
    readonly property var sleepReadRetry: ({ minimum: 5000, maximum: 300000 })
    // logind's sleep support (CanSuspend) not read: read again after a growing pause (ms)
    readonly property var supportRetry: ({ minimum: 10000, maximum: 600000 })
    // A screen-off that follows the screensaver waits for its fade in, and this much more
    // (ms): the screensaver's window is mapped and drawn once before the fade starts
    readonly property int saverFadeMargin: 250

    // The profile's values, by their names in the "lockscreen" group, normalised.
    // `values`: { screensaverEnabled, screensaverTimeout, screenOffEnabled, screenOffTimeout,
    // lockscreenEnabled, lockAfter, lockedScreenOffTimeout, perMonitor, monitorIdle
    // ({ monitorId: { screensaverEnabled, screensaverTimeout, screenOffEnabled,
    // screenOffTimeout } }), commandEntries ([{ id, moment, monitors, go, back }]:
    // commandEntries()), sleepEnabled, sleepTimeout, lockOnSleep, hibernateEnabled,
    // hibernateTimeout, fadeInDuration (the screensaver's fade in, ms) } — times in seconds
    // unless said; `monitors`: the
    // connected monitors' ids (make|model|serial, MonitorRules) or objects with an `id` — as
    // read ({ id, base, connector }), a monitor's entry is found under either form of its key
    // (MonitorRules.overrideFor); `canPowerOff`: a backend can cut a monitor's power;
    // `canSuspend`: logind's CanSuspend answer ("yes", "no", "challenge", "na", anything else
    // unknown) — sleep is a stage only on "yes"; `canHibernate`, `canSuspendThenHibernate`:
    // logind's answers to those — hibernation only on "yes" to the one it needs
    // (SuspendThenHibernate with sleep on, Hibernate with it off). → the
    // config every other function takes: times in seconds, 0 = never; `saverAfter` and
    // `screenOffAfter` the default's, `times` per connected monitor ({ saverAfter,
    // screenOffAfter }: its entry in `monitorIdle` while `perMonitor` is on, else the
    // default's). A screen-off without power control stays a stage: the screensaver at its
    // time (wanted). `hibernate`: { on (switched on and possible here), from ("sleep",
    // "lock", "saver" or "input": where it counts from), at (that moment, seconds from the
    // last input), after (the profile's time) } — hibernateBase; `hibernateAfter`: the stage
    // on the clock with sleep off (at + after, 0 = none); `sleepThenHibernate`: the sleep
    // asks SuspendThenHibernate; `commands`: the command entries understood
    // (commandEntries()); `saverFade`: the screensaver's fade in (ms), which a screen-off
    // following it waits for (offAt).
    function config(values, monitors, canPowerOff, canSuspend, canHibernate, canSuspendThenHibernate) {
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
        // Each monitor's connector ("" for one given by id only)
        const connectors = {};
        for (const id of ids) {
            keys[id] = MonitorRules.overrideKeys(byId[id]);
            connectors[id] = typeof byId[id]?.connector === "string" ? byId[id].connector : "";
            const entry = MonitorRules.overrideFor(entries, byId[id], monitors);
            times[id] = _isMap(entry) ? stages(entry, own) : Object.assign({}, defaults);
        }
        const lockAfter = flag(given.lockscreenEnabled, false) ? seconds(given.lockAfter, 600) : 0;
        const sleepAfter = flag(given.sleepEnabled, false) && canSuspend === "yes" ? seconds(given.sleepTimeout, 1800) : 0;
        const saverTimes = ids.length > 0 ? ids.map(id => times[id].saverAfter) : [defaults.saverAfter];
        const base = hibernateBase(sleepAfter, Math.max(...saverTimes), lockAfter);
        const hibernateOn = flag(given.hibernateEnabled, false)
            && (sleepAfter > 0 ? canSuspendThenHibernate === "yes" : canHibernate === "yes");
        const hibernateTime = seconds(given.hibernateTimeout, 7200);
        const hibernate = { on: hibernateOn && hibernateTime > 0, from: base.from, at: base.at, after: hibernateTime };
        return {
            saverAfter: defaults.saverAfter,
            screenOffAfter: defaults.screenOffAfter,
            lockAfter: lockAfter,
            lockedScreenOffAfter: seconds(given.lockedScreenOffTimeout, 60),
            saverFade: seconds(given.fadeInDuration, 800),
            sleepAfter: sleepAfter,
            hibernate: hibernate,
            hibernateAfter: hibernate.on && sleepAfter <= 0 ? base.at + hibernateTime : 0,
            sleepThenHibernate: hibernate.on && sleepAfter > 0,
            lockOnSleep: flag(given.lockOnSleep, false),
            perMonitor: perMonitor,
            times: times,
            keys: keys,
            connectors: connectors,
            canPowerOff: power,
            commands: commandEntries(given.commandEntries),
            monitors: ids,
            duplicates: duplicates
        };
    }

    function _isMap(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    // Where hibernation counts from (seconds from the last input): with sleep on, the sleep
    // (`sleepAfter` > 0; the system's delay follows it); else the last stage switched on
    // before it — the screensaver (`saverAfter`: the latest of the connected monitors') or
    // the idle lock (`lockAfter`), the lock at a tie; neither: the last input.
    // → { from: "sleep" | "lock" | "saver" | "input", at }
    function hibernateBase(sleepAfter, saverAfter, lockAfter) {
        const on = value => typeof value === "number" && value > 0;
        if (on(sleepAfter))
            return { from: "sleep", at: sleepAfter };
        if (on(lockAfter) && (!on(saverAfter) || lockAfter >= saverAfter))
            return { from: "lock", at: lockAfter };
        if (on(saverAfter))
            return { from: "saver", at: saverAfter };
        return { from: "input", at: 0 };
    }

    // The whole computer's stage on the clock (seconds from the last input; 0 none): the
    // sleep, or with sleep off the hibernation
    function machineAfter(config) {
        const sleepAfter = config?.sleepAfter ?? 0;
        return sleepAfter > 0 ? sleepAfter : (config?.hibernateAfter ?? 0);
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

    // ---- Command entries ----

    // The moments an entry can wait for: every monitor it waits for dark, the session
    // locked, the computer going to sleep
    readonly property var commandMoments: ["dark", "lock", "sleep"]
    // At most this many entries are kept; a command at most this long
    readonly property int maxCommandEntries: 16
    readonly property int maxCommandLength: 4096

    // One entry as given (the settings, the page) → the entry kept, or null when not
    // understood: { id (1–64 characters, no control characters), moment (commandMoments),
    // monitors (null: every monitor that goes dark; else the ids of the monitors it waits
    // for, as `config`'s monitors name them), go, back (commands for sh -c, "" none) }
    function commandEntry(given) {
        if (!_isMap(given))
            return null;
        const id = given.id;
        if (typeof id !== "string" || id.length === 0 || id.length > 64 || /[\u0000-\u001f\u007f]/.test(id))
            return null;
        if (!commandMoments.includes(given.moment))
            return null;
        const monitors = given.monitors ?? null;
        if (monitors !== null && !(Array.isArray(monitors) && monitors.length <= maxMonitorEntries
                                   && monitors.every(key => typeof key === "string" && key.length > 0 && key.length <= 400
                                                     && !/[\u0000-\u001f\u007f]/.test(key))))
            return null;
        const command = value => value === undefined || value === null ? "" : typeof value === "string" && value.length <= maxCommandLength ? value : null;
        const go = command(given.go);
        const back = command(given.back);
        if (go === null || back === null)
            return null;
        return { id: id, moment: given.moment, monitors: monitors === null ? null : monitors.slice(), go: go, back: back };
    }

    // The list as given → the entries understood, in order: one not understood, or with an
    // id taken by an earlier one, left out; at most maxCommandEntries
    function commandEntries(list) {
        const result = [];
        for (const given of Array.isArray(list) ? list : []) {
            const entry = commandEntry(given);
            if (entry !== null && !result.some(kept => kept.id === entry.id) && result.length < maxCommandEntries)
                result.push(entry);
        }
        return result;
    }

    // The list with one entry set (`entry` whole, under its id: replaced in place, or added
    // at the end) or dropped (`entry` null, `id` given). → the new list, or null when the
    // entry is not understood or one more would pass maxCommandEntries (nothing written)
    function withCommandEntry(list, id, entry) {
        const given = commandEntries(list);
        if (entry === null)
            return given.filter(kept => kept.id !== id);
        const understood = commandEntry(entry);
        if (understood === null || understood.id !== id)
            return null;
        const index = given.findIndex(kept => kept.id === id);
        if (index < 0) {
            if (given.length >= maxCommandEntries)
                return null;
            return given.concat([understood]);
        }
        given[index] = understood;
        return given;
    }

    // A new entry's id, not taken in `list`: from `seed` (the page's clock), so entries added
    // in two profiles are told apart
    function newCommandId(list, seed) {
        const taken = commandEntries(list).map(entry => entry.id);
        let number = Math.max(0, Math.floor(Number(seed) || 0));
        while (taken.includes("c" + number.toString(36)))
            number++;
        return "c" + number.toString(36);
    }

    // The connected monitors a "screens dark" entry waits for: those it names (either form
    // of a monitor's key) or, naming none, every one — of them, those that go dark
    // (`forced`: the screensaver forced, every monitor does)
    function commandWaits(entry, config, forced) {
        const state = { forced: forced === true };
        const named = Array.isArray(entry?.monitors) ? entry.monitors : null;
        return (config?.monitors ?? []).filter(id => {
            if (named !== null && !(config.keys?.[id] ?? [id]).some(key => named.includes(key)))
                return false;
            return _goesDark(_timesOf(config, id), state);
        });
    }

    // Retired keys a profile still sets in use (`set`: the profile's values): "Lock after"'s
    // old `lockscreenTimeout`, and the two screensaver commands with their switch — in use
    // when the switch is on or a command is written; never carried over
    function retiredKeys(set) {
        const values = _isMap(set) ? set : {};
        const keys = [];
        if ("lockscreen.lockscreenTimeout" in values)
            keys.push("lockscreen.lockscreenTimeout");
        const written = key => typeof values[key] === "string" && values[key].trim() !== "";
        if (values["lockscreen.screensaverCommands"] === true || written("lockscreen.screensaverStartCommand")
                || written("lockscreen.screensaverEndCommand"))
            keys.push("lockscreen.screensaverCommands");
        return keys;
    }

    // The command entries whose "go" ran, as kept across a restart of the shell (a file in
    // the user's runtime directory): one line, { key, run } — `key` the compositor session
    // it was written in (a file of another session or boot is stale), `run` commandsRun.
    // `run` empty → "" (nothing to keep)
    function commandsFile(run, key) {
        const records = _records(run);
        if (records.length === 0)
            return "";
        return JSON.stringify({ key: String(key ?? ""), run: records });
    }

    // The file's line as read → { run, problem }: "" none (no file, or an empty one),
    // "stale" written in another session (another key, or no key to compare), "corrupt"
    // not understood — `run` empty for both
    function commandsFromFile(line, key) {
        const text = typeof line === "string" ? line.trim() : "";
        if (text === "")
            return { run: [], problem: "" };
        let parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (error) {
            parsed = null;
        }
        if (!_isMap(parsed) || typeof parsed.key !== "string" || !Array.isArray(parsed.run))
            return { run: [], problem: "corrupt" };
        const records = _records(parsed.run);
        if (records.length !== parsed.run.length)
            return { run: [], problem: "corrupt" };
        if (typeof key !== "string" || key === "" || parsed.key !== key)
            return { run: [], problem: "stale" };
        return { run: records, problem: "" };
    }

    // commandsRun's records understood: { id, moment, back } each, at most maxCommandEntries
    function _records(run) {
        const records = [];
        for (const record of Array.isArray(run) ? run : []) {
            if (!_isMap(record) || typeof record.id !== "string" || record.id === "" || record.id.length > 64
                    || !commandMoments.includes(record.moment) || typeof record.back !== "string"
                    || record.back.length > maxCommandLength || records.length >= maxCommandEntries)
                continue;
            records.push({ id: record.id, moment: record.moment, back: record.back });
        }
        return records;
    }

    // The facts at the start: somebody is here, nothing is shown. `now`: monotonic ms.
    // `commandsPending`: the commands that ran before a restart are still being read — no
    // entry's "go" runs until they are (the `commandsRestored` event)
    function initial(now, commandsPending) {
        return {
            inputIdle: false,        // no input for baseTime (inhibitors ignored)
            awayIdle: false,         // the same, Wayland idle inhibitors respected
            idleSince: now,          // monotonic ms of the last input (moved at a release, a wake)
            busInhibitors: 0,        // org.freedesktop.ScreenSaver inhibits held
            logindIdleBlock: false,  // true, false or "unknown" (a failed read)
            logindSleepBlock: "unknown", // logind's `sleep` block: true, false or "unknown"
            sleepReadAt: null,       // monotonic ms of the last read of it (null: none in this period)
            sleepReadFails: 0,       // reads in a row that could not tell
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
            sleepAsked: false,       // the sleep asked in this period: not asked again
            sleepAskedThen: false,   // … as SuspendThenHibernate (read only while sleepAsked)
            sleepPlain: false,       // SuspendThenHibernate refused in this period: a plain Suspend instead
            sleepLeftUnlocked: false, // … and the settings leave it unlocked (no notice then)
            sleepSince: null,        // a profile switch made the sleep due: it counts from then (ms)
            sleepAfterSeen: null,    // the whole computer's stage at the last step (machineAfter)
            stage: ({}),             // monitor id → 0 none, 1 screensaver, 2 screens off: reached in this period
            saverSince: ({}),        // monitor id → when it first reached a stage in this period (ms): its screensaver appeared
            // The command entries whose "go" ran and whose "back" is due at their moment's
            // end: [{ id, moment, back }] — the "back" as it was when the "go" ran
            commandsRun: [],
            commandsReady: commandsPending !== true, // the commands run before a restart are known
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
            connectors: ({}),        // their connectors, monitor id → connector
            connectedPower: null,    // the config's canPowerOff at the last step
            // monitor id → { at, stage, shellOff, connector }: monitors that vanished while
            // dark in this period — one back in time is not a plug-in (replugWindow,
            // shellOffWindow)
            gone: ({}),
            // monitor id → the offs asked of it in this period: a monitor that comes back
            // powered after each cut (a reconnect) is asked again after a growing pause, and
            // given up on after powerRetry.tries — left under its black surface until input
            offAsks: ({})
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
        return waylandHeld(state) || state.busInhibitors > 0 || state.logindIdleBlock === true;
    }

    // A Wayland client holds idle off: no input for baseTime, yet not idle with inhibitors
    // respected — seen only once the input has been idle that long; unlocked only
    function waylandHeld(state) {
        return !state.locked && state.inputIdle === true && state.awayIdle !== true;
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

    // A monitor's screensaver shows before its screen-off (at or before its time)
    function _saverBeforeOff(times) {
        return times.saverAfter > 0 && times.saverAfter <= times.screenOffAfter;
    }

    // When a monitor's screen-off comes (ms from the last input), its stage on: its time, but
    // never before the screensaver shown at or before it has faded in (and saverFadeMargin) —
    // powering off at once would cut the fade short (equal times: never seen at all)
    function offAt(config, times) {
        const off = times.screenOffAfter * 1000;
        if (!_saverBeforeOff(times))
            return off;
        return Math.max(off, times.saverAfter * 1000 + (config.saverFade ?? 0) + saverFadeMargin);
    }

    // When a monitor's screen-off comes (monotonic ms), its stage on and not forced, or -1
    // while its screensaver has yet to appear (or appear anew: a monitor back after dropping
    // off): offAt from the last input, and never before
    // the screensaver has faded in since it appeared on that monitor (`saverSince`) — a
    // screensaver that came late (an old `since`, a step held past its time, a profile
    // switched while away) still gets its fade before the power goes
    function _offTime(state, config, id, times) {
        const fromInput = state.idleSince + offAt(config, times);
        if (!_saverBeforeOff(times))
            return fromInput;
        const since = state.saverSince?.[id];
        if (typeof since !== "number")
            return -1;
        return Math.max(fromInput, since + (config.saverFade ?? 0) + saverFadeMargin);
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
            if (_offOn(times) && now - state.forcedAt >= _forcedOffAfter(config, times))
                timeline = 2;
        } else {
            const idleFor = now - state.idleSince;
            if (times.saverAfter > 0 && idleFor >= times.saverAfter * 1000)
                timeline = 1;
            const offTime = times.screenOffAfter > 0 ? _offTime(state, config, id, times) : -1;
            if (offTime >= 0 && now >= offTime)
                timeline = 2;
        }
        return Math.max(reached, timeline);
    }

    // A forced screensaver shows on every monitor; a monitor's screen-off then comes as long
    // after it as it would after its own screensaver (seconds) — after its whole time where
    // it has no screensaver before the screen-off — never at once, nor before the forced
    // screensaver has faded in (ms)
    function _forcedOffAfter(config, times) {
        const gap = times.saverAfter < times.screenOffAfter ? times.screenOffAfter - times.saverAfter : times.screenOffAfter;
        return Math.max(gap * 1000, (config.saverFade ?? 0) + saverFadeMargin);
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

    // The apps keeping the screen on hold the sleep while unlocked — a forced screensaver
    // too: the force only shows the screensaver
    function _sleepHeld(state) {
        if (state.locked)
            return false;
        return waylandHeld(state) || state.busInhibitors > 0 || state.logindIdleBlock === true;
    }

    // When the sleep falls due (monotonic ms), or -1: from the last input (or a later profile
    // switch that made it due), once per period, unless held (_sleepHeld). After a forced
    // screensaver it comes as long after the force as it would after the screensaver's own
    // time (`sleepAfter − saverAfter`), or its whole time where that is not positive — never at
    // once. An idle lock due at or before it and not taken yet is waited for up to
    // sleepLockWait. Without `ignoreBlock`, only once a read of logind's inhibitors taken at or
    // after that time found no sleep block (a failed read lets nothing go)
    function _sleepAt(state, config, ignoreBlock) {
        const sleepAfter = machineAfter(config);
        if (state.sleeping || state.sleepAsked || sleepAfter <= 0)
            return -1;
        if (_sleepHeld(state) || !_counting(state))
            return -1;
        let due;
        if (state.forced) {
            const gap = sleepAfter - (config.saverAfter ?? 0);
            due = state.forcedAt + (gap > 0 ? gap : sleepAfter) * 1000;
        } else {
            due = state.idleSince + sleepAfter * 1000;
        }
        if (state.sleepSince !== null)
            due = Math.max(due, state.sleepSince + sleepAfter * 1000);
        if (config.lockAfter > 0 && !state.locked && !state.lockedThisPeriod) {
            const lockAt = _lockStart(state) + config.lockAfter * 1000;
            if (lockAt <= due)
                due = Math.max(due, lockAt + sleepLockWait);
        }
        if (ignoreBlock !== true && !(state.logindSleepBlock === false && _sleepReadSince(state, due)))
            return -1;
        return due;
    }

    // A read of logind's sleep block answered at or after `at`
    function _sleepReadSince(state, at) {
        return typeof state.sleepReadAt === "number" && state.sleepReadAt >= at;
    }

    // The pause before reading logind's inhibitors again for the sleep after `fails` reads in
    // a row that could not tell (ms)
    function sleepReadRetryDelay(fails) {
        if (fails <= 0)
            return 0;
        return Math.min(sleepReadRetry.maximum, sleepReadRetry.minimum * Math.pow(2, fails - 1));
    }

    // When logind's inhibitors are next read for the sleep (monotonic ms), or -1: at the time
    // it falls due; while a sleep block holds, again after logindRecheck; after a read that
    // could not tell, again after a growing pause; none once a fresh read found it free
    function _sleepReadAt(state, config) {
        const due = _sleepAt(state, config, true);
        if (due < 0)
            return -1;
        if (!_sleepReadSince(state, due))
            return due;
        if (state.logindSleepBlock === true)
            return state.sleepReadAt + logindRecheck;
        if (state.logindSleepBlock !== false)
            return state.sleepReadAt + sleepReadRetryDelay(state.sleepReadFails ?? 0);
        return -1;
    }

    // The pause before reading logind's sleep support again while it could not be read: the
    // n-th retry after `tries` reads that could not tell (ms)
    function supportRetryDelay(tries) {
        if (tries <= 0)
            return 0;
        return Math.min(supportRetry.maximum, supportRetry.minimum * Math.pow(2, tries - 1));
    }

    // The sleep is due: logind is asked to suspend now (Idle reads logind's inhibitors first,
    // logindReadDue)
    function sleepDue(state, config, now) {
        const at = _sleepAt(state, config, false);
        return at >= 0 && now >= at;
    }

    // The settings leave a sleep unlocked: neither "Lock before the computer sleeps" nor an
    // idle lock at or before the sleep — the sleep notice does not count such a sleep
    function sleepLeftUnlocked(state, config) {
        return state.locked !== true && config.lockOnSleep !== true
            && !(config.lockAfter > 0 && config.lockAfter <= machineAfter(config));
    }

    // logind's idle block is read before it matters, not on a clock (logind sends no signal
    // when one appears): unlocked and not forced, when a stage or the idle lock is due now,
    // and while a block holds (its re-read, logindRecheck). Its sleep block likewise, locked
    // or not: when the sleep is due but for it. Idle reads, steps the answers
    // (logindIdleBlock, logindSleepBlock), then the deadline.
    function logindReadDue(state, config, now) {
        if (state.sleeping)
            return false;
        const sleepReadAt = _sleepReadAt(state, config);
        if (sleepReadAt >= 0 && now >= sleepReadAt)
            return true;
        if (state.locked || state.forced)
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
                        due.push(state.forcedAt + _forcedOffAfter(config, times));
                    continue;
                }
                if (times.saverAfter > 0 && reached < 1)
                    due.push(state.idleSince + times.saverAfter * 1000);
                const offTime = times.screenOffAfter > 0 && reached < 2 ? _offTime(state, config, id, times) : -1;
                if (offTime >= 0)
                    due.push(offTime);
            }
        }
        const lockAt = _lockAt(state, config.lockAfter);
        if (lockAt >= 0)
            due.push(lockAt);
        if (state.locked && state.inputIdle && !state.lockAttended && config.lockedScreenOffAfter > 0 && !state.lockedDark)
            due.push(state.lockQuietSince + config.lockedScreenOffAfter * 1000);
        if (!state.locked && state.logindIdleBlock === true)
            due.push(now + logindRecheck);
        const sleepAt = _sleepAt(state, config, false);
        if (sleepAt >= 0)
            due.push(sleepAt);
        const sleepReadAt = _sleepReadAt(state, config);
        if (sleepReadAt >= 0)
            due.push(sleepReadAt);
        for (const id of Object.keys(state.pendingPower)) {
            const at = _powerRetryAt(state.pendingPower[id]);
            if (at >= 0)
                due.push(at);
        }
        return due.length === 0 ? -1 : Math.max(now, Math.min(...due));
    }

    // ---- The step ----

    // An off asked again of a monitor that came back powered (read on while off, or back
    // after dropping off at its cut): after the pause its asks in this period earn, given up
    // at powerRetry.tries without a word more (the give-up was said once)
    function _offAgain(next, id, now) {
        const asked = next.offAsks[id] ?? 0;
        next.pendingPower[id] = { on: false, at: now, tries: asked, read: "on", gaveUp: asked >= powerRetry.tries, again: true };
    }

    function _copy(state) {
        const next = Object.assign({}, state);
        next.shown = Object.assign({}, state.shown);
        next.stage = Object.assign({}, state.stage);
        next.saverSince = Object.assign({}, state.saverSince ?? {});
        next.connectors = Object.assign({}, state.connectors ?? {});
        next.offAsks = Object.assign({}, state.offAsks ?? {});
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
        next.saverSince = {};
        next.forced = false;
        next.dark = false;
        next.gone = {};
        next.offAsks = {};
        next.lockedThisPeriod = next.locked;
        next.lockAsks = 0;
        next.lockAskedAt = -1;
        next.lockSince = null;
        next.sleepAsked = false;
        next.sleepPlain = false;
        next.sleepLeftUnlocked = false;
        next.sleepSince = null;
        // Read again before the next sleep: a block seen now says nothing of then
        next.logindSleepBlock = "unknown";
        next.sleepReadAt = null;
        next.sleepReadFails = 0;
        next.lockedDark = false;
        if (next.locked)
            next.lockQuietSince = now;
        _commandsBack(next, "dark", actions);
    }

    // An entry's moment came: its "go" (none for an empty command), its "back" due at the end
    function _commandGo(next, entry, actions) {
        next.commandsRun = next.commandsRun.concat([{ id: entry.id, moment: entry.moment, back: entry.back }]);
        if (entry.go.trim() !== "")
            actions.push({ type: "runCommand", id: entry.id, which: "go", command: entry.go });
    }

    // A moment ended: the "back" of each entry of it whose "go" ran
    function _commandsBack(next, moment, actions) {
        const run = next.commandsRun ?? [];
        for (const record of run) {
            if (record.moment === moment && record.back.trim() !== "")
                actions.push({ type: "runCommand", id: record.id, which: "back", command: record.back });
        }
        next.commandsRun = run.filter(record => record.moment !== moment);
    }

    function _commandRan(next, entry) {
        return (next.commandsRun ?? []).some(record => record.id === entry.id && record.moment === entry.moment);
    }

    // The entries of a moment that come with an event (locked, sleep): each whose "go" has
    // not run
    function _commandsGo(next, config, moment, actions) {
        if (next.commandsReady === false)
            return;
        for (const entry of config.commands ?? []) {
            if (entry.moment === moment && !_commandRan(next, entry))
                _commandGo(next, entry, actions);
        }
    }

    // A "screens dark" entry's moment: every monitor it waits for has gone dark — naming
    // none, the period's own dark (every monitor that goes dark has, kept until input)
    function _commandDark(next, config, entry) {
        if (entry.monitors === null)
            return next.dark;
        const waited = commandWaits(entry, config, next.forced);
        return waited.length > 0 && waited.every(id => (next.stage[id] ?? 0) >= 1);
    }

    // A read of logind's sleep block answered at `now`
    function _sleepRead(next, held, now) {
        next.logindSleepBlock = held === true ? true : held === false ? false : "unknown";
        next.sleepReadAt = now;
        next.sleepReadFails = next.logindSleepBlock === "unknown" ? (next.sleepReadFails ?? 0) + 1 : 0;
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
    // busInhibitors { count }, logindIdleBlock { held: true | false | "unknown", sleepHeld? }
    // (logind's idle block and, from the same read, its sleep block), logindSleepBlock { held }
    // (the sleep block alone), sleepFailed (logind refused the sleep asked: not asked again
    // in this period — but a refused SuspendThenHibernate, which logind judges at the call
    // (swap against the memory in use then), is asked once more as a plain Suspend, after a
    // fresh read of its inhibitors), power
    // { power: { id: "on" | "off" | other } }, deadline, config, monitors, locked,
    // unlocked, sleep, resumed, force (IPC), busForce (D-Bus SetActive(true): as force, never
    // while locked or going to sleep — busForceTakes), activity (D-Bus SimulateUserActivity, and input on a
    // forced screensaver's surface: before baseTime has passed no inputIdle(true) came, so
    // no inputIdle(false) will — the surface sends `activity`; ignored while locked, where
    // video players send it every ~30 s), lockAttended { attended } (somebody at the lock
    // screen: the prompt awake, a check under way — its screen-off waits), commandsRestored
    // { run } (the commands whose "go" ran before a restart, commandsFromFile), restore { ids }
    // (monitors a previous run turned off: turned on, pending like any power-on). `config`: from config() — passed at every
    // step, so a changed profile or monitor list is the "config"/"monitors" event with the
    // new one. → { state, actions, ignored }. Actions, in this order: powerOn { ids },
    // hideSaver { ids }, showSaver { ids } (a surface for every monitor leaving "on", also
    // one going off: it takes the keys), powerOff { ids }, runCommand { id, which: "go" |
    // "back", command } (a command entry's, the "back"s of a moment's end first), power
    // actions asked again { ids: [id], attempt } (a reading since the last ask showed the
    // monitor otherwise; a `restore`'s first with `restore: true`, first of all), powerGaveUp
    // { ids, on } (asked powerRetry.tries times: not asked again), lock, sleep { leftUnlocked,
    // thenHibernate } (logind's Suspend, or SuspendThenHibernate; after the lock;
    // `leftUnlocked`: sleepLeftUnlocked) or hibernate { leftUnlocked } (logind's Hibernate,
    // sleep being off), active { active },
    // lockBlack { black }. `active` turns true unlocked once every monitor that goes dark has
    // (allDark); a command entry's "go" comes at its moment, its "back" at the moment's end.
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
            // The same read's sleep block, in the same step: the sleep is never asked on one
            // half of a read
            if ("sleepHeld" in event)
                _sleepRead(next, event.sleepHeld, now);
            break;
        }
        case "power": {
            const read = event.power ?? {};
            next.power = {};
            for (const id of Object.keys(read))
                next.power[id] = read[id] === "on" || read[id] === "off" ? read[id] : "unknown";
            // Read on while the shell has it off and nothing is asked (it came back powered:
            // a reconnect, its own button): the off is asked again, at once
            for (const id of config.monitors) {
                if (next.shown[id] === "off" && next.power[id] === "on" && next.pendingPower[id] === undefined)
                    _offAgain(next, id, now);
            }
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
        case "logindSleepBlock":
            _sleepRead(next, event.held, now);
            break;
        case "sleepFailed":
            next.sleepLeftUnlocked = false;
            if (next.sleepAsked && next.sleepAskedThen && !next.sleepPlain) {
                next.sleepPlain = true;
                next.sleepAsked = false;
                // Never on a read from before the refusal: read again first
                next.logindSleepBlock = "unknown";
                next.sleepReadAt = null;
                next.sleepReadFails = 0;
            }
            break;
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
        case "commandsRestored": {
            // The commands that ran before a restart (their "back"s still due), joined to any
            // that ran since; then the entries of a moment under way that has not run its "go"
            // (a lock or a sleep that came while the file was read — not the one before the
            // restart, whose go is among those restored)
            const known = next.commandsRun ?? [];
            const restored = _records(event.run).filter(record => !known.some(kept => kept.id === record.id && kept.moment === record.moment));
            next.commandsRun = known.concat(restored);
            if (next.commandsReady === false) {
                next.commandsReady = true;
                if (next.locked)
                    _commandsGo(next, config, "lock", actions);
                if (next.sleeping)
                    _commandsGo(next, config, "sleep", actions);
            }
            break;
        }
        case "deadline":
        case "config":
        case "monitors":
            break;
        case "locked":
            if (!next.locked) {
                _commandsGo(next, config, "lock", actions);
                next.locked = true;
                next.lockQuietSince = now;
                next.lockedThisPeriod = true;
                next.lockAsks = 0;
                next.lockAskedAt = -1;
            }
            break;
        case "unlocked":
            if (next.locked) {
                _commandsBack(next, "lock", actions);
                next.locked = false;
                wake = true;
            }
            break;
        case "sleep":
            if (!next.sleeping)
                _commandsGo(next, config, "sleep", actions);
            next.sleeping = true;
            break;
        case "resumed":
            _commandsBack(next, "sleep", actions);
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

    // The key in `candidates` ({ id: { connector, … } }) of the monitor `id` names, or "":
    // one of its own keys (its id under either form), else one on its connector, else one
    // matching loosely (MonitorRules.looseKey: a field empty on either side matches any — Qt
    // and the backends do not report the same fields)
    function _sameMonitor(candidates, id, config) {
        const exact = (config.keys?.[id] ?? [id]).find(key => key in candidates);
        if (exact !== undefined)
            return exact;
        const connector = config.connectors?.[id] ?? "";
        const onConnector = Object.keys(candidates).find(key => connector !== "" && candidates[key].connector === connector);
        if (onConnector !== undefined)
            return onConnector;
        return MonitorRules.looseKey(candidates, id, config.monitors);
    }

    // The monitors that came and went since the last step: a monitor plugged in is somebody
    // at the computer, as input (a new idle period; locked, the lock stays). Not a plug-in:
    // the first step; a change while going to sleep (the resume wakes); a change of where the
    // monitors come from (power control found or lost: the ids may change form), where each
    // keeps the stage of the one it was (_sameMonitor); and a monitor that vanished while
    // dark in this period and is back in time (replugWindow, shellOffWindow), which takes
    // back the stage it had. Vanished while dark: remembered for that (`gone`).
    function _pluggedIn(next, config, now) {
        const before = next.connected;
        const beforeConnectors = next.connectors ?? {};
        const sourceChanged = next.connectedPower !== null && next.connectedPower !== config.canPowerOff;
        next.connected = config.monitors.slice();
        next.connectors = Object.assign({}, config.connectors ?? {});
        next.connectedPower = config.canPowerOff;
        if (before === null)
            return false;
        const departed = {};
        for (const id of before) {
            if (config.monitors.includes(id))
                continue;
            departed[id] = { connector: beforeConnectors[id] ?? "", stage: next.stage[id], saverSince: next.saverSince[id] };
            const shown = next.shown[id] ?? "on";
            if (shown !== "on" && !sourceChanged)
                next.gone[id] = { at: now, stage: next.stage[id], shellOff: shown === "off", connector: beforeConnectors[id] ?? "",
                                  offAsks: next.offAsks[id] ?? 0 };
        }
        let plugged = false;
        for (const id of config.monitors) {
            if (before.includes(id))
                continue;
            if (sourceChanged) {
                const was = _sameMonitor(departed, id, config);
                if (was !== "") {
                    next.stage[id] = departed[was].stage;
                    if (departed[was].saverSince !== undefined)
                        next.saverSince[id] = departed[was].saverSince;
                    // Shown as it was: the picture in place moves to the new id, no action
                    if (next.shown[was] !== undefined)
                        next.shown[id] = next.shown[was];
                }
                continue;
            }
            const key = _sameMonitor(next.gone, id, config);
            const back = key !== "" ? next.gone[key] : null;
            if (back !== null && now - back.at <= (back.shellOff ? shellOffWindow : replugWindow)) {
                next.stage[id] = back.stage;
                next.offAsks[id] = Math.max(next.offAsks[id] ?? 0, back.offAsks);
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
        // The same for the sleep (or the hibernation in its place): a switch that makes it due
        // counts from the switch
        const sleepAfter = machineAfter(config);
        if (next.sleepAfterSeen !== null && next.sleepAfterSeen !== sleepAfter) {
            const before = _sleepAt(next, { sleepAfter: next.sleepAfterSeen, lockAfter: config.lockAfter }, true);
            const after = _sleepAt(next, config, true);
            if (after >= 0 && after <= now && !(before >= 0 && before <= now))
                next.sleepSince = now;
        }
        next.sleepAfterSeen = sleepAfter;
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
        // When each monitor first reached a stage in this period: kept while it holds one, so
        // its screen-off can wait for the fade in from then (a monitor back after dropping
        // off shows its screensaver anew: from now)
        const saverSince = {};
        for (const id of config.monitors) {
            if (next.stage[id] >= 1)
                saverSince[id] = typeof next.saverSince[id] === "number" ? next.saverSince[id] : now;
        }
        next.saverSince = saverSince;
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
        // The commands of an event (a wake's "back"s, a lock's "go"s) were pushed first; keep
        // them after the pictures
        const early = actions.splice(0, actions.length);
        if (powerOn.length > 0)
            actions.push({ type: "powerOn", ids: powerOn });
        if (hide.length > 0)
            actions.push({ type: "hideSaver", ids: hide });
        if (show.length > 0)
            actions.push({ type: "showSaver", ids: show });
        // A monitor already asked off in this period and shown again from "on" (back after
        // dropping off): asked through _offAgain, after its pause
        const offNow = powerOff.filter(id => (next.offAsks[id] ?? 0) === 0);
        if (offNow.length > 0)
            actions.push({ type: "powerOff", ids: offNow });
        actions.push(...early);
        next.shown = want;
        for (const id of powerOn)
            next.pendingPower[id] = { on: true, at: now, tries: 1, read: null, gaveUp: false };
        for (const id of powerOff) {
            if (offNow.includes(id)) {
                next.pendingPower[id] = { on: false, at: now, tries: 1, read: null, gaveUp: false };
                next.offAsks[id] = 1;
            } else {
                _offAgain(next, id, now);
            }
        }
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
                const ask = { type: pending.on ? "powerOn" : "powerOff", ids: [id], attempt: pending.tries };
                if (!pending.on)
                    next.offAsks[id] = pending.tries;
                // Came back powered (Idle says so, not "not turned off as asked")
                if (pending.again === true) {
                    ask.again = true;
                    pending.again = false;
                }
                actions.push(ask);
            }
        }

        // Once every monitor that goes dark has, the period stays dark until input, or until
        // no monitor goes dark any more (every stage switched off): a monitor given a stage
        // later, or plugged back, does not take it back
        // (No monitor connected, or one gone while dark, is no stage switched off: every
        // monitor dropping off at its power cut keeps the period dark)
        if (allDark(next, config, next.stage))
            next.dark = true;
        else if (config.monitors.length > 0 && Object.keys(next.gone).length === 0
                 && !config.monitors.some(id => _goesDark(_timesOf(config, id), next)))
            next.dark = false;
        const dark = next.dark;
        for (const entry of next.commandsReady === false ? [] : config.commands ?? []) {
            if (entry.moment === "dark" && !_commandRan(next, entry) && _commandDark(next, config, entry))
                _commandGo(next, entry, actions);
        }
        if (lockDue(next, config, now)) {
            next.lockAsks++;
            next.lockAskedAt = now;
            // `attempt`: 1 the first ask, more for an ask again (Idle logs the first of those)
            actions.push({ type: "lock", attempt: next.lockAsks });
        }
        // After the lock: logind's PrepareForSleep then finds it on its way
        if (sleepDue(next, config, now)) {
            next.sleepAsked = true;
            next.sleepLeftUnlocked = sleepLeftUnlocked(next, config);
            if ((config.sleepAfter ?? 0) > 0) {
                next.sleepAskedThen = config.sleepThenHibernate === true && next.sleepPlain !== true;
                actions.push({ type: "sleep", leftUnlocked: next.sleepLeftUnlocked, thenHibernate: next.sleepAskedThen });
            } else
                actions.push({ type: "hibernate", leftUnlocked: next.sleepLeftUnlocked });
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
