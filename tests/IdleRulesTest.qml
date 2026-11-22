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
            return action.type;
        }).join(",");
    }

    function _machine(values, monitors, canPowerOff) {
        const rules = IdleRules;
        const self = {
            config: rules.config(values, monitors, canPowerOff),
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
            self.config = rules.config(newValues, newMonitors ?? monitors, newCanPowerOff ?? canPowerOff);
            return self.at(ms, { type: "config" });
        };
        self.next = () => rules.nextDeadline(self.state, self.config, self.now);
        // The Timer fires at the next deadline
        self.deadline = () => self.at(self.next(), { type: "deadline" });
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

    readonly property var saver: ({ screensaverEnabled: true, screensaverTimeout: 300, screensaverCommands: true })

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
        _lock();
        _input();
        _lockScreen();
        _inhibitors();
        _profiles();
        _monitors();
        _sleep();
        _forced();
        _unknowns();
        _powerReadBack();
        _lockAttended();
        _restore();
        _edges();
    }

    // What tests/mutate.sh found no check for
    function _edges() {
        const rules = IdleRules;
        for (const unset of [null, ""])
            assertEqual(rules.config({ screensaverEnabled: true, screensaverTimeout: unset }, [], false).saverAfter, 300,
                        "a time not set (" + JSON.stringify(unset) + "): the default");
        assertEqual(rules.config({ monitorIdle: { oled: oledTimes } }, ["oled"], true).times.oled.screenOffAfter, 0,
                    "own times only with Set per monitor on, which is off unless set");
        const quick = _machine({ screensaverEnabled: true, screensaverTimeout: 1, screenOffEnabled: true, screenOffTimeout: 2 }, ["oled"], true);
        quick.idle(500, 0);
        assertEqual(quick.next(), 1000, "a time of one second: due after it");
        assertEqual([900, 1000, 2000].map(ms => rules.stage(quick.state, quick.config, ms).oled).join(" "), "0 1 2",
                    "times of one and two seconds: the screensaver at 1 s, the screens off at 2 s");
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
        assertEqual(commands.actions, "hideSaver:lcd,endCommand,active:false", "(input: the command ended)");
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
        assertEqual(machine.actions, "showSaver:lcd+oled,startCommand,active:true",
                    "Screensaver after: the screensaver on every monitor, the start command, active");
        assertEqual(machine.shown(), "lcd=saver oled=saver", "… both show it");
        assertEqual(machine.next(), -1, "… nothing further set");
        machine.at(400000, { type: "deadline" });
        assertEqual(machine.actions, "", "a deadline with nothing due: no action twice");

        const quiet = _machine(_with(saver, { screensaverCommands: false }), ["lcd"], true);
        quiet.idle(5000, 0).deadline();
        assertEqual(quiet.actions, "showSaver:lcd,active:true", "commands off: no start command");
    }

    function _perMonitorTimes() {
        // The OLED off at 5 min (no screensaver), the LCD the screensaver at 5 min: one deadline
        const oledOff = _own(saver, { oled: oledTimes });
        const machine = _machine(oledOff, ["lcd", "oled"], true);
        machine.idle(5000, 0).deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,powerOff:oled,startCommand,active:true",
                    "the OLED's own screen-off at the LCD's screensaver time: off, under a black surface that takes the keys");
        assertEqual(machine.shown(), "lcd=saver oled=off", "… what is in place");

        const noPower = _machine(oledOff, ["lcd", "oled"], false);
        noPower.idle(5000, 0).deadline();
        assertEqual(noPower.actions, "showSaver:lcd+oled,startCommand,active:true",
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
        assertEqual(laptop.actions, "showSaver:panel,powerOff:panel,startCommand,active:true",
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
        assertEqual(desk.actions, "showSaver:lcd+oled,powerOff:oled,startCommand,active:true",
                    "5 min: every monitor dark: the commands, active");
        assertEqual(desk.next(), 900000, "… next the LCD's screen-off");
        desk.deadline();
        assertEqual(desk.actions, "powerOff:lcd", "15 min: the LCD off too");
        assertEqual(desk.shown(), "lcd=off oled=off panel=off", "… all off");
        desk.input(1000000);
        assertEqual(desk.actions, "powerOn:lcd+oled+panel,hideSaver:lcd+oled+panel,endCommand,active:false", "input wakes all");
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
        assertEqual(reached.actions, "hideSaver:panel", "both its stages switched off: the desktop, without the end command");

        // A monitor with both stages off never goes dark and is not waited for
        const never = _machine(_own(saver, { lcd: _entry(0, 0) }), ["lcd", "oled"], true);
        never.idle(5000, 0);
        assertEqual(never.next(), 300000, "a monitor with both stages off: no time of its own");
        never.deadline();
        assertEqual(never.actions, "showSaver:oled,startCommand,active:true",
                    "the OLED's screensaver: the commands and active, not waiting for the LCD");
        assertEqual(never.shown(), "lcd=on oled=saver", "… the LCD keeps the desktop");
        const none = _machine(_own(saver, { lcd: _entry(0, 0), oled: _entry(0, 0) }), ["lcd", "oled"], true);
        none.idle(5000, 0);
        assertEqual(none.next(), -1, "no monitor goes dark: nothing due");
        none.at(400000, { type: "deadline" });
        assertEqual(none.actions, "", "… no commands, never active");
        none.at(410000, { type: "force" });
        assertEqual(none.actions, "showSaver:lcd+oled,startCommand,active:true",
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
        assertEqual(given.actions, "showSaver:lcd,startCommand,active:true", "(the LCD dark, the TV never)");
        given.reconfigure(310000, _own(saver, { tv: _entry(600, 0) }));
        assertEqual(given.actions, "", "the TV given a later stage mid-idle: still active, nothing ends");
        given.deadline();
        assertEqual(given.actions, "showSaver:tv", "… its screensaver at its time, no command again");
        given.reconfigure(610000, _own({}, { tv: _entry(0, 0) }));
        assertEqual(given.actions, "hideSaver:lcd+tv,active:false", "every stage switched off: not active (no end command: still away)");
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
        assertEqual(machine.actions, "powerOn:oled,hideSaver:lcd+oled+panel,endCommand,active:false",
                    "input at the screensaver: the OLED on, every screensaver hidden, the end command, inactive");
        assertEqual(machine.shown(), "lcd=on oled=on panel=on", "… all show the desktop");
        machine.idle(355000, 350000);
        assertEqual(machine.next(), 650000, "… the counting starts at the input");
        machine.deadline();
        machine.deadline();
        machine.input(1000000);
        assertEqual(machine.actions, "powerOn:lcd+oled+panel,hideSaver:lcd+oled+panel,endCommand,active:false",
                    "input with every screen off: all on");

        const quiet = _machine(_with(saver, { screensaverCommands: false }), ["lcd"], true);
        quiet.idle(5000, 0).deadline();
        quiet.input(310000);
        assertEqual(quiet.actions, "hideSaver:lcd,active:false", "no start command ran: no end command");
        quiet.input(320000);
        assertEqual(quiet.actions, "", "input again: nothing to undo");

        const user = _machine(saver, ["lcd"], true);
        user.idle(5000, 0).deadline();
        user.at(310000, { type: "activity" });
        assertEqual(user.actions, "hideSaver:lcd,endCommand,active:false",
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
        assertEqual(bus.actions, "showSaver:lcd,startCommand,active:true", "… the screensaver from there");
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
        wayland.at(5000, { type: "inputIdle", idle: true, since: 0 });
        assertEqual(wayland.next(), -1, "a Wayland inhibitor holds: no deadline");
        wayland.at(300000, { type: "deadline" });
        assertEqual(wayland.actions, "", "… no screensaver");
        wayland.at(605000, { type: "awayIdle", idle: true, since: 600000 });
        assertEqual(wayland.next(), 900000, "released at 600 s (away-idle comes the base time later): counted from there");

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
        assertEqual(failed.actions, "showSaver:lcd,startCommand,active:true",
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
        assertEqual(locked.actions, "startCommand", "… idle reaches Screensaver after under the lock: the start command, the screens stay off");
        locked.at(320000, { type: "busInhibitors", count: 0 });
        assertEqual(locked.actions, "", "a release while locked moves nothing");
        assertEqual(locked.state.idleSince, 0, "… the counting still from the last input");
    }

    function _profiles() {
        // Battery → AC during idle: the screensaver shown at 10 s stays under a 300 s profile
        const battery = { screensaverEnabled: true, screensaverTimeout: 10, screensaverCommands: true };
        const machine = _machine(battery, ["lcd"], true);
        machine.idle(5000, 0).deadline();
        assertEqual(machine.actions, "showSaver:lcd,startCommand,active:true", "the battery profile's screensaver at 10 s");
        machine.reconfigure(20000, saver);
        assertEqual(machine.actions, "", "a profile with a longer time mid-idle: the screensaver stays, nothing ends");
        machine.reconfigure(30000, _with(saver, { screenOffEnabled: true, screenOffTimeout: 60 }));
        assertEqual(machine.next(), 60000, "later stages take the new times");
        machine.reconfigure(40000, { screensaverEnabled: false });
        assertEqual(machine.actions, "hideSaver:lcd,active:false",
                    "a profile with the screensaver off: hidden, without the end command (still away)");
        machine.input(50000);
        assertEqual(machine.actions, "endCommand", "… which runs when the user comes back");

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
        assertEqual(machine.actions, "hideSaver:lcd,endCommand,active:false",
                    "a monitor plugged in during idle: as input — the screensaver gone, the end command, not active");
        assertEqual(machine.shown(), "lcd=on oled=on", "… every monitor on");
        assertEqual(machine.next(), 610000, "… counted again from the plug-in, every stage and the lock");
        machine.deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,powerOff:oled,startCommand,active:true", "… then each at its time again");
        machine.at(611000, { type: "power", power: { lcd: "on", oled: "off" } });
        machine.reconfigure(620000, values, ["lcd"]);
        assertEqual(machine.actions, "", "a monitor unplugged: no action");
        assertEqual(machine.shown(), "lcd=saver", "… dropped from what is shown");
        assertEqual(Object.keys(machine.state.power).join(" "), "lcd", "… and from the power read");
        machine.input(630000);
        assertEqual(machine.actions, "hideSaver:lcd,endCommand,active:false", "input: only the connected monitor");

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
        assertEqual(locked.actions, "powerOn:lcd,hideSaver:lcd,endCommand", "plugged in while locked: on again, the end command; still active");
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
        assertEqual(replugged.actions, "hideSaver:lcd,endCommand,active:false", "… back later (plugged in again, its button pressed): plugged in");
        assert(IdleRules.shellOffWindow > IdleRules.replugWindow, "a monitor powered off by the shell is given longer to come back");

        // The only monitor drops off at its power cut, and comes back with Qt's fields for its
        // id (no make): the same monitor, matched on its connector or loosely
        const offTimes = { screenOffEnabled: true, screenOffTimeout: 300, screensaverCommands: true };
        const backend = { id: "Dell|U27|SN", base: "Dell|U27|SN", connector: "DP-1" };
        const only = _machine(offTimes, [backend], true);
        only.idle(5000, 0).deadline();
        assertEqual(only.actions, "showSaver:Dell|U27|SN,powerOff:Dell|U27|SN,startCommand,active:true", "(the only monitor off)");
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
        assertEqual(other.actions, "endCommand,active:false",
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
        assertEqual(gaveUp.actions, "showSaver:Dell|U27|SN,powerOff:Dell|U27|SN,startCommand,active:true", "… the next period off at once again");

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
        assertEqual(sameLate.actions, "endCommand,active:false",
                    "the same id back after its window (switched on by its button): plugged in");
        const otherLate = _machine(offTimes, [backend], true);
        otherLate.idle(5000, 0).deadline();
        otherLate.reconfigure(301000, offTimes, []);
        otherLate.reconfigure(301001 + IdleRules.shellOffWindow, offTimes, [{ id: "LG|27GL|9", base: "LG|27GL|9", connector: "DP-1" }]);
        assertEqual(otherLate.actions, "endCommand,active:false", "another monitor on its connector after the window: plugged in");
        const saverLate = _machine(saver, [backend], true);
        saverLate.idle(5000, 0).deadline();
        saverLate.reconfigure(301000, saver, []);
        assertEqual(saverLate.actions, "", "(the screensaver monitor gone: still active)");
        saverLate.reconfigure(317000, saver, [backend]);
        assertEqual(saverLate.actions, "endCommand,active:false", "the screensaver monitor back after 16 s: plugged in");

        const named = _machine(offTimes, [backend], true);
        named.idle(5000, 0).deadline();
        named.reconfigure(301000, offTimes, []);
        named.reconfigure(302000, offTimes, [{ id: "|DELL U27|", base: "|DELL U27|", connector: "DP-1" }]);
        assertEqual(named.actions, "showSaver:|DELL U27|", "back with fields that match nothing, on its connector: the same monitor");
        const byIdOnly = _machine(saver, ["lcd", "tv"], true);
        byIdOnly.idle(5000, 0).deadline();
        byIdOnly.reconfigure(310000, saver, ["lcd"]);
        byIdOnly.reconfigure(311000, saver, ["lcd", "dock"]);
        assertEqual(byIdOnly.actions, "hideSaver:lcd,endCommand,active:false", "another monitor in time, neither with a connector: plugged in");
        const emptied = _machine(offTimes, [backend], true);
        emptied.idle(5000, 0).deadline();
        emptied.reconfigure(301000, offTimes, [], false);
        assertEqual(emptied.actions, "", "no monitor left as power control goes: still active");

        // Where the monitors come from changes (power control found: Qt's ids, then the
        // backend's): never a plug-in, each keeps what it had
        const qtForm = { id: "|U27|SN", base: "|U27|SN", connector: "DP-1" };
        const start = _machine(offTimes, [qtForm], false);
        start.idle(5000, 0).deadline();
        assertEqual(start.actions, "showSaver:|U27|SN,startCommand,active:true", "(no power control: the screensaver at the screen-off's time)");
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
        assertEqual(after.actions, "hideSaver:lcd,endCommand,active:false", "… back after the window: plugged in");

        // Gone while showing the desktop, back: plugged in
        const onGone = _machine(_own(saver, { tv: _entry(600, 0) }), ["lcd", "tv"], true);
        onGone.idle(5000, 0).deadline();
        onGone.reconfigure(310000, _own(saver, { tv: _entry(600, 0) }), ["lcd"]);
        onGone.reconfigure(311000, _own(saver, { tv: _entry(600, 0) }), ["lcd", "tv"]);
        assertEqual(onGone.actions, "hideSaver:lcd,endCommand,active:false", "gone while on, back at once: plugged in");

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
        assertEqual(first.actions, "showSaver:lcd+tv,startCommand,active:true", "the monitors at the first step: none plugged in");
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
        assertEqual(machine.actions, "hideSaver:lcd,endCommand,active:false",
                    "resumed: counts as input, no screensaver over the desktop after a wake");
        assertEqual(machine.state.idleSince, 900000, "… the counting from the resume");

        const locked = _machine(_with(saver, { screenOffEnabled: true, screenOffTimeout: 600 }), ["lcd"], true);
        locked.idle(5000, 0).deadline();
        locked.deadline();
        locked.at(700000, { type: "locked" });
        locked.at(710000, { type: "sleep" });
        locked.at(900000, { type: "resumed" });
        assertEqual(locked.actions, "powerOn:lcd,hideSaver:lcd,endCommand",
                    "resumed while locked: the monitors the shell turned off on again, the lock stays (active)");
        assertEqual(locked.next(), 960000, "… the lock screen's screen-off from the resume");
    }

    function _forced() {
        // On every monitor, then each by its own times from the force: the laptop panel
        // (no screensaver, off at 2 min) shows the screensaver, off 2 min later
        const panel = _machine(_own(saver, { panel: _entry(0, 120), lcd: _entry(300, 900) }), ["lcd", "panel"], true);
        panel.at(1000, { type: "force" });
        assertEqual(panel.actions, "showSaver:lcd+panel,startCommand,active:true", "forced: the screensaver on every monitor, none off");
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
        assertEqual(machine.actions, "showSaver:lcd,startCommand,active:true", "forced: the screensaver now");
        assertEqual(machine.next(), 301000, "… the stages after it as if idle since Screensaver after");
        machine.at(2000, { type: "busInhibitors", count: 1 });
        assertEqual(machine.next(), 301000, "… held stages ignored");
        machine.at(6000, { type: "inputIdle", idle: true, since: 1000 });
        assertEqual(machine.next(), 301000, "… idleness reported later moves nothing");
        machine.input(10000);
        assertEqual(machine.actions, "hideSaver:lcd,endCommand,active:false", "input ends it");
        machine.idle(15000, 10000);
        assertEqual(machine.next(), -1, "… then the inhibitor holds again");

        // Input on the forced screensaver before the base time: no inputIdle(true) came, so
        // no inputIdle(false) will; its surface sends activity
        const early = _machine(saver, ["lcd"], true);
        early.at(1000, { type: "force" });
        early.at(4000, { type: "activity" });
        assertEqual(early.actions, "hideSaver:lcd,endCommand,active:false", "forced, then a key within 5 s (activity): hidden");

        const off = _machine({}, ["lcd"], true);
        off.at(1000, { type: "force" });
        assertEqual(off.actions, "showSaver:lcd,active:true", "forced with the screensaver off: shown now anyway");

        // An app's SetActive(true): as a force while unlocked, nothing while locked or asleep
        const bus = _machine(saver, ["lcd"], true);
        assert(IdleRules.busForceTakes(bus.state), "SetActive(true) unlocked: it takes");
        bus.at(1000, { type: "busForce" });
        assertEqual(bus.actions, "showSaver:lcd,startCommand,active:true", "… the screensaver now");
        const busLocked = _machine(_own(saver, { oled: oledTimes }), ["oled"], true);
        busLocked.at(1000, { type: "locked" });
        assert(!IdleRules.busForceTakes(busLocked.state), "SetActive(true) locked: it does not take");
        busLocked.at(2000, { type: "busForce" });
        assertEqual(busLocked.actions, "", "… nothing turned off, no start command at the lock");
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
