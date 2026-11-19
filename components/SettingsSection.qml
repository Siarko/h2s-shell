import QtQuick
import QtQuick.Layouts
import qs.singletons

// A titled group on a settings page, as an anchor block (components/AnchorBlock.qml). Its
// root is a plain column: the `before` host, its frame — the title's line, with its buttons on
// the right (`buttons`: "Find networks") — the `prepend` host, its content, the `append` host,
// the `after` host; the parent sees one item, in a ColumnLayout or as a Repeater's delegate.
// The content is laid out in a column `spacing` apart, Layout.* apply; a module's elements
// stand `hostGap` from what they touch. What is hidden takes no room.
//
//   SettingsSection {
//       anchor: "saved"
//       title: "Saved networks"
//       Layout.fillWidth: true
//       buttons: SmallButton { label: "Find networks"; onClicked: … }
//       Repeater { … SettingsCard { anchor: "card"; Layout.fillWidth: true } }
//   }
AnchorBlock {
    id: root

    property string title: ""
    // Room above the block, from what stands before it on the page
    property real topMargin: 16
    property real spacing: 0
    property real hostGap: 6
    default property alias content: _content.data
    // On the title's line, right-aligned
    property alias buttons: _buttons.data
    // The hosts and the title's line, for the core's tests
    readonly property alias beforeHost: _before
    readonly property alias prependHost: _prepend
    readonly property alias appendHost: _append
    readonly property alias afterHost: _after
    readonly property alias frame: _frame

    kind: "section"
    placements: ["before", "after", "prepend", "append"]
    implicitWidth: _column.implicitWidth
    implicitHeight: _column.implicitHeight + topMargin

    ColumnLayout {
        id: _column
        y: root.topMargin
        width: root.width
        spacing: 0

        AnchorContent {
            id: _before
            block: root
            placement: "before"
            Layout.fillWidth: true
            Layout.bottomMargin: count > 0 ? root.hostGap : 0
        }

        // The frame: never content, so a prepended element comes under it
        RowLayout {
            id: _frame
            visible: root.title !== "" || _buttons.children.length > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textPrimary
            }

            // A layout, not a positioner: it gives each button a whole width, so its edges
            // stand on whole pixels
            RowLayout {
                id: _buttons
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: 8
            }
        }

        AnchorContent {
            id: _prepend
            block: root
            placement: "prepend"
            Layout.fillWidth: true
            Layout.bottomMargin: count > 0 ? root.hostGap : 0
        }

        ColumnLayout {
            id: _content
            Layout.fillWidth: true
            spacing: root.spacing
        }

        AnchorContent {
            id: _append
            block: root
            placement: "append"
            Layout.fillWidth: true
            Layout.topMargin: count > 0 ? root.hostGap : 0
        }

        AnchorContent {
            id: _after
            block: root
            placement: "after"
            Layout.fillWidth: true
            Layout.topMargin: count > 0 ? root.hostGap : 0
        }
    }
}
