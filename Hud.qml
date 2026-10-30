import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.hud
import qs.singletons

// Generic full-screen overlay for transient HUD components (toasts, OSD, etc.).
// Transparent and click-through everywhere except active HUD cards.
PanelWindow {
    id: hud
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
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
    // as tall as the visible toasts, so it covers nothing while there are none.
    mask: Region {
        Region { item: toastArea }
        Region { item: queueBadge }
        Region { item: volumeOsd }
        Region { item: shellNotifItem }
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

        opacity: Notifications.hudQueue.length > 0 ? 1.0 : 0.0
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
