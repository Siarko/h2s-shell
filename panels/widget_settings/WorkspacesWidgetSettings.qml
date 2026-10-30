import QtQuick
import QtQuick.Layouts
import qs.components
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
                    // A label longer than the column (a larger font) is cut, not run into the field
                    elide: Text.ElideRight
                }

                InputField {
                    id: _titleInput
                    Layout.fillWidth: true
                    text: _currentTitle
                    onEditingFinished: _saveTitle(text.trim())
                    onEditingChanged: if (!editing)
                        text = _currentTitle
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

                ToggleSwitch {
                    id: _specialToggle
                    checked: _showSpecial
                    onToggled: _saveShowSpecial(!_showSpecial)
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

                ToggleSwitch {
                    id: _normalToggle
                    checked: _showNormal
                    onToggled: _saveShowNormal(!_showNormal)
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

                    InputField {
                        id: _sysInput
                        width: 200
                        Component.onCompleted: text = _mapRow.system
                        onEditingFinished: {
                            _nameMapModel.set(_mapRow.index, {
                                system: text.trim(),
                                custom: _custInput.text
                            });
                            _saveNameMap();
                        }
                        onEditingChanged: if (!editing)
                            text = _mapRow.system
                    }

                    Text {
                        font.family: Theme.fontFamily
                        text: "→"
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textDisabled
                    }

                    InputField {
                        id: _custInput
                        Layout.fillWidth: true
                        Component.onCompleted: text = _mapRow.custom
                        onEditingFinished: {
                            _nameMapModel.set(_mapRow.index, {
                                system: _sysInput.text,
                                custom: text.trim()
                            });
                            _saveNameMap();
                        }
                        onEditingChanged: if (!editing)
                            text = _mapRow.custom
                    }

                    Rectangle {
                        // As big as the glyph, never less than 20 px
                        width: Math.max(20, _removeGlyph.implicitHeight)
                        height: width
                        radius: 4
                        color: _removeHover.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverClear
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                        Text {
                            id: _removeGlyph
                            font.family: Theme.fontFamily
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
