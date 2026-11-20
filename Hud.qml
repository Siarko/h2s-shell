import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.components
import qs.hud
import qs.singletons

// Generic full-screen overlay for transient HUD components (toasts, OSD, etc.).
// Transparent and click-through everywhere except active HUD cards.
PanelWindow {
    id: hud
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    // No keyboard, so clicking a toast leaves it with the app underneath — except while a
    // toast's reply is hovered or being written: then on demand, so a click in the field
    // brings the keyboard, and clicking elsewhere takes it back
    // By touch: exclusive from a tap on a reply field to a tap anywhere else (TouchTextFocus,
    // OutsideTapCatcher) — on demand, the on-screen keyboard appearing took it away
    WlrLayershell.keyboardFocus: _touchTyping ? WlrKeyboardFocus.Exclusive
        : _wantsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    property bool _touchTyping: false
    // A reply sent or cleared lets the keyboard go
    on_WantsKeyboardChanged: {
        if (!_wantsKeyboard)
            _touchTyping = false;
    }
    readonly property bool _wantsKeyboard: toastStack.wantsKeyboard
    WlrLayershell.namespace: "hud"

    anchors {
        top: true
        left: true
    }
    implicitWidth: hud.screen.width
    implicitHeight: hud.screen.height
    margins { top: 0; left: 0 }
    color: "transparent"

    // Input passthrough: only forward clicks to visible HUD card areas. The toast area is
    // as tall as the visible toasts, so it covers nothing while there are none. A Region
    // takes its item's geometry whether the item is shown or not: the OSDs hide by moving
    // off screen, but the startup warnings stay where they are, hidden — so they are in the
    // mask only while one is shown. In the mask while hidden, the launch warning took every
    // click in a 640 px band under the bar's middle, over the popups there (the calendar's
    // top half).
    // The modals (toasts dragged out or pinned) stand anywhere on the screen: each adds its
    // own rectangle, following it as it moves; the set changes as modals come and go.
    mask: Region {
        Region { item: toastArea }
        Region { regions: modalRegions.instances }
        Region { item: volumeOsd }
        Region { item: shellNotifItem }
        Region { item: startupWarnings.height > 0 ? startupWarnings : null }
    }

    // ---- Startup warnings ----
    // Banners under the bar, centred, about how the shell was started or set up
    Column {
        id: startupWarnings
        x: (hud.implicitWidth - width) / 2
        y: Theme.bar.reservedSpace + Theme.osdToast.screenGap
        width: Math.min(640, hud.implicitWidth - 2 * Theme.osdToast.screenGap)
        spacing: Theme.osdToast.screenGap

        // Started without scripts/launch.sh: the icon theme setting cannot apply
        StartupWarning {
            width: parent.width
            visible: !IconThemes.launchedByScript && !IconThemes.launchWarningDismissed
            icon: "󰀦"
            title: "The shell was started without scripts/launch.sh"
            body: "Quickshell reads the icon theme only when it starts, from QS_ICON_THEME, and the script "
                + "sets that from Settings → General → Icon theme. Started directly (qs, qs -c default), "
                + "the shell has no icon theme: the setting does nothing and icons such as warnings may be "
                + "missing. Start it with " + Quickshell.shellDir + "/scripts/launch.sh — Hyprland's autostart "
                + "does — or restart it with launch.sh --restart."
            onDismissed: IconThemes.launchWarningDismissed = true
        }

        // No Nerd Font: the bar's icons are its glyphs
        StartupWarning {
            width: parent.width
            visible: !Theme.nerdFontInstalled && !Theme.nerdFontWarningDismissed
            title: "No Nerd Font installed: icons show as empty boxes"
            body: "The shell's icons are Nerd Font glyphs, and no font on this system has them. Install "
                + "JetBrainsMono Nerd Font (any Nerd Font works), then restart the shell.\n"
                + "Arch: sudo pacman -S ttf-jetbrains-mono-nerd\n"
                + "NixOS: programs.h2s-shell.enable = true; (the module adds it), or "
                + "fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];"
            onDismissed: Theme.nerdFontWarningDismissed = true
        }
    }

    // ---- Typing a reply by touch ----
    // A tap on a toast's reply field gives the window the keyboard, a tap elsewhere on the
    // toasts or anywhere outside them takes it back (the catcher, under the HUD's layer)
    TouchTextFocus {
        id: touchText
        onFieldTapped: onField => { hud._touchTyping = onField; }
    }
    OutsideTapCatcher {
        visible: hud._touchTyping
        screen: hud.screen
        onTapped: {
            hud._touchTyping = false;
            touchText.release();
        }
    }

    // ---- Toasts ----
    // Three stacks under the bar at the right edge — critical, staying, ordinary — each
    // queue's badge beside its lowest toast (ToastStack, Notifications' queues)
    ToastStack {
        id: toastStack
        y: Theme.bar.reservedSpace + Theme.osdToast.screenGap
        width: hud.implicitWidth
        height: contentHeight
        screenWidth: hud.implicitWidth
        screenHeight: hud.implicitHeight
        // Where a dropped toast is kept: the window keeps out of the bar's reserved space, so
        // as much of it as that space is past the screen's edge
        dropWidth: hud.implicitWidth - (BarLayout.vertical ? Theme.bar.reservedSpace : 0)
        dropHeight: hud.implicitHeight - (BarLayout.vertical ? 0 : Theme.bar.reservedSpace)
        screenModelData: hud.modelData
    }

    // A region per modal's toast, for the input mask
    Variants {
        id: modalRegions
        model: toastStack.modalToasts
        Region {
            required property var modelData
            item: modelData
        }
    }

    // For tests driving the shell from outside (the lock test bed): where a toast is on
    // this screen, in the window's logical pixels (the window starts below the bar's reserved
    // space), whether it is a modal, can be dragged and has stopped moving — "{}" when it has
    // none here. The first screen's HUD answers.
    //   qs ipc call toasttest toastRect 7
    IpcHandler {
        target: "toasttest"
        enabled: hud.modelData === Quickshell.screens[0]

        function toastRect(id: int): string {
            const toast = toastStack.toastFor(id);
            if (!toast || !toast.visible)
                return "{}";
            const topLeft = toast.mapToItem(null, 0, 0);
            return JSON.stringify({ x: Math.round(topLeft.x), y: Math.round(topLeft.y), width: Math.round(toast.width),
                                    height: Math.round(toast.height), modal: toast.modal, movable: toast.movable,
                                    settled: toast.settled });
        }
    }

    // Where the toasts are, for the input mask: the toasts' strip at the right edge, as
    // tall as the visible toasts and badges
    Item {
        id: toastArea
        // The toast and, at most, the badge beside it
        readonly property int _reach: Theme.osdToast.width + Math.max(Theme.osdToast.screenGap, Theme.osdToast.badgeWidth + 8)
        x: hud.implicitWidth - _reach
        y: toastStack.y
        width: _reach
        height: toastStack.contentHeight
    }

    VolumeOsdItem {
        id: volumeOsd
        screenWidth: hud.implicitWidth
        screenHeight: hud.implicitHeight
    }

    ShellNotificationHudItem {
        id: shellNotifItem
        screenWidth: hud.implicitWidth
        screenHeight: hud.implicitHeight
        screenModelData: hud.modelData
    }
}
