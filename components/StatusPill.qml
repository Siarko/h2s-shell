import QtQuick
import QtQuick.Layouts
import qs.singletons

// A pill that sums up a state: an icon and a label, then its parts — each an icon and a
// short text (a count) in its kind's colour, its tip shown over it on hover. A click flips
// `expanded` while there are parts: the parts then one per line under a rule, each its icon
// and its line in its colour. A second click folds them away.
//
// `kind` and each part's `kind` are words of ApiElementRules.statusKinds (the colours they
// stand for); `parts` is ApiElementRules.statusParts' list — plain texts, capped. The public
// StatusPill (api/StatusPill.qml) hands both over checked; the shell's views may use this
// directly with words it knows.
//
//   StatusPill { icon: ""; label: "Sending 1/6"; parts: [{ icon: "", text: "3", kind: "muted", tip: "3 queued", line: "3 queued" }] }
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string kind: "normal"
    property var parts: []
    property bool expanded: false

    signal toggled(bool expanded)

    readonly property bool hasParts: (parts ?? []).length > 0
    readonly property bool open: expanded && hasParts
    readonly property var colours: ApiElementRules.statusKind(kind).value
    readonly property int gap: Math.round(Theme.fontSizeSmall / 2)
    readonly property real collapsedHeight: _row.implicitHeight + 2 * gap

    // A part's colours by its kind
    function partColours(part) {
        return ApiElementRules.statusKind(part?.kind).value;
    }

    implicitWidth: Math.max(_row.implicitWidth, open ? _lines.implicitWidth + Math.round(Theme.fontSizeSmall / 4) : 0) + 2 * Theme.row.horizontalPadding
    implicitHeight: collapsedHeight + (open ? _lines.implicitHeight + gap : 0)
    width: implicitWidth
    height: implicitHeight
    radius: collapsedHeight / 2
    color: _area.lit && hasParts ? Theme.surfaceHover : Theme.fill
    border.width: Theme.border.width
    border.color: Theme.outline
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    // The parts keyed by their place, for the views (a ScriptModel of keys, never the
    // objects: they are made anew with each change)
    KeyedModel {
        id: _keyed
        values: (root.parts ?? []).map((part, index) => Object.assign({}, part, { key: String(index) }))
        keyProp: "key"
    }

    // Below the parts: their hover handlers see the pointer, the click comes here
    PointerArea {
        id: _area
        enabled: root.hasParts
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.expanded = !root.expanded;
            root.toggled(root.expanded);
        }
    }

    RowLayout {
        id: _row
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.gap
        spacing: root.gap

        Text {
            objectName: "icon"
            visible: root.icon !== ""
            text: root.icon
            textFormat: Text.PlainText
            color: Theme[root.colours.icon]
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
        }
        Text {
            objectName: "label"
            visible: text !== ""
            text: root.label
            textFormat: Text.PlainText
            maximumLineCount: 1
            color: Theme[root.colours.text]
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            Layout.rightMargin: root.hasParts ? root.gap : 0
        }
        Repeater {
            model: _keyed.model
            Row {
                id: _part
                required property string modelData
                readonly property var part: _keyed.byKey[modelData] ?? null
                readonly property var colours: root.partColours(part)
                objectName: "part"
                spacing: Math.round(root.gap / 2)

                Text {
                    visible: text !== ""
                    text: _part.part?.icon ?? ""
                    textFormat: Text.PlainText
                    color: Theme[_part.colours.icon]
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: _part.part?.text ?? ""
                    textFormat: Text.PlainText
                    maximumLineCount: 1
                    color: Theme[_part.colours.icon]
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                }

                HoverHandler { id: _partHover }
                HoverTip {
                    target: _part
                    shown: _partHover.hovered && _part.visible
                    text: _part.part?.tip ?? ""
                }
            }
        }
    }

    // Expanded: one part per line, under a rule
    Rectangle {
        objectName: "rule"
        visible: root.open
        x: Theme.row.horizontalPadding
        y: root.collapsedHeight - 1
        width: root.width - 2 * Theme.row.horizontalPadding
        height: Theme.border.width
        color: Theme.divider
    }
    Column {
        id: _lines
        objectName: "lines"
        visible: root.open
        x: Theme.row.horizontalPadding + Math.round(Theme.fontSizeSmall / 4)
        y: root.collapsedHeight + Math.round(root.gap / 2)
        spacing: Math.round(root.gap / 2)

        Repeater {
            model: _keyed.model
            Row {
                id: _line
                required property string modelData
                readonly property var part: _keyed.byKey[modelData] ?? null
                readonly property var colours: root.partColours(part)
                objectName: "line"
                spacing: root.gap

                Text {
                    text: _line.part?.icon ?? ""
                    textFormat: Text.PlainText
                    color: Theme[_line.colours.icon]
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    width: Theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: _line.part?.line ?? ""
                    textFormat: Text.PlainText
                    maximumLineCount: 1
                    color: Theme[_line.colours.text]
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
