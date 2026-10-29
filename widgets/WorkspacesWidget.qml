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

    // From the widget's preset; without one, the workspaces defaults
    readonly property string _title: WidgetPresets.value("workspaces", preset, "title")

    readonly property var _nameMap: {
        var entries = WidgetPresets.value("workspaces", preset, "nameMap") ?? [];
        var map = {};
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].system)
                map[entries[i].system] = entries[i].custom || "";
        }
        return map;
    }

    readonly property bool _showSpecial: WidgetPresets.value("workspaces", preset, "showSpecial")
    readonly property bool _showNormal: WidgetPresets.value("workspaces", preset, "showNormal")

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
                        return Workspaces.isSpecialVisible(modelData) ? Theme.workspaceSpecial : (_wsHover.containsMouse ? Theme.surfaceHover : "transparent")
                    return modelData.focused ? Theme.accentDark : (modelData.active ? Theme.workspaceActive : (_wsHover.containsMouse ? Theme.surfaceHover : "transparent"))
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
