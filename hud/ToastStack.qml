import QtQuick
import qs.components
import qs.singletons

// The toasts of one screen: three stacks top to bottom — critical, staying, ordinary, each
// newest first, a wider gap between two queues (ToastRules.onScreen) — and each queue's badge
// "+N" beside its lowest toast, counting what waits there (the critical one with the critical
// outline, ToastRules.badgeLook). One toast per notification on screen, keyed by its id, made
// when it shows and destroyed after it slid out; a toast that leaves is kept until then.
// On the toasts' screen (Notifications.criticalToastScreen) the stack takes what fits whenever the
// queues change (Notifications.fillToasts).
// Modals — toasts dragged out of their queue, notifications pinned from the centre — are the
// same toasts, out of the stack at their own place on this screen (ToastRules.onScreen's
// modals); a pinned one is given its first place here (ToastRules.pinSpot). Hud adds each
// modal's rectangle to its window's input mask (`modalToasts`).
Item {
    id: root

    required property int screenWidth
    property int screenHeight: 0
    // The part of this window on the screen, where a dropped or pinned toast is kept
    property int dropWidth: screenWidth
    property int dropHeight: screenHeight
    required property var screenModelData
    readonly property string screenName: screenModelData?.name ?? ""

    // A toast's reply wants the keyboard (Hud gives its window the keyboard)
    readonly property bool wantsKeyboard: {
        for (let i = 0; i < toastRepeater.count; i++) {
            if (toastRepeater.itemAt(i)?.wantsKeyboard)
                return true;
        }
        return false;
    }
    // Down to the lowest visible toast or badge, for the input mask
    readonly property real contentHeight: {
        let bottom = 0;
        for (let i = 0; i < toastRepeater.count; i++) {
            const toast = toastRepeater.itemAt(i);
            if (toast && toast.visible && !toast.modal && !toast.dragging)
                bottom = Math.max(bottom, toast.y + toast.height);
        }
        for (const badge of [criticalBadge, stayingBadge, ordinaryBadge]) {
            if (badge.visible)
                bottom = Math.max(bottom, badge.y + badge.height);
        }
        return bottom;
    }

    // The screen toasts go to — the critical ones' screen, which is the others' too unless a
    // fullscreen window hides all but the critical ones there
    readonly property bool _toastScreen: screenName !== "" && Notifications.criticalToastScreen === screenName
    // The toasts in their queues on this screen, top to bottom: [{ id, queue }]
    readonly property var _onScreen: ToastRules.onScreen(Notifications.toastState, Notifications.fullscreenHidden)
    readonly property var stack: _onScreen.stack.filter(entry => Notifications.toastScreens[entry.id] === screenName)
    // The modals on this screen: [{ id, queue, x, y }], x and y in the window (null: not
    // placed yet)
    readonly property var modals: _onScreen.modals.filter(entry => Notifications.toastScreens[entry.id] === screenName)
    readonly property var _presentKeys: stack.map(entry => String(entry.id)).concat(modals.map(entry => String(entry.id)))
    // Where each modal goes in the stack's own coordinates, by id; null: not placed yet
    readonly property var modalPlaces: {
        const places = {};
        for (const entry of modals)
            places[entry.id] = entry.x === null || entry.y === null ? null : { x: entry.x, y: entry.y - root.y };
        return places;
    }
    // The modals' toasts on screen, for the window's input mask: a toast made or let go
    // changes the list (_itemsChanged)
    property int _itemsChanged: 0
    readonly property var modalToasts: {
        _itemsChanged;
        const toasts = [];
        for (const entry of modals) {
            const toast = toastFor(entry.id);
            if (toast !== null)
                toasts.push(toast);
        }
        return toasts;
    }

    // A pinned modal not placed yet gets its first place beside the toasts' column
    // (ToastRules.pinSpot): after the change that pinned it, when its toast exists
    onModalsChanged: {
        if (modals.some(entry => entry.x === null || entry.y === null))
            Qt.callLater(root._placeModals);
    }
    function _placeModals() {
        for (const entry of modals) {
            if (entry.x !== null && entry.y !== null)
                continue;
            const spot = ToastRules.pinSpot({
                modals: ToastRules.onScreen(Notifications.toastState).modals
                    .filter(other => Notifications.toastScreens[other.id] === screenName),
                width: Theme.osdToast.width,
                height: toastFor(entry.id)?.height ?? 0,
                screenWidth: dropWidth,
                screenHeight: dropHeight,
                column: screenWidth - Theme.osdToast.width - Theme.osdToast.badgeWidth - 8,
                top: root.y,
                gap: Theme.osdToast.screenGap
            });
            Notifications.placeModal(entry.id, spot.x, spot.y);
        }
    }
    // Toasts sliding out, by key: kept until they finish
    property var _leaving: []
    property var _shownBefore: []
    on_PresentKeysChanged: {
        const leaving = _leaving.concat(_shownBefore).filter((key, index, all) => !_presentKeys.includes(key) && all.indexOf(key) === index);
        _shownBefore = _presentKeys;
        _leaving = leaving;
    }

    function _left(key) {
        if (_leaving.includes(key))
            _leaving = _leaving.filter(leaving => leaving !== key);
    }

    KeyedModel {
        id: toastKeys
        values: root._presentKeys.concat(root._leaving.filter(key => !root._presentKeys.includes(key)))
    }

    // The waiting counts, on the toasts' screen only
    readonly property var _badges: _toastScreen ? Notifications.toastBadges : ({ critical: 0, staying: 0, ordinary: 0 })
    readonly property bool _anyBadge: _badges.critical > 0 || _badges.staying > 0 || _badges.ordinary > 0
    readonly property real restX: screenWidth - Theme.osdToast.width
        - (_anyBadge ? Theme.osdToast.badgeWidth + 8 : Theme.osdToast.screenGap)

    // The toast of notification `id`, or null
    function toastFor(id) {
        for (let i = 0; i < toastRepeater.count; i++) {
            const toast = toastRepeater.itemAt(i);
            if (toast && toast.toastId === id)
                return toast;
        }
        return null;
    }

    // Where each toast on screen goes and where each queue's badge sits: { places: { id: y },
    // badges: { queue: { y, height } } }. A queue that waits with nothing of it shown has its
    // badge below the stack.
    readonly property var layout: {
        const places = {};
        const badges = {};
        const spacing = Theme.osdToast.spacing;
        let y = 0;
        let previous = "";
        for (const entry of stack) {
            if (previous !== "" && entry.queue !== previous)
                y += spacing;
            const height = toastFor(entry.id)?.height ?? 0;
            places[entry.id] = y;
            badges[entry.queue] = { y: y, height: height };
            y += height + spacing;
            previous = entry.queue;
        }
        for (const queue of ToastRules.queues) {
            if (badges[queue] === undefined && _badges[queue] > 0) {
                if (previous !== "")
                    y += spacing;
                badges[queue] = { y: y, height: 36 };
                y += 36 + spacing;
                previous = queue;
            }
        }
        return { places: places, badges: badges };
    }

    // On the toasts' screen: what fits shows. Taking one changes the queues, which asks
    // again: that inner ask finds the queues being filled already.
    property bool _filling: false
    function fill() {
        if (!_toastScreen || _filling)
            return;
        _filling = true;
        try {
            Notifications.fillToasts(screenName);
        } finally {
            _filling = false;
        }
    }

    Connections {
        target: Notifications
        function onRoomForToasts() { root.fill(); }
        function onToastScreenChanged() { root.fill(); }
        function onCriticalToastScreenChanged() { root.fill(); }
        function onHudPanelOpenChanged() { root.fill(); }
    }
    Component.onCompleted: fill()

    Repeater {
        id: toastRepeater
        model: toastKeys.model

        onItemAdded: root._itemsChanged++
        onItemRemoved: root._itemsChanged++

        NotificationHudItem {
            id: toast
            required property string modelData
            screenWidth: root.screenWidth
            dropWidth: root.dropWidth
            dropHeight: root.dropHeight
            screenModelData: root.screenModelData
            toastId: Number(modelData)
            present: root._presentKeys.includes(modelData)
            restX: root.restX
            stackY: root.layout.places[toastId] ?? null
            originY: root.y
            modal: root.modalPlaces[toastId] !== undefined
            modalPlace: root.modalPlaces[toastId] ?? null
            onSlidOut: root._left(modelData)
        }
    }

    component QueueBadge: Rectangle {
        id: badge
        required property string queue
        readonly property int waiting: root._badges[queue] ?? 0
        readonly property var look: ToastRules.badgeLook(queue, waiting)
        readonly property var beside: root.layout.badges[queue] ?? null
        readonly property bool critical: look.border === "error"
        objectName: queue + "Badge"
        x: root.screenWidth - width
        y: beside?.y ?? 0
        width: Theme.osdToast.badgeWidth
        // As tall as the toast beside it; a sensible size without one
        height: Math.max(36, beside?.height ?? 36)
        // Shares the toast's rounding
        topLeftRadius: Theme.osdToast.radius
        bottomLeftRadius: Theme.osdToast.radius
        color: Theme.surface
        border.width: critical ? Math.max(Theme.osdToast.borderWidth, Theme.border.selectedWidth) : Theme.osdToast.borderWidth
        border.color: critical ? Theme.error : Theme.osdToastBorder
        opacity: look.shown && beside !== null ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
        // Moves with its toast; one coming into view appears in place
        Behavior on y {
            enabled: badge.visible
            NumberAnimation { duration: Theme.duration("move"); easing: Theme.curve("move") }
        }

        Text {
            anchors.centerIn: parent
            text: badge.look.label
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            font.bold: true
            color: badge.critical ? Theme.error : Theme.textPrimary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifications.openPanelRequested()
        }
    }

    QueueBadge { id: criticalBadge; queue: "critical" }
    QueueBadge { id: stayingBadge; queue: "staying" }
    QueueBadge { id: ordinaryBadge; queue: "ordinary" }
}
