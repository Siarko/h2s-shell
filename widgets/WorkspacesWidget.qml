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

    BarRow {
        id: wsRow
        anchors.centerIn: parent
        spacing: Theme.workspace.pillSpacing

        // As long as its text along the bar, a pill's thickness across it
        Item {
            visible: _title !== ""
            width: root.vertical ? Math.max(Theme.workspace.pillHeight, _titleText.implicitWidth) : _titleText.implicitWidth
            height: root.vertical ? _titleText.implicitHeight : Theme.workspace.pillHeight

            BarText {
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
                // Special workspaces wait for the config: until the preset's name map is
                // read they would show their raw names ("special:music") for a moment
                visible: Workspaces.isSpecial(modelData) ? _showSpecial && Config.ready : _showNormal
                // Its padding at its ends along the bar; at least as long as it is thick
                readonly property real _length: Math.max(Theme.workspace.pillHeight,
                    (root.vertical ? wsText.implicitHeight : wsText.implicitWidth) + 2 * Theme.workspace.pillHorizontalPadding)
                readonly property real _thickness: Math.max(Theme.workspace.pillHeight,
                    root.vertical ? wsText.implicitWidth : 0)
                width: root.vertical ? _thickness : _length
                height: root.vertical ? _length : Theme.workspace.pillHeight
                radius: Theme.workspace.pillRadius
                color: {
                    if (Workspaces.isSpecial(modelData))
                        return Workspaces.isSpecialVisible(modelData) ? Theme.workspaceSpecial : (_wsHover.lit ? Theme.surfaceHover : Theme.surfaceHoverClear)
                    return modelData.focused ? Theme.accentDark : (modelData.active ? Theme.workspaceActive : (_wsHover.lit ? Theme.surfaceHover : Theme.surfaceHoverClear))
                }
                Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

                BarText {
                    id: wsText
                    text: (_nameMap[modelData.name] || "") !== "" ? _nameMap[modelData.name] : (modelData.name || modelData.id)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.textPrimary
                    anchors.centerIn: parent
                }

                PointerArea {
                    id: _wsHover
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
