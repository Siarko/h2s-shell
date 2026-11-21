import QtQuick
import qs.singletons

// The idle rules (singletons/IdleRules.qml): every case of the plan's table
// (notes/plans/idle-lock-flow.md §8) and its examples — an OLED turned off, an LCD with the
// screensaver, a laptop panel off, a monitor unplugged, a profile switched mid-idle, input
// waking all, the lock screen's own screen-off, inhibitors holding while unlocked only.
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

    function run() {
        _config();
        _screensaver();
        _ways();
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
        assertEqual(rules.config({ screenOffEnabled: true }, ["a"], false).screenOffAfter, 0,
                    "no power control: no screen-off stage");
        assertEqual(rules.config({ screensaverEnabled: false, screensaverTimeout: 10 }, [], false).saverAfter, 0,
                    "a time without its switch: never");
        assertEqual(rules.config({ screensaverEnabled: true, screensaverTimeout: "junk" }, [], false).saverAfter, 300,
                    "a time not understood: the default");
        assertEqual(rules.config({}, ["a", "a", "", { id: "b" }, 7], false).monitors.join(" "), "a b",
                    "monitors by id, once each, objects with an id too");

        const ways = values => rules.config(values, ["oled", "lcd"], true).ways;
        assertEqual(ways({}).oled, "screensaver", "the default way: the screensaver");
        assertEqual(ways({ perMonitor: true, monitorBlanking: { oled: "off" } }).oled, "off", "an override: off");
        assertEqual(ways({ perMonitor: true, monitorBlanking: { oled: "off" } }).lcd, "screensaver", "… the others the default");
        assertEqual(ways({ perMonitor: false, monitorBlanking: { oled: "off" } }).oled, "screensaver",
                    "overrides only with Set per monitor on");
        assertEqual(ways({ blanking: "off", perMonitor: true, monitorBlanking: { lcd: "screensaver" } }).lcd, "screensaver",
                    "an override against the default");
        assertEqual(ways({ blanking: "slideshow" }).lcd, "screensaver", "slideshow, not built yet: the screensaver");
        assertEqual(ways({ perMonitor: true, monitorBlanking: { oled: "default" } }).oled, "screensaver",
                    "an override not understood: the default");
        assertEqual(rules.config({ blanking: "off" }, ["oled"], false).ways.oled, "screensaver",
                    "off without power control: the screensaver");
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

    function _ways() {
        // The OLED turned off, the LCD the screensaver, at the same deadline
        const perMonitor = _with(saver, { perMonitor: true, monitorBlanking: { oled: "off" } });
        const machine = _machine(perMonitor, ["lcd", "oled"], true);
        machine.idle(5000, 0).deadline();
        assertEqual(machine.actions, "showSaver:lcd+oled,powerOff:oled,startCommand,active:true",
                    "the OLED's way off: off, under a black surface that takes the keys; the LCD the screensaver");
        assertEqual(machine.shown(), "lcd=saver oled=off", "… what is in place");

        const noPower = _machine(perMonitor, ["lcd", "oled"], false);
        noPower.idle(5000, 0).deadline();
        assertEqual(noPower.actions, "showSaver:lcd+oled,startCommand,active:true",
                    "no power control: the OLED gets the screensaver");

        // A laptop: its panel off (its backlight costs power on black)
        const laptop = _machine(_with(saver, { blanking: "off" }), ["panel"], true);
        laptop.idle(5000, 0).deadline();
        assertEqual(laptop.actions, "showSaver:panel,powerOff:panel,startCommand,active:true",
                    "the laptop panel's way off: powered off at Screensaver after");

        // A way changed during idle: applied at once
        const changed = _machine(saver, ["lcd", "oled"], true);
        changed.idle(5000, 0).deadline();
        changed.reconfigure(310000, perMonitor);
        assertEqual(changed.actions, "powerOff:oled", "the OLED switched to off during idle: off now");
        changed.reconfigure(320000, saver);
        assertEqual(changed.actions, "powerOn:oled", "… and back to the screensaver: on, its screensaver stays");
        assertEqual(changed.shown(), "lcd=saver oled=saver", "… both the screensaver");
    }

    function _screenOff() {
        const values = _with(saver, { screenOffEnabled: true, screenOffTimeout: 600 });
        const machine = _machine(_with(values, { perMonitor: true, monitorBlanking: { oled: "off" } }), ["lcd", "oled"], true);
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
        assertEqual(machine.actions, "lock", "Lock after: lock once");
        assertEqual(machine.next(), -1, "refused (no lock came): no deadline for it again");
        machine.at(900000, { type: "deadline" });
        assertEqual(machine.actions, "", "… and not again in this idle period");
        machine.input(1000000);
        machine.idle(1005000, 1000000);
        assertEqual(machine.next(), 1300000, "a new idle period: the stages again");
        machine.deadline();
        machine.deadline();
        assertEqual(machine.actions, "lock", "… and the lock again");

        machine.at(1401000, { type: "locked" });
        assertEqual(machine.actions, "", "locked: active already, locking turns nothing on");
        assertEqual(machine.shown(), "lcd=saver", "… the screensaver stays under the lock");

        const alone = _machine({ lockscreenEnabled: true, lockAfter: 30 }, ["lcd"], true);
        alone.idle(5000, 0).deadline();
        assertEqual(alone.actions, "lock", "only the lock set: it comes at its time");
        alone.at(30100, { type: "locked" });
        assertEqual(alone.actions, "active:true", "… the lock is reported active");
    }

    function _input() {
        // Input wakes all, whatever each shows
        const values = _with(saver, { perMonitor: true, monitorBlanking: { oled: "off" }, screenOffEnabled: true,
                                      screenOffTimeout: 600 });
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
        logind.at(300000, { type: "logindIdleBlock", held: true });
        logind.at(300000, { type: "deadline" });
        assertEqual(logind.actions, "", "logind's idle block holds the screensaver");
        assertEqual(logind.next(), 330000, "… read again later (logind sends no signal)");
        logind.at(330000, { type: "logindIdleBlock", held: false });
        assertEqual(logind.next(), 630000, "released: counted from the read that saw it gone");

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
    }

    function _monitors() {
        const values = _with(saver, { perMonitor: true, monitorBlanking: { oled: "off" } });
        const machine = _machine(values, ["lcd"], true);
        machine.idle(5000, 0).deadline();
        machine.reconfigure(310000, values, ["lcd", "oled"]);
        assertEqual(machine.actions, "showSaver:oled,powerOff:oled", "a monitor plugged in during idle: the stage's picture for its way");
        machine.at(311000, { type: "power", power: { lcd: "on", oled: "off" } });
        machine.reconfigure(320000, values, ["lcd"]);
        assertEqual(machine.actions, "", "a monitor unplugged: no action");
        assertEqual(machine.shown(), "lcd=saver", "… dropped from what is shown");
        assertEqual(Object.keys(machine.state.power).join(" "), "lcd", "… and from the power read");
        machine.input(330000);
        assertEqual(machine.actions, "hideSaver:lcd,endCommand,active:false", "input: only the connected monitor");

        const replug = _machine(values, ["lcd", "oled"], true);
        replug.idle(5000, 0).deadline();
        replug.reconfigure(310000, values, ["lcd"]);
        replug.reconfigure(320000, values, ["lcd", "oled"]);
        assertEqual(replug.actions, "showSaver:oled,powerOff:oled", "plugged back in: taken as on, given its picture again");
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

        const off = _machine({}, ["lcd"], true);
        off.at(1000, { type: "force" });
        assertEqual(off.actions, "showSaver:lcd,active:true", "forced with the screensaver off: shown now anyway");
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
        assertEqual(machine.actions, "", "a cut that failed: still black");
        assertEqual(machine.at(65000, { type: "nonsense" }).ignored, "unknown event", "an unknown event: ignored");
        assertEqual(machine.actions, "", "… no action");
        const state = machine.state;
        machine.at(66000, { type: "busInhibitors", count: "junk" });
        assertEqual(machine.state.busInhibitors, 0, "an inhibitor count not understood: none");
        assert(state !== machine.state && state.shown !== machine.state.shown, "a step copies the state, never changes it");
    }
}
