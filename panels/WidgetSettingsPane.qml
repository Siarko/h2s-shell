import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.panels.widget_settings

Item {
    id: root

    property string widgetType: ""
    property string currentProfile: ""

    signal profileAssigned(string newProfileName)

    implicitHeight: _col.implicitHeight + 12

    readonly property var _knownProfiles: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data[widgetType] ? Object.keys(data[widgetType]) : []
    }

    readonly property var _settingsComponentMap: ({
        "workspaces": _workspacesComp,
        "clock": _clockComp
    })

    Component { id: _workspacesComp; WorkspacesWidgetSettings {} }
    Component { id: _clockComp; ClockWidgetSettings {} }

    Column {
        id: _col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: 6
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 4

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.3)
        }

        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: "Profile"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                Layout.preferredWidth: 60
            }

            Rectangle {
                Layout.fillWidth: true
                height: 26
                radius: 6
                color: Theme.cellDefault

                TextInput {
                    id: _profileInput
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    text: root.currentProfile
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    onEditingFinished: {
                        var name = text.trim()
                        if (name !== root.currentProfile)
                            root.profileAssigned(name)
                    }
                    onActiveFocusChanged: if (!activeFocus) text = root.currentProfile
                }
            }

            Rectangle {
                visible: root.currentProfile !== ""
                width: 20
                height: 20
                radius: 4
                color: _clearHover.containsMouse ? Theme.cellHover : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.textDim
                }

                MouseArea {
                    id: _clearHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.profileAssigned("")
                }
            }
        }

        // Inline autocomplete suggestions — part of the column layout to avoid clipping issues
        Column {
            id: _suggestionsList
            width: parent.width
            visible: _profileInput.activeFocus && _suggestionsRepeater.count > 0

            readonly property var _filteredProfiles: root._knownProfiles.filter(p =>
                p.toLowerCase().startsWith(_profileInput.text.toLowerCase())
                && p !== _profileInput.text)

            Repeater {
                id: _suggestionsRepeater
                model: _suggestionsList._filteredProfiles

                Item {
                    required property string modelData
                    width: _suggestionsList.width
                    height: 24

                    Rectangle {
                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                        radius: 4
                        color: _suggHover.containsMouse ? Theme.cellHover : "transparent"
                    }

                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                        text: modelData
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                    }

                    MouseArea {
                        id: _suggHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Use onPressed (fires before focus transfer) so the suggestion
                        // list doesn't disappear before the selection is processed
                        onPressed: {
                            _profileInput.text = modelData
                            root.profileAssigned(modelData)
                            _profileInput.focus = false
                        }
                    }
                }
            }
        }

        Loader {
            id: _specificLoader
            width: parent.width
            height: item ? item.implicitHeight : 0
            visible: root.currentProfile !== ""
            sourceComponent: visible ? (root._settingsComponentMap[root.widgetType] ?? null) : null
            onLoaded: {
                item.profileName = Qt.binding(() => root.currentProfile)
                item.widgetType  = Qt.binding(() => root.widgetType)
            }
        }
    }
}
