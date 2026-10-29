import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    property string profileName: ""
    property string widgetType: "stt"

    implicitHeight: _col.implicitHeight

    // An absent key means "inherit the Dictation setting of the active shell profile"
    readonly property var _previewOverride: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data[widgetType]?.[profileName]?.previewEnabled
    }

    readonly property var _widthOverride: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data[widgetType]?.[profileName]?.previewWidth
    }

    readonly property string _previewMode: {
        if (_previewOverride === undefined) return "global"
        return _previewOverride ? "on" : "off"
    }

    // Passing undefined drops the key, restoring inheritance
    function _saveKey(key, value) {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        if (!data[widgetType])              data[widgetType] = {}
        if (!data[widgetType][profileName]) data[widgetType][profileName] = {}
        if (value === undefined)
            delete data[widgetType][profileName][key]
        else
            data[widgetType][profileName][key] = value
        Config.widgetProfiles = JSON.stringify(data)
    }

    function _savePreviewMode(mode) {
        if (mode === "global") _saveKey("previewEnabled", undefined)
        else                   _saveKey("previewEnabled", mode === "on")
    }

    Column {
        id: _col
        width: parent.width
        topPadding: 4
        spacing: 0

        // Preview row
        Item {
            width: _col.width
            height: 28

            RowLayout {
                anchors { fill: parent; rightMargin: 4 }
                spacing: 8

                Text {
                    text: "Preview"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.preferredWidth: 60
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 22
                    radius: 6
                    color: Theme.cellDefault
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            model: ["global", "on", "off"]

                            Rectangle {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: root._previewMode === modelData ? Theme.sliderAccent : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: ({ "global": "Inherit", "on": "On", "off": "Off" })[modelData]
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeBody
                                    color: root._previewMode === modelData ? Theme.textPrimary : Theme.textSecondary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root._savePreviewMode(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Width row — empty input inherits the global width
        Item {
            width: _col.width
            height: 28

            RowLayout {
                anchors { fill: parent; rightMargin: 4 }
                spacing: 8

                Text {
                    text: "Width"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.preferredWidth: 60
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 22
                    radius: 6
                    color: Theme.cellDefault

                    TextInput {
                        id: _widthInput
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        text: root._widthOverride === undefined ? "" : String(root._widthOverride)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        // No IntValidator: it marks an empty field unacceptable, which
                        // would stop editingFinished from firing and leave the user
                        // unable to clear the override back to the global value.
                        inputMethodHints: Qt.ImhDigitsOnly
                        clip: true
                        onEditingFinished: {
                            var entered = text.trim()
                            if (entered === "") {
                                root._saveKey("previewWidth", undefined)
                                return
                            }
                            var parsed = parseInt(entered)
                            if (isNaN(parsed)) {
                                text = root._widthOverride === undefined ? "" : String(root._widthOverride)
                                return
                            }
                            root._saveKey("previewWidth", Math.max(0, Math.min(600, parsed)))
                        }
                        onActiveFocusChanged: if (!activeFocus)
                            text = root._widthOverride === undefined ? "" : String(root._widthOverride)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: _widthInput.text === "" && !_widthInput.activeFocus
                            text: (Profiles.value("stt.previewWidth") ?? 180) + " px (inherited)"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textTertiary
                        }
                    }
                }
            }
        }
    }
}
