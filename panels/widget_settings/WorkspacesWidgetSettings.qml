import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    property string profileName: ""
    property string widgetType: "workspaces"

    implicitHeight: _col.implicitHeight

    ListModel {
        id: _nameMapModel
    }

    readonly property string _currentTitle: {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        return data[widgetType]?.[profileName]?.title ?? "";
    }

    function _saveTitle(newTitle) {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        if (!data[widgetType])
            data[widgetType] = {};
        if (!data[widgetType][profileName])
            data[widgetType][profileName] = {};
        data[widgetType][profileName]["title"] = newTitle;
        Config.widgetProfiles = JSON.stringify(data);
    }

    function _loadNameMap() {
        _nameMapModel.clear();
        var data = JSON.parse(Config.widgetProfiles || "{}");
        var entries = data[widgetType]?.[profileName]?.nameMap ?? [];
        for (var i = 0; i < entries.length; i++)
            _nameMapModel.append({
                system: entries[i].system || "",
                custom: entries[i].custom || ""
            });
    }

    function _saveNameMap() {
        var entries = [];
        for (var i = 0; i < _nameMapModel.count; i++) {
            var item = _nameMapModel.get(i);
            entries.push({
                system: item.system,
                custom: item.custom
            });
        }
        var data = JSON.parse(Config.widgetProfiles || "{}");
        if (!data[widgetType])
            data[widgetType] = {};
        if (!data[widgetType][profileName])
            data[widgetType][profileName] = {};
        data[widgetType][profileName]["nameMap"] = entries;
        Config.widgetProfiles = JSON.stringify(data);
    }

    function _removeNameMapRow(index) {
        var entries = [];
        for (var i = 0; i < _nameMapModel.count; i++) {
            if (i === index) continue;
            var item = _nameMapModel.get(i);
            entries.push({ system: item.system, custom: item.custom });
        }
        var data = JSON.parse(Config.widgetProfiles || "{}");
        if (!data[widgetType]) data[widgetType] = {};
        if (!data[widgetType][profileName]) data[widgetType][profileName] = {};
        data[widgetType][profileName]["nameMap"] = entries;
        Config.widgetProfiles = JSON.stringify(data);
        _nameMapModel.remove(index);
    }

    readonly property bool _showSpecial: {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        return data[widgetType]?.[profileName]?.showSpecial ?? true;
    }

    function _saveShowSpecial(value) {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        if (!data[widgetType])
            data[widgetType] = {};
        if (!data[widgetType][profileName])
            data[widgetType][profileName] = {};
        data[widgetType][profileName]["showSpecial"] = value;
        Config.widgetProfiles = JSON.stringify(data);
    }

    readonly property bool _showNormal: {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        return data[widgetType]?.[profileName]?.showNormal ?? true;
    }

    function _saveShowNormal(value) {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        if (!data[widgetType])
            data[widgetType] = {};
        if (!data[widgetType][profileName])
            data[widgetType][profileName] = {};
        data[widgetType][profileName]["showNormal"] = value;
        Config.widgetProfiles = JSON.stringify(data);
    }

    Component.onCompleted: _loadNameMap()
    onProfileNameChanged: _loadNameMap()

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
                    color: Theme.cellDefault

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
                    color: _showSpecial ? Theme.sliderAccent : Theme.cellDefault

                    Rectangle {
                        x: _showSpecial ? parent.width - width - 2 : 2
                        y: 2
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.textPrimary
                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
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
                    color: _showNormal ? Theme.sliderAccent : Theme.cellDefault

                    Rectangle {
                        x: _showNormal ? parent.width - width - 2 : 2
                        y: 2
                        width: 16
                        height: 16
                        radius: 8
                        color: Theme.textPrimary
                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
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
                        color: Theme.cellDefault

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
                        color: Theme.textDim
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 22
                        radius: 6
                        color: Theme.cellDefault

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
                        color: _removeHover.containsMouse ? Theme.cellHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.textDim
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
