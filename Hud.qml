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

    // The whole screen, over the bar's reserved space too: kept out of it, the window would
    // start below a top bar (or right of a left one) and hang past the screen's far edge by
    // as much. Everything it shows keeps clear of the bar, at any edge (_barInsets).
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        left: true
    }
    implicitWidth: hud.screen.width
    implicitHeight: hud.screen.height
    margins { top: 0; left: 0 }
    color: "transparent"

    // The bar's reserved space at each screen edge, in this window
    readonly property var _barInsets: BarGeometry.reservedInsets(BarLayout.edge, Theme.bar.reservedSpace)

    // Input passthrough: only forward clicks to visible HUD card areas. The toast area is
    // as tall as the visible toasts, so it covers nothing while there are none. A Region
    // takes its item's geometry whether the item is shown or not: the OSDs hide by moving
    // off screen; the startup warnings are in the mask only while one is shown (maskItem).
    // The modals (toasts dragged out or pinned) stand anywhere on the screen: each adds its
    // own rectangle, following it as it moves; the set changes as modals come and go.
    mask: Region {
        Region { item: toastArea }
        Region { regions: modalRegions.instances }
        Region { item: volumeOsd }
        Region { item: shellNotifItem }
        Region { item: startupWarnings.maskItem }
    }

    // ---- Startup warnings ----
    // Banners under the bar, centred, about how the shell was started or set up
    StartupWarnings {
        id: startupWarnings
        x: (hud.implicitWidth - width) / 2
        y: hud._barInsets.top + Theme.osdToast.screenGap
        width: Math.min(640, hud.implicitWidth - 2 * Theme.osdToast.screenGap)
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
    // queue's badge beside its lowest toast (ToastStack, Toasts' queues)
    ToastStack {
        id: toastStack
        y: hud._barInsets.top + Theme.osdToast.screenGap
        width: hud.implicitWidth
        height: contentHeight
        screenWidth: hud.implicitWidth
        screenHeight: hud.implicitHeight
        barInsets: hud._barInsets
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
    // this screen, in the window's logical pixels (the window covers the whole screen),
    // whether it is a modal, can be dragged and has stopped moving — "{}" when it has
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

        // A queue's badge ("critical", "staying", "ordinary") on this screen: its rectangle
        // the same way, and whether it shows — "{}" when it is not shown
        function badgeRect(queue: string): string {
            const badge = toastStack.badgeFor(queue);
            if (!badge || !badge.visible)
                return "{}";
            const topLeft = badge.mapToItem(null, 0, 0);
            return JSON.stringify({ x: Math.round(topLeft.x), y: Math.round(topLeft.y), width: Math.round(badge.width),
                                    height: Math.round(badge.height), settled: badge.settled });
        }

        // The open notification centre's place (Toasts.centreArea): { screen, x, y,
        // width, height } on its screen, "{}" while it is closed; with the toasts' column's
        // right edge on this screen (stackRight) and whether it stands free of the screen's edge
        function centreArea(): string {
            const area = Toasts.centreArea;
            return JSON.stringify(Object.assign({}, area ?? {}, { stackRight: toastStack.rightEdge, free: toastStack.free }));
        }

        // The shell's own message (the pill at the bottom): its rectangle, the same way, and
        // whether it rests on screen showing one
        function shellPillRect(): string {
            const topLeft = shellNotifItem.mapToItem(null, 0, 0);
            return JSON.stringify({ x: Math.round(topLeft.x), y: Math.round(topLeft.y), width: Math.round(shellNotifItem.width),
                                    height: Math.round(shellNotifItem.height),
                                    resting: shellNotifItem.currentNotif !== null && shellNotifItem.y === shellNotifItem.restY });
        }
    }

    // Where the toasts are, for the input mask: the toasts' strip at the right edge — or
    // left of the open centre, so the centre's own clicks stay its — as tall as the visible
    // toasts and badges
    Item {
        id: toastArea
        objectName: "toastArea"
        x: toastStack.rightEdge - width
        y: toastStack.y
        width: toastStack.reach
        height: toastStack.contentHeight
    }

    VolumeOsdItem {
        id: volumeOsd
        screenWidth: hud.implicitWidth
        screenHeight: hud.implicitHeight
        rightInset: hud._barInsets.right
    }

    ShellNotificationHudItem {
        id: shellNotifItem
        screenWidth: hud.implicitWidth
        screenHeight: hud.implicitHeight
        bottomInset: hud._barInsets.bottom
        screenModelData: hud.modelData
    }
}
