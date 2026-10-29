import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// Mute icon + volume slider + percentage + collapsible device list.
// isSink: true = output (speaker); isSink: false = input (microphone).
Item {
    id: row
    property bool isSink: true
    implicitHeight: innerCol.implicitHeight

    readonly property bool muted: isSink ? Audio.muted : Audio.sourceMuted
    readonly property int volume: isSink ? Audio.volume : Audio.sourceVolume
    readonly property var node: isSink ? Audio.sink : Audio.source

    Column {
        id: innerCol
        width: parent.width
        spacing: 4

        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: row.muted ? (row.isSink ? "󰖁" : "󰍭") : (row.isSink ? "󰕾" : "󰍬")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeTitle
                color: row.muted ? Theme.textDisabled : Theme.textPrimary
                Layout.preferredWidth: 24
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (row.node?.audio)
                            row.node.audio.muted = !row.node.audio.muted;
                    }
                }
            }

            VolumeSlider {
                value: row.node?.audio?.volume ?? 0
                fillColor: row.volume > 100 ? Theme.warning : Theme.accent
                fillColorHover: row.volume > 100 ? Theme.warning : Theme.accentHover
                onMoved: v => {
                    if (row.node?.audio)
                        row.node.audio.volume = v;
                }
            }

            Text {
                text: row.volume + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                color: row.volume > 100 ? Theme.warning : Theme.textPrimary
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
            }

            Text {
                id: deviceToggle
                property bool expanded: false
                text: "󰒓"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                color: deviceToggleArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    id: deviceToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: deviceToggle.expanded = !deviceToggle.expanded
                }
            }

            Text {
                id: appMixerToggle
                property bool expanded: false
                text: "󰎹"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSection
                color: appMixerToggleArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    id: appMixerToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appMixerToggle.expanded = !appMixerToggle.expanded
                }
            }
        }

        // Collapsible device list
        Item {
            width: parent.width
            height: deviceToggle.expanded ? deviceCol.implicitHeight : 0
            clip: true
            Behavior on height {
                NumberAnimation {
                    duration: Theme.duration("expand")
                    easing.type: Theme.easing("expand")
                }
            }

            Column {
                id: deviceCol
                width: parent.width
                spacing: 0

                Repeater {
                    // ScriptModel diffs old vs. new values so only changed delegates
                    // get added/removed — see MusicPanel.qml for why binding a plain
                    // live-model array straight to Repeater.model was crashing this app.
                    model: ScriptModel {
                        values: Audio.nodes.values
                    }

                    delegate: Rectangle {
                        required property var modelData
                        property bool matches: !modelData.isStream && modelData.audio && modelData.isSink === row.isSink
                        visible: matches
                        width: deviceCol.width
                        height: matches ? 28 : 0
                        color: deviceArea.containsMouse ? Theme.surfaceHover : "transparent"
                        radius: 4

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                property var activeNode: row.node
                                text: modelData === activeNode ? "●" : "○"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBodyLarge
                                color: modelData === activeNode ? Theme.textPrimary : Theme.textDisabled
                            }

                            Text {
                                text: modelData.description || modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBodyLarge
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: deviceArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (row.isSink)
                                    Audio.setDefaultSink(modelData);
                                else
                                    Audio.setDefaultSource(modelData);
                            }
                        }
                    }
                }
            }
        }

        // Collapsible app mixer list
        Item {
            width: parent.width
            height: appMixerToggle.expanded ? appMixerCol.implicitHeight : 0
            clip: true
            Behavior on height {
                NumberAnimation {
                    duration: Theme.duration("expand")
                    easing.type: Theme.easing("expand")
                }
            }

            Column {
                id: appMixerCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: ScriptModel {
                        values: Audio.appNodes
                    }

                    delegate: Item {
                        // Null for a moment when an app stops playing: its node goes before
                        // the row does
                        required property var modelData
                        property bool matches: (modelData?.isStream ?? false) && !!modelData?.audio
                            && modelData?.isSink === row.isSink
                        visible: matches && modelData.ready
                        width: appMixerCol.width
                        height: matches ? 36 : 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: modelData?.description || modelData?.name || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                Layout.preferredWidth: 72
                            }

                            VolumeSlider {
                                value: modelData?.audio?.volume ?? 0
                                fillColor: Theme.accent
                                fillColorHover: Theme.accentHover
                                onMoved: v => {
                                    if (modelData?.audio) {
                                        var rounded = Math.round(v * 100) / 100;
                                        Audio.targetVolumes[modelData.name] = rounded;
                                        modelData.audio.volume = v;
                                        var volumes = JSON.parse(Config.audio.appVolumes || "{}");
                                        volumes[modelData.name] = rounded;
                                        Config.audio.appVolumes = JSON.stringify(volumes);
                                    }
                                }
                            }

                            Text {
                                text: modelData?.audio ? Math.round((modelData.audio.volume ?? 0) * 100) + "%" : "0%"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textSecondary
                                Layout.preferredWidth: 38
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }
    }
}
