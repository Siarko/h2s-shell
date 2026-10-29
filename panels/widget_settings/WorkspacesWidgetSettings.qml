import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    property string presetName: ""
    property string widgetType: "workspaces"

    implicitHeight: _col.implicitHeight

    ListModel {
        id: _nameMapModel
    }

    readonly property string _currentTitle: WidgetPresets.value(widgetType, presetName, "title")
    readonly property bool _showSpecial: WidgetPresets.value(widgetType, presetName, "showSpecial")
    readonly property bool _showNormal: WidgetPresets.value(widgetType, presetName, "showNormal")

    function _saveTitle(newTitle) {
        WidgetPresets.set(widgetType, presetName, "title", newTitle);
    }

    function _saveShowSpecial(value) {
        WidgetPresets.set(widgetType, presetName, "showSpecial", value);
    }

    function _saveShowNormal(value) {
        WidgetPresets.set(widgetType, presetName, "showNormal", value);
    }

    // The name map is edited in a ListModel, so rows keep their text fields while typing
    function _modelEntries() {
        var entries = [];
        for (var i = 0; i < _nameMapModel.count; i++) {
            var item = _nameMapModel.get(i);
            entries.push({ system: item.system, custom: item.custom });
        }
        return entries;
    }

    function _loadNameMap() {
        _nameMapModel.clear();
        var entries = WidgetPresets.value(widgetType, presetName, "nameMap") ?? [];
        for (var i = 0; i < entries.length; i++)
            _nameMapModel.append({
                system: entries[i].system || "",
                custom: entries[i].custom || ""
            });
    }

    function _saveNameMap() {
        WidgetPresets.set(widgetType, presetName, "nameMap", _modelEntries());
    }

    function _removeNameMapRow(index) {
        _nameMapModel.remove(index);
        _saveNameMap();
    }

    // The same preset edited elsewhere — another bar entry using it — reloads the list.
    // This page's own saves leave it equal to the model, so they do not.
    Connections {
        target: WidgetPresets
        function onAllChanged() {
            var stored = (WidgetPresets.value(root.widgetType, root.presetName, "nameMap") ?? [])
                .map(entry => ({ system: entry.system || "", custom: entry.custom || "" }));
            if (JSON.stringify(stored) !== JSON.stringify(root._modelEntries()))
                root._loadNameMap();
        }
    }

    Component.onCompleted: _loadNameMap()
    onPresetNameChanged: _loadNameMap()

    Column {
        id: _col
        width: parent.width
        topPadding: 4
        spacing: 0

        // Title row
        Item {
            width: _col.width
            height: 28

            RowLayout {
                anchors { fill: parent; rightMargin: 4 }
                spacing: 8

                Text {
                    text: "Title"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.preferredWidth: 60
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 22
                    radius: 6
                    color: Theme.surface

                    TextInput {
                        id: _titleInput
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                        }
                        text: _currentTitle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        onEditingFinished: _saveTitle(text.trim())
                        onActiveFocusChanged: if (!activeFocus)
                            text = _currentTitle
                    }
                }
            }
        }

        // Show special workspaces toggle
        Item {
            width: _col.width
            height: 28

            RowLayout {
                anchors { fill: parent; rightMargin: 4 }
                spacing: 8

                Text {
                    text: "Show special workspaces"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: _specialToggle
                    width: 36
                    height: 20
                    radius: 10
                    color: _showSpecial ? Theme.accent : Theme.surface

                    Rectangle {
                        x: _showSpecial ? parent.width - width - 2 : 2
                        y: 2
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.textPrimary
                        Behavior on x { NumberAnimation { duration: Theme.duration("state"); easing.type: Theme.easing("state") } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: _saveShowSpecial(!_showSpecial)
                    }
                }
            }
        }

        // Show normal workspaces toggle
        Item {
            width: _col.width
            height: 28

            RowLayout {
                anchors { fill: parent; rightMargin: 4 }
                spacing: 8

                Text {
                    text: "Show normal workspaces"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: _normalToggle
                    width: 36
                    height: 20
                    radius: 10
                    color: _showNormal ? Theme.accent : Theme.surface

                    Rectangle {
                        x: _showNormal ? parent.width - width - 2 : 2
                        y: 2
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.textPrimary
                        Behavior on x { NumberAnimation { duration: Theme.duration("state"); easing.type: Theme.easing("state") } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: _saveShowNormal(!_showNormal)
                    }
                }
            }
        }

        // Workspace names section label
        Text {
            text: "Workspace names"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: Theme.textSecondary
            topPadding: 10
            bottomPadding: 4
        }

        // Name mapping rows
        Repeater {
            model: _nameMapModel

            Item {
                id: _mapRow
                required property string system
                required property string custom
                required property int index

                width: _col.width
                height: 28

                RowLayout {
                    anchors {
                        fill: parent
                        rightMargin: 4
                    }
                    spacing: 4

                    Rectangle {
                        width: 200
                        height: 22
                        radius: 6
                        color: Theme.surface

                        TextInput {
                            id: _sysInput
                            anchors {
                                fill: parent
                                leftMargin: 6
                                rightMargin: 6
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            Component.onCompleted: text = _mapRow.system
                            onEditingFinished: {
                                _nameMapModel.set(_mapRow.index, {
                                    system: text.trim(),
                                    custom: _custInput.text
                                });
                                _saveNameMap();
                            }
                            onActiveFocusChanged: if (!activeFocus)
                                text = _mapRow.system
                        }
                    }

                    Text {
                        text: "→"
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textDisabled
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 22
                        radius: 6
                        color: Theme.surface

                        TextInput {
                            id: _custInput
                            anchors {
                                fill: parent
                                leftMargin: 6
                                rightMargin: 6
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            Component.onCompleted: text = _mapRow.custom
                            onEditingFinished: {
                                _nameMapModel.set(_mapRow.index, {
                                    system: _sysInput.text,
                                    custom: text.trim()
                                });
                                _saveNameMap();
                            }
                            onActiveFocusChanged: if (!activeFocus)
                                text = _mapRow.custom
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 4
                        color: _removeHover.containsMouse ? Theme.surfaceHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.textDisabled
                        }

                        MouseArea {
                            id: _removeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: _removeNameMapRow(_mapRow.index)
                        }
                    }
                }
            }
        }

        // Add row button
        Item {
            width: _col.width
            height: 28

            Text {
                anchors.centerIn: parent
                text: "＋ Add"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    _nameMapModel.append({
                        system: "",
                        custom: ""
                    });
                    _saveNameMap();
                }
            }
        }
    }
}
