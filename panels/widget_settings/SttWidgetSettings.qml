import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

Item {
    id: root
    property string presetName: ""
    property string widgetType: "stt"

    implicitHeight: _col.implicitHeight

    // An absent key means "inherit the Dictation setting of the active shell profile"
    readonly property var _previewOverride: WidgetPresets.value(widgetType, presetName, "previewEnabled")
    readonly property var _widthOverride: WidgetPresets.value(widgetType, presetName, "previewWidth")

    readonly property string _previewMode: {
        if (_previewOverride === undefined) return "global"
        return _previewOverride ? "on" : "off"
    }

    // Passing undefined drops the key, restoring inheritance
    function _saveKey(key, value) {
        WidgetPresets.set(widgetType, presetName, key, value)
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
                    // A label longer than the column (a larger font) is cut, not run into the field
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    // As tall as a line of its labels, never less than 22 px
                    height: Math.max(22, _lineMetrics.height + 6)
                    radius: 6
                    color: Theme.surface
                    clip: true

                    TextMetrics {
                        id: _lineMetrics
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        text: "Ag"
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            model: ["global", "on", "off"]

                            Rectangle {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: root._previewMode === modelData ? Theme.accent : "transparent"

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
                    // A label longer than the column (a larger font) is cut, not run into the field
                    elide: Text.ElideRight
                }

                InputField {
                    id: _widthInput
                    Layout.fillWidth: true
                    text: root._widthOverride === undefined ? "" : String(root._widthOverride)
                    placeholder: (Profiles.value("stt.previewWidth") ?? 180) + " px (inherited)"
                    // No IntValidator: it marks an empty field unacceptable, which
                    // would stop editingFinished from firing and leave the user
                    // unable to clear the override back to the global value.
                    input.inputMethodHints: Qt.ImhDigitsOnly
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
                    onEditingChanged: if (!editing)
                        text = root._widthOverride === undefined ? "" : String(root._widthOverride)

                }
            }
        }
    }
}
