pragma Singleton

import Quickshell
import QtQuick

// Where and how long toasts show — pure, so tests/ToastRulesTest.qml checks every case
// without the monitors or a notification server at hand. Notifications holds the live
// answers (`toastScreen`, the shown toasts and their times).
//
// Which screen — notifications' toasts and the shell's own messages:
// A rule and its exception, not two choices side by side:
// - where: the screen with the focused workspace, or a chosen one (by its port: "DP-2");
//   a chosen screen that is not connected falls back to the focused one;
// - when that screen — only that one — has a fullscreen window: show anyway, show
//   nowhere, or show on another screen: a chosen one, or the first without a fullscreen
//   window. A chosen one that has one too, or none free: nowhere.
// Nowhere: the notification goes to the panel only.
Singleton {
    id: root

    // `settings`: { screen: "" (the focused one) or a port, fullscreen: "show" | "hide" |
    // "elsewhere", fullscreenScreen: "" (any free one) or a port }; `screens`: [{ name,
    // focused, fullscreen }] in the compositor's order. → a screen's name, or "" for none.
    function screenFor(settings, screens): string {
        const list = screens ?? [];
        const named = name => list.find(screen => screen.name === name) ?? null;
        const focused = list.find(screen => screen.focused) ?? list[0] ?? null;
        const chosen = settings?.screen ? named(settings.screen) : null;
        const base = chosen ?? focused;
        if (base === null)
            return "";
        if (!base.fullscreen)
            return base.name;
        const behaviour = settings?.fullscreen ?? "show";
        if (behaviour === "hide")
            return "";
        if (behaviour !== "elsewhere")
            return base.name;
        if (settings?.fullscreenScreen) {
            const target = named(settings.fullscreenScreen);
            return target !== null && target !== base && !target.fullscreen ? target.name : "";
        }
        const free = list.find(screen => screen !== base && !screen.fullscreen);
        return free ? free.name : "";
    }

    // How long a notification's toast shows, from the time its sender asks for (the spec's
    // expire_timeout: -1 the server decides, 0 never expires, else milliseconds). Only the
    // toast: the entry stays in the centre until dismissed.
    // `args`: { expireTimeout, critical, defaultSeconds (the user's "Show each toast for"),
    // followSender (the user's "Apps choose how long") }
    // → { ms: how long, 0 for a toast that stays until taken away;
    //     kind: "default" (the user's time: these count down one at a time, the oldest
    //     first), "own" (the sender's time: counts by itself, at once), "stays" }
    function timing(args): var {
        const defaultMs = Math.max(1, Number(args?.defaultSeconds) || 5) * 1000;
        if (args?.critical === true)
            return { ms: 0, kind: "stays" };
        const asked = Number(args?.expireTimeout);
        if (args?.followSender === false || args?.expireTimeout === undefined || args?.expireTimeout === null
                || !Number.isFinite(asked) || asked < 0)
            return { ms: defaultMs, kind: "default" };
        if (asked === 0)
            return { ms: 0, kind: "stays" };
        // A shorter time would not be seen
        return { ms: Math.max(1000, Math.round(asked)), kind: "own" };
    }

    // The toast's time alone, in ms; 0: it stays
    function duration(args): int {
        return timing(args).ms;
    }

    // Room for toasts on screen. The layout's slots are for toasts that count down: 1 for
    // "One at a time" (layout "queue"), the column's size (2–10) for "A column". Toasts that
    // stay take none of them: they stack above, at most `maxStaying` (1–5); more wait in the
    // queue. `staying`: how many that stay are on screen now (a toast whose time changed
    // while shown may put it past the limit).
    // → { counting, maxStaying, stayingRoom (how many more that stay may show), total (the
    //     slots that may be in use at once) }
    function slots(layout, columnSize, staying, maxStaying): var {
        const clamp = (value, low, high, fallback) => {
            const number = Math.round(Number(value));
            return Number.isFinite(number) ? Math.min(high, Math.max(low, number)) : fallback;
        };
        const counting = layout === "column" ? clamp(columnSize, 2, 10, 3) : 1;
        const limit = clamp(maxStaying, 1, 5, 3);
        const shown = Math.max(0, Math.round(Number(staying)) || 0);
        return { counting: counting, maxStaying: limit, stayingRoom: Math.max(0, limit - shown), total: counting + limit };
    }

    // Which queued toast a free slot takes: the oldest that has room — one that stays while
    // fewer than the limit stay, any other while the layout's slots are not all taken by
    // toasts that count down. `kinds`: the queue's kinds (timing().kind), oldest first;
    // `countingShown`: the toasts on screen that do not stay; `room`: slots().
    // → its index in the queue, or -1: none fits, they wait
    function nextToast(kinds, countingShown, room): int {
        const list = kinds ?? [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] === "stays" ? room.stayingRoom > 0 : countingShown < room.counting)
                return i;
        }
        return -1;
    }

    // The order of the toasts on screen, top to bottom: those that stay above the others,
    // each group newest first. `shown`: ids oldest first; `staying`: the ids among them
    // that stay.
    function stackOrder(shown, staying): var {
        const newestFirst = (shown ?? []).slice().reverse();
        const stays = id => (staying ?? []).includes(id);
        return newestFirst.filter(stays).concat(newestFirst.filter(id => !stays(id)));
    }
}
