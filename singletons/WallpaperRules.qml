pragma Singleton

import Quickshell
import QtQuick

// Which image each screen's wallpaper shows — pure, so tests/WallpaperRulesTest.qml checks
// every case without screens or files at hand. Wallpapers holds the live state and asks
// here; docs/plans/wallpapers.md has the whole model.
//
// The source is a file (the same image everywhere, nothing else applies) or a folder.
// From a folder, images are named by their path relative to it, so the choices survive
// the folder moving. The scope says what has a wallpaper of its own — one everywhere ("*"),
// each monitor (its port, "DP-2") or each workspace (its number, "3") — and the mode how
// it is chosen:
// - fixed: the slot's own choice, else the first chosen (the first monitor in the
//   compositor's order, the lowest workspace number), else the first image;
// - random: the slot's draw, without repeats while the pool lasts;
// - weekday: the day's image, the same everywhere.
// In random and weekday mode a pinned workspace or monitor keeps its image (a workspace's
// pin before its monitor's), whatever the scope.
Singleton {
    id: root

    readonly property var imageExtensions: ["jpg", "jpeg", "png", "webp", "bmp"]

    // The layer namespace of the shell's own wallpaper, to tell it from another program's
    readonly property string namespace: "h2s-wallpaper"

    function isImage(path: string): bool {
        const dot = path.lastIndexOf(".");
        return dot > 0 && imageExtensions.includes(path.slice(dot + 1).toLowerCase());
    }

    // "~/x" → "<home>/x"; a trailing slash dropped
    function expand(path: string, home: string): string {
        let result = String(path ?? "").trim();
        if (result === "~" || result.startsWith("~/"))
            result = home + result.slice(1);
        while (result.length > 1 && result.endsWith("/"))
            result = result.slice(0, -1);
        return result;
    }

    // The images to draw from: the chosen subset that is still in the folder, or all
    function pool(files, subset) {
        const list = files ?? [];
        const chosen = (subset ?? []).filter(path => list.includes(path));
        return chosen.length > 0 ? chosen : list.slice();
    }

    // The slot a screen's wallpaper belongs to; null for none (no workspace known yet)
    function slotOf(scope: string, screen) {
        if (scope === "monitor")
            return screen?.name ?? null;
        if (scope === "workspace")
            return (screen?.workspace ?? 0) > 0 ? String(screen.workspace) : null;
        return "*";
    }

    // The slots the screens show now, in order, without repeats
    function slotsShown(scope: string, screens) {
        const slots = [];
        for (const screen of screens ?? []) {
            const slot = slotOf(scope, screen);
            if (slot !== null && !slots.includes(slot))
                slots.push(slot);
        }
        return slots;
    }

    // Fixed mode: `slot`'s own choice, else the first chosen of its kind, else ""
    function fixedFor(slot, scope: string, assignments, screens, available) {
        const chosen = assignments ?? {};
        const usable = path => typeof path === "string" && path !== "" && available(path);
        if (usable(chosen[slot]))
            return chosen[slot];
        let order = [];
        if (scope === "monitor")
            order = (screens ?? []).map(screen => screen.name);
        else if (scope === "workspace")
            order = Object.keys(chosen).filter(key => /^[0-9]+$/.test(key)).sort((a, b) => Number(a) - Number(b));
        const first = order.find(key => usable(chosen[key]));
        return first !== undefined ? chosen[first] : "";
    }

    // A pinned image for a screen: its workspace's, else its monitor's, else ""
    function pinnedFor(screen, pinned, available) {
        const pins = pinned ?? {};
        const usable = path => typeof path === "string" && path !== "" && available(path);
        const workspace = (screen?.workspace ?? 0) > 0 ? String(screen.workspace) : null;
        if (workspace !== null && usable(pins[workspace]))
            return pins[workspace];
        if (usable(pins[screen?.name]))
            return pins[screen.name];
        return "";
    }

    // Draws an image for each of `slots` not in `kept`, from `pool`: none twice while
    // others are left, then from the whole pool again; for a slot in `previous` another
    // image than it had, where there is one. `random` returns [0, 1) (Math.random; fixed
    // in tests). → { slot: path }, `kept` included.
    function draw(slots, pool, kept, previous, random) {
        const result = Object.assign({}, kept ?? {});
        const images = pool ?? [];
        let used = new Set(Object.values(result));
        for (const slot of slots ?? []) {
            if (slot in result)
                continue;
            let bag = images.filter(path => !used.has(path));
            if (bag.length === 0) {
                used = new Set();
                bag = images.slice();
            }
            const fresh = bag.filter(path => path !== previous?.[slot]);
            const from = fresh.length > 0 ? fresh : bag;
            if (from.length === 0)
                continue;
            const pick = from[Math.min(from.length - 1, Math.floor(random() * from.length))];
            result[slot] = pick;
            used.add(pick);
        }
        return result;
    }

    // The day's image (Monday first in `weekdays`), else the first day's that is set
    function weekdayFor(date, weekdays, available) {
        const days = weekdays ?? [];
        const usable = path => typeof path === "string" && path !== "" && available(path);
        const today = days[(date.getDay() + 6) % 7];
        if (usable(today))
            return today;
        return days.find(usable) ?? "";
    }

    // The image a screen shows, as an absolute path; "" for none (the background colour),
    // null to keep what it shows (no slot for it yet).
    // `settings`: { scope, mode, assignments, pinned, weekdays, subset }; `state`: { kind
    // ("file" | "folder" | "" while unknown or missing), source (the expanded path), files
    // (relative), draws ({ slot: path }), date, screens }.
    function fileFor(settings, screen, state) {
        if (state?.kind === "file")
            return state.source;
        if (state?.kind !== "folder")
            return "";
        const files = state.files ?? [];
        const present = new Set(files);
        const available = path => present.has(path);
        const images = pool(files, settings?.subset);
        const absolute = path => path === "" ? "" : state.source + "/" + path;
        const scope = settings?.scope ?? "everywhere";
        const mode = settings?.mode ?? "fixed";

        if (mode === "fixed") {
            const slot = slotOf(scope, screen);
            if (slot === null)
                return null;
            const chosen = fixedFor(slot, scope, settings?.assignments, state.screens, available);
            return absolute(chosen !== "" ? chosen : (images[0] ?? ""));
        }

        const pin = pinnedFor(screen, settings?.pinned, available);
        if (pin !== "")
            return absolute(pin);
        if (mode === "weekday") {
            const day = weekdayFor(state.date ?? new Date(), settings?.weekdays, available);
            return absolute(day !== "" ? day : (images[0] ?? ""));
        }
        const slot = slotOf(scope, screen);
        if (slot === null)
            return null;
        const drawn = state.draws?.[slot];
        return typeof drawn === "string" && available(drawn) ? absolute(drawn) : null;
    }

    // The colour an image's edge averages to ("#rrggbb"), for the background beside it: the
    // bars of a fitted image then look like the image carried on. `pixels`: RGBA bytes in
    // rows, `width` × `height`, as a canvas' getImageData gives them; transparent pixels
    // do not count. "" with nothing to go by.
    function edgeColor(pixels, width: int, height: int): string {
        let red = 0, green = 0, blue = 0, count = 0;
        const add = (x, y) => {
            const i = (y * width + x) * 4;
            if (i + 3 >= pixels.length || pixels[i + 3] < 128)
                return;
            red += pixels[i];
            green += pixels[i + 1];
            blue += pixels[i + 2];
            count++;
        };
        for (let x = 0; x < width; x++) {
            add(x, 0);
            if (height > 1)
                add(x, height - 1);
        }
        for (let y = 1; y < height - 1; y++) {
            add(0, y);
            if (width > 1)
                add(width - 1, y);
        }
        if (count === 0)
            return "";
        const hex = value => Math.round(value / count).toString(16).padStart(2, "0");
        return "#" + hex(red) + hex(green) + hex(blue);
    }

    // The name of an image's copy resized to a screen (kept in ~/.cache/h2s_shell/
    // wallpapers): a hash of the image's path, its stamp (modification time and size, so a
    // replaced image gets a new copy), the screen's size in physical pixels (a larger screen
    // never shows a smaller copy) and the fit — Fill keeps the screen's shape, cropped; Fit
    // the image's, inside the screen. Centre and Tile show the image's own pixels: no copy,
    // "". "" too without a stamp or a size.
    function screenCopyName(path: string, stamp: string, width: int, height: int, fit: string): string {
        if ((fit !== "cover" && fit !== "contain") || path === "" || stamp === "" || width <= 0 || height <= 0)
            return "";
        return Qt.md5([path, stamp, width + "x" + height, fit].join("|")) + ".jpg";
    }

    // Wallpapers another program draws: the background-layer surfaces in `hyprctl layers
    // -j` that are not ours → [{ monitor, namespace }]
    function foreignBackgrounds(layers) {
        const found = [];
        for (const monitor in layers ?? {}) {
            for (const surface of layers[monitor]?.levels?.["0"] ?? []) {
                if (surface.namespace !== root.namespace)
                    found.push({ monitor: monitor, namespace: surface.namespace || "unnamed" });
            }
        }
        return found;
    }
}
