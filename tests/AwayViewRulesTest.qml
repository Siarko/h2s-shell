import QtQuick
import qs.singletons

// The "When away" page's decisions: the timeline's lanes, marks and the labels' sides, the
// line under it, the holders, a monitor's name
TestCase {
    suiteName: "AwayViewRules"

    readonly property var rules: AwayViewRules
    readonly property var minutes: seconds => Format.duration(seconds)

    function _placed(list) {
        return list.map(label => label.row + "@" + Math.round(label.left)).join(" ");
    }

    function run() {
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
        assertEqual(rules.axisEnd([{ saverAfter: 0, screenOffAfter: 0 }], 0, 3600), Math.round(3600 * 1.18), "… or the commands");

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
        assertEqual(marks(rules.marks(desk, 1200, 300, minutes)), "time:2 min | time:5 min | commands:Commands 5 min | time:15 min | lock:Lock 20 min",
                    "equal times of two lanes once; the commands' moment between a stage and the lock");
        assertEqual(marks(rules.marks([{ saverAfter: 0, screenOffAfter: 300 }], 300, 300, minutes)), "time:5 min | commands:Commands 5 min | lock:Lock 5 min",
                    "at one time: the stage, the commands, the lock");
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
