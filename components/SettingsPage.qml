import QtQuick
import QtQuick.Layouts
import qs.singletons

// A settings page's root, as an anchor block (components/AnchorBlock.qml): it scrolls, keeps
// the page's margins, and draws its frame — the heading (`title`) and a banner under it
// (`banner`, a Component: the page's KeepSettingsBar) — above its content. Its path is the
// base the settings window gives the page, settings.<page id>; it offers `prepend` (first
// of the content, under the frame) and `append` (last).
//
//   SettingsPage {
//       anchors.fill: parent
//       title: "General"
//       context: ({ editIndex: root.editIndex })
//       SwitchRow { … }          // the content: laid out in a column, Layout.* apply
//   }
//
// Its content must not scroll itself: the page does.
AnchorBlock {
    id: root

    property string title: ""
    property Component banner: null
    property real spacing: 0
    default property alias content: _content.data
    // The hosts, for the core's tests
    readonly property alias prependHost: _prepend
    readonly property alias appendHost: _append
    readonly property alias flickable: _flickable

    kind: "page"
    placements: ["prepend", "append"]

    Flickable {
        id: _flickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: _column
            x: Theme.settings.pageMargin
            y: Theme.settings.pageMargin
            width: _flickable.width - 2 * Theme.settings.pageMargin
            spacing: 0

            // The frame: never content, so a prepended element comes under it
            Text {
                visible: root.title !== ""
                text: root.title
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                color: Theme.textSecondary
                Layout.fillWidth: true
                Layout.bottomMargin: 8
            }

            Loader {
                active: root.banner !== null
                visible: active
                sourceComponent: root.banner
                Layout.fillWidth: true
            }

            AnchorContent {
                id: _prepend
                block: root
                placement: "prepend"
                Layout.fillWidth: true
                Layout.bottomMargin: count > 0 ? 16 : 0
            }

            ColumnLayout {
                id: _content
                spacing: root.spacing
                Layout.fillWidth: true
            }

            AnchorContent {
                id: _append
                block: root
                placement: "append"
                Layout.fillWidth: true
                Layout.topMargin: count > 0 ? 16 : 0
            }
        }
    }
}
