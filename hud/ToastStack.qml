import QtQuick
import qs.components
import qs.singletons

// The toasts of one screen: three stacks top to bottom — critical, staying, ordinary, each
// newest first, a wider gap between two queues (ToastRules.onScreen) — and each queue's badge
// "+N" beside its lowest toast, counting what waits there (the critical one with the critical
// outline, ToastRules.badgeLook). One toast per notification on screen, keyed by its id, made
// when it shows and destroyed after it slid out; a toast that leaves is kept until then.
// On the toasts' screen (Notifications.toastScreen) the stack takes what fits whenever the
// queues change (Notifications.fillToasts).
Item {
    id: root

    required property int screenWidth
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
            if (toast && toast.visible)
                bottom = Math.max(bottom, toast.y + toast.height);
        }
        for (const badge of [criticalBadge, stayingBadge, ordinaryBadge]) {
            if (badge.visible)
                bottom = Math.max(bottom, badge.y + badge.height);
        }
        return bottom;
    }

    readonly property bool _toastScreen: screenName !== "" && Notifications.toastScreen === screenName
    // The toasts in their queues on this screen, top to bottom: [{ id, queue }]
    readonly property var stack: ToastRules.onScreen(Notifications.toastState, false).stack
        .filter(entry => Notifications.toastScreens[entry.id] === screenName)
    readonly property var _presentKeys: stack.map(entry => String(entry.id))
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
        function onHudPanelOpenChanged() { root.fill(); }
    }
    Component.onCompleted: fill()

    Repeater {
        id: toastRepeater
        model: toastKeys.model

        NotificationHudItem {
            id: toast
            required property string modelData
            screenWidth: root.screenWidth
            screenModelData: root.screenModelData
            toastId: Number(modelData)
            present: root._presentKeys.includes(modelData)
            restX: root.restX
            stackY: root.layout.places[toastId] ?? null
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
