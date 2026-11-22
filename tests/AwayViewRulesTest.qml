import QtQuick
import qs.singletons

// The "When away" page's decisions: the timeline's lanes, marks and the labels' sides, the
// line under it, the holders, a monitor's name, the Sleep section's lines
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

        // --- the sleep on the timeline ---
        assert(rules.anything([{ saverAfter: 0, screenOffAfter: 0 }], 0, 1800), "the sleep alone is something");
        assertEqual(rules.axisEnd([{ saverAfter: 300, screenOffAfter: 0 }], 600, -1, 1800), Math.round(1800 * 1.18), "the axis past the sleep");
        const linear = rules.axis([{ saverAfter: 300, screenOffAfter: 600 }], 900, -1, 1800);
        assertEqual(JSON.stringify(linear), JSON.stringify({ end: Math.round(1800 * 1.18), breakAt: -1, sleepAt: 1800 }),
                    "sleep at 30 min after a lock at 15: one linear axis");
        assertEqual(rules.axis([{ saverAfter: 300, screenOffAfter: 0 }], 1200, -1, 3600).breakAt, -1, "an hour, three times the rest: still linear");
        const broken = rules.axis([{ saverAfter: 300, screenOffAfter: 600 }], 900, -1, 7200);
        assertEqual(JSON.stringify(broken), JSON.stringify({ end: Math.round(7200 * 1.1), breakAt: Math.round(900 * 1.18), sleepAt: 7200 }),
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
