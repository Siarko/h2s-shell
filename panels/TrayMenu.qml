import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// Custom QML renderer for DBus tray menus, with submenu drill-down navigation.
Item {
    id: root

    required property var menuHandle
    signal closeRequested

    implicitWidth: 220
    implicitHeight: col.implicitHeight

    // Stack of previous menu values for back-navigation
    property var menuStack: []

    // Reset state whenever a new top-level menu is opened
    onMenuHandleChanged: {
        root.menuStack = [];
        // anchorOpener keeps the root handle's refcount ≥ 1 at all times so that
        // navigating away (which unrefs it from opener) never drops it to zero.
        // If refcount hits 0, DBusMenuHandle destroys the menu and all its
        // DBusMenuItem children — including the entry we just navigated into.
        anchorOpener.menu = menuHandle;
        opener.menu = menuHandle;
    }

    // Navigate into a submenu entry.
    // Lives on root (not inside a delegate) so opener is always in scope even
    // after the Repeater destroys the delegate when opener.children changes.
    function navigateToSubmenu(entry) {
        root.menuStack = root.menuStack.concat([opener.menu]);
        opener.menu = entry;
    }

    // Holds a permanent ref to the root handle so its refcount never drops to
    // zero while the user is navigating submenus.
    QsMenuOpener {
        id: anchorOpener
    }

    QsMenuOpener {
        id: opener
    }

    Column {
        id: col
        width: parent.width
        spacing: 0

        // Back button — only visible when inside a submenu
        Item {
            visible: root.menuStack.length > 0
            width: col.width
            height: 30

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 4
                color: backArea.containsMouse ? Theme.buttonHover : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 4

                    Text {
                        text: "‹"
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        color: Theme.textSecondary
                    }

                    Text {
                        text: "Back"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.textSecondary
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        opener.menu = root.menuStack[root.menuStack.length - 1];
                        root.menuStack = root.menuStack.slice(0, root.menuStack.length - 1);
                    }
                }
            }
        }

        // Divider below back button
        Item {
            visible: root.menuStack.length > 0
            width: col.width
            height: 9

            Rectangle {
                x: 8
                width: col.width - 16
                height: 1
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.textDim
                opacity: 0.2
            }
        }

        Repeater {
            model: opener.children

            delegate: Item {
                required property var modelData
                width: col.width
                height: modelData.isSeparator ? 9 : 32

                // Separator line
                Rectangle {
                    visible: modelData.isSeparator
                    x: 8
                    width: col.width - 16
                    height: 1
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.textDim
                    opacity: 0.25
                }

                // Regular menu item
                Rectangle {
                    visible: !modelData.isSeparator
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 4
                    color: itemArea.containsMouse && modelData.enabled ? Theme.buttonHover : "transparent"

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
                            font.pixelSize: 12
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
                            font.pixelSize: 13
                            color: modelData.enabled ? Theme.textPrimary : Theme.textDim
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        // Submenu arrow
                        Text {
                            visible: modelData.hasChildren
                            text: "›"
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: Theme.textDim
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
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
    }
}
