import QtQuick
import qs.singletons

// The idle rules (singletons/IdleRules.qml): every case of their table of outcomes and
// examples — an OLED turned off, an LCD with the screensaver, a laptop panel off, each at
// its own times on one clock, a monitor plugged in or unplugged, a profile switched
// mid-idle, input waking all, the lock screen's own screen-off, inhibitors holding while
// unlocked only.
// A machine drives the rules as Idle will: events at given times, the Timer at
// nextDeadline; actions are compared as "type:ids" lists.
TestCase {
    suiteName: "IdleRules"

    // "showSaver:lcd+oled,powerOff:oled,active:true"
    function _list(actions) {
        return actions.map(action => {
            if (action.ids !== undefined)
                return action.type + ":" + action.ids.join("+");
            if (action.active !== undefined)
                return action.type + ":" + action.active;
            if (action.black !== undefined)
                return action.type + ":" + action.black;
            if (action.type === "runCommand")
                return action.which + ":" + action.id;
            if (action.leftUnlocked !== undefined)
                return action.type + (action.thenHibernate === true ? "+hibernate" : "") + ":" + (action.leftUnlocked ? "unlocked" : "locked");
            return action.type;
        }).join(",");
    }

    function _machine(values, monitors, canPowerOff, canSuspend, canHibernate, canSuspendThenHibernate) {
        const rules = IdleRules;
        const self = {
            config: rules.config(values, monitors, canPowerOff, canSuspend, canHibernate, canSuspendThenHibernate),
            state: rules.initial(0),
            now: 0,
            actions: "",
            ignored: ""
        };
        self.at = (ms, event) => {
            self.now = ms;
            const result = rules.step(self.state, event, self.config, ms);
            self.state = result.state;
            self.actions = _list(result.actions);
            self.ignored = result.ignored;
            return self;
        };
        self.reconfigure = (ms, newValues, newMonitors, newCanPowerOff) => {
            self.config = rules.config(newValues, newMonitors ?? monitors, newCanPowerOff ?? canPowerOff, canSuspend, canHibernate,
                                       canSuspendThenHibernate);
            return self.at(ms, { type: "config" });
        };
        self.next = () => rules.nextDeadline(self.state, self.config, self.now);
        // The Timer fires at the next deadline
        self.deadline = () => self.at(self.next(), { type: "deadline" });
        // … as Idle takes it: where logind's inhibitors are due to be read, their answer
        // (no idle block; the sleep block `sleepHeld`, none by default) is the step
        self.sleepDeadline = sleepHeld => {
            const at = self.next();
            if (!rules.logindReadDue(self.state, self.config, at))
                return self.at(at, { type: "deadline" });
            return self.at(at, { type: "logindIdleBlock", held: false, sleepHeld: sleepHeld === undefined ? false : sleepHeld });
        };
        // Nobody touched anything since `since` (ms)
        self.idle = (ms, since) => {
            self.at(ms, { type: "inputIdle", idle: true, since: since });
            return self.at(ms, { type: "awayIdle", idle: true, since: since });
        };
        self.input = ms => {
            self.at(ms, { type: "awayIdle", idle: false });
            return self.at(ms, { type: "inputIdle", idle: false });
        };
        self.shown = () => Object.keys(self.state.shown).sort().map(id => id + "=" + self.state.shown[id]).join(" ");
        return self;
    }

    // The default command entry ("every screen dark") with its two commands: today's start
    // and back commands
    readonly property var darkCommands: ({ id: "d", moment: "dark", monitors: null, go: "start", back: "end" })
    readonly property var saver: ({ screensaverEnabled: true, screensaverTimeout: 300, commandEntries: [darkCommands] })

    function _with(base, extra) {
        return Object.assign({}, base, extra);
    }

    // A monitor's own times, as monitorIdle keeps them: an OLED's (no screensaver, off at 5 min)
    readonly property var oledTimes: ({ screensaverEnabled: false, screensaverTimeout: 300, screenOffEnabled: true, screenOffTimeout: 300 })

    // Per monitor on, these monitors with their own times
    function _own(base, entries) {
        return _with(base, { perMonitor: true, monitorIdle: entries });
    }

    function _entry(saverAfter, screenOffAfter) {
        return { screensaverEnabled: saverAfter > 0, screensaverTimeout: saverAfter > 0 ? saverAfter : 300,
                 screenOffEnabled: screenOffAfter > 0, screenOffTimeout: screenOffAfter > 0 ? screenOffAfter : 600 };
    }

    function run() {
        _config();
        _screensaver();
        _perMonitorTimes();
        _monitorTimes();
        _screenOff();
        _offAfterFade();
        _lateSaver();
        _lock();
        _input();
        _lockScreen();
        _inhibitors();
        _profiles();
        _monitors();
        _sleep();
        _sleepStage();
        _hibernate();
        _forced();
        _unknowns();
        _powerReadBack();
        _lockAttended();
        _restore();
        _commandEntries();
        _edges();
    }

    // The command entries: each its moment, its "go" then, its "back" at the moment's end
    function _commandEntries() {
        const rules = IdleRules;
        const entry = (id, moment, monitors) => ({ id: id, moment: moment, monitors: monitors, go: id + "-go", back: id + "-back" });
        const desk = ["lcd", "oled", "clock"];
        // The LCD's screensaver at 5 min, the OLED off at 5 min, the small clock off after 1 h
        const deskTimes = { lcd: _entry(300, 0), oled: _entry(0, 300), clock: _entry(0, 3600) };

        // Waiting for two of three monitors
        const two = _machine(_own({ commandEntries: [entry("pair", "dark", ["lcd", "oled"]), entry("all", "dark", null)] }, deskTimes), desk, true);
        two.idle(5000, 0).deadline();
        assertEqual(two.actions, "showSaver:lcd+oled,powerOff:oled,go:pair",
                    "an entry waiting for the LCD and the OLED: its go at 5 min, when both are dark");
        assertEqual(two.next(), 3600000, "… the next deadline: the clock's screen-off");
        two.deadline();
        assertEqual(two.actions, "showSaver:clock,powerOff:clock,go:all,active:true", "the default entry (every monitor): at 1 h, with active");
        two.input(3700000);
        assertEqual(two.actions, "powerOn:oled+clock,hideSaver:lcd+oled+clock,back:pair,back:all,active:false",
                    "input: both entries' backs, in the order their gos ran");
        assertEqual(JSON.stringify(two.state.commandsRun), "[]", "… none due any more");

        // A monitor that never goes dark is not waited for
        const always = _with(deskTimes, { clock: _entry(0, 0) });
        const never = _machine(_own({ commandEntries: [entry("all", "dark", null), entry("named", "dark", ["lcd", "clock"]),
                                                        entry("clockOnly", "dark", ["clock"])] }, always), desk, true);
        never.idle(5000, 0).deadline();
        assertEqual(never.actions, "showSaver:lcd+oled,powerOff:oled,go:all,go:named,active:true",
                    "the clock never dark: every screen dark at 5 min, an entry naming the clock and the LCD too");
        assertEqual(rules.commandWaits(entry("named", "dark", ["lcd", "clock"]), never.config, false).join(" "), "lcd",
                    "… it waits for the LCD only");
        assertEqual(rules.commandWaits(entry("clockOnly", "dark", ["clock"]), never.config, false).length, 0,
                    "an entry naming only the clock: its moment never comes");
        assert(!never.state.commandsRun.some(record => record.id === "clockOnly"), "… its go never runs");
        assertEqual(rules.commandWaits(entry("clockOnly", "dark", ["clock"]), never.config, true).join(" "), "clock",
                    "… with the screensaver forced every monitor goes dark: it waits for the clock");
        assertEqual(rules.commandWaits(entry("gone", "dark", ["Dell|U27|SN"]), never.config, false).length, 0,
                    "an entry naming a monitor not connected: nothing to wait for");
        const twinKeys = rules.config({ screensaverEnabled: true }, [{ id: "A|B||DP-1", base: "A|B|", connector: "DP-1" }], true);
        assertEqual(rules.commandWaits(entry("twin", "dark", ["A|B|"]), twinKeys, false).join(" "), "A|B||DP-1",
                    "a monitor named under the other form of its key: waited for");

        // Locked: the go at any lock, the back at the unlock — not at input on the lock screen
        const lockEntries = { screensaverEnabled: true, screensaverTimeout: 300, lockedScreenOffTimeout: 0, commandEntries: [darkCommands, entry("away", "lock", null)] };
        const lock = _machine(lockEntries, ["lcd"], true);
        lock.at(1000, { type: "locked" });
        assertEqual(lock.actions, "go:away,active:true", "locked by hand: the lock entry's go");
        lock.idle(10000, 5000).deadline();
        assertEqual(lock.actions, "showSaver:lcd,go:d", "… idle reaches the screensaver's time under the lock: the dark entry's go");
        lock.input(400000);
        assertEqual(lock.actions, "hideSaver:lcd,back:d", "input at the lock screen: the dark entry's back (the first input), not the lock's");
        lock.at(410000, { type: "locked" });
        assertEqual(lock.actions, "", "a locked event while locked: no go again");
        lock.at(420000, { type: "unlocked" });
        assertEqual(lock.actions, "back:away,active:false", "the unlock: the lock entry's back");
        lock.at(430000, { type: "unlocked" });
        assertEqual(lock.actions, "", "… once");

        // Before sleep: the go at any sleep, the back at the resume
        const sleepEntries = { screensaverEnabled: true, screensaverTimeout: 300, commandEntries: [darkCommands, entry("nap", "sleep", null)] };
        const nap = _machine(sleepEntries, ["lcd"], true);
        nap.at(1000, { type: "sleep" });
        assertEqual(nap.actions, "go:nap", "going to sleep (logind's PrepareForSleep): the sleep entry's go");
        nap.at(1500, { type: "sleep" });
        assertEqual(nap.actions, "", "… once for one sleep");
        nap.at(2000, { type: "inputIdle", idle: false });
        assertEqual(nap.actions, "", "input while going to sleep: no back (the resume ends it)");
        nap.at(60000, { type: "resumed" });
        assertEqual(nap.actions, "back:nap", "the resume: its back");
        const darkNap = _machine(sleepEntries, ["lcd"], true).idle(5000, 0).deadline();
        darkNap.at(400000, { type: "sleep" });
        darkNap.at(500000, { type: "resumed" });
        assertEqual(darkNap.actions, "hideSaver:lcd,back:nap,back:d,active:false", "asleep with the screens dark: the resume ends both moments");

        // Back only after go
        const early = _machine(lockEntries, ["lcd"], true).idle(5000, 0);
        early.input(100000);
        assertEqual(early.actions, "", "input before the screens went dark: no back");
        const addedLocked = _machine({ commandEntries: [] }, ["lcd"], true).at(1000, { type: "locked" });
        addedLocked.reconfigure(2000, { commandEntries: [entry("away", "lock", null)] });
        assertEqual(addedLocked.actions, "", "a lock entry added while locked: its moment has passed, no go");
        addedLocked.at(3000, { type: "unlocked" });
        assertEqual(addedLocked.actions, "active:false", "… so no back at the unlock");

        // A stage switched off after the go: the back still waits for the return
        const off = _machine(_with(saver, { screenOffEnabled: true, screenOffTimeout: 600 }), ["lcd"], true).idle(5000, 0).deadline();
        assertEqual(off.actions, "showSaver:lcd,go:d,active:true", "(the go at the screensaver)");
        off.reconfigure(400000, { screenOffEnabled: true, screenOffTimeout: 600, commandEntries: [darkCommands] });
        assertEqual(off.actions, "hideSaver:lcd", "the screensaver switched off while the screen-off is to come: hidden, no back");
        off.reconfigure(410000, { commandEntries: [darkCommands] });
        assertEqual(off.actions, "active:false", "every stage switched off: not active, still no back (still away)");
        off.input(420000);
        assertEqual(off.actions, "back:d", "… the back at the return");

        // The schema's default (every screen dark, no commands): nothing runs, as with no commands before
        const defaults = _with(saver, { commandEntries: SettingsSchema.entry("lockscreen.commandEntries").default });
        assertEqual(JSON.stringify(rules.config(defaults, ["lcd"], true).commands.map(kept => [kept.moment, kept.monitors, kept.go, kept.back])),
                    JSON.stringify([["dark", null, "", ""]]), "the default list: one \"every screen dark\" entry without commands");
        const quiet = _machine(defaults, ["lcd"], true).idle(5000, 0).deadline();
        assertEqual(quiet.actions, "showSaver:lcd,active:true", "… its moment comes, nothing runs");
        quiet.input(400000);
        assertEqual(quiet.actions, "hideSaver:lcd,active:false", "… nor at the return");
        const backOnly = _machine(_with(saver, { commandEntries: [{ id: "b", moment: "dark", monitors: null, go: "", back: "here" }] }), ["lcd"], true);
        backOnly.idle(5000, 0).deadline().input(400000);
        assertEqual(backOnly.actions, "hideSaver:lcd,back:b,active:false", "an entry with a back only: its moment came, the back at the return");

        // A profile switched mid-idle: the back of the go that ran, whatever the new list says
        const switched = _machine(saver, ["lcd"], true).idle(5000, 0).deadline();
        switched.reconfigure(400000, { screensaverEnabled: true, screensaverTimeout: 300, commandEntries: [entry("other", "dark", null)] });
        assertEqual(switched.actions, "go:other", "a profile with another dark entry, its moment passed: its go at the switch");
        switched.reconfigure(410000, { screensaverEnabled: true, screensaverTimeout: 300, commandEntries: [] });
        assertEqual(switched.actions, "", "a profile without entries: nothing runs at the switch");
        switched.input(420000);
        assertEqual(switched.actions, "hideSaver:lcd,back:d,back:other,active:false", "… at the return the backs of both gos, as they were");
        const sameId = _machine(saver, ["lcd"], true).idle(5000, 0).deadline();
        sameId.reconfigure(400000, _with(saver, { commandEntries: [Object.assign({}, darkCommands, { back: "changed" })] }));
        assertEqual(sameId.actions, "", "the same entry in another profile: its go not again");
        const backs = [];
        IdleRules.step(sameId.state, { type: "inputIdle", idle: false }, sameId.config, 410000).actions
            .filter(action => action.type === "runCommand").forEach(action => backs.push(action.which + " " + action.command));
        assertEqual(backs.join(","), "back end", "… and the back that runs is the one of the go");

        // The entries understood
        assertEqual(JSON.stringify(rules.commandEntry({ id: "x", moment: "lock" })), JSON.stringify({ id: "x", moment: "lock", monitors: null, go: "", back: "" }),
                    "an entry without monitors and commands: none of either");
        for (const [bad, why] of [[{ id: "", moment: "dark" }, "an empty id"], [{ id: "x", moment: "idle" }, "an unknown moment"],
                                  [{ id: "x", moment: "dark", monitors: "lcd" }, "monitors not a list"],
                                  [{ id: "x", moment: "dark", monitors: [""] }, "an empty monitor key"],
                                  [{ id: "x", moment: "dark", go: 5 }, "a command not a string"],
                                  [{ id: "x", moment: "dark", back: "a".repeat(rules.maxCommandLength + 1) }, "a command too long"],
                                  [{ id: "a\nb", moment: "dark" }, "an id with a line break"], [[], "a list"], [null, "nothing"]])
            assertEqual(rules.commandEntry(bad), null, why + ": not understood");
        assert(rules.commandEntry({ id: "x", moment: "dark", go: "a".repeat(rules.maxCommandLength) }) !== null, "a command of the longest length: taken");
        assert(rules.commandEntry({ id: "i".repeat(64), moment: "lock" }) !== null, "an id of 64 characters: taken");
        assertEqual(rules.commandEntry({ id: "i".repeat(65), moment: "lock" }), null, "… of 65: not understood");
        const keys = [];
        for (let i = 0; i < rules.maxMonitorEntries; i++)
            keys.push("m" + i);
        assert(rules.commandEntry({ id: "x", moment: "dark", monitors: keys }) !== null, "as many monitors as kept for a monitor's times: taken");
        assert(rules.commandEntry({ id: "x", moment: "dark", monitors: ["m", "k".repeat(400)] }) !== null, "monitor keys of 1 and 400 characters: taken");
        assertEqual(rules.commandEntry({ id: "x", moment: "dark", monitors: ["k".repeat(401)] }), null, "… of 401: not understood");
        assertEqual(rules.commandEntries([{ id: "a", moment: "lock" }, { id: "a", moment: "sleep" }, { id: "b", moment: "nope" }, { id: "c", moment: "sleep" }])
                    .map(kept => kept.id + ":" + kept.moment).join(" "), "a:lock c:sleep", "a list: a taken id and one not understood left out");
        assertEqual(rules.commandEntries("junk").length, 0, "not a list: no entries");
        const many = [];
        for (let i = 0; i < rules.maxCommandEntries + 2; i++)
            many.push({ id: "e" + i, moment: "lock" });
        assertEqual(rules.commandEntries(many).length, rules.maxCommandEntries, "at most maxCommandEntries kept");
        assertEqual(rules.maxCommandEntries, 16, "… 16");
        assertEqual(rules.withCommandEntry(many.slice(0, 16), "new", { id: "new", moment: "lock" }), null, "one more than the most: refused");
        const list = [{ id: "a", moment: "lock", go: "x" }, { id: "b", moment: "sleep" }];
        assertEqual(rules.withCommandEntry(list, "a", { id: "a", moment: "dark", monitors: ["lcd"], go: "y" }).map(kept => kept.id + ":" + kept.moment + ":" + kept.go).join(" "),
                    "a:dark:y b:sleep:", "an entry changed in place");
        assertEqual(rules.withCommandEntry(list, "c", { id: "c", moment: "dark" }).map(kept => kept.id).join(" "), "a b c", "a new one at the end");
        assertEqual(rules.withCommandEntry(list, "a", null).map(kept => kept.id).join(" "), "b", "one dropped");
        assertEqual(rules.withCommandEntry(list, "a", { id: "a", moment: "nope" }), null, "an entry not understood: nothing written");
        assertEqual(rules.withCommandEntry(list, "a", { id: "b", moment: "lock" }), null, "an entry under another id: nothing written");
        assertEqual(rules.newCommandId([], 35), "cz", "a new id from the seed");
        assertEqual(rules.newCommandId([{ id: "cz", moment: "lock" }], 35), "c10", "… the next free one when taken");
        assertEqual(rules.newCommandId([], undefined), "c0", "… no seed: from 0");

        // A restart of the shell: the commands that ran are kept, with the session's key
        const record = [{ id: "away", moment: "lock", back: "away-back" }, { id: "d", moment: "dark", back: "end" }];
        const line = rules.commandsFile(record, "boot:wayland-1:9:42:7");
        assertEqual(JSON.stringify(rules.commandsFromFile(line, "boot:wayland-1:9:42:7")), JSON.stringify({ run: record, problem: "" }),
                    "the record read back in the same session");
        assertEqual(rules.commandsFile([], "k"), "", "none ran: nothing to keep");
        assertEqual(JSON.stringify(rules.commandsFromFile("", "k")), JSON.stringify({ run: [], problem: "" }), "no record: none");
        assertEqual(rules.commandsFromFile(line, "boot:wayland-1:9:43:7").problem, "stale", "another compositor session's record: stale");
        assertEqual(rules.commandsFromFile(line, "").problem, "stale", "… and one with no key to compare");
        for (const [bad, why] of [["{", "not JSON"], ["[]", "not a record"], ['{"key": "k", "run": [{"id": "x"}]}', "a record not understood"],
                                  ['{"key": "k"}', "no run"]])
            assertEqual(JSON.stringify(rules.commandsFromFile(bad, "k")), JSON.stringify({ run: [], problem: "corrupt" }), why + ": corrupt, ignored");
        assertEqual(JSON.parse(rules.commandsFile([{ id: "i".repeat(64), moment: "lock", back: "" }], "k")).run.length, 1, "a record's id of 64 characters: kept");
        for (const [bad, why] of [[{ id: "i".repeat(65), moment: "lock", back: "" }, "an id of 65 characters"], [{ id: 5, moment: "lock", back: "" }, "an id not a string"],
                                  [{ id: "x", moment: "nope", back: "" }, "an unknown moment"]])
            assertEqual(rules.commandsFile([bad], "k"), "", "a record with " + why + ": not kept");
        assertEqual(rules.commandsFromFile(rules.commandsFile(record, ""), "").problem, "stale", "a record without a key, read without one: stale");
        const runs = [];
        for (let i = 0; i < rules.maxCommandEntries + 2; i++)
            runs.push({ id: "r" + i, moment: "lock", back: i === 0 ? "b".repeat(rules.maxCommandLength) : "" });
        assertEqual(JSON.parse(rules.commandsFile(runs, "k")).run.map(kept => kept.id).join(" "), runs.slice(0, rules.maxCommandEntries).map(run => run.id).join(" "),
                    "at most maxCommandEntries records kept, a back of the longest length among them");
        assertEqual(rules.commandsFile([{ id: "x", moment: "lock", back: "b".repeat(rules.maxCommandLength + 1) }], "k"), "",
                    "a record with a back too long: not kept");

        // Restarted while locked: the lock it finds is the one whose go ran
        const restarted = { screensaverEnabled: true, screensaverTimeout: 300, lockedScreenOffTimeout: 0,
                            commandEntries: [darkCommands, entry("away", "lock", null)] };
        const again = _machine(restarted, ["lcd"], true);
        again.state = rules.initial(0, true);
        again.at(100, { type: "locked" });
        assertEqual(again.actions, "active:true", "restarted, locked at the start, the record not read yet: no go");
        again.at(200, { type: "commandsRestored", run: record });
        assertEqual(again.actions, "", "the record read: the lock entry had run, no go again");
        again.idle(5000, 0).deadline();
        assertEqual(again.actions, "showSaver:lcd", "the dark entry had run before the restart: no go again");
        again.input(400000);
        assertEqual(again.actions, "hideSaver:lcd,back:d", "input at the lock screen: the kept dark back");
        again.at(410000, { type: "unlocked" });
        assertEqual(again.actions, "back:away,active:false", "the unlock: the kept lock back, once");
        const twice = _machine(restarted, ["lcd"], true);
        twice.state = rules.initial(0, true);
        twice.at(100, { type: "locked" }).at(200, { type: "commandsRestored", run: record }).at(300, { type: "commandsRestored", run: record });
        assertEqual(JSON.stringify(twice.state.commandsRun), JSON.stringify(record), "the record read twice: each command that ran kept once");
        const fresh = _machine(restarted, ["lcd"], true);
        fresh.state = rules.initial(0, true);
        fresh.at(100, { type: "locked" });
        fresh.at(200, { type: "commandsRestored", run: [] });
        assertEqual(fresh.actions, "go:away", "no record (or a stale one): the lock found is a new one, its go once read");
        fresh.at(300, { type: "commandsRestored", run: [] });
        assertEqual(fresh.actions, "", "… read once");
        fresh.at(400, { type: "commandsRestored", run: [{ id: "other", moment: "lock", back: "x" }] });
        assertEqual(fresh.state.commandsRun.map(kept => kept.id).join(" "), "away other",
                    "… a record of another entry at the same moment joined to the one that ran since");
        const waiting = _machine(saver, ["lcd"], true);
        waiting.state = rules.initial(0, true);
        waiting.idle(5000, 0).deadline();
        assertEqual(waiting.actions, "showSaver:lcd,active:true", "the screens dark before the record is read: no go yet");
        waiting.at(310000, { type: "commandsRestored", run: [] });
        assertEqual(waiting.actions, "go:d", "… its go once read");
        assert(rules.initial(0).commandsReady, "no record to read: ready from the start");

        // Retired keys still set: told, never carried over
        assertEqual(rules.retiredKeys({ "lockscreen.screensaverCommands": false, "lockscreen.screensaverStartCommand": "",
                                        "lockscreen.screensaverEndCommand": " " }).join(" "), "",
                    "the old commands off and empty (both development machines): nothing to tell");
        assertEqual(rules.retiredKeys({ "lockscreen.screensaverCommands": true }).join(" "), "lockscreen.screensaverCommands", "the old switch on: told");
        assertEqual(rules.retiredKeys({ "lockscreen.screensaverEndCommand": "playerctl play" }).join(" "), "lockscreen.screensaverCommands",
                    "an old command written: told");
        assertEqual(rules.retiredKeys({ "lockscreen.lockscreenTimeout": 5 }).join(" "), "lockscreen.lockscreenTimeout", "the old lock time: told");
        assertEqual(rules.retiredKeys(null).length, 0, "no profile values: nothing");
    }

    // What tests/mutate.sh found no check for
    function _edges() {
        const rules = IdleRules;
        for (const unset of [null, ""])
            assertEqual(rules.config({ screensaverEnabled: true, screensaverTimeout: unset }, [], false).saverAfter, 300,
                        "a time not set (" + JSON.stringify(unset) + "): the default");
        assertEqual(rules.config({ monitorIdle: { oled: oledTimes } }, ["oled"], true).times.oled.screenOffAfter, 0,
                    "own times only with Set per monitor on, which is off unless set");
        const quick = _machine({ screensaverEnabled: true, screensaverTimeout: 1, screenOffEnabled: true, screenOffTimeout: 2,
                                 fadeInDuration: 100 }, ["oled"], true);
        quick.idle(500, 0);
        assertEqual(quick.next(), 1000, "a time of one second: due after it");
        assertEqual([900, 1000, 2000].map(ms => rules.stage(quick.state, quick.config, ms).oled).join(" "), "0 1 1",
                    "times of one and two seconds: the screensaver at 1 s, and first, even asked late");
        quick.deadline();
        assertEqual([1999, 2000].map(ms => rules.stage(quick.state, quick.config, ms).oled).join(" "), "1 2",
                    "… the screens off at 2 s");
        const offQuick = _machine({ screenOffEnabled: true, screenOffTimeout: 1 }, ["oled"], true).idle(500, 0);
        assert(offQuick.next() === 1000 && rules.stage(offQuick.state, offQuick.config, 1000).oled === 2, "screens off after one second");
        offQuick.deadline().at(1500, { type: "busInhibitors", count: 1 });
        assertEqual(rules.stage(offQuick.state, offQuick.config, 2000).oled, 2, "… an inhibitor then holds them off");
        offQuick.at(2500, { type: "sleep" });
        assertEqual(rules.stage(offQuick.state, offQuick.config, 3000).oled, 2, "… going to sleep keeps the stage reached");
        assertEqual(rules.powerRetryDelay(0), 0, "no power action asked yet: no pause");
        const junk = _machine(saver, ["lcd"], false).at(20000, { type: "inputIdle", idle: true, since: "junk" });
        assertEqual(junk.state.idleSince, 20000 - IdleRules.baseTime, "an idle event with a time not understood: idle for the base time");
        const first = _machine({ screensaverEnabled: true, screensaverTimeout: 700, lockscreenEnabled: true, lockAfter: 600 }, ["lcd"], false)
            .at(700000, { type: "force" });
        assert(first.actions.split(",").includes("lock"), "the first step: a lock already due is asked, no switch to count from: " + first.actions);
        const dueAlready = _machine({ lockscreenEnabled: true, lockAfter: 60 }, ["lcd"], true).idle(5000, 0);
        dueAlready.reconfigure(60000, { lockscreenEnabled: true, lockAfter: 30 });
        assertEqual(dueAlready.actions, "lock", "Lock after shortened just as the lock fell due: it is asked, not put off");
        const full = {};
        for (let i = 0; i < IdleRules.maxMonitorEntries; i++)
            full["Make|Model|S" + i] = oledTimes;
        assertEqual(rules.withMonitorTimes(full, "Make|Model|New", oledTimes), null, "a new monitor's times beyond the most kept: refused");
        assertEqual(IdleRules.maxMonitorEntries, 32, "the most monitors kept: 32");
        delete full["Make|Model|S0"];
        assert(rules.withMonitorTimes(full, "Make|Model|New", oledTimes) !== null, "… one fewer: taken");
        const lockQuick = _machine({ lockscreenEnabled: true, lockAfter: 1 }, ["lcd"], true).idle(500, 0);
        assertEqual(lockQuick.next(), 1000, "Lock after one second: due after it");
        const lockedQuick = _machine({ lockedScreenOffTimeout: 1 }, ["lcd"], true).at(100, { type: "locked" }).idle(500, 100);
        assert(lockedQuick.next() === 1100 && rules.lockedDark(lockedQuick.state, lockedQuick.config, 1100),
               "the lock screen's screen-off after one second: due, and dark, after it");
        const lockedNever = _machine({ lockedScreenOffTimeout: 0 }, ["lcd"], true).at(100, { type: "locked" }).idle(500, 100);
        assert(!rules.lockedDark(lockedNever.state, lockedNever.config, 1000000) && lockedNever.next() === -1,
               "the lock screen's screen-off at 0: never");
        const commands = _machine(saver, ["lcd"], false).idle(5000, 0).deadline().input(400000);
        assertEqual(commands.actions, "hideSaver:lcd,back:d,active:false", "(input: the command ended)");
        commands.idle(405000, 400000).input(410000);
        assertEqual(commands.actions, "", "… and not again at the next input");
        assert(commands.state.inputIdle === false && commands.next() === -1, "input: not idle, nothing due");
        for (const [held, kept] of [[false, false], [true, true], [undefined, "unknown"], ["yes", "unknown"]])
            assertEqual(_machine(saver, ["lcd"], false).at(100, { type: "logindIdleBlock", held: held }).state.logindIdleBlock, kept,
                        "logind's idle block read as " + JSON.stringify(held));
        const restoring = IdleRules.step(IdleRules.initial(0), { type: "restore", ids: ["oled"] }, rules.config({}, ["oled"], true), 1000);
        assert(restoring.actions[0].type === "powerOn" && restoring.actions[0].restore === true, "a restore's power-on says it is one");
        const exact = _machine(saver, ["lcd"], true).idle(5000, 0);
        exact.reconfigure(60000, _with(saver, { lockscreenEnabled: true, lockAfter: 60 }));
        assert(exact.actions === "" && exact.next() === 120000, "the lock turned on exactly as long into idle as its time: from the switch");
        const held = _machine({ screensaverEnabled: true, screensaverTimeout: 1 }, ["lcd"], false);
        held.idle(500, 0).deadline();
        assertEqual(held.state.stage.lcd, 1, "(the screensaver after 1 s)");
        held.at(1500, { type: "busInhibitors", count: 1 });
        assertEqual(rules.stage(held.state, held.config, 2000).lcd, 1, "… an inhibitor then holds it there, it stays");
        assertEqual(rules.lockRetryDelay(0), 0, "no ask yet: no retry pause");
        const since = _machine(saver, ["lcd"], false).idle(20000, 3000);
        assertEqual(since.state.idleSince, 3000, "idle since the time the event gives");
        assertEqual(since.next(), 303000, "… the screensaver counted from it");
        const none = _machine(saver, ["lcd"], false).idle(5000, 0);
        none.at(100000, { type: "busInhibitors", count: 0 });
        assertEqual(none.next(), 300000, "no inhibitor held, none reported: no release, the idle time runs on");
    }

    // What the readings say after a power action: done, or asked again with a growing pause
    function _powerReadBack() {
        const direct = { screenOffEnabled: true, screenOffTimeout: 600 };
        const machine = _machine(direct, ["oled"], true);
        machine.idle(5000, 0).deadline();
        assertEqual(machine.actions, "showSaver:oled,powerOff:oled,active:true", "(off at its time)");
        assertEqual(machine.state.pendingPower.oled.on, false, "the off is pending until a reading shows it");
        machine.at(600100, { type: "power", power: { oled: "on" } });
        assertEqual(machine.actions, "", "a reading still on (a dispatch that did nothing): not at once");
        assertEqual(machine.next(), 602000, "… asked again after the shortest pause");
        machine.deadline();
        assertEqual(machine.actions, "powerOff:oled", "… asked again");
        assertEqual(machine.state.pendingPower.oled.tries, 2, "… the second try");
        assertEqual(machine.next(), -1, "… no further deadline until a reading says otherwise again");
        machine.at(602200, { type: "power", power: { oled: "unknown" } });
        assertEqual(machine.next(), 606000, "a reading that failed: asked again too, the pause doubled");
        machine.at(606000, { type: "deadline" });
        assertEqual(machine.actions, "powerOff:oled", "… asked a third time");
        machine.at(606100, { type: "power", power: { oled: "off" } });
        assertEqual(machine.actions, "", "read off: done");
        assertEqual(Object.keys(machine.state.pendingPower).length, 0, "… nothing pending");
        assertEqual(machine.next(), -1, "… no deadline left");
        assertEqual(IdleRules.powerRetryDelay(40), IdleRules.powerRetry.maximum, "the pause grows up to its longest");
        machine.at(650000, { type: "power", power: { oled: "on" } });
        assertEqual(machine.actions, "", "read on later while the shell has it off (it came back powered): not at once —");
        assertEqual(machine.next(), 650000 + IdleRules.powerRetryDelay(3), "… after the pause its three asks earn");
        machine.deadline();
        assertEqual(machine.actions, "powerOff:oled", "… then the off asked again");
        machine.at(650100, { type: "power", power: { oled: "off" } });
        assertEqual(Object.keys(machine.state.pendingPower).length, 0, "… read off: done");

        // Power on that did not take: a key at the lock screen must bring the monitor back
        machine.input(700000);
        assertEqual(machine.actions, "powerOn:oled,hideSaver:oled,active:false", "input: on again");
        machine.at(700100, { type: "power", power: { oled: "off" } });
        machine.at(702000, { type: "deadline" });
        assertEqual(machine.actions, "powerOn:oled", "still off after the on: asked again");
        machine.at(702100, { type: "power", power: { oled: "on" } });
        assertEqual(Object.keys(machine.state.pendingPower).length, 0, "read on: done");

        // A monitor another program turned off (hypridle) is never touched
        const other = _machine(direct, ["lcd"], true);
        other.at(1000, { type: "power", power: { lcd: "off" } });
        assertEqual(other.actions, "", "off by another program: no action");
        assertEqual(other.next(), -1, "… and nothing to ask again");
        assertEqual(IdleRules.turnedOff(other.state).length, 0, "… not one the shell turned off");

        // What a restarted shell turns back on
        assertEqual(IdleRules.turnedOff(machine.state).join(" "), "", "on and read on: nothing to remember");
        const off = _machine(direct, ["oled", "lcd"], true);
        off.idle(5000, 0).deadline();
        assertEqual(IdleRules.turnedOff(off.state).join(" "), "lcd oled", "turned off by the shell: remembered");
        assertEqual(IdleRules.restoreOnStart(["oled", "gone"], [{ id: "oled", power: "off" }, { id: "lcd", power: "off" },
                                                                 { id: "tv", power: "on" }]).join(" "), "oled",
                    "at the start: only remembered monitors, connected and read off, are turned on");
        assertEqual(IdleRules.restoreOnStart("junk", [{ id: "oled", power: "off" }]).length, 0, "nothing remembered: nothing");
    }

    // Somebody at the lock screen (the prompt awake, a password check under way): its
    // screen-off waits; once off, only input turns it on
    function _lockAttended() {
        const machine = _machine({}, ["lcd"], true);
        machine.at(10000, { type: "locked" });
        machine.idle(15000, 10000);
        machine.at(20000, { type: "lockAttended", attended: true });
        assertEqual(machine.next(), -1, "attended: the lock screen's screen-off waits");
        machine.at(90000, { type: "deadline" });
        assertEqual(machine.actions, "", "… nothing off past its time");
        machine.at(100000, { type: "lockAttended", attended: false });
        assertEqual(machine.actions, "showSaver:lcd,powerOff:lcd,lockBlack:true", "nobody any more, its time long past: off at once");
        machine.at(110000, { type: "lockAttended", attended: true });
        assertEqual(machine.actions, "", "attended again under a dark screen (a check started): nothing turned on");
        machine.input(120000);
        assertEqual(machine.actions, "powerOn:lcd,hideSaver:lcd,lockBlack:false", "… input does");

        // A reader that errors every round: attended for a moment each time, the off still comes
        const reader = _machine({}, ["lcd"], true);
        reader.at(10000, { type: "locked" });
        reader.idle(15000, 10000);
        for (let at = 20000; at <= 70000; at += 5000) {
            reader.at(at, { type: "lockAttended", attended: true });
            reader.at(at + 300, { type: "lockAttended", attended: false });
        }
        assertEqual(reader.actions, "showSaver:lcd,powerOff:lcd,lockBlack:true", "an erroring reader: off at the first moment past its time");
        reader.at(75000, { type: "lockAttended", attended: true });
        reader.at(75300, { type: "lockAttended", attended: false });
        assertEqual(reader.actions, "", "… and stays off through its rounds");
    }

    // A previous run's monitors turned on again after a restart, through the same retry
    function _restore() {
        const machine = _machine({ screenOffEnabled: true, screenOffTimeout: 600 }, ["oled", "lcd"], true);
        machine.at(1000, { type: "restore", ids: ["oled", "gone"] });
        assertEqual(machine.actions, "powerOn:oled", "restore: the remembered, connected monitor turned on");
        assertEqual(IdleRules.turnedOff(machine.state).join(" "), "oled", "… still remembered until a reading shows it on");
        machine.at(1100, { type: "power", power: { oled: "off", lcd: "on" } });
        assertEqual(machine.next(), 3000, "the turn-on failed: asked again after the pause");
        machine.deadline();
        assertEqual(machine.actions, "powerOn:oled", "… asked again");
        for (let i = 0; i < 6; i++) {
            machine.at(machine.now + 100, { type: "power", power: { oled: "off", lcd: "on" } });
            machine.deadline();
        }
        assertEqual(machine.state.pendingPower.oled.tries, IdleRules.powerRetry.tries, "(asked its most)");
        machine.at(machine.now + 100, { type: "power", power: { oled: "off", lcd: "on" } });
        machine.deadline();
        assertEqual(machine.actions, "powerGaveUp:oled", "then given up, said once");
        machine.at(machine.now + 100, { type: "power", power: { oled: "off", lcd: "on" } });
        assertEqual(machine.next(), -1, "… nothing asked again");
        assertEqual(IdleRules.turnedOff(machine.state).join(" "), "oled", "… still remembered for the next start");
        machine.at(machine.now + 100, { type: "power", power: { oled: "on", lcd: "on" } });
        assertEqual(IdleRules.turnedOff(machine.state).join(" "), "", "read on at last (turned on by hand): forgotten");

        const wanted = _machine({ screenOffEnabled: true, screenOffTimeout: 600 }, ["oled"], true);
        wanted.idle(5000, 0).deadline();
        wanted.at(600100, { type: "restore", ids: ["oled"] });
        assertEqual(wanted.actions, "", "restore of a monitor this run wants off: nothing");
    }

    function _config() {
        const rules = IdleRules;
        const empty = rules.config(undefined, [], false);
        assertEqual(empty.saverAfter, 0, "nothing set: no screensaver");
        assertEqual(empty.screenOffAfter, 0, "nothing set: no screen-off");
        assertEqual(empty.lockAfter, 0, "nothing set: no idle lock");
        assertEqual(empty.lockedScreenOffAfter, 60, "the lock screen's screen-off: on by default after 1 min");
        const set = rules.config({ screensaverEnabled: true, screensaverTimeout: 10, screenOffEnabled: true,
                                   screenOffTimeout: 20, lockscreenEnabled: true, lockAfter: 30,
                                   lockedScreenOffTimeout: 0 }, ["a"], true);
        assertEqual([set.saverAfter, set.screenOffAfter, set.lockAfter, set.lockedScreenOffAfter].join(" "), "10 20 30 0",
                    "the times as set, 0 = never");
        assertEqual(rules.config({ screenOffEnabled: true }, ["a"], false).times.a.screenOffAfter, 600,
                    "no power control: the screen-off stays a stage (the screensaver at its time)");
        assertEqual(rules.config({ screensaverEnabled: false, screensaverTimeout: 10 }, [], false).saverAfter, 0,
                    "a time without its switch: never");
        assertEqual(rules.config({ screensaverEnabled: true, screensaverTimeout: "junk" }, [], false).saverAfter, 300,
                    "a time not understood: the default");
        const twins = rules.config({}, ["a", "a", "", { id: "b" }, 7, "b", "a"], false);
        assertEqual(twins.monitors.join(" "), "a b", "monitors by id, once each, objects with an id too");
        assertEqual(twins.duplicates.join(" "), "a b", "… two monitors with one id reported, once each");
        assertEqual(rules.config({}, ["a", "b"], false).duplicates.length, 0, "distinct ids: no duplicates");

        const times = values => rules.config(values, ["oled", "lcd"], true).times;
        const pair = entry => entry.saverAfter + " " + entry.screenOffAfter;
        const base = { screensaverEnabled: true, screensaverTimeout: 120, screenOffEnabled: true, screenOffTimeout: 900 };
        assertEqual(pair(times(base).oled), "120 900", "every monitor the default's times");
        assertEqual(pair(times(_own(base, { oled: oledTimes })).oled), "0 300", "own times: the OLED's");
        assertEqual(pair(times(_own(base, { oled: oledTimes })).lcd), "120 900", "… the others the default's");
        assertEqual(pair(times(_with(base, { perMonitor: false, monitorIdle: { oled: oledTimes } })).oled), "120 900",
                    "own times only with Set per monitor on");
        assertEqual(pair(times(_own(base, { oled: { screenOffEnabled: false } })).oled), "120 0",
                    "an entry without a field: the default's for that field");
        assertEqual(pair(times(_own(base, { oled: "off", lcd: [1] })).oled), "120 900", "an entry not understood: the default");
        assertEqual(pair(times(_own(base, { lcd: [1] })).lcd), "120 900", "… a list neither");
        assertEqual(pair(times(_own(base, "junk")).oled), "120 900", "a map not understood: the default");
        assertEqual(pair(times(_own({}, { oled: { screensaverEnabled: true } })).oled), "300 0",
                    "an entry's switch on without its time: the default's time, or its default");
        assertEqual(pair(times(_own({}, { oled: { screenOffEnabled: true } })).oled), "0 600", "… for the screen-off too");
        const given = { oled: oledTimes };
        const resolved = rules.config(_own(base, given), ["oled"], true);
        resolved.times.oled.saverAfter = 7;
        assertEqual(rules.config(_own(base, given), ["oled"], true).times.oled.saverAfter, 0, "a config's times are its own copy");
        const twoDefaults = rules.config(base, ["a", "b"], true);
        twoDefaults.times.a.saverAfter = 7;
        assertEqual(twoDefaults.times.b.saverAfter, 120, "… each monitor's too");
        assertEqual(rules.monitorTimeRange.minimum, SettingsSchema.entry("lockscreen.screensaverTimeout").min,
                    "a monitor's times: the default's shortest");
        assertEqual(rules.monitorTimeRange.maximum, SettingsSchema.entry("lockscreen.screenOffTimeout").max, "… and longest");
    }

    function _screensaver() {
        // An LCD and an OLED, both the screensaver
        const machine = _machine(saver, ["lcd", "oled"], true);
        machine.idle(5000, 0);
        assertEqual(machine.actions, "", "idle for the base time: nothing yet");
        assertEqual(machine.next(), 300000, "the next deadline: Screensaver after, from the last input");
        machine.at(200000, { type: "deadline" });
        assertEqual(machine.actions, "", "a timer early: nothing");
        machine.deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,go:d,active:true",
                    "Screensaver after: the screensaver on every monitor, the go command, active");
        assertEqual(machine.shown(), "lcd=saver oled=saver", "… both show it");
        assertEqual(machine.next(), -1, "… nothing further set");
        machine.at(400000, { type: "deadline" });
        assertEqual(machine.actions, "", "a deadline with nothing due: no action twice");

        const quiet = _machine(_with(saver, { commandEntries: [] }), ["lcd"], true);
        quiet.idle(5000, 0).deadline();
        assertEqual(quiet.actions, "showSaver:lcd,active:true", "commands off: no go command");
    }

    function _perMonitorTimes() {
        // The OLED off at 5 min (no screensaver), the LCD the screensaver at 5 min: one deadline
        const oledOff = _own(saver, { oled: oledTimes });
        const machine = _machine(oledOff, ["lcd", "oled"], true);
        machine.idle(5000, 0).deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,powerOff:oled,go:d,active:true",
                    "the OLED's own screen-off at the LCD's screensaver time: off, under a black surface that takes the keys");
        assertEqual(machine.shown(), "lcd=saver oled=off", "… what is in place");

        const noPower = _machine(oledOff, ["lcd", "oled"], false);
        noPower.idle(5000, 0).deadline();
        assertEqual(noPower.actions, "showSaver:lcd+oled,go:d,active:true",
                    "no power control: the OLED's screen-off is the screensaver at its time");
        assertEqual(noPower.shown(), "lcd=saver oled=saver", "… both the screensaver");

        // No power control, the monitors as the screens give them (Idle's other path): the
        // OLED's own times are found by its make, model and serial, and still darken it
        const screens = MonitorRules.screenMonitors([{ name: "DP-1", manufacturer: "Samsung", model: "Odyssey", serialNumber: "S1" },
                                                     { name: "DP-2", manufacturer: "LG", model: "27GL", serialNumber: "9" }], []);
        const fromScreens = _machine({ perMonitor: true, monitorIdle: { "Samsung|Odyssey|S1": oledTimes } }, screens, false);
        fromScreens.idle(5000, 0);
        assertEqual(fromScreens.next(), 300000, "the screens' ids: the OLED's own screen-off is due");
        fromScreens.deadline();
        assertEqual(fromScreens.actions, "showSaver:Samsung|Odyssey|S1,active:true",
                    "… and darkens it with the black screensaver; the LCD, with no stage, not waited for");

        // A laptop: its panel off (its backlight costs power on black)
        const laptop = _machine(_own(saver, { panel: _entry(0, 120) }), ["panel"], true);
        laptop.idle(5000, 0).deadline();
        assertEqual(laptop.actions, "showSaver:panel,powerOff:panel,go:d,active:true",
                    "the laptop panel's own screen-off at 2 min: powered off then");

        // Times changed during idle: applied at once
        const changed = _machine(saver, ["lcd", "oled"], true);
        changed.idle(5000, 0).deadline();
        changed.reconfigure(310000, oledOff);
        assertEqual(changed.actions, "powerOff:oled", "the OLED given its own screen-off, already past: off now");
        changed.reconfigure(320000, saver);
        assertEqual(changed.actions, "powerOn:oled", "… and back to the default: on, its screensaver stays");
        assertEqual(changed.shown(), "lcd=saver oled=saver", "… both the screensaver");

        // Three monitors at different times on one clock: the laptop panel off at 2 min, the
        // OLED off at 5 min, the LCD the screensaver at 5 min and off at 15
        const three = _own(_with(saver, { screenOffEnabled: true, screenOffTimeout: 900 }), { panel: _entry(0, 120), oled: oledTimes });
        const desk = _machine(three, ["lcd", "oled", "panel"], true);
        desk.idle(5000, 0);
        assertEqual(desk.next(), 120000, "the earliest of every monitor's times");
        desk.deadline();
        assertEqual(desk.actions, "showSaver:panel,powerOff:panel",
                    "2 min: the panel off; the commands and active wait for the other monitors");
        assertEqual(desk.next(), 300000, "… next the OLED's and the LCD's");
        desk.deadline();
        assertEqual(desk.actions, "showSaver:lcd+oled,powerOff:oled,go:d,active:true",
                    "5 min: every monitor dark: the commands, active");
        assertEqual(desk.next(), 900000, "… next the LCD's screen-off");
        desk.deadline();
        assertEqual(desk.actions, "powerOff:lcd", "15 min: the LCD off too");
        assertEqual(desk.shown(), "lcd=off oled=off panel=off", "… all off");
        desk.input(1000000);
        assertEqual(desk.actions, "powerOn:lcd+oled+panel,hideSaver:lcd+oled+panel,back:d,active:false", "input wakes all");
        desk.idle(1005000, 1000000);
        assertEqual(desk.next(), 1120000, "… each monitor's times again from the input");

        // Reached stays per monitor: a profile with longer times keeps what each reached
        const reached = _machine(three, ["lcd", "oled", "panel"], true);
        reached.idle(5000, 0).deadline();
        reached.reconfigure(130000, _own(_with(saver, { screenOffEnabled: true, screenOffTimeout: 900 }),
                                         { panel: _entry(0, 600), oled: oledTimes }));
        assertEqual(reached.actions, "", "the panel's time made longer once it is off: it stays off");
        assertEqual(reached.shown(), "lcd=on oled=on panel=off", "… the others still on");
        assertEqual(reached.next(), 300000, "… the others at their own times");
        reached.reconfigure(140000, _own(saver, { panel: _entry(60, 0), oled: oledTimes }));
        assertEqual(reached.actions, "powerOn:panel", "the panel's screen-off switched off: back to its screensaver, its own");
        assertEqual(reached.shown(), "lcd=on oled=on panel=saver", "… the others untouched");
        reached.reconfigure(150000, _own(saver, { panel: _entry(0, 0), oled: oledTimes }));
        assertEqual(reached.actions, "hideSaver:panel", "both its stages switched off: the desktop, without the back command");

        // A monitor with both stages off never goes dark and is not waited for
        const never = _machine(_own(saver, { lcd: _entry(0, 0) }), ["lcd", "oled"], true);
        never.idle(5000, 0);
        assertEqual(never.next(), 300000, "a monitor with both stages off: no time of its own");
        never.deadline();
        assertEqual(never.actions, "showSaver:oled,go:d,active:true",
                    "the OLED's screensaver: the commands and active, not waiting for the LCD");
        assertEqual(never.shown(), "lcd=on oled=saver", "… the LCD keeps the desktop");
        const none = _machine(_own(saver, { lcd: _entry(0, 0), oled: _entry(0, 0) }), ["lcd", "oled"], true);
        none.idle(5000, 0);
        assertEqual(none.next(), -1, "no monitor goes dark: nothing due");
        none.at(400000, { type: "deadline" });
        assertEqual(none.actions, "", "… no commands, never active");
        none.at(410000, { type: "force" });
        assertEqual(none.actions, "showSaver:lcd+oled,go:d,active:true",
                    "a forced screensaver: on every monitor, whatever its own stages");

        // A monitor in the config before a step has seen it (the monitors event still queued):
        // its times count already, for the deadline and for logind's read
        const queued = _machine(saver, ["lcd"], true);
        queued.idle(5000, 0);
        queued.config = IdleRules.config(_own(saver, { tv: _entry(60, 0) }), ["lcd", "tv"], true);
        assertEqual(queued.next(), 60000, "a monitor not stepped yet: its own time is the next deadline");
        assert(IdleRules.logindReadDue(queued.state, queued.config, 60000), "… and logind's block is read when it is due");

        // Once every monitor that goes dark has, it stays so until input: a monitor given a
        // stage mid-idle does not take active back
        const given = _machine(_own(saver, { tv: _entry(0, 0) }), ["lcd", "tv"], true);
        given.idle(5000, 0).deadline();
        assertEqual(given.actions, "showSaver:lcd,go:d,active:true", "(the LCD dark, the TV never)");
        given.reconfigure(310000, _own(saver, { tv: _entry(600, 0) }));
        assertEqual(given.actions, "", "the TV given a later stage mid-idle: still active, nothing ends");
        given.deadline();
        assertEqual(given.actions, "showSaver:tv", "… its screensaver at its time, no command again");
        given.reconfigure(610000, _own({}, { tv: _entry(0, 0) }));
        assertEqual(given.actions, "hideSaver:lcd+tv,active:false", "every stage switched off: not active (no back command: still away)");
        given.reconfigure(620000, _own(saver, { tv: _entry(0, 0) }));
        assertEqual(given.actions, "showSaver:lcd,active:true", "… a stage on again, past its time: active again, the command not twice");
    }

    // One monitor's times written into the per-monitor map (the IPC; the page's editor)
    function _monitorTimes() {
        const rules = IdleRules;
        const keys = map => JSON.stringify(map);
        const oled = "Samsung|Odyssey|S1";
        const gone = "Dell|U27|X9";
        const lcdTimes = _entry(300, 900);
        assertEqual(keys(rules.withMonitorTimes({}, oled, oledTimes)), keys({ [oled]: oledTimes }), "times set");
        assertEqual(keys(rules.withMonitorTimes({ [oled]: oledTimes, [gone]: lcdTimes }, oled, lcdTimes)),
                    keys({ [gone]: lcdTimes, [oled]: lcdTimes }),
                    "times changed; a monitor not connected keeps its entry");
        assertEqual(keys(rules.withMonitorTimes({ [oled]: oledTimes, [gone]: oledTimes }, oled, "default")), keys({ [gone]: oledTimes }),
                    "default: the entry dropped, the others kept");
        assertEqual(keys(rules.withMonitorTimes({ "Samsung|C27JG5x|H4Z": oledTimes }, { id: "Samsung|C27JG5x|", base: "Samsung|C27JG5x|", connector: "DP-2" }, lcdTimes)),
                    keys({ "Samsung|C27JG5x|": lcdTimes }), "a connected monitor's times: the key it matched loosely replaced");
        assertEqual(keys(rules.withMonitorTimes({ "Samsung|C27JG5x|H4Z": oledTimes }, "Samsung|C27JG5x|", lcdTimes)),
                    keys({ "Samsung|C27JG5x|H4Z": oledTimes, "Samsung|C27JG5x|": lcdTimes }), "… an id not connected: only its own key");
        const dellA = { id: "Dell|U2419H|S1", base: "Dell|U2419H|S1", connector: "DP-1" };
        const dellB = { id: "Dell|U2419H|", base: "Dell|U2419H|", connector: "DP-3" };
        assertEqual(keys(rules.withMonitorTimes({ "Dell|U2419H|S1": oledTimes }, dellB, lcdTimes, [dellA, dellB])),
                    keys({ "Dell|U2419H|S1": oledTimes, "Dell|U2419H|": lcdTimes }), "B's times with A connected and stored: B's own key added, A's kept");
        assertEqual(rules.config({ perMonitor: true, monitorIdle: { "Dell|U2419H|S1": oledTimes } }, [dellB, dellA], true).times["Dell|U2419H|"].screenOffAfter,
                    0, "… and B does not take A's times");
        assertEqual(keys(rules.withMonitorTimes(null, oled, oledTimes)), keys({ [oled]: oledTimes }), "no map yet: a new one");
        assertEqual(keys(rules.withMonitorTimes(["junk"], oled, oledTimes)), keys({ [oled]: oledTimes }), "a list is no map");
        const given = { [oled]: oledTimes };
        rules.withMonitorTimes(given, oled, "default");
        assertEqual(keys(given), keys({ [oled]: oledTimes }), "the map given is not changed");

        // Only times of the entry's shape: four fields, switches as booleans, whole seconds in range
        const without = Object.assign({}, oledTimes);
        delete without.screenOffTimeout;
        const refused = [
            ["off", "a way"], [null, "nothing"], [[1], "a list"], [without, "a field missing"],
            [_with(oledTimes, { slideshow: true }), "a field more"], [_with(oledTimes, { screensaverEnabled: "true" }), "a switch as text"],
            [_with(oledTimes, { screenOffEnabled: 1 }), "a switch as a number"], [_with(oledTimes, { screensaverTimeout: "300" }), "a time as text"],
            [_with(oledTimes, { screenOffTimeout: 4 }), "a time under 5 s"], [_with(oledTimes, { screensaverTimeout: 86401 }), "a time over a day"],
            [_with(oledTimes, { screenOffTimeout: 30.5 }), "a time not whole"]
        ];
        for (const [times, what] of refused)
            assertEqual(rules.withMonitorTimes({}, oled, times), null, what + ": refused");
        assertEqual(keys(rules.withMonitorTimes({}, oled, _with(oledTimes, { screensaverTimeout: 5, screenOffTimeout: 86400 }))),
                    keys({ [oled]: _with(oledTimes, { screensaverTimeout: 5, screenOffTimeout: 86400 }) }), "the shortest and longest times: taken");
        assertEqual(Object.keys(rules.withMonitorTimes({}, oled, { screenOffTimeout: 300, screenOffEnabled: true, screensaverTimeout: 300,
                                                                    screensaverEnabled: false })[oled]).join(" "),
                    "screensaverEnabled screensaverTimeout screenOffEnabled screenOffTimeout", "kept in one order, a copy of the times given");

        // Only ids of MonitorRules' shape
        assertEqual(rules.withMonitorTimes({}, "", oledTimes), null, "no id: refused");
        assertEqual(rules.withMonitorTimes({}, "DP-2", oledTimes), null, "a connector name: refused");
        assertEqual(rules.withMonitorTimes({}, "__proto__", oledTimes), null, "an object key: refused");
        assertEqual(rules.withMonitorTimes({}, "a|b", "default"), null, "two fields: refused, also to drop");
        assertEqual(rules.withMonitorTimes({}, "a|b|c|DP-1|x", oledTimes), null, "five fields: refused");
        assertEqual(rules.withMonitorTimes({}, "a|b|c|bad name", oledTimes), null, "a twin's connector not valid: refused");
        assertEqual(rules.withMonitorTimes({}, "a\nb|c|d", oledTimes), null, "a control character: refused");
        assertEqual(rules.withMonitorTimes({}, "x".repeat(81) + "||", oledTimes), null, "a field over 80: refused");
        assertEqual(keys(rules.withMonitorTimes({}, "||", oledTimes)), keys({ "||": oledTimes }), "empty fields: taken");
        assertEqual(keys(rules.withMonitorTimes({}, "A|B||DP-1", oledTimes)), keys({ "A|B||DP-1": oledTimes }), "a twin's id: taken");

        // At most maxMonitorEntries entries
        const full = {};
        for (let i = 0; i < rules.maxMonitorEntries; i++)
            full["M|" + i + "|"] = oledTimes;
        assertEqual(rules.withMonitorTimes(full, oled, oledTimes), null, "a new entry beyond the cap: refused");
        assertEqual(keys(rules.withMonitorTimes(full, "M|0|", lcdTimes)["M|0|"]), keys(lcdTimes), "… one changed: taken");
        assertEqual(Object.keys(rules.withMonitorTimes(full, "M|0|", "default")).length, rules.maxMonitorEntries - 1,
                    "… one dropped: taken");

        // A monitor's key changes form (alone → twin and back): its times follow it
        const twin = { id: "A|B||DP-1", base: "A|B|", connector: "DP-1" };
        assertEqual(rules.config({ perMonitor: true, monitorIdle: { "A|B|": oledTimes } }, [twin], true).times["A|B||DP-1"].screenOffAfter, 300,
                    "set alone, now a twin: its times found under the plain form");
        const alone = { id: "A|B|", base: "A|B|", connector: "DP-1" };
        assertEqual(rules.config({ perMonitor: true, monitorIdle: { "A|B||DP-1": oledTimes } }, [alone], true).times["A|B|"].screenOffAfter, 300,
                    "set as a twin, now alone: its times found under the twin's form");
        assertEqual(keys(rules.withMonitorTimes({ "A|B|": oledTimes, [gone]: oledTimes }, twin, lcdTimes)),
                    keys({ [gone]: oledTimes, "A|B||DP-1": lcdTimes }),
                    "written under the form it has now, the other form dropped");
        assertEqual(keys(rules.withMonitorTimes({ "A|B||DP-1": oledTimes }, alone, "default")), keys({}),
                    "default drops it under either form");

        // Read back by config: the entry applies only with Set per monitor on
        const map = rules.withMonitorTimes({}, "L|C|D", oledTimes);
        const read = rules.config({ perMonitor: true, monitorIdle: map }, ["L|C|D", oled], true).times["L|C|D"];
        assertEqual(read.saverAfter + " " + read.screenOffAfter, "0 300", "the map written is the one config reads");
    }

    function _screenOff() {
        const values = _with(saver, { screenOffEnabled: true, screenOffTimeout: 600 });
        const machine = _machine(_own(values, { oled: oledTimes }), ["lcd", "oled"], true);
        machine.idle(5000, 0).deadline();
        assertEqual(machine.next(), 600000, "after the screensaver: Turn screens off after, from the last input");
        machine.deadline();
        assertEqual(machine.actions, "powerOff:lcd", "Turn screens off after: every monitor still on or in the screensaver");
        assertEqual(machine.shown(), "lcd=off oled=off", "… all off");

        const direct = _machine({ screenOffEnabled: true, screenOffTimeout: 600 }, ["lcd"], true);
        direct.idle(5000, 0).deadline();
        assertEqual(direct.actions, "showSaver:lcd,powerOff:lcd,active:true",
                    "screen-off without the screensaver: off with its black surface");
    }

    // A screen-off at or soon after the screensaver waits for its fade in: the OLED with the
    // screensaver and the screen-off both at 60 s, a fade in of 2 s
    function _offAfterFade() {
        const rules = IdleRules;
        const fade = 2000 + rules.saverFadeMargin;
        const values = { screensaverEnabled: true, screensaverTimeout: 60, screenOffEnabled: true, screenOffTimeout: 60,
                         fadeInDuration: 2000 };
        const oled = _machine(_own({ fadeInDuration: 2000 }, { oled: _entry(60, 60) }), ["oled"], true);
        oled.idle(5000, 0).deadline();
        assertEqual(oled.actions, "showSaver:oled,active:true", "equal times: the screensaver first, not off at once");
        assertEqual(oled.next(), 60000 + fade, "… off once it has faded in");
        oled.at(60000 + fade - 1, { type: "deadline" });
        assertEqual(oled.actions, "", "… not a moment before");
        oled.deadline();
        assertEqual(oled.actions, "powerOff:oled", "… then off");

        const close = _machine(_with(values, { screenOffTimeout: 61 }), ["lcd"], true);
        close.idle(5000, 0).deadline();
        assertEqual(close.next(), 60000 + fade, "a screen-off within the fade: after the fade");
        const later = _machine(_with(values, { screenOffTimeout: 120 }), ["lcd"], true);
        later.idle(5000, 0).deadline();
        assertEqual(later.next(), 120000, "a screen-off well after the screensaver: its own time");
        const before = _machine(_with(values, { screensaverTimeout: 120 }), ["lcd"], true);
        before.idle(5000, 0).deadline();
        assertEqual(before.actions, "showSaver:lcd,powerOff:lcd,active:true",
                    "a screensaver after the screen-off never shows: off at its own time");
        const noSaver = _machine({ screenOffEnabled: true, screenOffTimeout: 60, fadeInDuration: 2000 }, ["lcd"], true);
        noSaver.idle(5000, 0);
        assertEqual(noSaver.next(), 60000, "no screensaver: off at its own time");
        const noPower = _machine(values, ["lcd"], false);
        noPower.idle(5000, 0).deadline();
        assertEqual(noPower.shown(), "lcd=saver", "without power control: the screensaver, as before");

        const forced = _machine(_own({ fadeInDuration: 2000 }, { tv: _entry(60, 61) }), ["tv"], true);
        forced.at(1000, { type: "force" });
        assertEqual(forced.next(), 1000 + fade, "forced: the screen-off one second after it waits for the fade too");
        const forcedLong = _machine(_own({ fadeInDuration: 2000 }, { tv: _entry(60, 120) }), ["tv"], true);
        forcedLong.at(1000, { type: "force" });
        assertEqual(forcedLong.next(), 61000, "… a longer gap: as long after the force as after the screensaver");

        const locked = _machine(_with(values, { lockedScreenOffTimeout: 30 }), ["lcd"], true);
        locked.at(1000, { type: "locked" }).idle(6000, 1000);
        assertEqual(locked.next(), 31000, "the lock screen's own screen-off: its time, no fade waited for");
        assertEqual(rules.config({ fadeInDuration: 1500 }, [], false).saverFade, 1500, "the fade in read from the profile (ms)");
        assertEqual(rules.config({}, [], false).saverFade, 800, "… its default when not set");
    }

    // A screensaver that comes late (an old `since`, a step held past its time by a slow read
    // of logind, a profile switched while away) still fades in before its monitor's screen
    // goes off: the wait counts from when it appeared on that monitor, not from the last input
    function _lateSaver() {
        const rules = IdleRules;
        const fade = 2000 + rules.saverFadeMargin;
        const values = { screensaverEnabled: true, screensaverTimeout: 60, screenOffEnabled: true, screenOffTimeout: 60,
                         fadeInDuration: 2000 };

        const old = _machine(values, ["oled"], true);
        old.idle(100000, 0);
        assertEqual(old.shown(), "oled=saver", "an old since: the screensaver first, not off at once");
        assertEqual(old.next(), 100000 + fade, "… off once it has faded in, counted from when it appeared");
        old.at(100000 + fade - 1, { type: "deadline" });
        assertEqual(old.actions, "", "… not a moment before");
        old.deadline();
        assertEqual(old.actions, "powerOff:oled", "… then off");

        const gap = _machine(_with(values, { screenOffTimeout: 61 }), ["lcd"], true);
        gap.idle(100000, 0);
        assertEqual(gap.shown(), "lcd=saver", "an old since, the screen-off a second after: the screensaver only");
        assertEqual(gap.next(), 100000 + fade, "… off after its fade in");

        const slow = _machine(values, ["oled"], true);
        slow.idle(5000, 0);
        slow.at(70000, { type: "logindIdleBlock", held: false });
        assertEqual(slow.actions, "showSaver:oled,active:true", "a step late past both times (logind's read): the screensaver only");
        assertEqual(slow.next(), 70000 + fade, "… off once it has faded in");
        slow.deadline();
        assertEqual(slow.actions, "powerOff:oled", "… then off");

        const switched = _machine({ screensaverEnabled: true, screensaverTimeout: 300, screenOffEnabled: true, screenOffTimeout: 300,
                                     fadeInDuration: 2000 }, ["oled"], true);
        switched.idle(5000, 0);
        switched.reconfigure(100000, values);
        assertEqual(switched.actions, "showSaver:oled,active:true", "a profile switched while away, both times past: the screensaver only");
        assertEqual(switched.next(), 100000 + fade, "… off once it has faded in");
        switched.deadline();
        assertEqual(switched.actions, "powerOff:oled", "… then off");

        // Per monitor: the LCD's screensaver came on time, the OLED's late
        const pair = _machine(_own({ fadeInDuration: 2000 }, { lcd: _entry(30, 60), oled: _entry(60, 60) }), ["lcd", "oled"], true);
        pair.idle(5000, 0).deadline();
        assertEqual(pair.actions, "showSaver:lcd", "per monitor: the LCD's screensaver on time");
        pair.at(70000, { type: "logindIdleBlock", held: false });
        assertEqual(pair.actions, "showSaver:oled,powerOff:lcd,active:true",
                    "… a late step: the LCD, long faded in, off; the OLED only its screensaver");
        assertEqual(pair.next(), 70000 + fade, "… the OLED off once its own screensaver has faded in");
        pair.deadline();
        assertEqual(pair.actions, "powerOff:oled", "… then the OLED off");
        pair.input(80000);
        assertEqual(pair.shown(), "lcd=on oled=on", "input: both on");
        pair.idle(200000, 80000);
        assertEqual(pair.shown(), "lcd=saver oled=saver", "a new period with an old since: both their screensavers, the last period's moment forgotten");
        assertEqual(pair.next(), 200000 + fade, "… both off after the fade in");

        // Power control found while the screensaver shows (the monitor's id changes form): it
        // has been fading in since it appeared, not since the change
        const qtForm = { id: "|U27|SN", base: "|U27|SN", connector: "DP-1" };
        const backend = { id: "Dell|U27|SN", base: "Dell|U27|SN", connector: "DP-1" };
        const found = _machine(values, [qtForm], false);
        found.idle(5000, 0).deadline();
        found.reconfigure(61000, values, [backend], true);
        assertEqual(found.actions, "", "power control found during the fade in: still the screensaver");
        assertEqual(found.next(), 60000 + fade, "… off once it has faded in since it appeared");

        // A monitor that drops off and comes back within the window keeps its screensaver's
        // moment: dropping off again and again never puts its screen-off off
        const flapping = _machine(_with(values, { screenOffTimeout: 61 }), ["lcd", "tv"], true);
        flapping.idle(5000, 0).deadline();
        flapping.reconfigure(61000, _with(values, { screenOffTimeout: 61 }), ["lcd"]);
        flapping.reconfigure(62000, _with(values, { screenOffTimeout: 61 }), ["lcd", "tv"]);
        assertEqual(flapping.next(), 60000 + fade, "a monitor back within the window: …");
        flapping.deadline();
        assertEqual(flapping.shown(), "lcd=off tv=off", "… off as long after its screensaver appeared as the one that stayed");

        // Nothing to wait for: the screen-off before the screensaver, or no screensaver on
        // that monitor
        const offFirst = _machine(_with(values, { screensaverTimeout: 120 }), ["oled"], true);
        offFirst.idle(100000, 0);
        assertEqual(offFirst.shown(), "oled=off", "an old since, the screen-off before the screensaver: off at once");
        const mixed = _machine(_own({ fadeInDuration: 2000 }, { lcd: _entry(60, 60), oled: _entry(0, 60) }), ["lcd", "oled"], true);
        mixed.idle(5000, 0);
        mixed.at(70000, { type: "logindIdleBlock", held: false });
        assertEqual(mixed.actions, "showSaver:lcd+oled,powerOff:oled,active:true",
                    "a late step, the OLED without a screensaver: off at once; the LCD its screensaver first");
        assertEqual(mixed.next(), 70000 + fade, "… the LCD off after its fade in");
    }

    function _lock() {
        const values = _with(saver, { lockscreenEnabled: true, lockAfter: 400 });
        const machine = _machine(values, ["lcd"], true);
        machine.idle(5000, 0).deadline();
        assertEqual(machine.next(), 400000, "Lock after counts from the last input, not from the screensaver");
        machine.deadline();
        assertEqual(machine.actions, "lock", "Lock after: lock");
        assertEqual(machine.state.lockAsks, 1, "… asked once");
        assertEqual(machine.next(), 405000, "not taken (no lock came): asked again after the shortest pause");
        machine.at(402000, { type: "deadline" });
        assertEqual(machine.actions, "", "… not before it");
        machine.deadline();
        assertEqual(machine.actions, "lock", "… asked again");
        assertEqual(machine.state.lockAsks, 2, "… the second ask");
        assertEqual(machine.next(), 415000, "… the pause grows: 10 s");
        machine.deadline();
        assertEqual(machine.next(), 435000, "… 20 s");
        assertEqual(IdleRules.lockRetryDelay(30), IdleRules.lockRetry.maximum, "… up to its longest");
        machine.input(1000000);
        assertEqual(machine.state.lockAsks, 0, "input: a new idle period, no asks counted");
        machine.idle(1005000, 1000000);
        assertEqual(machine.next(), 1300000, "a new idle period: the stages again");
        machine.deadline();
        machine.deadline();
        assertEqual(machine.actions, "lock", "… and the lock again");

        machine.at(1401000, { type: "locked" });
        assertEqual(machine.actions, "", "locked: active already, locking turns nothing on");
        assertEqual(machine.shown(), "lcd=saver", "… the screensaver stays under the lock");
        assertEqual(machine.state.lockAsks, 0, "… the lock taken: no ask pending");
        assertEqual(machine.next(), 1461000, "… nothing more to ask: next, only the lock screen's own screen-off");
        machine.at(1500000, { type: "unlocked" });
        machine.idle(1500000, 1500000);
        assertEqual(machine.next(), 1800000, "unlocked: a new period, the stages again from there");

        // Locked by something else in the period (Super+L) and unlocked without input: the
        // unlock counts as input, nothing is asked twice
        const taken = _machine(values, ["lcd"], true);
        taken.idle(5000, 0);
        taken.at(100000, { type: "locked" });
        taken.at(500000, { type: "deadline" });
        assertEqual(taken.actions.split(",").includes("lock"), false, "locked already: the idle lock is not asked");

        const alone = _machine({ lockscreenEnabled: true, lockAfter: 30 }, ["lcd"], true);
        alone.idle(5000, 0).deadline();
        assertEqual(alone.actions, "lock", "only the lock set: it comes at its time");
        alone.at(30100, { type: "locked" });
        assertEqual(alone.actions, "active:true", "… the lock is reported active");
    }

    function _input() {
        // Input wakes all, whatever each shows
        const values = _own(_with(saver, { screenOffEnabled: true, screenOffTimeout: 600 }), { oled: oledTimes });
        const machine = _machine(values, ["lcd", "oled", "panel"], true);
        machine.idle(5000, 0).deadline();
        machine.input(350000);
        assertEqual(machine.actions, "powerOn:oled,hideSaver:lcd+oled+panel,back:d,active:false",
                    "input at the screensaver: the OLED on, every screensaver hidden, the back command, inactive");
        assertEqual(machine.shown(), "lcd=on oled=on panel=on", "… all show the desktop");
        machine.idle(355000, 350000);
        assertEqual(machine.next(), 650000, "… the counting starts at the input");
        machine.deadline();
        machine.deadline();
        machine.input(1000000);
        assertEqual(machine.actions, "powerOn:lcd+oled+panel,hideSaver:lcd+oled+panel,back:d,active:false",
                    "input with every screen off: all on");

        const quiet = _machine(_with(saver, { commandEntries: [] }), ["lcd"], true);
        quiet.idle(5000, 0).deadline();
        quiet.input(310000);
        assertEqual(quiet.actions, "hideSaver:lcd,active:false", "no go command ran: no back command");
        quiet.input(320000);
        assertEqual(quiet.actions, "", "input again: nothing to undo");

        const user = _machine(saver, ["lcd"], true);
        user.idle(5000, 0).deadline();
        user.at(310000, { type: "activity" });
        assertEqual(user.actions, "hideSaver:lcd,back:d,active:false",
                    "an app's SimulateUserActivity counts as input");
        assertEqual(user.next(), 610000, "… the counting starts there");
    }

    function _lockScreen() {
        // Super+L while working, then nobody comes back: the lock screen's own screen-off
        const machine = _machine({}, ["lcd", "oled"], true);
        machine.at(10000, { type: "locked" });
        assertEqual(machine.actions, "active:true", "locked: active");
        assertEqual(machine.next(), -1, "still at the keyboard: no deadline yet");
        machine.idle(14000, 9000);
        assertEqual(machine.next(), 70000, "the lock screen's time from the lock (later than the last input)");
        machine.deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,powerOff:lcd+oled,lockBlack:true",
                    "after its time: every monitor off; the lock surface black until they read as off");
        machine.at(71000, { type: "power", power: { lcd: "off", oled: "off" } });
        assertEqual(machine.actions, "lockBlack:false", "both read as off: the lock surface need not be black");
        machine.input(90000);
        assertEqual(machine.actions, "powerOn:lcd+oled,hideSaver:lcd+oled",
                    "input at the lock screen: on again, still active (locked)");
        machine.idle(95000, 90000);
        assertEqual(machine.next(), 150000, "… the lock's quiet time starts again from that input");

        // A read from before the shell changed the power is not trusted
        machine.deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,powerOff:lcd+oled,lockBlack:true",
                    "off again after the input: black, the earlier \"off\" read no longer trusted");
        assertEqual(machine.state.power.lcd, "unknown", "… the power unknown until a fresh read");
        machine.at(151000, { type: "power", power: { lcd: "off", oled: "off" } });
        assertEqual(machine.actions, "lockBlack:false", "… a fresh read: not black");

        // Video players send SimulateUserActivity every ~30 s: the lock screen ignores it
        const player = _machine({}, ["lcd"], true);
        player.at(10000, { type: "locked" });
        player.idle(15000, 10000);
        player.at(40000, { type: "activity" });
        assertEqual(player.actions, "", "activity while locked: nothing");
        assertEqual(player.next(), 70000, "… the lock screen's screen-off still comes at its time");
        player.deadline();
        player.at(100000, { type: "activity" });
        assertEqual(player.actions, "", "… and once off, activity powers nothing on");
        assertEqual(player.shown(), "lcd=off", "… still off");

        const noPower = _machine({}, ["lcd"], false);
        noPower.at(10000, { type: "locked" });
        noPower.idle(15000, 10000).deadline();
        assertEqual(noPower.actions, "lockBlack:true", "no power control: the lock surface goes black instead");
        assertEqual(noPower.shown(), "lcd=on", "… no monitor pretended off");
        noPower.input(80000);
        assertEqual(noPower.actions, "lockBlack:false", "… input brings the lock back");

        const never = _machine({ lockedScreenOffTimeout: 0 }, ["lcd"], true);
        never.at(10000, { type: "locked" });
        never.idle(15000, 10000);
        assertEqual(never.next(), -1, "the lock screen's screen-off set to never: no deadline");

        // The idle lock, with the screen-off: both from their own starting points
        const idleLock = _machine(_with(saver, { lockscreenEnabled: true, lockAfter: 400 }), ["lcd"], true);
        idleLock.idle(5000, 0).deadline();
        idleLock.deadline();
        idleLock.at(400100, { type: "locked" });
        assertEqual(idleLock.next(), 460100, "an idle lock: the lock screen's time from the lock moment");
        idleLock.deadline();
        assertEqual(idleLock.actions, "powerOff:lcd,lockBlack:true", "… then off");

        const unlock = _machine({}, ["lcd"], true);
        unlock.at(10000, { type: "locked" });
        unlock.idle(15000, 10000).deadline();
        unlock.at(80000, { type: "unlocked" });
        assertEqual(unlock.actions, "powerOn:lcd,hideSaver:lcd,active:false,lockBlack:false",
                    "unlocked: a person is here; on, inactive");
    }

    function _inhibitors() {
        const values = _with(saver, { lockscreenEnabled: true, lockAfter: 400, screenOffEnabled: true, screenOffTimeout: 350 });

        // The bus: an app (a video) keeps the screen on
        const bus = _machine(values, ["lcd"], true);
        bus.idle(5000, 0);
        bus.at(100000, { type: "busInhibitors", count: 1 });
        assertEqual(bus.next(), -1, "an app holds: no deadline");
        bus.at(300000, { type: "deadline" });
        assertEqual(bus.actions, "", "… the screensaver waits");
        bus.at(500000, { type: "busInhibitors", count: 0 });
        assertEqual(bus.actions, "", "released: nothing at once");
        assertEqual(bus.next(), 800000, "… the counting starts at the release");
        bus.deadline();
        assertEqual(bus.actions, "showSaver:lcd,go:d,active:true", "… the screensaver from there");
        assertEqual(bus.next(), 850000, "… screen-off and lock from there too");

        // A stage reached stays when an app starts holding
        const reached = _machine(values, ["lcd"], true);
        reached.idle(5000, 0).deadline();
        reached.at(320000, { type: "busInhibitors", count: 2 });
        assertEqual(reached.actions, "", "an inhibitor after the screensaver: it stays");
        reached.at(360000, { type: "deadline" });
        assertEqual(reached.actions, "", "… the next stage (screen-off) waits");
        reached.at(400000, { type: "deadline" });
        assertEqual(reached.actions, "", "… the lock waits");
        reached.at(500000, { type: "busInhibitors", count: 0 });
        assertEqual(reached.shown(), "lcd=saver", "released: the screensaver still shown");
        assertEqual(reached.next(), 850000, "… screen-off 350 s after the release");

        // Wayland: an idle inhibitor (inputIdle without awayIdle)
        const wayland = _machine(values, ["lcd"], true);
        assert(!IdleRules.waylandHeld(wayland.state), "a Wayland hold is not seen before the input is idle");
        wayland.at(5000, { type: "inputIdle", idle: true, since: 0 });
        assertEqual(wayland.next(), -1, "a Wayland inhibitor holds: no deadline");
        assert(IdleRules.waylandHeld(wayland.state), "… seen as a Wayland hold (the page's unnamed app)");
        wayland.at(300000, { type: "deadline" });
        assertEqual(wayland.actions, "", "… no screensaver");
        wayland.at(605000, { type: "awayIdle", idle: true, since: 600000 });
        assertEqual(wayland.next(), 900000, "released at 600 s (away-idle comes the base time later): counted from there");
        assert(!IdleRules.waylandHeld(wayland.state), "… no longer held");
        wayland.at(610000, { type: "awayIdle", idle: false });
        wayland.at(610000, { type: "locked" });
        assert(!IdleRules.waylandHeld(wayland.state), "never a hold while locked");

        // logind: an idle block, read at deadlines
        const logind = _machine(values, ["lcd"], true);
        logind.idle(5000, 0);
        const readDue = (machine, ms) => IdleRules.logindReadDue(machine.state, machine.config, ms);
        assert(!readDue(logind, 299999), "logind's block not read before a stage is due");
        assert(readDue(logind, 300000), "… read when the screensaver is due");
        logind.at(300000, { type: "logindIdleBlock", held: true });
        logind.at(300000, { type: "deadline" });
        assertEqual(logind.actions, "", "logind's idle block holds the screensaver");
        assertEqual(logind.next(), 330000, "… read again later (logind sends no signal)");
        assert(readDue(logind, 310000), "… while held, read at its re-read");
        logind.at(330000, { type: "logindIdleBlock", held: false });
        assertEqual(logind.next(), 630000, "released: counted from the read that saw it gone");
        assert(!readDue(logind, 629999), "… free: not read again until the next stage is due");
        assert(readDue(logind, 630000), "… read then");
        logind.at(630000, { type: "deadline" });
        assert(!readDue(logind, 640000), "the screensaver reached: not read until screen-off is due");
        assert(readDue(logind, 680000), "… read at screen-off");
        logind.at(631000, { type: "logindIdleBlock", held: true });
        logind.at(632000, { type: "locked" });
        assert(!readDue(logind, 700000), "locked: never read (inhibitors are ignored there)");
        logind.at(633000, { type: "unlocked" });
        logind.at(634000, { type: "sleep" });
        assert(!readDue(logind, 700000), "asleep: never read");

        const busHeld = _machine(values, ["lcd"], true);
        busHeld.idle(5000, 0);
        busHeld.at(100000, { type: "busInhibitors", count: 1 });
        assert(!readDue(busHeld, 400000), "another inhibitor holds: nothing due, nothing read");
        busHeld.at(100000, { type: "force" });
        assert(!readDue(busHeld, 400000), "forced: inhibitors ignored, nothing read");

        const failed = _machine(values, ["lcd"], true);
        failed.idle(5000, 0);
        failed.at(300000, { type: "logindIdleBlock", held: "unknown" });
        assertEqual(failed.actions, "showSaver:lcd,go:d,active:true",
                    "a failed read is unknown, not held: the screensaver comes (it ends at the first input)");

        // Locked: keep-awake requests are ignored
        const locked = _machine(_with(values, { lockedScreenOffTimeout: 60 }), ["lcd"], true);
        locked.idle(5000, 0);
        locked.at(10000, { type: "locked" });
        locked.at(11000, { type: "busInhibitors", count: 1 });
        locked.at(12000, { type: "logindIdleBlock", held: true });
        locked.at(13000, { type: "awayIdle", idle: false });
        assertEqual(locked.next(), 70000, "inhibitors while locked: ignored, the lock screen's time runs");
        locked.deadline();
        assertEqual(locked.actions, "showSaver:lcd,powerOff:lcd,lockBlack:true", "… and the screens go off");
        locked.deadline();
        assertEqual(locked.actions, "go:d", "… idle reaches Screensaver after under the lock: the go command, the screens stay off");
        locked.at(320000, { type: "busInhibitors", count: 0 });
        assertEqual(locked.actions, "", "a release while locked moves nothing");
        assertEqual(locked.state.idleSince, 0, "… the counting still from the last input");
    }

    function _profiles() {
        // Battery → AC during idle: the screensaver shown at 10 s stays under a 300 s profile
        const battery = { screensaverEnabled: true, screensaverTimeout: 10, commandEntries: [darkCommands] };
        const machine = _machine(battery, ["lcd"], true);
        machine.idle(5000, 0).deadline();
        assertEqual(machine.actions, "showSaver:lcd,go:d,active:true", "the battery profile's screensaver at 10 s");
        machine.reconfigure(20000, saver);
        assertEqual(machine.actions, "", "a profile with a longer time mid-idle: the screensaver stays, nothing ends");
        machine.reconfigure(30000, _with(saver, { screenOffEnabled: true, screenOffTimeout: 60 }));
        assertEqual(machine.next(), 60000, "later stages take the new times");
        machine.reconfigure(40000, { screensaverEnabled: false });
        assertEqual(machine.actions, "hideSaver:lcd,active:false",
                    "a profile with the screensaver off: hidden, without the back command (still away)");
        machine.input(50000);
        assertEqual(machine.actions, "back:d", "… which runs when the user comes back");

        const off = _machine(_with(saver, { screenOffEnabled: true, screenOffTimeout: 600 }), ["lcd"], true);
        off.idle(5000, 0).deadline();
        off.deadline();
        off.reconfigure(700000, saver);
        assertEqual(off.actions, "powerOn:lcd", "screen-off switched off while off: back to the screensaver, not the desktop");

        // A profile that turns the idle lock on (or shortens it) past the time already idle:
        // it counts from the switch, never locks at once
        const lockOn = _machine(saver, ["lcd"], true);
        lockOn.idle(5000, 0).deadline();
        lockOn.reconfigure(400000, _with(saver, { lockscreenEnabled: true, lockAfter: 60 }));
        assertEqual(lockOn.actions, "", "the lock turned on 400 s into idle, 60 s: no lock at once");
        assertEqual(lockOn.next(), 460000, "… it comes 60 s after the switch");
        lockOn.deadline();
        assertEqual(lockOn.actions, "lock", "… and then locks");
        const shorter = _machine(_with(saver, { lockscreenEnabled: true, lockAfter: 600 }), ["lcd"], true);
        shorter.idle(5000, 0).deadline();
        shorter.reconfigure(400000, _with(saver, { lockscreenEnabled: true, lockAfter: 120 }));
        assertEqual(shorter.actions, "", "Lock after shortened below the time idle: not at once");
        assertEqual(shorter.next(), 520000, "… from the switch");
        const notYet = _machine(_with(saver, { lockscreenEnabled: true, lockAfter: 600 }), ["lcd"], true);
        notYet.idle(5000, 0).deadline();
        notYet.reconfigure(400000, _with(saver, { lockscreenEnabled: true, lockAfter: 500 }));
        assertEqual(notYet.next(), 500000, "shortened but not yet due: still from the last input");
        notYet.input(410000);
        notYet.idle(415000, 410000);
        assertEqual(notYet.next(), 710000, "… input: a new period from the last input, the switch forgotten");
    }

    // A monitor plugged in is somebody at the computer: a new idle period, as input. A
    // monitor that vanished while dark and is back (dropped off at its power cut, or within
    // replugWindow) is not
    function _monitors() {
        const values = _own(_with(saver, { lockscreenEnabled: true, lockAfter: 600 }), { oled: oledTimes });
        const machine = _machine(values, ["lcd"], true);
        machine.idle(5000, 0).deadline();
        machine.reconfigure(310000, values, ["lcd", "oled"]);
        assertEqual(machine.actions, "hideSaver:lcd,back:d,active:false",
                    "a monitor plugged in during idle: as input — the screensaver gone, the back command, not active");
        assertEqual(machine.shown(), "lcd=on oled=on", "… every monitor on");
        assertEqual(machine.next(), 610000, "… counted again from the plug-in, every stage and the lock");
        machine.deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,powerOff:oled,go:d,active:true", "… then each at its time again");
        machine.at(611000, { type: "power", power: { lcd: "on", oled: "off" } });
        machine.reconfigure(620000, values, ["lcd"]);
        assertEqual(machine.actions, "", "a monitor unplugged: no action");
        assertEqual(machine.shown(), "lcd=saver", "… dropped from what is shown");
        assertEqual(Object.keys(machine.state.power).join(" "), "lcd", "… and from the power read");
        machine.input(630000);
        assertEqual(machine.actions, "hideSaver:lcd,back:d,active:false", "input: only the connected monitor");

        // Plugged in while nothing was reached: the counting starts again from it
        const early = _machine(saver, ["lcd"], true);
        early.idle(5000, 0);
        early.reconfigure(200000, saver, ["lcd", "tv"]);
        assertEqual(early.actions, "", "plugged in before any stage: nothing to undo");
        assertEqual(early.next(), 500000, "… the screensaver counted from the plug-in");

        // Locked: the clock starts again, the lock stays
        const locked = _machine(_with(saver, { screenOffEnabled: true, screenOffTimeout: 400 }), ["lcd"], true);
        locked.idle(5000, 0).deadline();
        locked.deadline();
        locked.at(410000, { type: "locked" });
        locked.reconfigure(420000, _with(saver, { screenOffEnabled: true, screenOffTimeout: 400 }), ["lcd", "tv"]);
        assertEqual(locked.actions, "powerOn:lcd,hideSaver:lcd,back:d", "plugged in while locked: on again, the back command; still active");
        assert(locked.state.locked && locked.state.lockQuietSince === 420000, "… still locked, the lock screen's quiet time from the plug-in");

        // Powered off by the shell, then gone and back (a monitor that drops off at its power
        // cut): its stage again, nothing woken — within shellOffWindow, a plug-in after it
        const dropped = _machine(values, ["lcd", "oled"], true);
        dropped.idle(5000, 0).deadline();
        dropped.reconfigure(310000, values, ["lcd"]);
        dropped.reconfigure(310000 + IdleRules.shellOffWindow, values, ["lcd", "oled"]);
        assertEqual(dropped.actions, "showSaver:oled", "powered off by the shell, back within its window: its black surface, no wake");
        assertEqual(dropped.state.stage.oled, 2, "… its stage taken back");
        assertEqual(Object.keys(dropped.state.gone).length, 0, "… no longer remembered as gone");
        const replugged = _machine(values, ["lcd", "oled"], true);
        replugged.idle(5000, 0).deadline();
        replugged.reconfigure(310000, values, ["lcd"]);
        replugged.reconfigure(310001 + IdleRules.shellOffWindow, values, ["lcd", "oled"]);
        assertEqual(replugged.actions, "hideSaver:lcd,back:d,active:false", "… back later (plugged in again, its button pressed): plugged in");
        assert(IdleRules.shellOffWindow > IdleRules.replugWindow, "a monitor powered off by the shell is given longer to come back");

        // The only monitor drops off at its power cut, and comes back with Qt's fields for its
        // id (no make): the same monitor, matched on its connector or loosely
        const offTimes = { screenOffEnabled: true, screenOffTimeout: 300, commandEntries: [darkCommands] };
        const backend = { id: "Dell|U27|SN", base: "Dell|U27|SN", connector: "DP-1" };
        const only = _machine(offTimes, [backend], true);
        only.idle(5000, 0).deadline();
        assertEqual(only.actions, "showSaver:Dell|U27|SN,powerOff:Dell|U27|SN,go:d,active:true", "(the only monitor off)");
        only.reconfigure(301000, offTimes, []);
        assertEqual(only.actions, "", "every monitor gone while dark: no action, still active");
        only.reconfigure(302000, offTimes, [{ id: "|U27|SN", base: "|U27|SN", connector: "DP-1" }]);
        assertEqual(only.actions, "showSaver:|U27|SN", "back under Qt's id, on its connector: its black surface, no wake, still active");
        only.reconfigure(303000, offTimes, [backend]);
        assertEqual(only.actions, "showSaver:Dell|U27|SN", "… and under the backend's id again: its black surface, no wake");
        const loose = _machine(offTimes, [backend], true);
        loose.idle(5000, 0).deadline();
        loose.reconfigure(301000, offTimes, []);
        loose.reconfigure(302000, offTimes, ["|U27|SN"]);
        assertEqual(loose.actions, "showSaver:|U27|SN", "back with no connector known, a field empty: matched loosely");
        const other = _machine(offTimes, [backend], true);
        other.idle(5000, 0).deadline();
        other.reconfigure(301000, offTimes, []);
        other.reconfigure(302000, offTimes, [{ id: "LG|27GL|9", base: "LG|27GL|9", connector: "DP-2" }]);
        assertEqual(other.actions, "back:d,active:false",
                    "another monitor plugged in where it went: plugged in");

        // A monitor that comes back powered after every cut: asked again after a growing pause,
        // then given up on — left under its black surface until input, which starts afresh
        const cycling = _machine(offTimes, [backend], true);
        cycling.idle(5000, 0).deadline();
        assertEqual(cycling.state.offAsks["Dell|U27|SN"], 1, "(off asked once)");
        const pauses = [];
        let clock = 300000;
        for (let round = 0; round < IdleRules.powerRetry.tries + 1; round++) {
            clock += 1000;
            cycling.reconfigure(clock, offTimes, []);
            clock += 1000;
            cycling.reconfigure(clock, offTimes, [backend]);
            const due = cycling.next();
            if (due < 0) {
                pauses.push("none");
                break;
            }
            pauses.push(due - clock);
            clock = due;
            cycling.deadline();
        }
        assertEqual(pauses.join(" "), [1, 2, 3, 4, 5, 6, 7].map(asks => IdleRules.powerRetryDelay(asks)).join(" ") + " none",
                    "back powered after each cut: each off after a longer pause, then none");
        assertEqual(cycling.actions, "showSaver:Dell|U27|SN", "… the last time only its black surface");
        assert(cycling.state.pendingPower["Dell|U27|SN"].gaveUp, "… given up for this period");
        const said = [];
        const gaveUp = _machine(offTimes, [backend], true);
        gaveUp.idle(5000, 0).deadline();
        clock = 300000;
        for (let round = 0; round < IdleRules.powerRetry.tries + 2; round++) {
            gaveUp.at(clock += 1000, { type: "power", power: { "Dell|U27|SN": "on" } });
            said.push(gaveUp.actions);
            const due = gaveUp.next();
            if (due >= 0) {
                gaveUp.at(clock = due, { type: "deadline" });
                said.push(gaveUp.actions);
            }
        }
        assertEqual(said.filter(text => text.startsWith("powerGaveUp")).length, 1, "read on after each off: the give-up said once");
        assertEqual(said.filter(text => text === "powerOff:Dell|U27|SN").length, IdleRules.powerRetry.tries - 1, "… after asking its most");
        gaveUp.input(clock += 1000);
        assertEqual(Object.keys(gaveUp.state.offAsks).length, 0, "input: the asks counted afresh");
        gaveUp.idle(clock + 5000, clock).deadline();
        assertEqual(gaveUp.actions, "showSaver:Dell|U27|SN,powerOff:Dell|U27|SN,go:d,active:true", "… the next period off at once again");

        // Back while showing the screensaver: never asked off, so its screen-off comes at once
        const saverBack = _machine(_with(offTimes, { screensaverEnabled: true, screensaverTimeout: 60 }), [backend], true);
        saverBack.idle(5000, 0).deadline();
        saverBack.reconfigure(61000, _with(offTimes, { screensaverEnabled: true, screensaverTimeout: 60 }), []);
        saverBack.reconfigure(62000, _with(offTimes, { screensaverEnabled: true, screensaverTimeout: 60 }), [backend]);
        saverBack.deadline();
        assertEqual(saverBack.actions, "powerOff:Dell|U27|SN", "a screensaver monitor back, then its screen-off: off at once, no pause");
        // The re-off says why it is asked (Idle logs it so), only on that ask
        const said2 = _machine(offTimes, [backend], true);
        said2.idle(5000, 0).deadline();
        said2.at(301000, { type: "power", power: { "Dell|U27|SN": "off" } });
        said2.at(302000, { type: "power", power: { "Dell|U27|SN": "on" } });
        const reOff = IdleRules.step(said2.state, { type: "deadline" }, said2.config, said2.next());
        assert(reOff.actions.length === 1 && reOff.actions[0].again === true, "the re-off: marked as one");
        const reState = IdleRules.step(reOff.state, { type: "power", power: { "Dell|U27|SN": "on" } }, said2.config, said2.next() + 100).state;
        const later = IdleRules.step(reState, { type: "deadline" }, said2.config, IdleRules.nextDeadline(reState, said2.config, said2.next() + 100));
        assert(later.actions.length === 1 && later.actions[0].type === "powerOff" && later.actions[0].again !== true,
               "… its own ask again (the reading still on) is not");

        // As Idle hands it: the only monitor gone ([]), the same id back
        const sameBack = _machine(offTimes, [backend], true);
        sameBack.idle(5000, 0).deadline();
        sameBack.reconfigure(301000, offTimes, []);
        sameBack.reconfigure(302000, offTimes, [backend]);
        assertEqual(sameBack.actions, "showSaver:Dell|U27|SN", "the same id back within its window: its black surface, no wake");
        const sameLate = _machine(offTimes, [backend], true);
        sameLate.idle(5000, 0).deadline();
        sameLate.reconfigure(301000, offTimes, []);
        sameLate.reconfigure(301001 + IdleRules.shellOffWindow, offTimes, [backend]);
        assertEqual(sameLate.actions, "back:d,active:false",
                    "the same id back after its window (switched on by its button): plugged in");
        const otherLate = _machine(offTimes, [backend], true);
        otherLate.idle(5000, 0).deadline();
        otherLate.reconfigure(301000, offTimes, []);
        otherLate.reconfigure(301001 + IdleRules.shellOffWindow, offTimes, [{ id: "LG|27GL|9", base: "LG|27GL|9", connector: "DP-1" }]);
        assertEqual(otherLate.actions, "back:d,active:false", "another monitor on its connector after the window: plugged in");
        const saverLate = _machine(saver, [backend], true);
        saverLate.idle(5000, 0).deadline();
        saverLate.reconfigure(301000, saver, []);
        assertEqual(saverLate.actions, "", "(the screensaver monitor gone: still active)");
        saverLate.reconfigure(317000, saver, [backend]);
        assertEqual(saverLate.actions, "back:d,active:false", "the screensaver monitor back after 16 s: plugged in");

        const named = _machine(offTimes, [backend], true);
        named.idle(5000, 0).deadline();
        named.reconfigure(301000, offTimes, []);
        named.reconfigure(302000, offTimes, [{ id: "|DELL U27|", base: "|DELL U27|", connector: "DP-1" }]);
        assertEqual(named.actions, "showSaver:|DELL U27|", "back with fields that match nothing, on its connector: the same monitor");
        const byIdOnly = _machine(saver, ["lcd", "tv"], true);
        byIdOnly.idle(5000, 0).deadline();
        byIdOnly.reconfigure(310000, saver, ["lcd"]);
        byIdOnly.reconfigure(311000, saver, ["lcd", "dock"]);
        assertEqual(byIdOnly.actions, "hideSaver:lcd,back:d,active:false", "another monitor in time, neither with a connector: plugged in");
        const emptied = _machine(offTimes, [backend], true);
        emptied.idle(5000, 0).deadline();
        emptied.reconfigure(301000, offTimes, [], false);
        assertEqual(emptied.actions, "", "no monitor left as power control goes: still active");

        // Where the monitors come from changes (power control found: Qt's ids, then the
        // backend's): never a plug-in, each keeps what it had
        const qtForm = { id: "|U27|SN", base: "|U27|SN", connector: "DP-1" };
        const start = _machine(offTimes, [qtForm], false);
        start.idle(5000, 0).deadline();
        assertEqual(start.actions, "showSaver:|U27|SN,go:d,active:true", "(no power control: the screensaver at the screen-off's time)");
        start.reconfigure(301000, offTimes, [backend], true);
        assertEqual(start.actions, "powerOff:Dell|U27|SN", "power control found: the same monitor under the backend's id, now off — no wake");
        assertEqual(start.state.stage["Dell|U27|SN"], 2, "… its stage kept");
        const fresh = _machine(offTimes, [qtForm], false);
        fresh.idle(5000, 0);
        fresh.reconfigure(6000, offTimes, [backend], true);
        assert(fresh.actions === "" && fresh.state.idleSince === 0, "the first reading after a start: no plug-in, the counting goes on");
        fresh.reconfigure(7000, offTimes, [backend, { id: "LG|27GL|9", base: "LG|27GL|9", connector: "DP-2" }], false);
        assertEqual(fresh.state.idleSince, 0, "power control lost with a monitor more: not a plug-in either");

        // Showing the screensaver, gone and back: within the window the same monitor, after it
        // a plug-in
        const shortly = _machine(saver, ["lcd", "tv"], true);
        shortly.idle(5000, 0).deadline();
        shortly.at(301000, { type: "busInhibitors", count: 1 });
        shortly.reconfigure(310000, saver, ["lcd"]);
        shortly.reconfigure(310000 + IdleRules.replugWindow, saver, ["lcd", "tv"]);
        assertEqual(shortly.actions, "showSaver:tv", "dark, gone and back within the window: its stage again (held: from what it had)");
        const after = _machine(saver, ["lcd", "tv"], true);
        after.idle(5000, 0).deadline();
        after.reconfigure(310000, saver, ["lcd"]);
        after.reconfigure(310001 + IdleRules.replugWindow, saver, ["lcd", "tv"]);
        assertEqual(after.actions, "hideSaver:lcd,back:d,active:false", "… back after the window: plugged in");

        // Gone while showing the desktop, back: plugged in
        const onGone = _machine(_own(saver, { tv: _entry(600, 0) }), ["lcd", "tv"], true);
        onGone.idle(5000, 0).deadline();
        onGone.reconfigure(310000, _own(saver, { tv: _entry(600, 0) }), ["lcd"]);
        onGone.reconfigure(311000, _own(saver, { tv: _entry(600, 0) }), ["lcd", "tv"]);
        assertEqual(onGone.actions, "hideSaver:lcd,back:d,active:false", "gone while on, back at once: plugged in");

        // Back under the other form of its id (a twin's connector): the same monitor
        const twin = { id: "A|B||DP-1", base: "A|B|", connector: "DP-1" };
        const alone = { id: "A|B|", base: "A|B|", connector: "DP-1" };
        const form = _machine(_with(saver, { screenOffEnabled: true, screenOffTimeout: 400 }), [twin, "lcd"], true);
        form.idle(5000, 0).deadline();
        form.deadline();
        form.reconfigure(410000, _with(saver, { screenOffEnabled: true, screenOffTimeout: 400 }), ["lcd"]);
        form.reconfigure(420000, _with(saver, { screenOffEnabled: true, screenOffTimeout: 400 }), [alone, "lcd"]);
        assertEqual(form.actions, "showSaver:A|B|", "back under its plain id: its black surface, no wake");

        // Not plug-ins: the first step, and a change while going to sleep
        const first = _machine(saver, ["lcd", "tv"], true);
        first.idle(5000, 0).deadline();
        assertEqual(first.actions, "showSaver:lcd+tv,go:d,active:true", "the monitors at the first step: none plugged in");
        first.at(310000, { type: "sleep" });
        first.reconfigure(320000, saver, ["lcd", "tv", "dock"]);
        assertEqual(first.actions, "", "a monitor appearing while going to sleep: nothing (the resume wakes)");
    }

    function _sleep() {
        const values = _with(saver, { lockscreenEnabled: true, lockAfter: 400 });
        const machine = _machine(values, ["lcd"], true);
        machine.idle(5000, 0).deadline();
        machine.at(310000, { type: "sleep" });
        assertEqual(machine.actions, "", "sleep: nothing changes");
        assertEqual(machine.next(), -1, "… no deadline");
        machine.at(500000, { type: "deadline" });
        assertEqual(machine.actions, "", "… a deadline while asleep does nothing (no lock)");
        machine.at(311000, { type: "inputIdle", idle: false });
        assertEqual(machine.actions, "", "… the hand that closed the lid wakes nothing");
        machine.at(900000, { type: "resumed" });
        assertEqual(machine.actions, "hideSaver:lcd,back:d,active:false",
                    "resumed: counts as input, no screensaver over the desktop after a wake");
        assertEqual(machine.state.idleSince, 900000, "… the counting from the resume");

        const locked = _machine(_with(saver, { screenOffEnabled: true, screenOffTimeout: 600 }), ["lcd"], true);
        locked.idle(5000, 0).deadline();
        locked.deadline();
        locked.at(700000, { type: "locked" });
        locked.at(710000, { type: "sleep" });
        locked.at(900000, { type: "resumed" });
        assertEqual(locked.actions, "powerOn:lcd,hideSaver:lcd,back:d",
                    "resumed while locked: the monitors the shell turned off on again, the lock stays (active)");
        assertEqual(locked.next(), 960000, "… the lock screen's screen-off from the resume");
    }

    // Sleep after idle: the whole computer, logind's Suspend, once per idle period
    function _sleepStage() {
        const rules = IdleRules;
        // (The lock screen's own screen-off off: its steps would stand between)
        const values = { sleepEnabled: true, sleepTimeout: 1800, lockedScreenOffTimeout: 0 };
        assertEqual(rules.config(values, ["lcd"], true, "yes").sleepAfter, 1800, "sleep on where logind answers CanSuspend yes: a stage");
        for (const answer of ["challenge", "no", "na", "unknown", undefined])
            assertEqual(rules.config(values, ["lcd"], true, answer).sleepAfter, 0,
                        "CanSuspend " + answer + ": no sleep stage (never called; challenge would ask for a password)");
        assertEqual(rules.config({ sleepTimeout: 1800 }, ["lcd"], true, "yes").sleepAfter, 0, "sleep off unless switched on");
        assertEqual(rules.config({ sleepEnabled: true }, ["lcd"], true, "yes").sleepAfter, 1800, "… its time unset: 30 min");
        const challenged = _machine(values, ["lcd"], true, "challenge").idle(5000, 0);
        assertEqual(challenged.next(), -1, "challenge: no deadline for it");
        challenged.at(4000000, { type: "deadline" });
        assertEqual(challenged.actions, "", "… nor a call, however long idle");
        assert(!rules.logindReadDue(challenged.state, challenged.config, 4000000), "… nor a read for it");

        // The due time, from the last input; asked once per period
        const plain = _machine(values, ["lcd"], true, "yes").idle(5000, 0);
        assertEqual(plain.next(), 1800000, "due 30 min after the last input");
        assert(!rules.logindReadDue(plain.state, plain.config, 1799999), "… nothing read a moment before");
        assert(rules.logindReadDue(plain.state, plain.config, 1800000), "… logind's inhibitors read first");
        plain.at(1800000, { type: "deadline" });
        assertEqual(plain.actions, "", "… never asked without that read");
        assertEqual(plain.next(), 1800000, "… the read still due");
        plain.sleepDeadline();
        assertEqual(plain.actions, "sleep:unlocked", "then the sleep asked, unlocked as the settings say (no lock before it)");
        assertEqual(plain.next(), -1, "… asked once");
        plain.at(3600000, { type: "deadline" });
        assertEqual(plain.actions, "", "… not again in the same period");
        assert(!rules.logindReadDue(plain.state, plain.config, 3600000), "… nor read for again");
        plain.at(3601000, { type: "sleep" }).at(3700000, { type: "resumed" });
        assertEqual(plain.state.sleepAsked, false, "the resume: a new period");
        plain.idle(3705000, 3700000);
        assertEqual(plain.next(), 3700000 + 1800000, "… the sleep due again from the resume");
        plain.input(3800000).idle(3805000, 3800000);
        assertEqual(plain.next(), 3800000 + 1800000, "input: counted from it");

        // Held by the apps keeping the screen on, unlocked only
        const held = _machine(values, ["lcd"], true, "yes").idle(5000, 0);
        held.at(60000, { type: "busInhibitors", count: 1 });
        assertEqual(held.next(), -1, "an app keeping the screen on holds the sleep");
        held.at(2000000, { type: "deadline" });
        assertEqual(held.actions, "", "… past its time too");
        held.at(2100000, { type: "busInhibitors", count: 0 });
        assertEqual(held.next(), 2100000 + 1800000, "released: counted from the release");
        const wayland = _machine(values, ["lcd"], true, "yes").at(5000, { type: "inputIdle", idle: true, since: 0 });
        assertEqual(wayland.next(), -1, "a Wayland client holding idle off holds the sleep");
        const lockedHeld = _machine(values, ["lcd"], true, "yes").idle(5000, 0);
        lockedHeld.at(10000, { type: "locked" }).at(20000, { type: "busInhibitors", count: 1 });
        assertEqual(lockedHeld.next(), 1800000, "locked: the apps are ignored, the sleep comes at its time");
        lockedHeld.sleepDeadline();
        assertEqual(lockedHeld.actions, "sleep:locked", "… asked, from a locked session");
        const forcedHeld = _machine(_with(values, { screensaverEnabled: true, screensaverTimeout: 300 }), ["lcd"], true, "yes");
        forcedHeld.at(1000, { type: "busInhibitors", count: 1 }).at(2000, { type: "force" });
        assertEqual(forcedHeld.next(), -1, "a forced screensaver with an app keeping the screen on: no sleep (the force only shows the screensaver)");
        forcedHeld.at(4000000, { type: "deadline" });
        assertEqual(forcedHeld.actions, "", "… however long");
        const forced = _machine(_with(values, { screensaverEnabled: true, screensaverTimeout: 600 }), ["lcd"], true, "yes")
            .at(1000, { type: "force" });
        assertEqual(forced.actions.includes("sleep"), false, "a force with the screensaver at 10 min and sleep at 30: no sleep at once");
        assertEqual(forced.next(), 1000 + 1200000, "… the sleep 20 min after the force, as after the screensaver's own time");
        forced.sleepDeadline();
        assertEqual(forced.actions, "sleep:unlocked", "… asked then, after a read");
        const forcedLong = _machine(_with(values, { screensaverEnabled: true, screensaverTimeout: 3600 }), ["lcd"], true, "yes")
            .at(1000, { type: "force" });
        assertEqual(forcedLong.actions.includes("sleep"), false, "the screensaver at 60 min, sleep at 30: a force does not sleep at once");
        assertEqual(forcedLong.next(), 1000 + 1800000, "… the sleep its whole time after the force");
        const forcedClose = _machine(_with(values, { screensaverEnabled: true, screensaverTimeout: 1799 }), ["lcd"], true, "yes")
            .at(1000, { type: "force" });
        assertEqual(forcedClose.next(), 1000 + 1000, "the screensaver a second before the sleep: the sleep a second after the force");
        forcedLong.at(500000, { type: "busInhibitors", count: 1 });
        assertEqual(forcedLong.next(), -1, "… an app keeping the screen on after the force holds it");

        // logind's sleep block: read before the call, locked or not; held → paused, read again
        const blocked = _machine(values, ["lcd"], true, "yes").idle(5000, 0);
        blocked.at(1800000, { type: "logindSleepBlock", held: true });
        assertEqual(blocked.actions, "", "a sleep block held (a backup): no call");
        assertEqual(blocked.next(), 1800000 + IdleRules.logindRecheck, "… read again after a while");
        assert(rules.logindReadDue(blocked.state, blocked.config, blocked.next()), "… a read then");
        blocked.at(1830000, { type: "logindSleepBlock", held: false });
        assertEqual(blocked.actions, "sleep:unlocked", "free again: the sleep asked");
        const oneRead = _machine(values, ["lcd"], true, "yes").idle(5000, 0)
            .at(1800000, { type: "logindIdleBlock", held: false, sleepHeld: true });
        assert(oneRead.actions === "" && oneRead.state.logindSleepBlock === true,
               "one read's idle and sleep blocks in one step: the sleep block holds (never asked on half a read)");
        assertEqual(_machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1800000, { type: "logindIdleBlock", held: false }).state.logindSleepBlock,
                    "unknown", "an idle block's read alone leaves the sleep block as it was (not read)");
        assertEqual(_machine(values, ["lcd"], true, "yes").at(1000, { type: "logindIdleBlock", held: false, sleepHeld: "junk" }).state.logindSleepBlock,
                    "unknown", "a sleep block not understood: unknown");
        const lockedBlock = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(10000, { type: "locked" });
        assert(rules.logindReadDue(lockedBlock.state, lockedBlock.config, 1800000), "locked: logind's sleep block is still read");
        lockedBlock.at(1800000, { type: "logindSleepBlock", held: true });
        assertEqual(lockedBlock.actions, "", "… and holds the sleep");
        assertEqual(lockedBlock.next(), 1800000 + IdleRules.logindRecheck, "… read again");
        const unread = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1800000, { type: "logindSleepBlock", held: "unknown" });
        assertEqual(unread.actions, "", "a failed read: never asked blind");
        assertEqual(unread.next(), 1800000 + IdleRules.sleepReadRetry.minimum, "… read again after a pause");
        unread.sleepDeadline("unknown");
        assertEqual(unread.actions, "", "… failed again: still not asked");
        assertEqual(unread.next(), 1805000 + 2 * IdleRules.sleepReadRetry.minimum, "… the pause grows");
        unread.sleepDeadline();
        assertEqual(unread.actions, "sleep:unlocked", "… a read that finds no block: asked");
        const recount = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1800000, { type: "logindSleepBlock", held: "unknown" })
            .at(1805000, { type: "logindSleepBlock", held: true }).at(1835000, { type: "logindSleepBlock", held: "unknown" });
        assertEqual(recount.next(), 1835000 + IdleRules.sleepReadRetry.minimum, "a read that told, between two that could not: the pause starts again");
        const afterInput = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1800000, { type: "logindSleepBlock", held: "unknown" })
            .at(1801000, { type: "logindSleepBlock", held: "unknown" });
        afterInput.input(1900000).idle(1905000, 1900000).at(3700000, { type: "logindSleepBlock", held: "unknown" });
        assertEqual(afterInput.next(), 3700000 + IdleRules.sleepReadRetry.minimum, "input: the failed reads before count no more");
        assertEqual(rules.sleepReadRetryDelay(0), 0, "no failed read: no pause");
        assertEqual([0, 1, 2, 3, 30].map(tries => rules.supportRetryDelay(tries)).join(" "),
                    "0 " + IdleRules.supportRetry.minimum + " " + 2 * IdleRules.supportRetry.minimum + " " + 4 * IdleRules.supportRetry.minimum
                    + " " + IdleRules.supportRetry.maximum, "logind's sleep support not read: read again after a growing pause, to a ceiling");
        assertEqual(rules.sleepReadRetryDelay(20), IdleRules.sleepReadRetry.maximum, "the pause has a ceiling");
        const early = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1000000, { type: "logindIdleBlock", held: false, sleepHeld: false });
        assertEqual(early.next(), 1800000, "a read before the sleep's time does not count for it");
        early.at(1800000, { type: "deadline" });
        assertEqual(early.actions, "", "… not asked on it");
        const stale = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1800000, { type: "logindSleepBlock", held: true });
        stale.input(1900000);
        assertEqual(stale.state.logindSleepBlock, "unknown", "input: a block seen before says nothing of the next sleep");
        stale.idle(1905000, 1900000);
        assertEqual(stale.next(), 1900000 + 1800000, "… the next sleep counted, read before it");

        // Lock first: an idle lock due at or before the sleep is waited for
        const both = _machine(_with(values, { lockscreenEnabled: true, lockAfter: 1800 }), ["lcd"], true, "yes").idle(5000, 0);
        both.sleepDeadline();
        assertEqual(both.actions, "lock", "lock and sleep at one time: the lock asked first, the sleep waits for it");
        assertEqual(both.next(), 1800000 + IdleRules.sleepLockWait, "… at most a moment");
        both.at(1801000, { type: "locked" });
        assertEqual(both.actions, "sleep:locked,active:true", "locked: the sleep now");
        const quickBoth = _machine(_with(values, { sleepTimeout: 1, lockscreenEnabled: true, lockAfter: 1 }), ["lcd"], true, "yes").idle(500, 0);
        quickBoth.sleepDeadline();
        assertEqual(quickBoth.actions, "lock", "lock and sleep both after one second: the lock first, the sleep waits for it");
        const refused = _machine(_with(values, { lockscreenEnabled: true, lockAfter: 1800 }), ["lcd"], true, "yes").idle(5000, 0);
        refused.sleepDeadline();
        refused.sleepDeadline();
        assertEqual(refused.actions, "lock,sleep:locked",
                    "the lock not taken: asked again, then the sleep after the wait — not taken as the settings' choice (the notice counts it)");
        const earlier = _machine(_with(values, { lockscreenEnabled: true, lockAfter: 600 }), ["lcd"], true, "yes").idle(5000, 0);
        earlier.sleepDeadline();
        earlier.at(601000, { type: "locked" });
        assertEqual(earlier.next(), 1800000, "the lock long before: the sleep at its own time");
        earlier.sleepDeadline();
        assertEqual(earlier.actions, "sleep:locked", "… from the locked session");
        const later = _machine(_with(values, { lockscreenEnabled: true, lockAfter: 3600 }), ["lcd"], true, "yes").idle(5000, 0);
        assertEqual(later.next(), 1800000, "the idle lock later than the sleep: not waited for");
        later.sleepDeadline();
        assertEqual(later.actions, "sleep:unlocked", "… it sleeps unlocked, as the settings say");
        const onSleep = _machine(_with(values, { lockOnSleep: true }), ["lcd"], true, "yes").idle(5000, 0);
        onSleep.sleepDeadline();
        assertEqual(onSleep.actions, "sleep:locked", "Lock before the computer sleeps: asked as locked (it locks at PrepareForSleep)");
        assert(!rules.sleepLeftUnlocked({ locked: false }, rules.config(_with(values, { lockscreenEnabled: true, lockAfter: 1800 }), [], true, "yes")),
               "an idle lock at the sleep's time: not left unlocked");
        assert(rules.sleepLeftUnlocked({ locked: false }, rules.config(_with(values, { lockscreenEnabled: true, lockAfter: 1801 }), [], true, "yes")),
               "… a second later: left unlocked");
        const failed = _machine(values, ["lcd"], true, "yes").idle(5000, 0);
        failed.sleepDeadline().at(1801000, { type: "sleepFailed" });
        assert(failed.state.sleepAsked && !failed.state.sleepLeftUnlocked, "logind refused: not asked again, and no sleep of ours to excuse");
        assertEqual(failed.next(), -1, "… no deadline for it");

        // A switch that makes the sleep due counts from the switch, never sleeps at once
        const switched = _machine({}, ["lcd"], true, "yes").idle(5000, 0);
        switched.reconfigure(3600000, values);
        assertEqual(switched.actions, "", "sleep switched on past its time: not at once");
        assertEqual(switched.next(), 3600000 + 1800000, "… counted from the switch");
        const notYet = _machine({ sleepEnabled: true, sleepTimeout: 3600 }, ["lcd"], true, "yes").idle(5000, 0);
        notYet.reconfigure(600000, values);
        assertEqual(notYet.next(), 1800000, "a shorter time not yet reached: from the last input");
        const dueThen = _machine({ sleepEnabled: true, sleepTimeout: 3600, lockedScreenOffTimeout: 0 }, ["lcd"], true, "yes").idle(5000, 0);
        dueThen.reconfigure(1800000, values);
        assertEqual(dueThen.next(), 3600000, "shortened to just now: due from the switch, not at once");
        const dueAnyway = _machine({ sleepEnabled: true, sleepTimeout: 3600, lockedScreenOffTimeout: 0 }, ["lcd"], true, "yes").idle(5000, 0);
        dueAnyway.reconfigure(3600000, values);
        assertEqual(dueAnyway.next(), 3600000, "shortened just as the sleep fell due: not put off");
        dueAnyway.sleepDeadline();
        assertEqual(dueAnyway.actions, "sleep:unlocked", "… asked after the read");
        const blockedSwitch = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1800000, { type: "logindSleepBlock", held: true });
        blockedSwitch.reconfigure(2000000, _with(values, { sleepTimeout: 1700 }));
        blockedSwitch.at(2010000, { type: "logindIdleBlock", held: false, sleepHeld: false });
        assertEqual(blockedSwitch.actions, "sleep:unlocked", "a time changed while a block held the sleep due: asked once the block goes");
        // Forced: the old time's due moment counts from the force, less the screensaver's time
        // (25 min after a force at 1 s), as the new one's does — due before the switch, not put off
        const forcedValues = _with(values, { screensaverEnabled: true, screensaverTimeout: 300 });
        const forcedSwitch = _machine(forcedValues, ["lcd"], true, "yes").at(1000, { type: "force" })
            .at(1501000, { type: "logindSleepBlock", held: true });
        forcedSwitch.reconfigure(1600000, _with(forcedValues, { sleepTimeout: 1700 }));
        forcedSwitch.at(1610000, { type: "logindIdleBlock", held: false, sleepHeld: false });
        assertEqual(forcedSwitch.actions, "sleep:unlocked",
                    "forced: a time changed while a block held the sleep due: asked once the block goes, not counted from the switch");
        const firstStep = _machine(values, ["lcd"], true, "yes").idle(1800000, 0).sleepDeadline();
        assertEqual(firstStep.actions, "sleep:unlocked", "a sleep due at the step that makes the idle known: asked");
        const forcedFirst = _machine(_with(values, { screensaverEnabled: true, screensaverTimeout: 1800 }), ["lcd"], true, "yes")
            .at(2000000, { type: "force" });
        assert(!forcedFirst.actions.includes("sleep"), "a force never sleeps at once, even at the very first step: " + forcedFirst.actions);
        assertEqual(forcedFirst.next(), 2000000 + 1800000, "… the sleep its whole time after it (the screensaver's time equals it)");
        const firstRead = _machine(values, ["lcd"], true, "yes");
        firstRead.state = Object.assign({}, firstRead.state, { inputIdle: true, awayIdle: true, idleSince: 0 });
        firstRead.at(1800000, { type: "logindIdleBlock", held: false, sleepHeld: false });
        assertEqual(firstRead.actions, "sleep:unlocked", "the very first step: a sleep already due, read free, is asked (no switch to count from)");
        const second = _machine({ sleepEnabled: true, sleepTimeout: 1 }, ["lcd"], true, "yes").idle(500, 0);
        assertEqual(second.next(), 1000, "a sleep after one second: due after it, with no lock to wait for");
        second.sleepDeadline();
        assertEqual(second.actions, "sleep:unlocked", "… asked then");
        assert(rules.sleepLeftUnlocked({ locked: false }, rules.config(_with(values, { lockscreenEnabled: true, lockAfter: 1 }), [], true, "yes")) === false,
               "an idle lock after one second, before the sleep: not left unlocked");
        const heldBlocked = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1800000, { type: "logindSleepBlock", held: true });
        heldBlocked.at(1810000, { type: "busInhibitors", count: 1 });
        assertEqual(heldBlocked.next(), -1, "blocked, then an app keeps the screen on: no re-read for the sleep while that holds");
        const freed = _machine(values, ["lcd"], true, "yes").idle(5000, 0).at(1800000, { type: "logindIdleBlock", held: false, sleepHeld: true });
        freed.at(1830000, { type: "logindIdleBlock", held: false, sleepHeld: false });
        assertEqual(freed.actions, "sleep:unlocked", "the next read finds the sleep block gone: the sleep asked");
        const answered = _machine(values, ["lcd"], true, "unknown").idle(5000, 0);
        answered.config = rules.config(values, ["lcd"], true, "yes");
        answered.at(3600000, { type: "config" });
        assertEqual(answered.actions, "", "logind's yes coming late: no sleep at once");
        assertEqual(answered.next(), 3600000 + 1800000, "… counted from then");
    }

    // Hibernation: with sleep on, the sleep's call becomes SuspendThenHibernate (the system's
    // delay); with sleep off, a stage of its own counted from the last stage switched on
    // before it — the screensaver, the lock, or neither (the last input) — and logind's
    // Hibernate, under the sleep's rules (holders, blocks, a fresh read, logind's "yes")
    function _hibernate() {
        const rules = IdleRules;
        const hours = { hibernateEnabled: true, hibernateTimeout: 7200, lockedScreenOffTimeout: 0 };
        const lockAt20 = _with(hours, { lockscreenEnabled: true, lockAfter: 1200, screensaverEnabled: true, screensaverTimeout: 300 });
        const fromLock = rules.config(lockAt20, ["lcd"], true, "yes", "yes", "yes");
        assertEqual(JSON.stringify(fromLock.hibernate), JSON.stringify({ on: true, from: "lock", at: 1200, after: 7200 }),
                    "sleep off, the lock at 20 min after the screensaver at 5: counted from the lock");
        assertEqual(fromLock.hibernateAfter, 8400, "… hibernation at 2 h 20 min from the last input");
        assertEqual(fromLock.sleepThenHibernate, false, "… no sleep to hibernate from");
        const fromSaver = rules.config(_with(lockAt20, { screensaverTimeout: 1800 }), ["lcd"], true, "yes", "yes", "yes");
        assertEqual(fromSaver.hibernate.from + " " + fromSaver.hibernateAfter, "saver 9000",
                    "the screensaver at 30 min after the lock at 20: counted from the screensaver");
        const tie = rules.config(_with(lockAt20, { screensaverTimeout: 1200 }), ["lcd"], true, "yes", "yes", "yes");
        assertEqual(tie.hibernate.from, "lock", "the screensaver and the lock at one time: from the lock");
        const neither = rules.config(hours, ["lcd"], true, "yes", "yes", "yes");
        assertEqual(neither.hibernate.from + " " + neither.hibernateAfter, "input 7200", "neither on: from the last input");
        const offOnly = rules.config(_with(hours, { screenOffEnabled: true, screenOffTimeout: 600 }), ["lcd"], true, "yes", "yes", "yes");
        assertEqual(offOnly.hibernate.from, "input", "a screen-off is not the screensaver: still from the last input");
        const perMonitor = rules.config(_own(_with(hours, { screensaverEnabled: true, screensaverTimeout: 300 }),
                                             { oled: _entry(900, 0), panel: _entry(0, 300) }),
                                        ["lcd", "oled", "panel"], true, "yes", "yes", "yes");
        assertEqual(perMonitor.hibernate.from + " " + perMonitor.hibernate.at, "saver 900",
                    "per monitor: from the latest screensaver of the connected monitors");
        const unplugged = rules.config(_own(_with(hours, { screensaverEnabled: true, screensaverTimeout: 300 }), { oled: _entry(900, 0) }),
                                       ["lcd"], true, "yes", "yes", "yes");
        assertEqual(unplugged.hibernate.at, 300, "… a monitor not connected does not count");
        for (const answer of ["challenge", "no", "na", "unknown", undefined]) {
            const config = rules.config(lockAt20, ["lcd"], true, "yes", answer, "yes");
            assertEqual(config.hibernate.on + " " + config.hibernateAfter, "false 0",
                        "sleep off, CanHibernate " + answer + ": no hibernation (never called; challenge would ask for a password)");
        }
        assertEqual(rules.config(_with(lockAt20, { hibernateEnabled: false }), ["lcd"], true, "yes", "yes", "yes").hibernateAfter, 0,
                    "switched off: none");
        assertEqual(rules.config({ hibernateEnabled: true }, ["lcd"], true, "yes", "yes", "yes").hibernateAfter, 7200,
                    "its time unset: 2 h");
        assertEqual(rules.config(hours, ["lcd"], true, "yes").hibernateAfter, 0, "logind's answers not given: none");
        const withSleep = _with(hours, { sleepEnabled: true, sleepTimeout: 1800 });
        const thenHibernate = rules.config(withSleep, ["lcd"], true, "yes", "na", "yes");
        assertEqual(JSON.stringify(thenHibernate.hibernate), JSON.stringify({ on: true, from: "sleep", at: 1800, after: 7200 }),
                    "sleep on: counted from the sleep (the system's delay)");
        assertEqual(thenHibernate.sleepThenHibernate + " " + thenHibernate.hibernateAfter, "true 0",
                    "… the sleep asks SuspendThenHibernate, no stage of its own (CanHibernate does not matter then)");
        for (const answer of ["challenge", "no", "na", "unknown"]) {
            const config = rules.config(withSleep, ["lcd"], true, "yes", "yes", answer);
            assertEqual(config.sleepThenHibernate + " " + config.hibernateAfter + " " + config.sleepAfter, "false 0 1800",
                        "sleep on, CanSuspendThenHibernate " + answer + ": a plain sleep, no hibernation");
        }
        const noSleepHere = rules.config(_with(withSleep, { lockscreenEnabled: true, lockAfter: 1200 }), ["lcd"], true, "na", "yes", "yes");
        assertEqual(noSleepHere.hibernate.from + " " + noSleepHere.hibernateAfter, "lock 8400",
                    "sleep switched on where the computer cannot sleep: hibernation counted as with sleep off");
        assertEqual(JSON.stringify(rules.hibernateBase(0, 0, 0)), JSON.stringify({ from: "input", at: 0 }), "the base: nothing on, the input");
        assertEqual(rules.machineAfter({ sleepAfter: 0, hibernateAfter: 8400 }), 8400, "the whole computer's stage: the hibernation with sleep off");
        assertEqual(rules.machineAfter({ sleepAfter: 1800, hibernateAfter: 8400 }), 1800, "… the sleep when it is on");
        assertEqual(rules.machineAfter({ hibernateAfter: 8400 }), 8400, "… a config without a sleep: the hibernation");
        assertEqual(JSON.stringify(rules.hibernateBase(0, 0, 1)), JSON.stringify({ from: "lock", at: 1 }), "a lock after one second is a stage");
        const noMonitors = rules.config(_with(hours, { screensaverEnabled: true, screensaverTimeout: 600 }), [], true, "yes", "yes", "yes");
        assertEqual(noMonitors.hibernate.from + " " + noMonitors.hibernate.at, "saver 600", "no monitor connected: the default's screensaver");
        const oneOwn = rules.config(_own(_with(hours, { screensaverEnabled: true, screensaverTimeout: 300 }), { oled: _entry(900, 0) }),
                                    ["oled"], true, "yes", "yes", "yes");
        assertEqual(oneOwn.hibernate.at, 900, "one monitor with its own screensaver: its time, not the default's");
        assertEqual(rules.config({ hibernateTimeout: 7200 }, ["lcd"], true, "yes", "yes", "yes").hibernate.on, false, "not switched on: off");
        assertEqual(rules.config(_with(hours, { hibernateTimeout: 0 }), ["lcd"], true, "yes", "yes", "yes").hibernate.on, false, "a time of 0: none");
        assertEqual(rules.config(_with(hours, { hibernateTimeout: 1 }), ["lcd"], true, "yes", "yes", "yes").hibernateAfter, 1, "a time of one second: on");
        const quickSleep = rules.config(_with(hours, { sleepEnabled: true, sleepTimeout: 1 }), ["lcd"], true, "yes", "na", "yes");
        assertEqual(quickSleep.sleepThenHibernate + " " + quickSleep.hibernateAfter, "true 0",
                    "a sleep after one second: still the sleep's hibernation (CanSuspendThenHibernate)");

        // The stage on the clock: from the lock at 20 min, 2 h later; once; locked first
        const machine = _machine(lockAt20, ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        machine.at(1200000, { type: "deadline" });
        assertEqual(machine.actions, "showSaver:lcd,lock,active:true", "the lock at 20 min (the screensaver's deadline taken late)");
        machine.at(1201000, { type: "locked" });
        assertEqual(machine.next(), 8400000, "… hibernation due 2 h after the lock");
        machine.sleepDeadline();
        assertEqual(machine.actions, "hibernate:locked", "… asked after a read found no sleep block, from the locked session");
        assertEqual(machine.state.sleepAsked, true, "… once in this period");
        assertEqual(machine.next(), -1, "… not again");
        machine.at(8401000, { type: "sleep" }).at(9000000, { type: "resumed" });
        assertEqual(machine.state.sleepAsked, false, "the resume: a new period");
        const fromInput = _machine(hours, ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        assertEqual(fromInput.next(), 7200000, "neither stage on: 2 h after the last input");
        fromInput.sleepDeadline();
        assertEqual(fromInput.actions, "hibernate:unlocked", "… asked, unlocked as the settings say (no lock, no lock before sleep)");
        const saverBase = _machine(_with(hours, { screensaverEnabled: true, screensaverTimeout: 600 }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        saverBase.deadline();
        assertEqual(saverBase.actions, "showSaver:lcd,active:true", "the screensaver at 10 min");
        assertEqual(saverBase.next(), 7800000, "… hibernation 2 h after it");
        const onSleep = _machine(_with(hours, { lockOnSleep: true }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        onSleep.sleepDeadline();
        assertEqual(onSleep.actions, "hibernate:locked", "Lock before the computer sleeps: it locks at the PrepareForSleep");

        // Never on logind's no: nothing is ever asked
        for (const answer of ["challenge", "no", "na", "unknown"]) {
            const never = _machine(lockAt20, ["lcd"], true, "yes", answer, answer).idle(5000, 0);
            never.at(1200000, { type: "deadline" }).at(1201000, { type: "locked" });
            assertEqual(never.next(), -1, "CanHibernate " + answer + ": nothing due after the lock");
            never.at(9000000, { type: "logindIdleBlock", held: false, sleepHeld: false });
            assertEqual(never.actions, "", "… nor asked later");
        }

        // Holders, blocks, a fresh read: the sleep's rules
        const held = _machine(hours, ["lcd"], true, "yes", "yes", "yes").idle(5000, 0).at(6000, { type: "busInhibitors", count: 1 });
        assertEqual(held.next(), -1, "an app keeping the screen on holds the hibernation while unlocked");
        const lockedHeld = _machine(hours, ["lcd"], true, "yes", "yes", "yes").idle(5000, 0)
            .at(6000, { type: "busInhibitors", count: 1 }).at(7000, { type: "locked" });
        assertEqual(lockedHeld.next(), 7200000, "locked (by hand): the apps are ignored, it comes at its time");
        const blocked = _machine(hours, ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        blocked.sleepDeadline(true);
        assertEqual(blocked.actions, "", "a sleep block held (a backup): no call");
        assertEqual(blocked.next(), 7200000 + IdleRules.logindRecheck, "… read again later");
        blocked.sleepDeadline(false);
        assertEqual(blocked.actions, "hibernate:unlocked", "free again: asked");
        const blind = _machine(hours, ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        blind.at(7200000, { type: "deadline" });
        assertEqual(blind.actions, "", "due, but no read since: never asked blind");
        blind.at(7200000, { type: "logindIdleBlock", held: false, sleepHeld: "unknown" });
        assertEqual(blind.actions, "", "a read that could not tell: not asked");
        const stale = _machine(hours, ["lcd"], true, "yes", "yes", "yes").idle(5000, 0).at(7000000, { type: "logindSleepBlock", held: false });
        stale.at(7200000, { type: "deadline" });
        assertEqual(stale.actions, "", "a read before its time does not count for it");

        // A force: as long after it as after the screensaver's own time
        const forced = _machine(_with(hours, { screensaverEnabled: true, screensaverTimeout: 300 }), ["lcd"], true, "yes", "yes", "yes")
            .at(1000, { type: "force" });
        assert(!forced.actions.includes("hibernate"), "a force never hibernates at once: " + forced.actions);
        assertEqual(forced.next(), 1000 + 7200000, "… 2 h after the force (2 h after the screensaver it stands for)");

        // With sleep on: the sleep asks SuspendThenHibernate, the stage is the sleep's
        const sleepFirst = _machine(_with(withSleep, { lockOnSleep: true }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        assertEqual(sleepFirst.next(), 1800000, "sleep and hibernation: the sleep's time");
        sleepFirst.sleepDeadline();
        assertEqual(sleepFirst.actions, "sleep+hibernate:locked", "… SuspendThenHibernate asked");
        const plainSleep = _machine(_with(withSleep, { lockOnSleep: true }), ["lcd"], true, "yes", "yes", "na").idle(5000, 0);
        plainSleep.sleepDeadline();
        assertEqual(plainSleep.actions, "sleep:locked", "SuspendThenHibernate not possible: a plain Suspend");

        // A SuspendThenHibernate refused at the call (logind weighs swap against the memory in
        // use then): a plain Suspend once more in the period, after a fresh read
        const refusedThen = _machine(_with(withSleep, { lockOnSleep: true }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        refusedThen.sleepDeadline();
        assertEqual(refusedThen.actions, "sleep+hibernate:locked", "SuspendThenHibernate asked");
        refusedThen.at(1801000, { type: "sleepFailed" });
        assertEqual(refusedThen.actions, "", "refused: nothing at once");
        assertEqual(refusedThen.next(), 1801000, "… logind's inhibitors to be read again now");
        refusedThen.at(1801000, { type: "deadline" });
        assertEqual(refusedThen.actions, "", "… never asked on the read from before the refusal");
        refusedThen.sleepDeadline();
        assertEqual(refusedThen.actions, "sleep:locked", "… after a fresh read: a plain Suspend");
        refusedThen.at(1802000, { type: "sleepFailed" });
        assertEqual(refusedThen.next(), -1, "the plain Suspend refused too: not asked again in this period");
        const blockedThen = _machine(_with(withSleep, { lockOnSleep: true }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        blockedThen.sleepDeadline().at(1801000, { type: "sleepFailed" });
        blockedThen.sleepDeadline(true);
        assertEqual(blockedThen.actions, "", "the read after the refusal finds a sleep block: paused, as ever");
        const failedReads = _machine(_with(withSleep, { lockOnSleep: true }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        failedReads.sleepDeadline("unknown").sleepDeadline();
        assertEqual(failedReads.actions, "sleep+hibernate:locked", "a read that could not tell, then one that did: asked");
        failedReads.at(1900000, { type: "sleepFailed" }).sleepDeadline("unknown");
        assertEqual(failedReads.next(), 1900000 + IdleRules.sleepReadRetry.minimum,
                    "after the refusal a read that could not tell: read again after the first pause (the earlier failures not counted)");
        const nextPeriod = _machine(_with(withSleep, { lockOnSleep: true }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        nextPeriod.sleepDeadline().at(1801000, { type: "sleepFailed" }).sleepDeadline();
        nextPeriod.input(1900000).idle(1905000, 1900000);
        nextPeriod.sleepDeadline();
        assertEqual(nextPeriod.actions, "sleep+hibernate:locked", "a new period: SuspendThenHibernate again");
        const plainRefused = _machine(_with(withSleep, { lockOnSleep: true }), ["lcd"], true, "yes", "yes", "na").idle(5000, 0);
        plainRefused.sleepDeadline().at(1801000, { type: "sleepFailed" });
        assertEqual(plainRefused.next(), -1, "a plain Suspend refused: not asked again (nothing to fall back to)");
        const hibernateRefused = _machine(hours, ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        hibernateRefused.sleepDeadline().at(7201000, { type: "sleepFailed" });
        assertEqual(hibernateRefused.next(), -1, "a Hibernate refused (sleep off): not asked again");

        // A lock due no later is waited for, as for the sleep
        const lockFirst = _machine(_with(hours, { lockscreenEnabled: true, lockAfter: 7200 }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        assertEqual(lockFirst.config.hibernateAfter, 14400, "lock at 2 h: hibernation 2 h after it");
        // A switch that makes it due counts from the switch, never at once
        const switched = _machine(_with(hours, { hibernateEnabled: false }), ["lcd"], true, "yes", "yes", "yes").idle(5000, 0);
        switched.reconfigure(8000000, hours);
        assertEqual(switched.actions, "", "hibernation switched on past its time: not at once");
        assertEqual(switched.next(), 8000000 + 7200000, "… counted from the switch");
    }

    function _forced() {
        // On every monitor, then each by its own times from the force: the laptop panel
        // (no screensaver, off at 2 min) shows the screensaver, off 2 min later
        const panel = _machine(_own(saver, { panel: _entry(0, 120), lcd: _entry(300, 900) }), ["lcd", "panel"], true);
        panel.at(1000, { type: "force" });
        assertEqual(panel.actions, "showSaver:lcd+panel,go:d,active:true", "forced: the screensaver on every monitor, none off");
        assertEqual(panel.next(), 121000, "… the panel's screen-off its own time after the force");
        panel.deadline();
        assertEqual(panel.actions, "powerOff:panel", "… then off");
        assertEqual(panel.next(), 601000, "… the LCD's as long after the force as after its screensaver");
        panel.deadline();
        assertEqual(panel.actions, "powerOff:lcd", "… then off");
        const sooner = _machine(_own(saver, { tv: _entry(300, 120) }), ["tv"], true);
        sooner.at(1000, { type: "force" });
        assertEqual(sooner.next(), 121000, "a screen-off sooner than its screensaver: its whole time after the force, never at once");
        assert(sooner.actions.startsWith("showSaver:tv,") && !sooner.actions.includes("powerOff"), "… the screensaver first");
        const same = _machine(_own(saver, { tv: _entry(300, 300) }), ["tv"], true);
        same.at(1000, { type: "force" });
        assertEqual(same.next(), 301000, "a screen-off at its screensaver's time: its whole time after the force, never at once");

        const machine = _machine(_with(saver, { lockscreenEnabled: true, lockAfter: 600 }), ["lcd"], true);
        machine.at(1000, { type: "force" });
        assertEqual(machine.actions, "showSaver:lcd,go:d,active:true", "forced: the screensaver now");
        assertEqual(machine.next(), 301000, "… the stages after it as if idle since Screensaver after");
        machine.at(2000, { type: "busInhibitors", count: 1 });
        assertEqual(machine.next(), 301000, "… held stages ignored");
        machine.at(6000, { type: "inputIdle", idle: true, since: 1000 });
        assertEqual(machine.next(), 301000, "… idleness reported later moves nothing");
        machine.input(10000);
        assertEqual(machine.actions, "hideSaver:lcd,back:d,active:false", "input ends it");
        machine.idle(15000, 10000);
        assertEqual(machine.next(), -1, "… then the inhibitor holds again");

        // Input on the forced screensaver before the base time: no inputIdle(true) came, so
        // no inputIdle(false) will; its surface sends activity
        const early = _machine(saver, ["lcd"], true);
        early.at(1000, { type: "force" });
        early.at(4000, { type: "activity" });
        assertEqual(early.actions, "hideSaver:lcd,back:d,active:false", "forced, then a key within 5 s (activity): hidden");

        const off = _machine({}, ["lcd"], true);
        off.at(1000, { type: "force" });
        assertEqual(off.actions, "showSaver:lcd,active:true", "forced with the screensaver off: shown now anyway");

        // An app's SetActive(true): as a force while unlocked, nothing while locked or asleep
        const bus = _machine(saver, ["lcd"], true);
        assert(IdleRules.busForceTakes(bus.state), "SetActive(true) unlocked: it takes");
        bus.at(1000, { type: "busForce" });
        assertEqual(bus.actions, "showSaver:lcd,go:d,active:true", "… the screensaver now");
        const busLocked = _machine(_own(saver, { oled: oledTimes }), ["oled"], true);
        busLocked.at(1000, { type: "locked" });
        assert(!IdleRules.busForceTakes(busLocked.state), "SetActive(true) locked: it does not take");
        busLocked.at(2000, { type: "busForce" });
        assertEqual(busLocked.actions, "", "… nothing turned off, no go command at the lock");
        assertEqual(busLocked.state.forced, false, "… and nothing forced for after the unlock");
        const busAsleep = _machine(saver, ["lcd"], true);
        busAsleep.at(1000, { type: "sleep" });
        assert(!IdleRules.busForceTakes(busAsleep.state), "SetActive(true) going to sleep: it does not take");
    }

    function _unknowns() {
        const machine = _machine({}, ["lcd", "oled"], true);
        machine.at(1000, { type: "power", power: { lcd: "off", oled: "Error: no reply" } });
        assertEqual(machine.state.power.oled, "unknown", "a power read not understood: unknown, never off");
        machine.at(2000, { type: "locked" });
        machine.idle(7000, 2000).deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,powerOff:lcd+oled,lockBlack:true",
                    "a monitor read off before the shell turned it off: still powered off by the shell");
        machine.at(63000, { type: "power", power: { lcd: "off" } });
        assertEqual(machine.actions, "", "one monitor not read: the lock surface stays black");
        machine.at(64000, { type: "power", power: { lcd: "off", oled: "on" } });
        assertEqual(machine.actions, "powerOff:oled", "a cut that failed: still black, the cut asked again (its pause over)");
        assertEqual(machine.at(65000, { type: "nonsense" }).ignored, "unknown event", "an unknown event: ignored");
        assertEqual(machine.actions, "", "… no action");
        const state = machine.state;
        machine.at(66000, { type: "busInhibitors", count: "junk" });
        assertEqual(machine.state.busInhibitors, 0, "an inhibitor count not understood: none");
        assert(state !== machine.state && state.shown !== machine.state.shown, "a step copies the state, never changes it");
    }
}
