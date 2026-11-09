import Quickshell
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
    readonly property bool _wantsKeyboard: {
        for (let i = 0; i < toastSlots.count; i++) {
            if (toastSlots.itemAt(i)?.wantsKeyboard)
                return true;
        }
        return false;
    }
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
    mask: Region {
        Region { item: toastArea }
        Region { item: queueBadge }
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
    // Slots stacked newest on top: one shows notifications one at a time (the rest
    // counted on the badge), more show a column of them. The slots always exist — the
    // setting only enables them — so changing it never destroys a toast on screen. Each
    // toast's place comes from Notifications.shownToasts (oldest first): above it are
    // the newer ones, so a new toast pushes the others down and the oldest, at the
    // bottom, is the one counting down.
    readonly property int _toastTop: Theme.bar.reservedSpace + Theme.osdToast.screenGap
    readonly property int _toastSlots: Profiles.value("notifications.toastLayout") === "column"
        ? (Profiles.value("notifications.toastColumnSize") ?? 3) : 1
    readonly property int _maxToastSlots: 10
    readonly property int _toastSpacing: Theme.osdToast.spacing

    // The toast on screen showing notification `id`
    function _slotFor(id) {
        for (let i = 0; i < toastSlots.count; i++) {
            const slot = toastSlots.itemAt(i);
            if (slot && slot.currentNotif !== null && slot.currentNotif.id === id)
                return slot;
        }
        return null;
    }

    // Distance from the top of the stack for the toast showing `id`: the heights of the
    // newer toasts above it. null for a toast not in the list (leaving, or empty).
    function _toastY(id) {
        const shown = Notifications.shownToasts;
        const index = shown.indexOf(id);
        if (index < 0)
            return null;
        let y = 0;
        for (let i = index + 1; i < shown.length; i++)
            y += (_slotFor(shown[i])?.height ?? 0) + _toastSpacing;
        return y;
    }

    Item {
        id: toastStack
        y: hud._toastTop
        width: hud.implicitWidth
        // Down to the lowest visible toast, for the input mask
        height: {
            let bottom = 0;
            for (let i = 0; i < toastSlots.count; i++) {
                const slot = toastSlots.itemAt(i);
                if (slot && slot.visible)
                    bottom = Math.max(bottom, slot.y + slot.height);
            }
            return bottom;
        }

        Repeater {
            id: toastSlots
            // A count, not an array: the slots never change
            model: hud._maxToastSlots

            NotificationHudItem {
                required property int index
                screenWidth: hud.implicitWidth
                screenModelData: hud.modelData
                slotEnabled: index < hud._toastSlots
                stackY: hud._toastY(currentNotif?.id ?? -1)
            }
        }
    }

    // Where the toasts are, for the input mask: the toasts' strip at the right edge, as
    // tall as the visible ones
    Item {
        id: toastArea
        // The toast and, at most, the badge beside it
        readonly property int _reach: Theme.osdToast.width + Math.max(Theme.osdToast.screenGap, Theme.osdToast.badgeWidth + 8)
        x: hud.implicitWidth - _reach
        y: toastStack.y
        width: _reach
        height: toastStack.height
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

    // Badge showing how many notifications are waiting in the queue.
    // Positioned flush to the right screen edge, just below the bar.
    Rectangle {
        id: queueBadge
        x: visible ? hud.implicitWidth - width : hud.implicitWidth
        y: hud._toastTop
        width: Theme.osdToast.badgeWidth
        // As tall as the first toast; a sensible size before there is one
        height: Math.max(36, toastSlots.count > 0 ? (toastSlots.itemAt(0)?.height ?? 36) : 36)
        // Shares the toast's rounding
        topLeftRadius: Theme.osdToast.radius
        bottomLeftRadius: Theme.osdToast.radius
        color: Theme.surface
        border.width: Theme.osdToast.borderWidth
        border.color: Theme.osdToastBorder

        // On the toasts' screen only
        opacity: Notifications.hudQueue.length > 0 && Notifications.toastScreen === hud.modelData.name ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }

        Text {
            anchors.centerIn: parent
            text: Notifications.hudQueue.length
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            font.bold: true
            color: Theme.textPrimary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifications.openPanelRequested()
        }
    }
}
