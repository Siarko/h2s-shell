import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Each workspace is its own button, so the cell itself takes no input
BarWidget {
    id: root
    widgetType: "workspaces"
    interactive: false
    // Narrower than a plain cell is fine with a single workspace showing
    Layout.minimumWidth: 0

    property string preset: ""

    readonly property string _title: {
        if (preset === "")
            return "";
        var data = JSON.parse(Config.widgetPresets || "{}");
        return data["workspaces"]?.[preset]?.title ?? "";
    }

    readonly property var _nameMap: {
        if (preset === "")
            return ({});
        var data = JSON.parse(Config.widgetPresets || "{}");
        var entries = data["workspaces"]?.[preset]?.nameMap ?? [];
        var map = {};
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].system)
                map[entries[i].system] = entries[i].custom || "";
        }
        return map;
    }

    readonly property bool _showSpecial: {
        if (preset === "")
            return true;
        var data = JSON.parse(Config.widgetPresets || "{}");
        return data["workspaces"]?.[preset]?.showSpecial ?? true;
    }

    readonly property bool _showNormal: {
        if (preset === "")
            return true;
        var data = JSON.parse(Config.widgetPresets || "{}");
        return data["workspaces"]?.[preset]?.showNormal ?? true;
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
            // Bound directly to the live Hyprland ObjectModel (not .values, no
            // ScriptModel needed) — Quickshell's ObjectModel is already a proper
            // QAbstractListModel that emits incremental insert/remove signals, so
            // Repeater updates delegates in place instead of tearing everything
            // down. The crash-prone pattern (see MusicPanel.qml) only happens when
            // a live model's .values snapshot — a plain JS array — gets reassigned
            // to Repeater.model directly.
            model: Workspaces.workspaces
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
