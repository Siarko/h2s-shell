import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.components
import qs.singletons

// Sound management popup with output/input volume sliders and device selectors
Item {
    id: root
    implicitWidth: 300
    implicitHeight: col.implicitHeight

    PwObjectTracker {
        id: nodeTracker
        objects: Audio.nodes
    }

    Column {
        id: col
        width: parent.implicitWidth
        spacing: 4

        // --- Output section ---
        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: Audio.muted ? "󰖁" : "󰕾"
                font.family: Theme.fontFamily
                font.pixelSize: 20
                color: Audio.muted ? Theme.textDim : Theme.textPrimary
                Layout.preferredWidth: 24
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (Audio.sink?.audio)
                            Audio.sink.audio.muted = !Audio.sink.audio.muted;
                    }
                }
            }

            VolumeSlider {
                value: Audio.sink?.audio?.volume ?? 0
                fillColor: Audio.volume > 100 ? Theme.textWarning : Theme.sliderAccent
                fillColorHover: Audio.volume > 100 ? Theme.textWarning : Theme.sliderAccentHover
                onMoved: volume => { if (Audio.sink?.audio) Audio.sink.audio.volume = volume; }
            }

            Text {
                text: Audio.volume + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Audio.volume > 100 ? Theme.textWarning : Theme.textPrimary
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
            }

            Text {
                id: outputArrow
                property bool expanded: false
                text: expanded ? "▲" : "▼"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: outputArrowArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    id: outputArrowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: outputArrow.expanded = !outputArrow.expanded
                }
            }
        }

        // Output device list
        Item {
            width: parent.width
            height: outputArrow.expanded ? outputDeviceCol.implicitHeight : 0
            clip: true
            Behavior on height {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            Column {
                id: outputDeviceCol
                width: parent.width
                spacing: 0

                Repeater {
                    model: Audio.nodes

                    delegate: Rectangle {
                        required property var modelData
                        property bool matches: !modelData.isStream && modelData.audio && modelData.isSink
                        visible: matches
                        width: outputDeviceCol.width
                        height: matches ? 28 : 0
                        color: deviceOutArea.containsMouse ? Theme.buttonHover : "transparent"
                        radius: 4

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: modelData === Audio.sink ? "●" : "○"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: modelData === Audio.sink ? Theme.textPrimary : Theme.textDim
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
                            id: deviceOutArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Audio.setDefaultSink(modelData)
                        }
                    }
                }
            }
        }

        // Separator
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.textDim
        }

        // --- Input section ---
        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: Audio.sourceMuted ? "󰍭" : "󰍬"
                font.family: Theme.fontFamily
                font.pixelSize: 20
                color: Audio.sourceMuted ? Theme.textDim : Theme.textPrimary
                Layout.preferredWidth: 24
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (Audio.source?.audio)
                            Audio.source.audio.muted = !Audio.source.audio.muted;
                    }
                }
            }

            VolumeSlider {
                value: Audio.source?.audio?.volume ?? 0
                fillColor: Audio.sourceVolume > 100 ? Theme.textWarning : Theme.sliderAccent
                fillColorHover: Audio.sourceVolume > 100 ? Theme.textWarning : Theme.sliderAccentHover
                onMoved: volume => { if (Audio.source?.audio) Audio.source.audio.volume = volume; }
            }

            Text {
                text: Audio.sourceVolume + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Audio.sourceVolume > 100 ? Theme.textWarning : Theme.textPrimary
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
            }

            Text {
                id: inputArrow
                property bool expanded: false
                text: expanded ? "▲" : "▼"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: inputArrowArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Layout.preferredWidth: 20
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    id: inputArrowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: inputArrow.expanded = !inputArrow.expanded
                }
            }
        }

        // Input device list
        Item {
            width: parent.width
            height: inputArrow.expanded ? inputDeviceCol.implicitHeight : 0
            clip: true
            Behavior on height {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            Column {
                id: inputDeviceCol
                width: parent.width
                spacing: 0

                Repeater {
                    model: Audio.nodes

                    delegate: Rectangle {
                        required property var modelData
                        property bool matches: !modelData.isStream && modelData.audio && !modelData.isSink
                        visible: matches
                        width: inputDeviceCol.width
                        height: matches ? 28 : 0
                        color: deviceInArea.containsMouse ? Theme.buttonHover : "transparent"
                        radius: 4

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: modelData === Audio.source ? "●" : "○"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                color: modelData === Audio.source ? Theme.textPrimary : Theme.textDim
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
                            id: deviceInArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Audio.setDefaultSource(modelData)
                        }
                    }
                }
            }
        }
    }
}
