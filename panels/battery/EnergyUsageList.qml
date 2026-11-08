import QtQuick
import qs.components
import QtQuick.Layouts
import Quickshell
import qs.singletons

// Use per app, as Android lists it — estimated (EnergyUsage, EnergyRules): each app's
// share of the energy drawn, the screen and the rest of the laptop as "System and screen",
// largest first. Since the last full charge, or within a stretch picked on the graph
// (`rangeFrom`, `rangeTo`, seconds; NaN for none).
ColumnLayout {
    id: root

    property real rangeFrom: NaN
    property real rangeTo: NaN
    readonly property bool _ranged: !isNaN(rangeFrom) && !isNaN(rangeTo)
    signal rangeCleared

    readonly property var _usage: (EnergyUsage.buckets, _ranged
        ? EnergyUsage.usageBetween(EnergyRules.bucketStart(rangeFrom), rangeTo)
        : EnergyUsage.sinceCharge)

    // Repaints the "how long ago" while shown
    property double _now: Date.now()
    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: root._now = Date.now()
    }

    readonly property var _rows: {
        const rows = EnergyRules.ranked(root._usage.apps, 8);
        if (root._usage.system > 0)
            rows.push({ name: "System and screen", wh: root._usage.system, system: true });
        // By energy, "Other" last whatever it adds up to
        return rows.sort((a, b) => (a.other ? 1 : 0) - (b.other ? 1 : 0) || b.wh - a.wh);
    }
    readonly property real _total: Object.values(_usage.apps).reduce((sum, wh) => sum + wh, _usage.system)

    // "<0.1 Wh" for what rounds to nothing, else one decimal
    function _wh(value) {
        return value < 0.05 ? "<0.1 Wh" : value.toFixed(1) + " Wh";
    }

    function _clock(seconds) {
        return Qt.formatDateTime(new Date(seconds * 1000), "hh:mm");
    }

    function _ago(milliseconds) {
        const minutes = Math.max(0, Math.round((root._now - milliseconds) / 60000));
        const hours = Math.floor(minutes / 60);
        if (hours >= 48)
            return Math.floor(hours / 24) + " days ago";
        return hours > 0 ? hours + " h " + (minutes % 60) + " min ago" : minutes + " min ago";
    }

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.fillWidth: true
            // Until the shell has seen a full charge it counts from when it began
            text: root._ranged ? root._clock(root.rangeFrom) + " – " + root._clock(root.rangeTo)
                : EnergyUsage.fromFullCharge ? "Since full charge" : "Since counting began"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: Theme.textPrimary
        }

        // Back to since the full charge
        Text {
            visible: root._ranged
            text: "×"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
            color: _clearArea.lit ? Theme.textPrimary : Theme.textSecondary

            PointerArea {
                id: _clearArea
                reach: 8
                cursorShape: Qt.PointingHandCursor
                onClicked: root.rangeCleared()
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: root._ranged
            ? (root._usage.count > 0 ? root._wh(root._total) + " in the span picked" : "No use per app recorded in this span")
            : EnergyUsage.since > 0
            ? root._ago(EnergyUsage.since * 1000) + " · " + root._wh(root._total) + " used"
            : "Counted while on battery — nothing yet"
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
    }

    Repeater {
        // ScriptModel, never the bare array (CLAUDE.md)
        model: ScriptModel { values: root._rows }

        ColumnLayout {
            id: _row
            required property var modelData
            readonly property real _share: root._total > 0 ? modelData.wh / root._total : 0

            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: _row.modelData.name
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: _row.modelData.system ? Theme.textSecondary : Theme.textPrimary
                }
                Text {
                    text: Math.round(_row._share * 100) + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textSecondary
                }
                Text {
                    Layout.preferredWidth: _whMetrics.width
                    horizontalAlignment: Text.AlignRight
                    text: root._wh(_row.modelData.wh)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textMuted
                }
            }

            // The share, as a bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Qt.alpha(Theme.textDisabled, 0.3)

                Rectangle {
                    width: parent.width * _row._share
                    height: parent.height
                    radius: 2
                    color: _row.modelData.system ? Theme.textSecondary : Theme.accent
                }
            }
        }
    }

    TextMetrics {
        id: _whMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        text: "88.8 Wh"
    }

    Item { Layout.fillHeight: true }

    Text {
        Layout.fillWidth: true
        text: "Estimated from each app's CPU and GPU time; the screen, Wi-Fi and the rest count as System and screen."
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTiny
        color: Theme.textMuted
    }
}
