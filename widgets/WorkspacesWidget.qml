import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    Layout.fillHeight: true
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    implicitWidth: wsRow.width + 16

    property string profile: ""
    property var _workspaceModel: null

    Component.onCompleted: { _workspaceModel = Workspaces.workspaces }

    Connections {
        target: Workspaces
        function onWorkspacesChanged() {
            Qt.callLater(() => { root._workspaceModel = Workspaces.workspaces })
        }
    }

    readonly property string _title: {
        if (profile === "")
            return "";
        var data = JSON.parse(Config.widgetProfiles || "{}");
        return data["workspaces"]?.[profile]?.title ?? "";
    }

    readonly property var _nameMap: {
        if (profile === "")
            return ({});
        var data = JSON.parse(Config.widgetProfiles || "{}");
        var entries = data["workspaces"]?.[profile]?.nameMap ?? [];
        var map = {};
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].system)
                map[entries[i].system] = entries[i].custom || "";
        }
        return map;
    }

    readonly property bool _showSpecial: {
        if (profile === "")
            return true;
        var data = JSON.parse(Config.widgetProfiles || "{}");
        return data["workspaces"]?.[profile]?.showSpecial ?? true;
    }

    readonly property bool _showNormal: {
        if (profile === "")
            return true;
        var data = JSON.parse(Config.widgetProfiles || "{}");
        return data["workspaces"]?.[profile]?.showNormal ?? true;
    }

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: Theme.cellDefault
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: 4

        Item {
            visible: _title !== ""
            width: _titleText.implicitWidth
            height: 22

            Text {
                id: _titleText
                anchors.centerIn: parent
                text: _title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }
        }

        Repeater {
            model: root._workspaceModel
            delegate: Rectangle {
                required property var modelData
                visible: (Workspaces.isSpecial(modelData) ? _showSpecial : _showNormal)
                width: Math.max(22, wsText.implicitWidth + 8)
                height: 22
                radius: 4
                color: {
                    if (Workspaces.isSpecial(modelData))
                        return Workspaces.isSpecialVisible(modelData) ? Theme.cellAccentSpecial : (_wsHover.containsMouse ? Theme.cellHover : "transparent")
                    return modelData.focused ? Theme.cellAccent : (modelData.active ? Theme.cellAccentSecondary : (_wsHover.containsMouse ? Theme.cellHover : "transparent"))
                }

                Text {
                    id: wsText
                    text: (_nameMap[modelData.name] || "") !== "" ? _nameMap[modelData.name] : (modelData.name || modelData.id)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.textPrimary
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: _wsHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (Workspaces.isSpecial(modelData) && Workspaces.isSpecialVisible(modelData))
                            Workspaces.toggleSpecial(modelData)
                        else
                            Workspaces.activate(modelData)
                    }
                }
            }
        }
    }
}
