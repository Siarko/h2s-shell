import QtQuick
import qs.singletons

TestCase {
    suiteName: "ToastRules"

    function _screens(focused, fullscreen) {
        return ["DP-2", "HDMI-A-1", "eDP-1"].map(name => ({
            name: name, focused: name === focused, fullscreen: (fullscreen ?? []).includes(name)
        }));
    }

    function run() {
        const at = (settings, screens) => ToastRules.screenFor(settings, screens);
        const defaults = { screen: "", fullscreen: "show", fullscreenScreen: "" };
        const with_ = change => Object.assign({}, defaults, change);

        // --- where ---
        assertEqual(at(defaults, _screens("HDMI-A-1")), "HDMI-A-1", "the focused screen");
        assertEqual(at(with_({ screen: "DP-2" }), _screens("HDMI-A-1")), "DP-2", "a chosen screen, focused or not");
        assertEqual(at(with_({ screen: "DP-3" }), _screens("HDMI-A-1")), "HDMI-A-1",
                    "a chosen screen not connected: the focused one");
        assertEqual(at(defaults, [{ name: "eDP-1", focused: false, fullscreen: false }]), "eDP-1",
                    "none focused (not known yet): the first");
        assertEqual(at(defaults, []), "", "no screens: nowhere");
        assertEqual(at(undefined, _screens("DP-2")), "DP-2", "no settings: the focused screen");

        // --- a fullscreen window on the toasts' screen ---
        assertEqual(at(defaults, _screens("DP-2", ["DP-2"])), "DP-2", "show anyway");
        assertEqual(at(with_({ fullscreen: "hide" }), _screens("DP-2", ["DP-2"])), "", "hide: nowhere");
        assertEqual(at(with_({ fullscreen: "hide" }), _screens("DP-2", ["HDMI-A-1"])), "DP-2",
                    "hide looks at the toasts' screen only: fullscreen elsewhere changes nothing");
        assertEqual(at(with_({ screen: "HDMI-A-1", fullscreen: "hide" }), _screens("DP-2", ["DP-2"])), "HDMI-A-1",
                    "a chosen screen without one: fullscreen on the focused screen changes nothing");

        // --- elsewhere ---
        const elsewhere = with_({ fullscreen: "elsewhere" });
        assertEqual(at(elsewhere, _screens("DP-2", ["DP-2"])), "HDMI-A-1", "any free screen: the first free one");
        assertEqual(at(elsewhere, _screens("HDMI-A-1", ["DP-2", "HDMI-A-1"])), "eDP-1", "skipping others in fullscreen");
        assertEqual(at(elsewhere, _screens("DP-2", ["DP-2", "HDMI-A-1", "eDP-1"])), "", "none free: nowhere");
        assertEqual(at(elsewhere, [{ name: "eDP-1", focused: true, fullscreen: true }]), "",
                    "one screen, in fullscreen: nowhere");
        const onHdmi = with_({ fullscreen: "elsewhere", fullscreenScreen: "HDMI-A-1" });
        assertEqual(at(onHdmi, _screens("DP-2", ["DP-2"])), "HDMI-A-1", "a chosen screen for fullscreen");
        assertEqual(at(onHdmi, _screens("DP-2", ["DP-2", "HDMI-A-1"])), "",
                    "the chosen screen in fullscreen too: nowhere");
        assertEqual(at(onHdmi, _screens("HDMI-A-1", ["HDMI-A-1"])), "",
                    "the chosen screen is the toasts' screen, in fullscreen: nowhere");
        assertEqual(at(with_({ fullscreen: "elsewhere", fullscreenScreen: "DP-3" }), _screens("DP-2", ["DP-2"])), "",
                    "the chosen screen not connected: nowhere");
        assertEqual(at(onHdmi, _screens("DP-2", [])), "DP-2", "no fullscreen window: where it would be");

        // --- how long a toast shows: the sender's time, else the user's ---
        const time = change => ToastRules.timing(Object.assign({ critical: false, defaultSeconds: 5, followSender: true }, change));
        const said = (change, expected, message) => assertEqual(JSON.stringify(time(change)), JSON.stringify(expected), message);
        said({ expireTimeout: -1 }, { ms: 5000, kind: "default" }, "-1 (the server decides): the user's time");
        said({ expireTimeout: -7 }, { ms: 5000, kind: "default" }, "below 0: the user's time");
        said({}, { ms: 5000, kind: "default" }, "absent: the user's time");
        said({ expireTimeout: null }, { ms: 5000, kind: "default" }, "null: the user's time");
        said({ expireTimeout: NaN }, { ms: 5000, kind: "default" }, "NaN: the user's time");
        said({ expireTimeout: "soon" }, { ms: 5000, kind: "default" }, "not a number: the user's time");
        said({ expireTimeout: 0 }, { ms: 0, kind: "stays" }, "0: stays");
        said({ expireTimeout: 500 }, { ms: 1000, kind: "own" }, "500 ms: at least 1 s, counted by itself");
        said({ expireTimeout: 30000 }, { ms: 30000, kind: "own" }, "30 s: 30 s");
        said({ expireTimeout: 2000, defaultSeconds: 12 }, { ms: 2000, kind: "own" }, "the sender's time, not the user's");
        said({ expireTimeout: -1, defaultSeconds: 12 }, { ms: 12000, kind: "default" }, "the user's time as set");
        for (const expire of [-1, undefined, NaN, 0, 500, 30000])
            said({ expireTimeout: expire, critical: true }, { ms: 0, kind: "stays" }, "critical, expire " + expire + ": stays");
        for (const expire of [-1, undefined, NaN, 0, 500, 30000])
            said({ expireTimeout: expire, followSender: false }, { ms: 5000, kind: "default" },
                 "\"Apps choose how long\" off, expire " + expire + ": the user's time");
        said({ expireTimeout: 0, critical: true, followSender: false }, { ms: 0, kind: "stays" },
             "critical with the setting off: still stays");
        assertEqual(ToastRules.duration({ expireTimeout: 2000, defaultSeconds: 5, followSender: true }), 2000, "duration: the time alone");

        // --- room on screen: the layout's slots for toasts that count down, those that stay above ---
        for (const layout of ["queue", "column"]) {
            for (const limit of [1, 3, 5]) {
                for (let staying = 0; staying <= 6; staying++) {
                    const room = ToastRules.slots(layout, 4, staying, limit);
                    const counting = layout === "column" ? 4 : 1;
                    assertEqual(JSON.stringify(room), JSON.stringify({ counting: counting, maxStaying: limit,
                        stayingRoom: Math.max(0, limit - staying), total: counting + limit }),
                        "slots: " + layout + ", " + staying + " staying, at most " + limit);
                }
            }
        }
        assertEqual(ToastRules.slots("column", 25, 0, 9).counting + " " + ToastRules.slots("column", 25, 0, 9).maxStaying, "10 5",
                    "slots: the column at most 10, those that stay at most 5");
        assertEqual(ToastRules.slots("column", undefined, 0, undefined).counting + " " + ToastRules.slots("queue", 5, 0, 0).maxStaying, "3 1",
                    "slots: no column size: 3; a limit below 1: 1");

        // --- which waiting toast a free slot takes ---
        const one = ToastRules.slots("queue", 3, 0, 3);
        assertEqual(ToastRules.nextToast(["default", "own"], 0, one), 0, "next: the oldest");
        assertEqual(ToastRules.nextToast(["default"], 1, one), -1, "next: the layout's slot taken, the next waits");
        assertEqual(ToastRules.nextToast(["own", "stays"], 1, one), 1, "next: the slot taken, one that stays still shows");
        assertEqual(ToastRules.nextToast(["stays", "default"], 0, ToastRules.slots("queue", 3, 3, 3)), 1,
                    "next: the limit of those that stay reached, it waits and a later one takes the slot");
        assertEqual(ToastRules.nextToast(["stays"], 0, ToastRules.slots("queue", 3, 4, 3)), -1,
                    "next: past the limit (a time changed while shown), none that stays");
        assertEqual(ToastRules.nextToast([], 0, one), -1, "next: nothing waiting");

        // --- the order on screen, top to bottom ---
        assertEqual(JSON.stringify(ToastRules.stackOrder([1, 2, 3, 4], [2, 4])), "[4,2,3,1]",
                    "stack: those that stay on top, each group newest first");
        assertEqual(JSON.stringify(ToastRules.stackOrder([1, 2], [])), "[2,1]", "stack: none that stays, newest first");
    }
}
