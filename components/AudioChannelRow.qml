import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Mute icon + volume slider + percentage + collapsible device list.
// isSink: true = output (speaker); isSink: false = input (microphone).
Item {
    id: row
    property bool isSink: true
    implicitHeight: innerCol.implicitHeight

    readonly property bool muted:   isSink ? Audio.muted        : Audio.sourceMuted
    readonly property int  volume:  isSink ? Audio.volume       : Audio.sourceVolume
    readonly property var  node:    isSink ? Audio.sink         : Audio.source

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
                font.pixelSize: 20
                color: row.muted ? Theme.textDim : Theme.textPrimary
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
                fillColor: row.volume > 100 ? Theme.textWarning : Theme.sliderAccent
                fillColorHover: row.volume > 100 ? Theme.textWarning : Theme.sliderAccentHover
                onMoved: v => { if (row.node?.audio) row.node.audio.volume = v; }
            }

            Text {
                text: row.volume + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: row.volume > 100 ? Theme.textWarning : Theme.textPrimary
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
            }

            Text {
                id: expandArrow
                property bool expanded: false
                text: expanded ? "▲" : "▼"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: arrowArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    id: arrowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: expandArrow.expanded = !expandArrow.expanded
                }
            }
        }

        // Collapsible device list
        Item {
            width: parent.width
            height: expandArrow.expanded ? deviceCol.implicitHeight : 0
            clip: true
            Behavior on height {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            Column {
                id: deviceCol
                width: parent.width
                spacing: 0

                Repeater {
                    model: Audio.nodes

                    delegate: Rectangle {
                        required property var modelData
                        property bool matches: !modelData.isStream && modelData.audio && modelData.isSink === row.isSink
                        visible: matches
                        width: deviceCol.width
                        height: matches ? 28 : 0
                        color: deviceArea.containsMouse ? Theme.buttonHover : "transparent"
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
                                font.pixelSize: 13
                                color: modelData === activeNode ? Theme.textPrimary : Theme.textDim
                            }

                            Text {
                                text: modelData.description || modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
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
    }
}
