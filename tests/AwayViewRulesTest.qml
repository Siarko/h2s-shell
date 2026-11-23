import QtQuick
import qs.singletons

// The "When away" page's decisions: the timeline's lanes, marks and the labels' sides, the
// line under it, the holders, a monitor's name, the Sleep section's lines
TestCase {
    suiteName: "AwayViewRules"

    readonly property var rules: AwayViewRules
    readonly property var minutes: seconds => Format.duration(seconds)

    // The command entries: their moments, lines, marks and the editor's chips
    function _commands() {
        const own = (saverAfter, screenOffAfter) => ({ screensaverEnabled: saverAfter > 0, screensaverTimeout: saverAfter || 300,
                                                       screenOffEnabled: screenOffAfter > 0, screenOffTimeout: screenOffAfter || 600 });
        // The OLED off at 5 min, the LCD's screensaver at 5 min, the clock off after 1 h
        const config = IdleRules.config({ perMonitor: true, lockscreenEnabled: true, lockAfter: 1200,
                                          monitorIdle: { oled: own(0, 300), lcd: own(300, 0), clock: own(0, 3600) } },
                                        ["oled", "lcd", "clock"], true);
        const facts = { config: config, lockAfter: 1200, sleepAt: 0 };
        const names = { oled: "OLED", lcd: "LCD", clock: "Clock" };
        const entry = (moment, monitors, go, back) => ({ id: "e", moment: moment, monitors: monitors, go: go ?? "", back: back ?? "" });
        const moment = given => rules.commandMoment(given, facts, names, minutes);
        assertEqual(moment(entry("dark", null)).text, "Every screen dark (1 h)", "every screen: when the last goes dark");
        assertEqual(moment(entry("dark", ["oled", "lcd"])).text, "OLED and LCD dark (5 min)", "two of three: named, when both are dark");
        assertEqual(moment(entry("lock", null)).text, "Locked (20 min, or by hand)", "locked: the idle lock's time");
        assertEqual(moment(entry("sleep", null)).text, "Before any sleep", "before sleep with sleep off: any sleep");
        assertEqual(rules.commandMoment(entry("sleep", null), Object.assign({}, facts, { sleepAt: 1800 }), names, minutes).text,
                    "Before sleep (30 min, or any sleep)", "… with sleep on: its time");
        assertEqual(rules.commandMoment(entry("lock", null), Object.assign({}, facts, { lockAfter: 0 }), names, minutes).text,
                    "Locked (by hand)", "locked with the idle lock off: by hand");
        assert(!moment(entry("lock", null)).greyed && !moment(entry("sleep", null)).greyed, "a lock and a sleep can always come: never greyed");
        const never = moment(entry("dark", ["gone|monitor|1"]));
        assert(never.greyed && never.text === "No screen goes dark", "a dark entry waiting for no connected monitor: greyed");
        const allOff = rules.commandMoment(entry("dark", null), { config: IdleRules.config({}, ["lcd"], true) }, names, minutes);
        assert(allOff.greyed, "no monitor goes dark: greyed");
        assertEqual(rules.commandAt(entry("dark", ["clock"]), facts), 3600, "the clock alone: at 1 h");

        assertEqual(rules.commandLine(entry("dark", null, "playerctl pause", "playerctl play")), "playerctl pause   /   back: playerctl play",
                    "the line: both commands");
        assertEqual(rules.commandLine(entry("dark", null, "", "x")), "\u2014   /   back: x", "… a dash for one not set");
        assertEqual(rules.commandLine(entry("dark", null)), "No commands yet", "… none: said so");
        assertEqual(rules.commandLine(entry("dark", null, "a".repeat(60), "")).split("   /")[0], "a".repeat(39) + "\u2026", "… a long one cut short");
        assertEqual(rules.commandLine(entry("dark", null, "one\ntwo", "")).split("   /")[0], "one two", "… on one line");

        const marks = rules.commandMarks([entry("dark", ["oled", "lcd"], "a"), entry("lock", null, "", "b"), entry("sleep", null, "c"),
                                          entry("dark", null), entry("dark", ["gone|monitor|1"], "d")], facts);
        assertEqual(marks.map(mark => mark.number + "@" + mark.t).join(" "), "1@300 2@1200",
                    "the marks: entries with a command and a time, numbered by place (sleep off, none without commands, none never dark)");

        const chips = rules.commandChips(entry("dark", ["lcd"]), facts, [{ id: "oled" }, { id: "lcd" }, { id: "clock" }]);
        assertEqual(chips.map(chip => chip.id + (chip.ticked ? "+" : "-") + chip.at).join(" "), "oled-300 lcd+300 clock-3600",
                    "the chips: each monitor, ticked where waited for, its dark time");
        const darklessFacts = () => ({ config: darkless });
        const darkless = IdleRules.config({ perMonitor: true, screensaverEnabled: true, monitorIdle: { clock: own(0, 0) } }, ["lcd", "clock"], true);
        const always = rules.commandChips(entry("dark", null), { config: darkless }, ["lcd", "clock"]);
        assertEqual(always.map(chip => chip.id + (chip.ticked ? "+" : "-") + (chip.dark ? "dark" : "never")).join(" "), "lcd+dark clock-never",
                    "a monitor that never goes dark: not ticked, not waited for");
        assertEqual(JSON.stringify(rules.commandMonitorsToggled(entry("dark", null), facts, "clock")), JSON.stringify(["oled", "lcd"]),
                    "every screen, one unticked: the others named");
        assertEqual(JSON.stringify(rules.commandMonitorsToggled(entry("dark", ["lcd"]), facts, "oled")), JSON.stringify(["lcd", "oled"]),
                    "a monitor ticked: added");
        assertEqual(rules.commandMonitorsToggled(entry("dark", ["lcd"]), facts, "lcd"), null, "the last one waited for: not unticked");
        assertEqual(rules.commandMonitorsToggled(entry("dark", ["lcd", "clock"]), darklessFacts(), "lcd"), null,
                    "… nor the last that goes dark (the other named never does)");
        // Twins: two identical monitors, told apart by their connectors, named by their shared key
        const twins = [{ id: "A|B||DP-1", base: "A|B|", connector: "DP-1" }, { id: "A|B||DP-2", base: "A|B|", connector: "DP-2" },
                       { id: "C|D|1", base: "C|D|1", connector: "HDMI-A-1" }];
        const twinFacts = { config: IdleRules.config({ screensaverEnabled: true }, twins, true) };
        assertEqual(JSON.stringify(rules.commandMonitorsToggled(entry("dark", ["A|B|", "C|D|1"]), twinFacts, "A|B||DP-1")),
                    JSON.stringify(["A|B||DP-2", "C|D|1"]), "one twin unticked: the other stays, under its own id");
        assertEqual(rules.commandChips(entry("dark", ["A|B||DP-2", "C|D|1"]), twinFacts, twins).map(chip => chip.ticked ? "+" : "-").join(""), "-++",
                    "… its chip alone unticked");
        assertEqual(JSON.stringify(rules.commandMonitorsToggled(entry("dark", null), twinFacts, "A|B||DP-2")),
                    JSON.stringify(["A|B||DP-1", "C|D|1"]), "every screen, a twin unticked: the others named");
    }

    // Edges: one second, a time off, wrong values, the defaults — each where it changes what
    // the page shows
    function _edges() {
        const none = [{ saverAfter: 0, screenOffAfter: 0 }];
        const stretches = list => list.map(part => part.kind + ":" + part.from + "-" + part.to).join(" ");
        const marks = list => list.map(mark => mark.kind + ":" + mark.text).join(" | ");
        assertEqual(rules.firstDark({ saverAfter: 1, screenOffAfter: 0 }), 1, "a screensaver after one second goes dark");
        assert(rules.anySaver([{ saverAfter: 1, screenOffAfter: 0 }], true), "a screensaver after one second shows");
        assert(rules.anySaver([{ saverAfter: 0, screenOffAfter: 1 }], false), "… a screen-off after one second stands in for it");
        assertEqual(stretches(rules.segments({ saverAfter: 1, screenOffAfter: 0 }, 3, true)), "on:0-1 saver:1-3", "the screensaver from one second");
        assertEqual(stretches(rules.segments({ saverAfter: 0, screenOffAfter: 1 }, 3, true)), "on:0-1 off:1-3", "off from one second");
        assertEqual(marks(rules.marks([{ saverAfter: 0, screenOffAfter: 1 }], 1, [{ t: 1, number: 1 }], null, true, 1)),
                    "time:1 s | lock:Lock 1 s | sleep:Sleep 1 s | commands:▸1 1 s", "the marks of a stage, a lock, a sleep and an entry after one second");
        assertEqual(marks(rules.marks(none, 0, [{ t: 1800, number: 1 }], minutes, true, 0, 1800)), "hibernate:Hibernate 30 min | commands:▸1 30 min",
                    "at one time: the hibernation, then a command entry");
        assertEqual(stretches(rules.segments({ saverAfter: 1062, screenOffAfter: 0 }, 7920, true, 7200, 1062)),
                    "on:0-1062 saver:1062-7200 asleep:7200-7920", "a stage at the break: no empty stretch");
        assertEqual(rules.hibernateAt({ on: true, at: -100, after: 7200 }), 7200, "a negative time counts as none");
        assertEqual(rules.hibernateAt({ on: true, at: Infinity, after: 60 }), 60, "… so does an endless one");
        // Command entries before the tail stay with the minutes, one at the tail goes after the break
        assertEqual(rules.axis(none, 600, [{ t: 1500, number: 1 }, { t: 7200, number: 2 }], 7200).breakAt, Math.round(1500 * 1.18),
                    "the break past the entries before the sleep, not the one at it");
        assertEqual(rules.place(1, { end: 1, breakAt: -1 }), 1, "an axis of one second: its end at the right");
        assertEqual(rules.place(1, null), 1, "… no axis: one second long");

        // --- the labels ---
        assertEqual(_placed(rules.placeLabels([{ x: 300, width: 40 }, { x: 348, width: 40 }], 700)), "0@280 0@328", "the default gap: 8 px");
        assertEqual(_placed(rules.placeLabels([{ x: 50, width: 0 }], 0, 8)), "0@0", "no track width yet: at the left");
        assertEqual(_placed(rules.placeLabels([{ x: 100, width: 0 }, { x: 108, width: 0 }], 700, 8)), "0@100 0@108", "labels without a width");
        assertEqual(_placed(rules.placeLabels([{ width: 0 }], 700, 8)), "0@0", "… without a place: at the left");

        // --- the lines ---
        assertEqual(rules.caption({ holders: [], anything: true, lockAfter: 0, lockedScreenOffAfter: 1, canPowerOff: true }, minutes),
                    "No lock when idle. Locked: screens off after 1 s without input.", "the lock screen's screen-off after one second");
        assertEqual(rules.caption({ holders: [], anything: true, lockAfter: 1, lockedScreenOffAfter: 0 }, minutes),
                    "Locks at 1 s. Locked: screens stay on.", "an idle lock after one second: said");
        assertEqual(rules.caption({ holders: [{ who: "mpv", why: "" }, { who: "vlc", why: "" }], anything: true }, minutes),
                    "Paused: mpv keeps the screen on, and 1 more.", "two holders: the second counted");
        assertEqual(rules.sleepLockLine({ lockOnSleep: false, lockAfter: 1, sleepAfter: 1800 }, minutes), "Already locked by then (lock at 1 s).",
                    "an idle lock after one second");
        assert(rules.systemSleeps({ action: "suspend", after: 1 }, minutes).startsWith("The system already puts the computer to sleep after 1 s "),
               "logind's IdleAction after one second");
        assertEqual(rules.holders([{ app: "a".repeat(50), reason: "" }], null, false)[0].who, "a".repeat(40), "an app's name: 40 characters");
        assertEqual(rules.monitorName("|" + "m".repeat(100) + "|", "DP-1"), "m".repeat(80), "a model: 80 characters");
        assertEqual(rules.monitorName("||", "X".repeat(50)), "X".repeat(40), "a connector: 40 characters");

        // --- a card's times ---
        const range = { minimum: 5, maximum: 3600 };
        const defaults = { screensaverEnabled: true, screensaverTimeout: 300, screenOffEnabled: false, screenOffTimeout: 900 };
        assertEqual(rules.cardTimes({ screenOffTimeout: 99999 }, defaults, range).screenOffTimeout, 3600, "clamped to the range's maximum");
        assertEqual(rules.cardTimes({ screensaverTimeout: NaN }, defaults, range).screensaverTimeout, 300, "a time not a number: the default's");
        assertEqual(rules.cardTimes({ screensaverTimeout: 1 }, defaults, null).screensaverTimeout, 1, "no range: from one second");

        // --- command entries' moments ---
        const entry = (moment, monitors, go) => ({ id: "e", moment: moment, monitors: monitors, go: go ?? "", back: "" });
        const config = IdleRules.config({ screensaverEnabled: true }, ["lcd"], true);
        assertEqual(rules.commandAt(entry("lock", null), { config: config, lockAfter: 0 }), -1, "locked with the idle lock off: no time");
        assertEqual(rules.commandAt(entry("lock", null), { config: config, lockAfter: 1 }), 1, "… an idle lock after one second: its time");
        assertEqual(rules.commandAt(entry("sleep", null), { config: config, sleepAt: 0 }), -1, "before sleep with sleep off: no time");
        assertEqual(rules.commandAt(entry("sleep", null), { config: config, sleepAt: 1 }), 1, "… a sleep after one second: its time");
        assertEqual(rules.commandAt(entry("dark", ["gone|monitor|1"]), { config: config }), -1, "dark, waiting for no connected monitor: no time");
        assertEqual(rules.commandMarks([entry("lock", null, "x")], { config: config, lockAfter: 1 }).map(mark => mark.t).join(), "1",
                    "the mark of an entry whose moment comes after one second");
        assertEqual(rules.commandMoment(entry("lock", null), { config: config, lockAfter: 1 }, {}, minutes).text, "Locked (1 s, or by hand)",
                    "locked after one second: said");
        assertEqual(rules.commandMoment(entry("sleep", null), { config: config, sleepAt: 1 }, {}, minutes).text, "Before sleep (1 s, or any sleep)",
                    "before a sleep after one second: said");
        const quick = { config: { monitors: ["a"], times: { a: { saverAfter: 1, screenOffAfter: 0 } } } };
        assert(rules.commandChips(entry("dark", null), quick, ["a"])[0].dark, "a chip's monitor dark after one second goes dark");
        assertEqual(rules.commandLine({ go: "c".repeat(40), back: "" }).split("   /")[0], "c".repeat(40), "a command of 40 characters kept whole");
        const pair = IdleRules.config({ screensaverEnabled: true }, ["oled", "lcd"], true);
        assertEqual(JSON.stringify(rules.commandMonitorsToggled(entry("dark", ["oled", "lcd"]), { config: pair }, "lcd")), JSON.stringify(["oled"]),
                    "two waited for, one unticked: the other stays");
        assertEqual(rules.monitorName("M".repeat(100) + "|X|", "DP-1"), "M".repeat(80) + " X", "a make: 80 characters");
        assertEqual(rules.monitorNames([{ id: "A|B||1", connector: "C".repeat(50) }, { id: "A|B||2", connector: "D".repeat(50) }])[0],
                    "A B (" + "C".repeat(40) + ")", "a twin's connector: 40 characters");
    }

    function _placed(list) {
        return list.map(label => label.row + "@" + Math.round(label.left)).join(" ");
    }

    function run() {
        _commands();
        _edges();
        // --- dark moments ---
        assertEqual(rules.firstDark({ saverAfter: 300, screenOffAfter: 900 }), 300, "a monitor goes dark at its first stage");
        assertEqual(rules.firstDark({ saverAfter: 0, screenOffAfter: 120 }), 120, "… its screen-off when it has no screensaver");
        assertEqual(rules.firstDark({ saverAfter: 600, screenOffAfter: 120 }), 120, "… the screen-off when it comes first");
        assertEqual(rules.firstDark({ saverAfter: 0, screenOffAfter: 0 }), -1, "never, with both stages off");
        const desk = [{ saverAfter: 0, screenOffAfter: 300 }, { saverAfter: 300, screenOffAfter: 900 }, { saverAfter: 0, screenOffAfter: 120 }];
        assertEqual(rules.allDarkAt(desk), 300, "every screen dark: the last monitor's first stage");
        assertEqual(rules.allDarkAt(desk.concat([{ saverAfter: 0, screenOffAfter: 0 }])), 300, "a monitor that never goes dark is not waited for");
        assertEqual(rules.allDarkAt([{ saverAfter: 0, screenOffAfter: 0 }]), -1, "none goes dark: never");
        assertEqual(rules.allDarkAt([]), -1, "no lanes: never");

        // --- the screensaver used at all ---
        assert(rules.anySaver([{ saverAfter: 300, screenOffAfter: 0 }], true), "a lane with the screensaver uses it");
        assert(!rules.anySaver([{ saverAfter: 0, screenOffAfter: 300 }], true), "a lane only turned off does not");
        assert(rules.anySaver([{ saverAfter: 0, screenOffAfter: 300 }], false), "… unless monitors cannot be turned off: the screensaver stands in");
        assert(!rules.anySaver([{ saverAfter: 0, screenOffAfter: 0 }], false), "both off: no screensaver");
        assert(!rules.anySaver([{ saverAfter: 600, screenOffAfter: 300 }], true), "a screen-off before the screensaver: it never shows");
        assert(!rules.anySaver([{ saverAfter: 300, screenOffAfter: 300 }], true), "… at the same time neither");
        assert(rules.anySaver([{ saverAfter: 600, screenOffAfter: 300 }], false), "… without power control it does (the screen-off shows it)");
        assert(rules.anySaver([{ saverAfter: 600, screenOffAfter: 300 }, { saverAfter: 300, screenOffAfter: 0 }], true), "another lane showing it is enough");
        assert(rules.anything([{ saverAfter: 0, screenOffAfter: 0 }], 600), "the lock alone is something");
        assert(!rules.anything([{ saverAfter: 0, screenOffAfter: 0 }], 0), "nothing on: nothing happens");
        assert(rules.anything([{ saverAfter: 0, screenOffAfter: 60 }], 0), "a stage alone is something");

        // --- the axis ---
        assertEqual(rules.axisEnd([{ saverAfter: 60, screenOffAfter: 0 }], 0, -1), 600, "never shorter than 10 min");
        assertEqual(rules.axisEnd([{ saverAfter: 300, screenOffAfter: 900 }], 1200, -1), Math.round(1200 * 1.18), "past the last mark: the lock");
        assertEqual(rules.axisEnd([{ saverAfter: 300, screenOffAfter: 1800 }], 1200, -1), Math.round(1800 * 1.18), "… or a screen-off after it");
        assertEqual(rules.axisEnd([{ saverAfter: 0, screenOffAfter: 0 }], 0, [{ t: 3600, number: 1 }]), Math.round(3600 * 1.18), "… or a command entry");

        // --- a lane's stretches ---
        const stretches = list => list.map(part => part.kind + ":" + part.from + "-" + part.to).join(" ");
        assertEqual(stretches(rules.segments({ saverAfter: 300, screenOffAfter: 900 }, 1416, true)), "on:0-300 saver:300-900 off:900-1416",
                    "desktop, screensaver, off");
        assertEqual(stretches(rules.segments({ saverAfter: 0, screenOffAfter: 300 }, 600, true)), "on:0-300 off:300-600", "an OLED: off only");
        assertEqual(stretches(rules.segments({ saverAfter: 600, screenOffAfter: 120 }, 708, true)), "on:0-120 off:120-708",
                    "a screen-off before the screensaver hides it");
        assertEqual(stretches(rules.segments({ saverAfter: 300, screenOffAfter: 900 }, 1416, false)), "on:0-300 saver:300-1416",
                    "without power control the screen-off shows the screensaver");
        assertEqual(stretches(rules.segments({ saverAfter: 0, screenOffAfter: 0 }, 600, true)), "on:0-600", "nothing on: the desktop throughout");
        assertEqual(stretches(rules.segments({ saverAfter: 300, screenOffAfter: 300 }, 600, true)), "on:0-300 off:300-600", "equal times: the screen-off");

        // --- the marks ---
        const marks = list => list.map(mark => mark.kind + ":" + mark.text).join(" | ");
        assertEqual(marks(rules.marks([{ saverAfter: 300, screenOffAfter: 900 }], 1200, -1, minutes)), "time:5 min | time:15 min | lock:Lock 20 min",
                    "the stages and the lock, in time order");
        assertEqual(marks(rules.marks([{ saverAfter: 600, screenOffAfter: 900 }], 600, -1, minutes)), "time:10 min | lock:Lock 10 min | time:15 min",
                    "at one time the stage first, the lock after it");
        assertEqual(marks(rules.marks(desk, 1200, [{ t: 300, number: 1 }], minutes)), "time:2 min | time:5 min | commands:\u25B81 5 min | time:15 min | lock:Lock 20 min",
                    "equal times of two lanes once; a command entry's moment after the stage");
        assertEqual(marks(rules.marks([{ saverAfter: 0, screenOffAfter: 300 }], 300, [{ t: 300, number: 1 }, { t: 300, number: 2 }], minutes)),
                    "time:5 min | lock:Lock 5 min | commands:\u25B81 5 min | commands:\u25B82 5 min",
                    "at one time: the stage, the lock, then the command entries in their order");
        assertEqual(marks(rules.marks([{ saverAfter: 0, screenOffAfter: 0 }], 0, [{ t: 1800, number: 1 }], minutes, true, 1800)),
                    "sleep:Sleep 30 min | commands:\u25B81 30 min", "a before-sleep entry after the sleep's mark");
        assertEqual(marks(rules.marks([{ saverAfter: 0, screenOffAfter: 0 }], 0, [{ t: 0, number: 1 }], minutes)), "",
                    "a command entry without a time: no mark");
        assertEqual(marks(rules.marks([{ saverAfter: 600, screenOffAfter: 300 }], 0, -1, minutes, true)), "time:5 min",
                    "a screensaver after the screen-off is no mark: nothing happens there");
        assertEqual(marks(rules.marks([{ saverAfter: 600, screenOffAfter: 300 }], 0, -1, minutes, false)), "time:5 min | time:10 min",
                    "… without power control it stays");
        assertEqual(marks(rules.marks([{ saverAfter: 0, screenOffAfter: 0 }], 0, -1, minutes)), "", "nothing on: no marks");

        // --- the labels' sides ---
        assertEqual(_placed(rules.placeLabels([{ x: 100, width: 40 }, { x: 300, width: 40 }, { x: 500, width: 60 }], 700, 8)),
                    "0@80 0@280 0@470", "apart: all above, centred on their marks");
        assertEqual(_placed(rules.placeLabels([{ x: 300, width: 40 }, { x: 300, width: 60 }], 700, 8)), "0@280 1@270",
                    "two at one time: one above, one below");
        assertEqual(_placed(rules.placeLabels([{ x: 300, width: 40 }, { x: 330, width: 40 }], 700, 8)), "0@280 1@310",
                    "a label that would touch the one before it goes below");
        assertEqual(_placed(rules.placeLabels([{ x: 300, width: 40 }, { x: 300, width: 40 }, { x: 300, width: 40 }], 700, 8)),
                    "0@280 1@280 0@328", "both sides taken: the side that frees first, pushed right");
        assertEqual(_placed(rules.placeLabels([{ x: 300, width: 40 }, { x: 300, width: 60 }, { x: 305, width: 40 }], 700, 8)),
                    "0@280 1@270 0@328", "… the side whose label ends first");
        assertEqual(_placed(rules.placeLabels([{ x: 0, width: 40 }, { x: 700, width: 60 }], 700, 8)), "0@0 0@640",
                    "kept inside the track at both ends");
        assertEqual(_placed(rules.placeLabels([{ x: 300, width: 40 }, { x: 348, width: 40 }], 700, 8)), "0@280 0@328",
                    "the gap's width apart is apart");
        assertEqual(_placed(rules.placeLabels([{ x: 300, width: 40 }, { x: 347, width: 40 }], 700, 8)), "0@280 1@327",
                    "… a pixel less touches");
        assertEqual(_placed(rules.placeLabels([{ x: 300, width: 60 }, { x: 300, width: 40 }, { x: 300, width: 40 }], 700, 8)),
                    "0@270 1@280 1@328", "… below, when the label there ends first");
        assertEqual(rules.placeLabels([], 700).length, 0, "no labels: none placed");

        // --- the line under the timeline ---
        const caption = facts => rules.caption(facts, minutes);
        assertEqual(caption({ holders: [], anything: false, lockAfter: 0, lockedScreenOffAfter: 60, canPowerOff: true }),
                    "Nothing happens when you are away.", "nothing on");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 1200, lockedScreenOffAfter: 60, canPowerOff: true }),
                    "Locks at 20 min. Locked: screens off after 1 min without input.", "the lock and the lock screen's screen-off");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 1200, perMonitor: true, lockedScreenOffAfter: 0, canPowerOff: true }),
                    "Locks at 20 min on every monitor. Locked: screens stay on.", "per monitor: one lock for all; the lock screen kept on");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 0, lockedScreenOffAfter: 60, canPowerOff: false }),
                    "No lock when idle. Locked: screens black after 1 min without input.", "no idle lock; black without power control");
        assertEqual(caption({ holders: [{ who: "Firefox", why: "Playing video" }], anything: true, lockAfter: 1200 }),
                    "Paused: Firefox keeps the screen on (Playing video).", "a holder takes the line");
        assertEqual(caption({ holders: [{ who: "mpv", why: "" }, { who: "an app (unnamed)", why: "" }, { who: "x", why: "" }], anything: false }),
                    "Paused: mpv keeps the screen on, and 2 more.", "… the first named, the rest counted, even with nothing on");

        // --- the sleep on the timeline ---
        assert(rules.anything([{ saverAfter: 0, screenOffAfter: 0 }], 0, 1800), "the sleep alone is something");
        assertEqual(rules.axisEnd([{ saverAfter: 300, screenOffAfter: 0 }], 600, -1, 1800), Math.round(1800 * 1.18), "the axis past the sleep");
        const linear = rules.axis([{ saverAfter: 300, screenOffAfter: 600 }], 900, -1, 1800);
        assertEqual(JSON.stringify(linear), JSON.stringify({ end: Math.round(1800 * 1.18), breakAt: -1, tailAt: 1800 }),
                    "sleep at 30 min after a lock at 15: one linear axis");
        assertEqual(rules.axis([{ saverAfter: 300, screenOffAfter: 0 }], 1200, -1, 3600).breakAt, -1, "an hour, three times the rest: still linear");
        const broken = rules.axis([{ saverAfter: 300, screenOffAfter: 600 }], 900, -1, 7200);
        assertEqual(JSON.stringify(broken), JSON.stringify({ end: Math.round(7200 * 1.1), breakAt: Math.round(900 * 1.18), tailAt: 7200 }),
                    "sleep at 2 h after a lock at 15 min: after a break, the minutes up to it");
        assertEqual(rules.axis([{ saverAfter: 0, screenOffAfter: 0 }], 0, -1, 7200).breakAt, -1, "nothing before the sleep: no break");
        assertEqual(rules.axis([{ saverAfter: 0, screenOffAfter: 0 }], 600, -1, 3600).breakAt, -1, "a sleep at an hour exactly: no break (past an hour only)");
        assertEqual(rules.axis([{ saverAfter: 0, screenOffAfter: 0 }], 2034, -1, 7200).breakAt, -1, "… nor at exactly three times the rest");
        assertEqual(rules.axis([{ saverAfter: 0, screenOffAfter: 0 }], 2100, -1, 7200).breakAt, -1, "a sleep less than three times the rest: no break");
        assertEqual(rules.axis([{ saverAfter: 0, screenOffAfter: 0 }], 2000, -1, 7200).breakAt, 2360, "… more than that: a break");
        const at = (t, given) => Math.round(rules.place(t, given) * 1000);
        assertEqual([0, 900, linear.end, linear.end * 2].map(t => at(t, linear)).join(" "), "0 " + Math.round(900 / linear.end * 1000) + " 1000 1000",
                    "linear: in proportion, kept on the axis");
        assertEqual([0, broken.breakAt / 2, broken.breakAt, (broken.breakAt + 7200) / 2, 7200, broken.end].map(t => at(t, broken)).join(" "),
                    "0 350 700 775 850 1000", "with a break: the minutes 70 %, the stretch to the sleep 15 %, after it the rest");
        assertEqual(stretches(rules.segments({ saverAfter: 300, screenOffAfter: 600 }, 2124, true, 1800)),
                    "on:0-300 saver:300-600 off:600-1800 asleep:1800-2124", "the sleep: asleep to the end, on every lane");
        assertEqual(stretches(rules.segments({ saverAfter: 0, screenOffAfter: 0 }, 7920, true, 7200, 1062)),
                    "on:0-1062 on:1062-7200 asleep:7200-7920", "a stretch cut at the break, so it shows as a gap");
        assertEqual(stretches(rules.segments({ saverAfter: 300, screenOffAfter: 3600 }, 2124, true, 1800)),
                    "on:0-300 saver:300-1800 asleep:1800-2124", "a screen-off after the sleep never comes");
        assertEqual(marks(rules.marks([{ saverAfter: 300, screenOffAfter: 0 }], 1800, -1, minutes, true, 1800)),
                    "time:5 min | lock:Lock 30 min | sleep:Sleep 30 min", "the sleep's mark: at one time after the lock");
        assertEqual(marks(rules.marks([{ saverAfter: 0, screenOffAfter: 0 }], 0, -1, minutes, true, 0)), "", "no sleep: no mark");

        // --- the hibernation on the timeline ---
        assert(rules.anything([{ saverAfter: 0, screenOffAfter: 0 }], 0, 0, 7200), "the hibernation alone is something");
        assertEqual(rules.axisEnd([{ saverAfter: 0, screenOffAfter: 0 }], 0, -1, 0, 1800), Math.round(1800 * 1.18), "the axis past the hibernation");
        const afterLock = rules.axis([{ saverAfter: 300, screenOffAfter: 900 }], 1200, -1, 0, 8400);
        assertEqual(JSON.stringify(afterLock), JSON.stringify({ end: Math.round(8400 * 1.1), breakAt: Math.round(1200 * 1.18), tailAt: 8400 }),
                    "hibernation 2 h after the lock at 20 min: after a break, the minutes up to it");
        const afterSleep = rules.axis([{ saverAfter: 300, screenOffAfter: 600 }], 900, -1, 1800, 12600);
        assertEqual(JSON.stringify(afterSleep), JSON.stringify({ end: Math.round(12600 * 1.1), breakAt: Math.round(1800 * 1.18), tailAt: 12600 }),
                    "sleep at 30 min, hibernation 3 h later: the break after the sleep, before the hibernation");
        assertEqual(JSON.stringify(rules.axis([{ saverAfter: 300, screenOffAfter: 0 }], 600, -1, 3000, 4000)),
                    JSON.stringify({ end: Math.round(4000 * 1.18), breakAt: -1, tailAt: 4000 }), "hibernation soon after a late sleep: linear");
        assertEqual(rules.axis([{ saverAfter: 0, screenOffAfter: 0 }], 0, -1, 0, 7200).breakAt, -1, "nothing before the hibernation: no break");
        assertEqual(rules.axis([{ saverAfter: 0, screenOffAfter: 0 }], 0, -1, 900, 9000).breakAt, Math.round(900 * 1.18),
                    "the sleep alone before it: the break after the sleep");
        assertEqual([afterSleep.breakAt, 12600].map(t => at(t, afterSleep)).join(" "), "700 850", "the break and the hibernation placed as for a sleep");
        assertEqual(stretches(rules.segments({ saverAfter: 300, screenOffAfter: 900 }, 9240, true, 0, 1416, 8400)),
                    "on:0-300 saver:300-900 off:900-1416 off:1416-8400 hibernated:8400-9240", "hibernated after the screens off, the break a gap");
        assertEqual(stretches(rules.segments({ saverAfter: 300, screenOffAfter: 0 }, 13860, true, 1800, 2124, 12600)),
                    "on:0-300 saver:300-1800 asleep:1800-2124 asleep:2124-12600 hibernated:12600-13860", "asleep, then hibernated");
        assertEqual(marks(rules.marks([{ saverAfter: 300, screenOffAfter: 0 }], 1200, -1, minutes, true, 0, 8400)),
                    "time:5 min | lock:Lock 20 min | hibernate:Hibernate 2 h 20 min", "the hibernation's mark");
        assertEqual(marks(rules.marks([{ saverAfter: 0, screenOffAfter: 0 }], 0, -1, minutes, true, 1800, 1800)),
                    "sleep:Sleep 30 min | hibernate:Hibernate 30 min", "at one time: the sleep, then the hibernation");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 1200, sleepAfter: 0, hibernate: { on: true, from: "lock", at: 1200, after: 7200 } }),
                    "Locks at 20 min. Hibernates 2 h after the lock.", "the caption: hibernation after the lock");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 900, sleepAfter: 1800, hibernate: { on: true, from: "sleep", at: 1800, after: 10800 } }),
                    "Locks at 15 min. Sleeps at 30 min, hibernates 3 h later.", "… after the sleep");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 0, sleepAfter: 0, hibernate: { on: true, from: "input", at: 0, after: 7200 } }),
                    "No lock when idle. Hibernates 2 h after your last input.", "… after the last input");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 0, sleepAfter: 0, lockedScreenOffAfter: 0,
                              hibernate: { on: false, from: "input", at: 0, after: 7200 } }),
                    "No lock when idle. Locked: screens stay on.", "… not on: not said");
        assertEqual(caption({ holders: [], sleepBlockers: [{ who: "borg", why: "" }], anything: true, sleepAfter: 0,
                              hibernate: { on: true, from: "input", at: 0, after: 7200 } }),
                    "Paused: borg blocks sleep.", "a sleep block pauses the hibernation too");

        // One second is a time like any other
        const none = [{ saverAfter: 0, screenOffAfter: 0 }];
        assert(rules.anything(none, 1, 0, 0) && rules.anything(none, 0, 1, 0) && rules.anything(none, 0, 0, 1),
               "a lock, a sleep or a hibernation after one second is something");
        assertEqual(rules.axis(none, 0, -1, 0, 1).tailAt, 1, "a hibernation after one second is the tail");
        assertEqual(stretches(rules.segments(none, 3, true, 0, 0, 1)), "on:0-1 hibernated:1-3", "hibernated from one second");
        assertEqual(stretches(rules.segments(none, 3, true, 1, 0, 0)), "on:0-1 asleep:1-3", "asleep from one second");
        assertEqual(marks(rules.marks(none, 0, -1, minutes, true, 0, 1)), "hibernate:Hibernate 1 s", "the mark of a hibernation after one second");
        assertEqual(caption({ holders: [], sleepBlockers: [{ who: "borg", why: "" }], anything: true, sleepAfter: 1 }), "Paused: borg blocks sleep.",
                    "a sleep after one second is paused by a block too");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 0, sleepAfter: 1 }), "No lock when idle. Sleeps at 1 s.", "… and said");

        // --- the Hibernate section ---
        assertEqual(rules.hibernateAt({ on: true, from: "lock", at: 1200, after: 7200 }), 8400, "hibernation at 2 h 20 min from the last input");
        assertEqual(rules.hibernateAt({ on: false, from: "lock", at: 1200, after: 7200 }), 0, "… none when not on");
        assertEqual(rules.hibernateAt(null), 0, "… none when not given");
        assertEqual(["sleep", "lock", "saver", "input", undefined].map(rules.hibernatePillsLabel).join(" | "),
                    "after sleeping for | after the lock | after the screensaver | after your last input | after your last input", "the pills' words");
        assertEqual(rules.hibernateCaption("Not available here: no swap space to save the session to.", "lock"),
                    "Not available here: no swap space to save the session to.", "not possible: the reason");
        assertEqual(rules.hibernateCaption("", "sleep"),
                    "Saves the session to disk and powers off, after the computer has slept this long \u2014 it wakes briefly to do it.", "with sleep on");
        assertEqual(rules.hibernateCaption("", "saver"), "Saves the session to disk and powers off, this long after the screensaver.", "with sleep off");
        assertEqual(rules.hibernateLine({ from: "lock", at: 1200, after: 7200 }, minutes), "Hibernates 2 h after the lock (2 h 20 min after your last input).",
                    "the line: after the lock");
        assertEqual(rules.hibernateLine({ from: "sleep", at: 1800, after: 10800 }, minutes),
                    "Hibernates 3 h after sleeping (3 h 30 min after your last input).", "… after sleeping");
        assertEqual(rules.hibernateLine({ from: "input", at: 0, after: 7200 }, minutes), "Hibernates 2 h after your last input.",
                    "… from the last input: said once");

        // --- the Sleep section ---
        assertEqual(rules.sleepUnavailable("yes"), "", "CanSuspend yes: available");
        assertEqual(rules.sleepUnavailable("challenge"), "Not available here: the system asks for a password to sleep",
                    "challenge: the password named");
        assert(rules.sleepUnavailable("na").startsWith("Not available here: ") && rules.sleepUnavailable("no").startsWith("Not available here: ")
               && rules.sleepUnavailable(undefined).startsWith("Not available here: "), "na, no, not read: not available");
        const lockLine = facts => rules.sleepLockLine(facts, minutes);
        assertEqual(lockLine({ lockOnSleep: true, lockAfter: 0, sleepAfter: 1800 }), "Locks first (\"Lock before the computer sleeps\").",
                    "lock before sleep on: it locks first");
        assertEqual(lockLine({ lockOnSleep: false, lockAfter: 900, sleepAfter: 1800 }), "Already locked by then (lock at 15 min).",
                    "the idle lock before it");
        assertEqual(lockLine({ lockOnSleep: false, lockAfter: 1800, sleepAfter: 1800 }), "Already locked by then (lock at 30 min).",
                    "… at the same time (the sleep waits for it)");
        assertEqual(lockLine({ lockOnSleep: false, lockAfter: 3600, sleepAfter: 1800 }), "Sleeps unlocked: \"Lock before the computer sleeps\" is off.",
                    "the idle lock later: said in advance that it sleeps unlocked");
        assertEqual(lockLine({ lockOnSleep: false, lockAfter: 0, sleepAfter: 1800 }), "Sleeps unlocked: \"Lock before the computer sleeps\" is off.",
                    "… no idle lock: the same");
        assertEqual(rules.systemSleeps({ action: "suspend", after: 1800 }, minutes),
                    "The system already puts the computer to sleep after 30 min without input (logind's IdleAction). With this on too, whichever comes first acts.",
                    "logind suspends by itself: said, a warning");
        assertEqual(rules.systemSleeps({ action: "suspend", after: 0 }, minutes),
                    "The system already puts the computer to sleep without input (logind's IdleAction). With this on too, whichever comes first acts.",
                    "… with no time of its own: none said");
        assert(rules.systemSleeps({ action: "hibernate", after: 600 }, minutes).startsWith("The system already hibernates the computer after 10 min"),
               "… hibernates");
        assert(rules.systemSleeps({ action: "poweroff", after: 600 }, minutes).startsWith("The system already turns the computer off"), "… powers off");
        for (const quiet of [{ action: "ignore", after: 1800 }, { action: "lock", after: 1800 }, null, { action: "toString", after: 1 }])
            assertEqual(rules.systemSleeps(quiet, minutes), "", "nothing said for " + JSON.stringify(quiet));
        assertEqual(caption({ holders: [], anything: true, lockAfter: 900, sleepAfter: 1800, lockedScreenOffAfter: 60, canPowerOff: true }),
                    "Locks at 15 min. Sleeps at 30 min.", "the lock, then the sleep");
        assertEqual(caption({ holders: [], anything: true, lockAfter: 0, sleepAfter: 1800, lockedScreenOffAfter: 60, canPowerOff: true }),
                    "No lock when idle. Sleeps at 30 min.", "no idle lock, the sleep");
        assertEqual(caption({ holders: [], sleepBlockers: [{ who: "borg", why: "Backup" }, { who: "x", why: "" }], anything: true, sleepAfter: 1800 }),
                    "Paused: borg blocks sleep (Backup), and 1 more.", "logind's sleep block takes the line");
        assertEqual(caption({ holders: [], sleepBlockers: [{ who: "borg", why: "" }], anything: true, sleepAfter: 1800 }),
                    "Paused: borg blocks sleep.", "… one, without a reason");
        assertEqual(caption({ holders: [], sleepBlockers: [{ who: "borg", why: "" }], anything: true, lockAfter: 900, sleepAfter: 0,
                              lockedScreenOffAfter: 0 }), "Locks at 15 min. Locked: screens stay on.", "… only while the sleep is on");
        assertEqual(caption({ holders: [{ who: "mpv", why: "" }], sleepBlockers: [{ who: "borg", why: "" }], anything: true, sleepAfter: 1800 }),
                    "Paused: mpv keeps the screen on.", "an app keeping the screen on comes first: it holds everything");

        // --- the holders ---
        const listed = list => list.map(holder => holder.who + "/" + holder.why).join(" | ");
        assertEqual(listed(rules.holders([{ app: "Firefox", reason: "Playing video", cookie: 3 }], [{ who: "mpv", why: "video" }], true)),
                    "Firefox/Playing video | mpv/video | an app (unnamed)/", "the bus's, logind's and an unnamed Wayland one, in that order");
        assertEqual(listed(rules.holders([{ app: "a\nb", reason: "x".repeat(200) }], null, false)), "a b/" + "x".repeat(80),
                    "on one line, capped");
        assertEqual(listed(rules.holders([{ app: "", reason: "" }], undefined, false)), "an app/", "a nameless one is an app");
        assertEqual(rules.holders(null, null, false).length, 0, "none");

        // --- a card's times ---
        const range = { minimum: 5, maximum: 86400 };
        const defaults = { screensaverEnabled: true, screensaverTimeout: 300, screenOffEnabled: false, screenOffTimeout: 900 };
        assertEqual(JSON.stringify(rules.cardTimes({ screenOffEnabled: true, screenOffTimeout: 300 }, defaults, range)),
                    JSON.stringify({ screensaverEnabled: true, screensaverTimeout: 300, screenOffEnabled: true, screenOffTimeout: 300 }),
                    "a partial entry: the default's for what it lacks, whole");
        assertEqual(JSON.stringify(rules.cardTimes({ screensaverEnabled: "yes", screensaverTimeout: 2, screenOffEnabled: false, screenOffTimeout: 99999.4, extra: 1 }, defaults, range)),
                    JSON.stringify({ screensaverEnabled: true, screensaverTimeout: 5, screenOffEnabled: false, screenOffTimeout: 86400 }),
                    "wrong fields the default's, times clamped to the range, nothing else kept");
        assertEqual(JSON.stringify(rules.cardTimes(null, defaults, range)), JSON.stringify(defaults), "no entry: the default's");
        assertEqual(JSON.stringify(rules.cardTimes({ screensaverTimeout: 120.6 }, {}, range)),
                    JSON.stringify({ screensaverEnabled: false, screensaverTimeout: 121, screenOffEnabled: false, screenOffTimeout: 600 }),
                    "whole seconds; nothing known: off");

        // --- a monitor's name ---
        assertEqual(rules.monitorName("Samsung Electric Company|C27JG5x|H4ZMC00268", "DP-2"), "Samsung C27JG5x", "the make's first word and the model");
        assertEqual(rules.monitorName("BOE|0x0BCA|", "eDP-1"), "Built-in screen", "the built-in panel by its kind");
        assertEqual(rules.monitorName("A|B||eDP-1", ""), "Built-in screen", "… a twin's id names its connector");
        assertEqual(rules.monitorName("GIGA-BYTE TECHNOLOGY CO., LTD.|M27Q|1", "HDMI-A-1"), "GIGA-BYTE M27Q", "a long make shortened");
        assertEqual(rules.monitorName("||", "DP-3"), "DP-3", "no make or model: the connector");
        assertEqual(rules.monitorName("||", ""), "Monitor", "nothing at all");
        assertEqual(rules.monitorName("|Odyssey|S1", "DP-1"), "Odyssey", "no make: the model");
        assertEqual(rules.monitorNames([{ id: "Dell|U2419H||DP-1", connector: "DP-1" }, { id: "Dell|U2419H||DP-2", connector: "DP-2" },
                                        { id: "BOE|X|", connector: "eDP-1" }]).join(" | "),
                    "Dell U2419H (DP-1) | Dell U2419H (DP-2) | Built-in screen", "twins told apart by their connectors, the rest as named");
        assertEqual(rules.monitorNames([]).length, 0, "no monitors: no names");
    }
}
