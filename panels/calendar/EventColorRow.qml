import QtQuick
import QtQuick.Controls
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// The event form's colour swatches: "none" (the calendar's own colour), then Google's
// event colours, in a row that scrolls sideways when the card is too narrow for it.
// Clicking a swatch sets `selectedColorId` ("" for none).
Item {
    id: root

    property string selectedColorId: ""

    readonly property var _colorEntries: {
        const keys = Object.keys(GoogleCalendar.eventColors).sort((a, b) => parseInt(a) - parseInt(b));
        return keys.map(key => ({
                    id: key,
                    hex: GoogleCalendar.eventColors[key]
                }));
    }

    implicitHeight: 24 + _colorScrollBar.height

    Flickable {
        id: _colorFlickable
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 24
        contentWidth: _colorRow.implicitWidth
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick

        WheelScroll {
            target: null
            onWheel: event => {
                _colorFlickable.contentX = Math.max(0, Math.min(_colorFlickable.contentWidth - _colorFlickable.width, _colorFlickable.contentX - event.angleDelta.y / 2));
            }
        }

        Row {
            id: _colorRow
            height: parent.height
            spacing: 6

            // Default swatch (no color override)
            Item {
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 16
                    height: 16
                    radius: width / 2
                    anchors.centerIn: parent
                    color: Theme.textMuted
                    border.color: root.selectedColorId === "" ? Theme.textPrimary : "transparent"
                    border.width: Theme.border.selectedWidth

                    Text {
                        font.family: Theme.fontFamily
                        anchors.centerIn: parent
                        text: "×"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeXSmall
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedColorId = ""
                }
            }

            // Keyed by id: _colorEntries is new objects on each change ("The Repeater crash"
            // in docs/ARCHITECTURE.md)
            KeyedModel { id: _colorsModel; values: root._colorEntries; keyProp: "id" }
            Repeater {
                model: _colorsModel.model

                Item {
                    required property string modelData
                    readonly property var colorEntry: _colorsModel.byKey[modelData] ?? ({})
                    width: 20
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 16
                        height: 16
                        radius: width / 2
                        anchors.centerIn: parent
                        color: colorEntry.hex ?? "transparent"
                        border.color: root.selectedColorId === colorEntry.id ? Theme.textPrimary : "transparent"
                        border.width: Theme.border.selectedWidth
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedColorId = colorEntry.id
                    }
                }
            }
        }
    }

    ScrollBar {
        id: _colorScrollBar
        anchors {
            left: parent.left
            right: parent.right
            top: _colorFlickable.bottom
        }
        orientation: Qt.Horizontal
        size: _colorFlickable.visibleArea.widthRatio
        position: _colorFlickable.visibleArea.xPosition
        onPositionChanged: if (active)
            _colorFlickable.contentX = position * _colorFlickable.contentWidth
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
            implicitWidth: 5
            implicitHeight: 5
            radius: height / 2
            color: Theme.textSecondary
        }
    }
}
