import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.panels

Flickable {
    anchors.fill: parent
    contentHeight: _barCol.implicitHeight
    clip: true

    ColumnLayout {
        id: _barCol
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 16

        Text {
            text: "Geometry"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
        }

        SettingsGroup {
            SettingSlider {
                label: "Bar height"
                tooltip: "Bar height. Excluding the reserved space and top offset"
                tooltipIcon: true
                from: 10
                to: 80
                value: Config.bar.layout.barHeight
                onValueEdited: newValue => {
                    Config.bar.layout.barHeight = newValue;
                    if (Config.bar.layout.reservedSpace < newValue)
                        Config.bar.layout.reservedSpace = newValue;
                    var maxOffset = Config.bar.layout.reservedSpace - newValue;
                    if (Config.bar.layout.topOffset > maxOffset)
                        Config.bar.layout.topOffset = maxOffset;
                }
            }

            SettingSlider {
                label: "Reserved space"
                tooltip: "Overall reserved space for the bar, includes bar height and offset"
                tooltipIcon: true
                from: 10
                to: 80
                lockedFrom: Config.bar.layout.barHeight
                value: Config.bar.layout.reservedSpace
                onValueEdited: newValue => {
                    Config.bar.layout.reservedSpace = newValue;
                    var maxOffset = newValue - Config.bar.layout.barHeight;
                    if (Config.bar.layout.topOffset > maxOffset)
                        Config.bar.layout.topOffset = maxOffset;
                }
            }
            SettingSlider {
                label: "Top offset"
                tooltip: "Top offset between the bar and top of the screen"
                tooltipIcon: true
                from: 0
                to: Config.bar.layout.reservedSpace - Config.bar.layout.barHeight
                disabled: Config.bar.layout.reservedSpace <= Config.bar.layout.barHeight
                value: Config.bar.layout.topOffset
                onValueEdited: newValue => Config.bar.layout.topOffset = newValue
            }
            SettingSlider {
                label: "Left margin"
                from: 0
                to: 300
                value: Config.bar.layout.leftMargin
                onValueEdited: newValue => Config.bar.layout.leftMargin = newValue
            }
            SettingSlider {
                label: "Right margin"
                from: 0
                to: 300
                value: Config.bar.layout.rightMargin
                onValueEdited: newValue => Config.bar.layout.rightMargin = newValue
            }
            SettingSlider {
                label: "Left padding"
                from: 0
                to: 300
                value: Config.bar.layout.leftPadding
                onValueEdited: newValue => Config.bar.layout.leftPadding = newValue
            }
            SettingSlider {
                label: "Right padding"
                from: 0
                to: 300
                value: Config.bar.layout.rightPadding
                onValueEdited: newValue => Config.bar.layout.rightPadding = newValue
            }
        }

        Text {
            text: "Corners"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 4
        }

        SettingsGroup {
            SettingSlider {
                label: "Top left"
                from: 0
                to: 100
                suffix: "%"
                value: Config.bar.layout.radiusTopLeft
                onValueEdited: newValue => Config.bar.layout.radiusTopLeft = newValue
            }
            SettingSlider {
                label: "Top right"
                from: 0
                to: 100
                suffix: "%"
                value: Config.bar.layout.radiusTopRight
                onValueEdited: newValue => Config.bar.layout.radiusTopRight = newValue
            }
            SettingSlider {
                label: "Bottom left"
                from: 0
                to: 100
                suffix: "%"
                value: Config.bar.layout.radiusBottomLeft
                onValueEdited: newValue => Config.bar.layout.radiusBottomLeft = newValue
            }
            SettingSlider {
                label: "Bottom right"
                from: 0
                to: 100
                suffix: "%"
                value: Config.bar.layout.radiusBottomRight
                onValueEdited: newValue => Config.bar.layout.radiusBottomRight = newValue
            }
        }

        Text {
            text: "Content"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 4
        }

        SettingsGroup {
            BarSectionList {
                title: "Left section"
                model: Config.bar.content.left
                onListChanged: newList => Config.bar.content.left = newList
            }

            BarSectionList {
                title: "Center section"
                model: Config.bar.content.center
                onListChanged: newList => Config.bar.content.center = newList
            }

            BarSectionList {
                title: "Right section"
                model: Config.bar.content.right
                onListChanged: newList => Config.bar.content.right = newList
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
