import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.components
import qs.panels
import qs.singletons

// The bar along one screen edge (the bar.edge setting, docs/plans/bar-position.md):
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
    onNotifPanelOpenChanged: Notifications.setHudPanelOpen(notifPanelOpen)

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
    // The preset binding must read through the delegate, not a captured modelData: the
    // section is built before the config has loaded, and ScriptModel then updates the
    // existing delegate's modelData in place rather than recreating it. A captured object
    // keeps the empty profile from that first pass.
    function _wireWidget(item, delegate) {
        if (typeof item.popup !== "undefined")
            item.popup = popupLoader
        if (typeof item.preset !== "undefined")
            item.preset = Qt.binding(() => delegate.modelData.preset)
        if (delegate.modelData.type === "notifications")
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
        required property var modelData
        readonly property bool leaving: modelData.leaving ?? false
        // 0 to 1 as it grows in, back to 0 as it goes; drawn at full size meanwhile and
        // clipped, so its content does not squeeze
        property real _shown: bar._contentAnimated ? 0 : 1
        Component.onCompleted: _shown = Qt.binding(() => leaving ? 0 : 1)
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
        source: WidgetRegistry.widgetUrl(modelData.type)
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

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    // in docs/ARCHITECTURE.md
                    model: ScriptModel {
                        objectProp: "key"
                        values: bar._leftShown
                    }
                    delegate: SectionWidget {}
                }
            }

            // Center section
            WidgetSection {
                anchors.centerIn: parent

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    // in docs/ARCHITECTURE.md
                    model: ScriptModel {
                        objectProp: "key"
                        values: bar._centerShown
                    }
                    delegate: SectionWidget {}
                }
            }

            // Right section, at the end
            WidgetSection {
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    // in docs/ARCHITECTURE.md
                    model: ScriptModel {
                        objectProp: "key"
                        values: bar._rightShown
                    }
                    delegate: SectionWidget {}
                }
            }
        }
    }

    Connections {
        target: Notifications
        function onOpenPanelRequested() {
            if (notifWidget && (!popupLoader.active || popupLoader.contentType !== "notifications")) {
                popupLoader.open(notifWidget, true, "notifications");
            }
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
