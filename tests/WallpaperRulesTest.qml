import QtQuick
import qs.singletons

TestCase {
    suiteName: "WallpaperRules"

    // Two monitors: DP-2 on workspace 1, HDMI-A-1 on workspace 4
    readonly property var _screens: [
        { name: "DP-2", workspace: 1 },
        { name: "HDMI-A-1", workspace: 4 }
    ]
    readonly property var _files: ["a.jpg", "b.png", "sub/c.webp"]

    // Cycles through the given values, for a draw that is known in advance
    function _sequence(values) {
        let index = 0;
        return () => values[index++ % values.length];
    }

    function _state(change) {
        return Object.assign({ kind: "folder", source: "/w", files: _files, draws: {},
                               date: new Date(2026, 10, 11), screens: _screens }, change ?? {});
    }

    function run() {
        const rules = WallpaperRules;
        const all = () => true;

        // --- small rules ---
        assert(rules.isImage("x/Y.JPG"), "an image by its extension, any case");
        assert(!rules.isImage("notes.txt"), "not an image");
        assert(!rules.isImage(".png"), "a hidden file named only by the extension: no");
        assertEqual(rules.expand("~/Pictures/w/", "/home/u"), "/home/u/Pictures/w", "~ expanded, trailing slash dropped");
        assertEqual(rules.expand("/", "/home/u"), "/", "the root stays");
        assertEqual(JSON.stringify(rules.pool(_files, ["b.png", "gone.jpg"])), "[\"b.png\"]",
                    "the subset, without images no longer there");
        assertEqual(rules.pool(_files, ["gone.jpg"]).length, 3, "a subset of only missing images: all");
        assertEqual(rules.pool(_files, []).length, 3, "no subset: all");

        assertEqual(rules.slotOf("everywhere", _screens[0]), "*", "everywhere: one slot");
        assertEqual(rules.slotOf("monitor", _screens[1]), "HDMI-A-1", "per monitor: its port");
        assertEqual(rules.slotOf("workspace", _screens[1]), "4", "per workspace: its number");
        assertEqual(rules.slotOf("workspace", { name: "DP-2", workspace: 0 }), null, "no workspace yet: none");
        assertEqual(JSON.stringify(rules.slotsShown("everywhere", _screens)), "[\"*\"]", "one slot shown for two screens");

        // --- fixed ---
        assertEqual(rules.fixedFor("HDMI-A-1", "monitor", { "HDMI-A-1": "b.png" }, _screens, all), "b.png", "its own choice");
        assertEqual(rules.fixedFor("HDMI-A-1", "monitor", { "DP-2": "a.jpg" }, _screens, all), "a.jpg",
                    "unchosen: the first chosen monitor");
        assertEqual(rules.fixedFor("9", "workspace", { "7": "b.png", "3": "a.jpg", "DP-2": "x" }, _screens, all), "a.jpg",
                    "unchosen workspace: the lowest chosen number, monitors ignored");
        assertEqual(rules.fixedFor("3", "workspace", { "3": "gone.jpg", "5": "b.png" }, _screens, path => path !== "gone.jpg"), "b.png",
                    "its choice missing: the first chosen still there");
        assertEqual(rules.fixedFor("*", "everywhere", {}, _screens, all), "", "nothing chosen: none");

        const fixed = { scope: "monitor", mode: "fixed", assignments: { "DP-2": "sub/c.webp" } };
        assertEqual(rules.fileFor(fixed, _screens[1], _state()), "/w/sub/c.webp", "fileFor: absolute, from the first chosen");
        assertEqual(rules.fileFor({ scope: "everywhere", mode: "fixed" }, _screens[0], _state()), "/w/a.jpg",
                    "fixed with nothing chosen: the first image");
        assertEqual(rules.fileFor({ scope: "everywhere", mode: "fixed", subset: ["b.png"] }, _screens[0], _state()), "/w/b.png",
                    "the first image of the subset");
        assertEqual(rules.fileFor({ scope: "workspace", mode: "fixed" }, { name: "DP-2", workspace: 0 }, _state()), null,
                    "no slot: keep what is shown");

        // --- the source ---
        assertEqual(rules.fileFor(fixed, _screens[0], _state({ kind: "file", source: "/p/one.png" })), "/p/one.png",
                    "a file: that file, whatever else is set");
        assertEqual(rules.fileFor(fixed, _screens[0], _state({ kind: "" })), "", "a missing source: none");
        assertEqual(rules.fileFor({ mode: "fixed" }, _screens[0], _state({ files: [] })), "", "an empty folder: none");

        // --- draw ---
        const first = rules.draw(["DP-2", "HDMI-A-1"], _files, {}, {}, _sequence([0]));
        assertEqual(JSON.stringify(first), "{\"DP-2\":\"a.jpg\",\"HDMI-A-1\":\"b.png\"}", "no repeats while others are left");
        const again = rules.draw(["DP-2", "HDMI-A-1"], _files, {}, first, _sequence([0]));
        assert(again["DP-2"] !== "a.jpg" && again["HDMI-A-1"] !== "b.png", "a new draw changes each slot where it can");
        const many = rules.draw(["1", "2", "3", "4"], _files, {}, {}, _sequence([0]));
        assertEqual(new Set(Object.values(many).slice(0, 3)).size, 3, "the first three all different");
        assert(_files.includes(many["4"]), "the pool used up: from all again");
        const extended = rules.draw(["1", "2"], _files, { "1": "b.png" }, {}, _sequence([0]));
        assertEqual(extended["1"], "b.png", "a kept slot stays");
        assert(extended["2"] !== "b.png", "and its image is not drawn again");
        assertEqual(JSON.stringify(rules.draw(["*"], [], {}, {}, Math.random)), "{}", "nothing to draw from: nothing");
        assertEqual(rules.draw(["*"], ["a.jpg"], {}, { "*": "a.jpg" }, Math.random)["*"], "a.jpg",
                    "one image only: the same again");

        const random = { scope: "monitor", mode: "random" };
        assertEqual(rules.fileFor(random, _screens[1], _state({ draws: { "HDMI-A-1": "b.png" } })), "/w/b.png", "random: the slot's draw");
        assertEqual(rules.fileFor(random, _screens[1], _state()), null, "not drawn yet: keep, the draw comes");
        assertEqual(rules.fileFor(random, _screens[1], _state({ draws: { "HDMI-A-1": "gone.jpg" } })), null,
                    "a drawn image gone: keep until drawn again");

        // --- pinned ---
        const pinnedRandom = { scope: "workspace", mode: "random", pinned: { "HDMI-A-1": "a.jpg", "4": "sub/c.webp" } };
        assertEqual(rules.fileFor(pinnedRandom, _screens[1], _state({ draws: { "4": "b.png" } })), "/w/sub/c.webp",
                    "a pinned workspace before its monitor and the draw");
        assertEqual(rules.fileFor(pinnedRandom, { name: "HDMI-A-1", workspace: 5 }, _state({ draws: { "5": "b.png" } })), "/w/a.jpg",
                    "a pinned monitor, in workspace scope");
        assertEqual(rules.fileFor({ scope: "everywhere", mode: "random", pinned: { "DP-2": "gone.jpg" } }, _screens[0],
                                  _state({ draws: { "*": "b.png" } })), "/w/b.png", "a pin to a missing image: drawn as others");
        assertEqual(rules.fileFor({ scope: "everywhere", mode: "fixed", pinned: { "DP-2": "b.png" } }, _screens[0], _state()), "/w/a.jpg",
                    "pins do not apply in fixed mode");

        // --- weekday ---  2026-11-11 is a Wednesday
        const week = ["a.jpg", "", "b.png", "", "", "", ""];
        assertEqual(rules.weekdayFor(new Date(2026, 10, 11), week, all), "b.png", "Wednesday's");
        assertEqual(rules.weekdayFor(new Date(2026, 10, 15), week, all), "a.jpg", "Sunday unset: the first set day's");
        assertEqual(rules.weekdayFor(new Date(2026, 10, 9), ["", "", "", "", "", "", ""], all), "", "none set: none");
        const weekday = { mode: "weekday", weekdays: week, pinned: { "DP-2": "sub/c.webp" } };
        assertEqual(rules.fileFor(weekday, _screens[1], _state()), "/w/b.png", "weekday, the same everywhere");
        assertEqual(rules.fileFor(weekday, _screens[0], _state()), "/w/sub/c.webp", "a pinned monitor keeps its own");
        assertEqual(rules.fileFor({ mode: "weekday" }, _screens[0], _state()), "/w/a.jpg", "no days set: the first image");

        // --- the background from the image's edge ---
        // 3 × 3: a red ring round a white middle that must not count
        const ring = [];
        for (let y = 0; y < 3; y++)
            for (let x = 0; x < 3; x++)
                ring.push(...(x === 1 && y === 1 ? [255, 255, 255, 255] : [200, 0, 0, 255]));
        assertEqual(rules.edgeColor(ring, 3, 3), "#c80000", "the edge only, not the middle");
        const halves = [0, 0, 0, 255, 255, 255, 255, 255];
        assertEqual(rules.edgeColor(halves, 2, 1), "#808080", "averaged");
        assertEqual(rules.edgeColor([10, 20, 30, 0, 100, 100, 100, 255], 2, 1), "#646464", "transparent pixels left out");
        assertEqual(rules.edgeColor([0, 0, 0, 0], 1, 1), "", "nothing to go by: none");

        // --- copies resized to a screen ---
        const copy = rules.screenCopyName("/w/a.png", "100 2000", 2880, 1920, "cover");
        assert(/^[0-9a-f]{32}\.jpg$/.test(copy), "a hashed name, a JPEG");
        assertEqual(rules.screenCopyName("/w/a.png", "100 2000", 2880, 1920, "cover"), copy, "the same image, screen and fit: the same copy");
        assert(rules.screenCopyName("/w/a.png", "100 2000", 3840, 2160, "cover") !== copy, "a larger screen: another copy, never the smaller one");
        assert(rules.screenCopyName("/w/a.png", "101 2000", 2880, 1920, "cover") !== copy, "the image replaced: another copy");
        assert(rules.screenCopyName("/w/a.png", "100 2000", 2880, 1920, "contain") !== copy, "another fit: another copy");
        assertEqual(rules.screenCopyName("/w/a.png", "100 2000", 2880, 1920, "tile"), "", "tile shows the image's own pixels: none");
        assertEqual(rules.screenCopyName("/w/a.png", "", 2880, 1920, "cover"), "", "no stamp: none");

        // --- another program's wallpaper ---
        const layers = {
            "DP-2": { levels: { "0": [{ namespace: "hyprpaper" }, { namespace: "h2s-wallpaper" }], "2": [{ namespace: "quickshell" }] } },
            "HDMI-A-1": { levels: { "0": [{ namespace: "h2s-wallpaper" }] } }
        };
        assertEqual(JSON.stringify(rules.foreignBackgrounds(layers)), "[{\"monitor\":\"DP-2\",\"namespace\":\"hyprpaper\"}]",
                    "only background surfaces not ours");
        assertEqual(rules.foreignBackgrounds({}).length, 0, "none");
    }
}
