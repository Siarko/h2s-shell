import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.components
import qs.panels
import qs.singletons

// Top-anchored horizontal bar spanning the full screen width
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
        top: true
        left: true
        right: true
    }
    color: "transparent"

    implicitHeight: bar._layout("reservedSpace")

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

    // Geometry, from the active profile
    function _layout(name) {
        return Profiles.value("bar.layout." + name) ?? 0
    }

    // Visual bar rectangle — floats within the reserved space
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: bar._layout("topOffset")
            leftMargin: bar._layout("leftMargin")
            rightMargin: bar._layout("rightMargin")
        }
        height: bar._layout("barHeight")
        color: Theme.barBackground
        topLeftRadius: bar._layout("radiusTopLeft") / 100 * (bar._layout("barHeight") / 2)
        topRightRadius: bar._layout("radiusTopRight") / 100 * (bar._layout("barHeight") / 2)
        bottomLeftRadius: bar._layout("radiusBottomLeft") / 100 * (bar._layout("barHeight") / 2)
        bottomRightRadius: bar._layout("radiusBottomRight") / 100 * (bar._layout("barHeight") / 2)

        // Three-section bar layout: left-aligned, centered, right-aligned
        Item {
            anchors.fill: parent
            anchors.leftMargin: bar._layout("leftPadding")
            anchors.rightMargin: bar._layout("rightPadding")

            // Left section
            RowLayout {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 5

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    // in docs/ARCHITECTURE.md
                    model: ScriptModel {
                        objectProp: "key"
                        values: bar._leftModel
                    }
                    delegate: Loader {
                        id: widgetLoader
                        required property var modelData
                        Layout.fillHeight: true
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        source: WidgetRegistry.widgetUrl(modelData.type)
                        onLoaded: bar._wireWidget(item, widgetLoader)
                    }
                }
            }

            // Center section
            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    // in docs/ARCHITECTURE.md
                    model: ScriptModel {
                        objectProp: "key"
                        values: bar._centerModel
                    }
                    delegate: Loader {
                        id: widgetLoader
                        required property var modelData
                        Layout.fillHeight: true
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        source: WidgetRegistry.widgetUrl(modelData.type)
                        onLoaded: bar._wireWidget(item, widgetLoader)
                    }
                }
            }

            // Right section
            RowLayout {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 5

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    // in docs/ARCHITECTURE.md
                    model: ScriptModel {
                        objectProp: "key"
                        values: bar._rightModel
                    }
                    delegate: Loader {
                        id: widgetLoader
                        required property var modelData
                        Layout.fillHeight: true
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        source: WidgetRegistry.widgetUrl(modelData.type)
                        onLoaded: bar._wireWidget(item, widgetLoader)
                    }
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

    // Popup panel that appears below the hovered cell
    Popup {
        id: popupLoader
        popupPosition: 0
        popupWidth: 0
        // Notify parent so other screens close their popups
        onOpened: bar.popupOpened()
    }
}
