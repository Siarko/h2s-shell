import QtQuick
import qs.components
import QtQuick.Layouts
import Quickshell
import qs.singletons

// Custom QML renderer for DBus tray menus, with submenu drill-down navigation.
Item {
    id: root

    signal closeRequested

    implicitWidth: Theme.popupWidth("tray", 220)
    // Track whichever slot is incoming so height follows new content immediately
    implicitHeight: activeSlot === 0 ? slot0.implicitHeight : slot1.implicitHeight
    clip: true

    // The menu to show and the way it slides in: { menu, direction } (1 from the right,
    // -1 from the left), from the tray icon that was clicked. A new object for every
    // click, so another icon's menu, opened over this one, slides in.
    property var request: null
    // Only once built: the first menu is shown by Component.onCompleted, and the request
    // set while building must not start a second transition. Nor for no request: the
    // popup switching to another panel clears it, and this menu stays on screen until
    // the new panel replaces it.
    onRequestChanged: if (_built && request) changeMenu()
    property bool _built: false

    property var menuStack: []

    // Which slot is currently the "active" (fully visible) one.
    // 0 → slot0/opener0 is showing, 1 → slot1/opener1 is showing.
    property int activeSlot: 0

    // A menu opening fresh (no popup open, or another panel's) is shown in place: the
    // popup brings it in from the bar, as it does every panel. Only a switch from another
    // icon's menu slides sideways (onRequestChanged).
    Component.onCompleted: {
        anchorOpener.menu = root.request?.menu ?? null;
        opener0.menu = root.request?.menu ?? null;
        _built = true;
    }

    function changeMenu() {
        root.menuStack = [];
        anchorOpener.menu = root.request?.menu ?? null;
        const next = root.activeSlot === 0 ? opener1 : opener0;
        next.menu = root.request?.menu ?? null;
        // Between the tray's icons: the way they run — down a bar at a side
        root.beginTransition(root.request?.direction ?? 1, BarLayout.vertical);
    }

    // Navigate into a submenu entry.
    function navigateToSubmenu(entry) {
        const curr = root.activeSlot === 0 ? opener0 : opener1;
        const next = root.activeSlot === 0 ? opener1 : opener0;
        root.menuStack = root.menuStack.concat([curr.menu]);
        next.menu = entry;
        root.beginTransition(1, false);
    }

    // Navigate back to the previous menu level.
    function navigateBack() {
        const next = root.activeSlot === 0 ? opener1 : opener0;
        next.menu = root.menuStack[root.menuStack.length - 1];
        root.menuStack = root.menuStack.slice(0, root.menuStack.length - 1);
        root.beginTransition(-1, false);
    }

    // direction: +1 = the new menu comes in from the right (from below, `vertical`), -1 =
    // from the left (from above). Sideways into and out of submenus; down or up between
    // the icons of a tray running down a bar at a side.
    function beginTransition(direction, vertical) {
        root._direction = direction;
        root._verticalSlide = vertical;
        // Switch activeSlot so implicitHeight immediately tracks new content
        root.activeSlot = 1 - root.activeSlot;
        _slide.stop();
        root._progress = 1;
        _slide.start();
    }

    // The slide: 1 as it starts, 0 at rest. The menus' places follow from it and from the
    // distance, worked out as they go — a new menu has no height until its entries arrive,
    // a frame or more after it is asked for, and a distance taken at the start left a taller
    // one sliding in already mostly in sight.
    property real _progress: 0
    property int _direction: 1
    property bool _verticalSlide: false
    // Far enough for the taller of the two menus (or the menu's width) to be out of sight
    readonly property real _distance: _verticalSlide ? Math.max(slot0.height, slot1.height) : root.implicitWidth
    // Where a slot is along the slide: the shown one coming in, the other going out
    function _offset(slotIndex) {
        return slotIndex === root.activeSlot ? root._direction * root._distance * root._progress
            : -root._direction * root._distance * (1 - root._progress);
    }

    NumberAnimation {
        id: _slide
        target: root
        property: "_progress"
        to: 0
        duration: Theme.duration("slide")
        easing: Theme.curve("slide")
    }

    // Holds a permanent ref to the root handle so its refcount never hits zero
    // while navigating submenus (unrefing the root destroys all its DBusMenuItems).
    QsMenuOpener {
        id: anchorOpener
    }

    QsMenuOpener {
        id: opener0
    }
    QsMenuOpener {
        id: opener1
    }

    // Shared item delegate — defined once, used by both Repeaters
    Component {
        id: menuDelegate

        Item {
            required property var modelData
            width: parent.width
            height: modelData.isSeparator ? 9 : 32

            // Separator line
            Rectangle {
                visible: modelData.isSeparator
                x: 8
                width: parent.width - 16
                height: 1
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.textDisabled
                opacity: 0.25
            }

            // Regular menu item
            Rectangle {
                visible: !modelData.isSeparator
                anchors.fill: parent
                anchors.margins: 2
                radius: Theme.listItem.radius
                color: itemArea.lit && modelData.enabled ? Theme.surfaceHover : Theme.surfaceHoverClear
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    // Checkbox / radio indicator
                    Text {
                        visible: modelData.buttonType !== QsMenuButtonType.None
                        text: {
                            if (modelData.buttonType === QsMenuButtonType.CheckBox)
                                return modelData.checkState === Qt.Checked ? "✓" : "";
                            if (modelData.buttonType === QsMenuButtonType.RadioButton)
                                return modelData.checkState === Qt.Checked ? "●" : "○";
                            return "";
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                        width: 14
                    }

                    // App-supplied icon
                    Image {
                        visible: modelData.icon !== ""
                        source: modelData.icon
                        width: 16
                        height: 16
                        sourceSize: Qt.size(16, 16)
                    }

                    // Label
                    Text {
                        text: modelData.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBodyLarge
                        color: modelData.enabled ? Theme.textPrimary : Theme.textDisabled
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    // Submenu arrow
                    Text {
                        visible: modelData.hasChildren
                        text: "›"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.textDisabled
                    }
                }

                PointerArea {
                    id: itemArea
                    centred: false
                    anchors.fill: parent
                    enabled: modelData.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.hasChildren) {
                            root.navigateToSubmenu(modelData);
                        } else {
                            const entry = modelData;
                            entry.triggered();
                            root.closeRequested();
                        }
                    }
                }
            }
        }
    }

    // Menu slot template — instantiated twice (slot0/slot1) for slide transitions.
    // `opener` is set from the Loader's onLoaded handler.
    Component {
        id: menuSlotComponent

        Column {
            property var opener: null
            width: root.width
            spacing: 0

            // Back button — visible when inside a submenu
            Item {
                visible: root.menuStack.length > 0
                width: parent.width
                height: 30

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Theme.listItem.radius
                    color: backArea.lit ? Theme.surfaceHover : Theme.surfaceHoverClear
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4

                        Text {
                            text: "‹"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSection
                            color: Theme.textSecondary
                        }
                        Text {
                            text: "Back"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBodyLarge
                            color: Theme.textSecondary
                            Layout.fillWidth: true
                        }
                    }

                    PointerArea {
                        id: backArea
                        centred: false
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.navigateBack()
                    }
                }
            }

            // Separator below back button
            Item {
                visible: root.menuStack.length > 0
                width: parent.width
                height: 9

                Rectangle {
                    x: 8
                    width: parent.width - 16
                    height: 1
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.textDisabled
                    opacity: 0.2
                }
            }

            Repeater {
                model: opener ? opener.children : null
                delegate: menuDelegate
            }
        }
    }

    // Slot 0
    Loader {
        id: slot0
        sourceComponent: menuSlotComponent
        width: root.width
        x: root._verticalSlide ? 0 : root._offset(0)
        y: root._verticalSlide ? root._offset(0) : 0
        onLoaded: item.opener = opener0
    }

    // Slot 1
    Loader {
        id: slot1
        sourceComponent: menuSlotComponent
        width: root.width
        x: root._verticalSlide ? 0 : root._offset(1)
        y: root._verticalSlide ? root._offset(1) : 0
        onLoaded: item.opener = opener1
    }
}
