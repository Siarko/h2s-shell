import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.components
import qs.panels
import qs.singletons

// The bar along one screen edge (the bar.edge setting, notes/plans/bar-position.md):
// across the top or bottom, or down a side, its widgets then stacked down it
PanelWindow {
    id: bar
    required property var modelData
    property var activeScreen: null
    signal popupOpened

    screen: modelData

    // Tracks the loaded NotificationsWidget item for signal routing
    property var notifWidget: null

    // Exposed so Component definitions (which have their own id scope) can reference it

    // True when the notifications popup is the active panel — suppresses HUD toasts
    property bool notifPanelOpen: popupLoader.active && popupLoader.contentType === "notifications"
    onNotifPanelOpenChanged: Toasts.setHudPanelOpen(notifPanelOpen)

    // Close this screen's popup when another screen's popup opens
    onActiveScreenChanged: {
        if (activeScreen !== bar.modelData) {
            popupLoader.close();
        }
    }

    anchors {
        top: screenEdge !== "bottom"
        bottom: screenEdge !== "top"
        left: screenEdge !== "right"
        right: screenEdge !== "left"
    }
    color: "transparent"

    // Windows keep clear of the reserved space, which changes at once: animating it would
    // re-tile them every frame. The window itself is as tall as the bar needs meanwhile.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Theme.bar.reservedSpace
    // Across the bar: its height at the top or bottom, its width at a side
    readonly property int _thickness: Math.max(Theme.bar.reservedSpace, Math.ceil(_shape.topOffset + _shape.barHeight + Theme.bar.borderWidth))
    implicitHeight: _vertical ? 0 : _thickness
    implicitWidth: _vertical ? _thickness : 0

    // Widgets are loaded by URL from WidgetRegistry, so what used to be declared on each
    // Component is set here, only where the widget has the property.
    //
    // The preset binding must read through the delegate, not a captured entry: the section
    // is built before the config has loaded, and the delegate's `entry` then follows the new
    // entry under the same key rather than being recreated. A captured object keeps the
    // empty profile from that first pass.
    function _wireWidget(item, delegate) {
        if (typeof item.popup !== "undefined")
            item.popup = popupLoader
        if (typeof item.preset !== "undefined")
            item.preset = Qt.binding(() => delegate.entry.preset)
        if (delegate.entry.type === "notifications")
            bar.notifWidget = item
    }

    // Each section is a profile setting, [{ type, preset }]; the model entries carry a key
    // that only changes with the entry, so a profile change elsewhere keeps the widgets
    readonly property var _leftModel:   ProfileRules.sectionModel(Profiles.value("bar.left"))
    readonly property var _centerModel: ProfileRules.sectionModel(Profiles.value("bar.center"))
    readonly property var _rightModel:  ProfileRules.sectionModel(Profiles.value("bar.right"))

    // What each section shows: its model, plus the widgets that are going, kept while they
    // shrink away (ProfileRules.withLeaving). A widget that arrives grows in, so the ones
    // beside it slide aside rather than jump — but not while the bar is starting.
    // Not bound to the models: a binding could update before the handlers below run,
    // and the widgets going would be lost
    property var _leftShown: []
    property var _centerShown: []
    property var _rightShown: []
    Component.onCompleted: {
        _leftShown = _leftModel
        _centerShown = _centerModel
        _rightShown = _rightModel
    }
    on_LeftModelChanged: _leftShown = ProfileRules.withLeaving(_leftShown, _leftModel)
    on_CenterModelChanged: _centerShown = ProfileRules.withLeaving(_centerShown, _centerModel)
    on_RightModelChanged: _rightShown = ProfileRules.withLeaving(_rightShown, _rightModel)
    readonly property bool _anyLeaving: _leftShown.concat(_centerShown, _rightShown).some(entry => entry.leaving)
    on_AnyLeavingChanged: if (_anyLeaving) _dropLeaving.restart()

    Timer {
        id: _dropLeaving
        interval: Theme.duration("exit") + 50
        onTriggered: {
            bar._leftShown = bar._leftShown.filter(entry => !entry.leaving)
            bar._centerShown = bar._centerShown.filter(entry => !entry.leaving)
            bar._rightShown = bar._rightShown.filter(entry => !entry.leaving)
        }
    }

    property bool _contentAnimated: false
    Timer {
        interval: 3000
        running: true
        onTriggered: bar._contentAnimated = true
    }

    // One widget of a section, loaded by type
    component SectionWidget: Loader {
        id: widgetLoader
        // The entry's key, and the section's keyed entries it is looked up in: a widget
        // stays with its entry while others are added or dropped before it
        required property string modelData
        property var entries: null
        readonly property var entry: entries?.byKey[modelData] ?? ({})
        readonly property bool leaving: entry.leaving ?? false
        // 0 to 1 as it grows in, back to 0 as it goes; drawn at full size meanwhile and
        // clipped, so its content does not squeeze
        property real _shown: bar._contentAnimated ? 0 : 1
        Component.onCompleted: {
            _shown = Qt.binding(() => leaving ? 0 : 1)
            _load()
        }
        Behavior on _shown {
            NumberAnimation {
                duration: Theme.duration(widgetLoader.leaving ? "exit" : "enter")
                easing: Theme.curve(widgetLoader.leaving ? "exit" : "enter")
            }
        }
        // Along the bar it grows; across it, it fills the bar less the cell margins
        Layout.preferredWidth: !bar._vertical && _shown < 1 ? (item?.implicitWidth ?? 0) * _shown : -1
        Layout.preferredHeight: bar._vertical && _shown < 1 ? (item?.implicitHeight ?? 0) * _shown : -1
        // The section's spacing shrinks with it, so nothing jumps when it is dropped
        readonly property real _spacingTaken: _shown < 1 ? -(parent?.columnSpacing ?? 0) * (1 - _shown) : 0
        Layout.rightMargin: bar._vertical ? Theme.bar.cellVerticalMargin : _spacingTaken
        Layout.bottomMargin: bar._vertical ? _spacingTaken : Theme.bar.cellVerticalMargin
        Layout.topMargin: bar._vertical ? 0 : Theme.bar.cellVerticalMargin
        Layout.leftMargin: bar._vertical ? Theme.bar.cellVerticalMargin : 0
        clip: _shown < 1
        opacity: _shown
        Layout.fillHeight: !bar._vertical
        Layout.fillWidth: bar._vertical
        // By URL from WidgetRegistry; a module's widget gets its module's handle as `module`
        // before it completes. A type that is gone (its module turned off, uninstalled) leaves
        // the entry in its section and shows nothing; back, it shows again.
        readonly property string _url: WidgetRegistry.widgetUrl(entry.type ?? "")
        on_UrlChanged: _load()
        // The module's handle looked up here, not bound: a binding of its own may not have
        // caught up when the URL changes (Modules.initialProperties: {} for a core widget)
        function _load() {
            if (_url === "")
                source = ""
            else
                setSource(_url, Modules.initialProperties(_url))
        }
        onStatusChanged: {
            const owner = WidgetRegistry.moduleOf(entry.type)
            if (status === Loader.Error && owner !== "")
                Modules.reportError(owner, "widget " + entry.type + ": " + _url + " could not be loaded")
        }
        onLoaded: bar._wireWidget(item, widgetLoader)
    }

    // A section's widgets in a row along the bar, or a column down a bar at a side; as
    // thick as the bar, as long as its widgets. Sized, with fixed anchors, so nothing is
    // swapped when the bar turns.
    component WidgetSection: GridLayout {
        flow: bar._vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Theme.bar.widgetSpacing
        rowSpacing: Theme.bar.widgetSpacing
        width: bar._vertical ? parent.width : implicitWidth
        height: bar._vertical ? implicitHeight : parent.height
    }

    // Geometry, from the theme. Moving to another theme — a profile switch, say — slides
    // the bar into its new shape; editing the theme in use (the Bar page's sliders) applies
    // at once, so a slider does not lag behind the pointer.
    function _layout(name) {
        return name === "reservedSpace" ? Theme.bar.reservedSpace : _shape[name]
    }

    property bool _sliding: false

    Connections {
        target: Theme
        function onThemeNameChanged() {
            bar._sliding = true
            _slideEnd.restart()
        }
    }

    // The new theme's values arrive a moment after its name; this covers both
    Timer {
        id: _slideEnd
        interval: Theme.duration("slide") + 200
        onTriggered: bar._sliding = false
    }

    component SlideBehavior: Behavior {
        enabled: bar._sliding
        NumberAnimation { duration: Theme.duration("slide"); easing: Theme.curve("slide") }
    }

    Item {
        id: _shape
        visible: false
        property real barHeight: Theme.bar.barHeight
        property real topOffset: Theme.bar.topOffset
        property real leftMargin: Theme.bar.leftMargin
        property real rightMargin: Theme.bar.rightMargin
        property real leftPadding: Theme.bar.leftPadding
        property real rightPadding: Theme.bar.rightPadding
        property real radiusTopLeft: Theme.bar.radiusTopLeft
        property real radiusTopRight: Theme.bar.radiusTopRight
        property real radiusBottomLeft: Theme.bar.radiusBottomLeft
        property real radiusBottomRight: Theme.bar.radiusBottomRight
        SlideBehavior on barHeight {}
        SlideBehavior on topOffset {}
        SlideBehavior on leftMargin {}
        SlideBehavior on rightMargin {}
        SlideBehavior on leftPadding {}
        SlideBehavior on rightPadding {}
        SlideBehavior on radiusTopLeft {}
        SlideBehavior on radiusTopRight {}
        SlideBehavior on radiusBottomLeft {}
        SlideBehavior on radiusBottomRight {}
    }

    // The screen edge the bar stands at
    readonly property string screenEdge: BarLayout.edge
    readonly property bool _vertical: BarLayout.vertical
    // The corners on screen: the theme's are named for a bar at the top
    readonly property var _corners: BarGeometry.corners(screenEdge, {
        barHeight: _layout("barHeight"),
        radiusTopLeft: _layout("radiusTopLeft"), radiusTopRight: _layout("radiusTopRight"),
        radiusBottomLeft: _layout("radiusBottomLeft"), radiusBottomRight: _layout("radiusBottomRight")
    })

    // The bar's shape on screen, placed in the bar's frame (BarGeometry), `grownBy` more
    // across it towards the desktop: the theme's top offset is the gap to the bar's own
    // edge, its left and right margins the gaps at its start and end — the top and bottom
    // of a bar at a side
    function _shapeRect(width, height, grownBy) {
        return BarGeometry.fromBarFrame(screenEdge, {
            along: _layout("leftMargin"),
            across: _layout("topOffset"),
            alongLength: (_vertical ? height : width) - _layout("leftMargin") - _layout("rightMargin"),
            acrossLength: _layout("barHeight") + grownBy
        }, width, height);
    }

    // The bar's border, outside it, along the edge facing the desktop only: a shape like
    // the bar's, grown by the border's width on that side, behind the bar. The bar keeps
    // its full height, and a popup, opening from the bar's edge in a window above, covers
    // the border where it joins the bar.
    readonly property real _borderWidth: Theme.bar.borderWidth
    Rectangle {
        visible: bar._borderWidth > 0
        readonly property var _placed: bar._shapeRect(parent.width, parent.height, bar._borderWidth)
        x: _placed.x
        y: _placed.y
        width: _placed.width
        height: _placed.height
        color: Theme.barBorder
        topLeftRadius: _barShape.topLeftRadius
        topRightRadius: _barShape.topRightRadius
        bottomLeftRadius: _barShape.bottomLeftRadius
        bottomRightRadius: _barShape.bottomRightRadius
    }

    // Visual bar rectangle — floats within the reserved space
    Rectangle {
        id: _barShape
        // Positioned, not anchored: anchors swapped as the bar turns left sizes behind
        readonly property var _placed: bar._shapeRect(parent.width, parent.height, 0)
        x: _placed.x
        y: _placed.y
        width: _placed.width
        height: _placed.height
        color: Theme.barBackground
        topLeftRadius: bar._corners.topLeft
        topRightRadius: bar._corners.topRight
        bottomLeftRadius: bar._corners.bottomLeft
        bottomRightRadius: bar._corners.bottomRight

        // Three sections: at the start, in the middle and at the end of the bar — left,
        // centre, right; top, middle, bottom at a side. The paddings are at its ends.
        Item {
            anchors.fill: parent
            anchors.leftMargin: bar._vertical ? 0 : bar._layout("leftPadding")
            anchors.rightMargin: bar._vertical ? 0 : bar._layout("rightPadding")
            anchors.topMargin: bar._vertical ? bar._layout("leftPadding") : 0
            anchors.bottomMargin: bar._vertical ? bar._layout("rightPadding") : 0

            // Left section, at the start
            WidgetSection {
                anchors.left: parent.left
                anchors.top: parent.top

                // Keyed by the entries' keys — "The Repeater crash" in docs/ARCHITECTURE.md
                KeyedModel { id: _leftEntries; values: bar._leftShown; keyProp: "key" }
                Repeater {
                    model: _leftEntries.model
                    delegate: SectionWidget { entries: _leftEntries }
                }
            }

            // Center section
            WidgetSection {
                anchors.centerIn: parent

                // Keyed by the entries' keys — "The Repeater crash" in docs/ARCHITECTURE.md
                KeyedModel { id: _centerEntries; values: bar._centerShown; keyProp: "key" }
                Repeater {
                    model: _centerEntries.model
                    delegate: SectionWidget { entries: _centerEntries }
                }
            }

            // Right section, at the end
            WidgetSection {
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                // Keyed by the entries' keys — "The Repeater crash" in docs/ARCHITECTURE.md
                KeyedModel { id: _rightEntries; values: bar._rightShown; keyProp: "key" }
                Repeater {
                    model: _rightEntries.model
                    delegate: SectionWidget { entries: _rightEntries }
                }
            }
        }
    }

    Connections {
        target: Notifications
        // A badge opens the centre on its own screen, or closes it there (ToastRules.badgeClick)
        function onOpenPanelRequested(screen) {
            const effect = ToastRules.badgeClick(screen, bar.modelData?.name ?? "",
                popupLoader.active && !popupLoader.closing && popupLoader.contentType === "notifications");
            if (effect === "close")
                popupLoader.close();
            else if (effect === "open" && notifWidget)
                popupLoader.open(notifWidget, true, "notifications");
        }
    }

    // Helpers for the shelltest IPC below (outside it: an IpcHandler offers every function)
    function _testFind(root, test) {
        if (!root)
            return null;
        for (const child of root.children) {
            if (test(child))
                return child;
            const found = _testFind(child, test);
            if (found)
                return found;
        }
        return null;
    }

    function _testRect(item, offset) {
        if (!item)
            return "{}";
        const topLeft = item.mapToItem(null, 0, 0);
        return JSON.stringify({ x: Math.round(topLeft.x + offset.x), y: Math.round(topLeft.y + offset.y),
                                width: Math.round(item.width), height: Math.round(item.height) });
    }

    // For tests driving the shell from outside (tests/device/): where things are on the
    // screen, in logical pixels, so a virtual touchscreen can tap them, and the popup's
    // state. The first screen's bar answers.
    //   qs ipc call shelltest cellRect clock
    //   qs ipc call shelltest popupItemRect calendarAdd
    //   qs ipc call shelltest popupState
    //   qs ipc call shelltest toastBadges
    //   qs ipc call shelltest notificationAction 7 cancel
    //   qs ipc call shelltest notificationDismiss 7
    //   qs ipc call shelltest toastDismiss 7
    IpcHandler {
        target: "shelltest"
        enabled: bar.modelData === Quickshell.screens[0]

        function cellRect(widgetType: string): string {
            const cell = bar._testFind(bar.contentItem, item => item.widgetType === widgetType && item.visible);
            const screenWidth = bar.modelData.width;
            const screenHeight = bar.modelData.height;
            const offset = bar.screenEdge === "bottom" ? Qt.point(0, screenHeight - bar.height)
                : bar.screenEdge === "right" ? Qt.point(screenWidth - bar.width, 0) : Qt.point(0, 0);
            return bar._testRect(cell, offset);
        }

        function popupItemRect(name: string): string {
            const window = popupLoader.item;
            if (!window)
                return "{}";
            return bar._testRect(bar._testFind(window.contentItem, item => item.objectName === name && item.visible), window._screenOffset);
        }

        // How many toasts wait in each queue, as the badges count them: { critical, staying,
        // ordinary }
        function toastBadges(): string {
            return JSON.stringify(Toasts.toastBadges);
        }

        // A notification's action run as its card runs it (Notifications.invokeAction), and
        // a notification dismissed as the centre dismisses it (tracked = false); "" when done,
        // else what was not found
        function notificationAction(id: int, action: string): string {
            const notification = Notifications.notifications.values.find(candidate => candidate.id === id);
            const found = notification?.actions.find(candidate => candidate.identifier === action);
            if (!found)
                return "not found";
            Notifications.invokeAction(notification, found);
            return "";
        }

        function notificationDismiss(id: int): string {
            const notification = Notifications.notifications.values.find(candidate => candidate.id === id);
            if (!notification)
                return "not found";
            notification.tracked = false;
            return "";
        }

        // "×" on a notification's toast, as its card's "×" does (Toasts.dismissToast);
        // "" when done, "not shown" when it has no toast on screen
        function toastDismiss(id: int): string {
            const place = Toasts.toastPlace(id).place;
            if (place !== "shown" && place !== "moved")
                return "not shown";
            Toasts.dismissToast(id);
            return "";
        }

        function popupState(): string {
            return JSON.stringify({ open: popupLoader.active && !popupLoader.closing, content: popupLoader.contentType,
                                    touchOpened: popupLoader.touchOpened, typing: popupLoader._typing });
        }
    }

    // Popup panel that opens from the bar, by the hovered cell
    Popup {
        id: popupLoader
        barEdge: bar.screenEdge
        barScreen: bar.modelData
        barWindow: bar
        popupPosition: 0
        popupLength: 0
        // Notify parent so other screens close their popups
        onOpened: bar.popupOpened()
    }
}
