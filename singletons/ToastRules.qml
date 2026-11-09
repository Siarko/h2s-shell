pragma Singleton

import Quickshell
import QtQuick

// Which screen toasts show on — notifications' and the shell's own messages — pure, so
// tests/ToastRulesTest.qml checks every case without the monitors at hand. Notifications
// holds the live answer (`toastScreen`).
//
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
}
