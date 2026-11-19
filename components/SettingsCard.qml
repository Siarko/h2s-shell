import QtQuick
import QtQuick.Layouts
import qs.singletons

// A framed item on a settings page that opens (a saved network, a VPN), as an anchor block
// (components/AnchorBlock.qml). Its root is a plain column: the `before` host, its body — the
// frame: a header (the name and a line under it, on the right the primary controls
// (`primary`) and, opened, the secondary buttons stacked under them (`buttons`), each at its
// own width on one right edge) and a notice line; opened, its own rows (the content) — the
// `after` host. The parent sees one item, so it serves as a Repeater's delegate; a card
// repeated per item is named by its kind (`anchor: "card"`), its item in `context`.
//
// A card takes nothing inside itself: modules reach its opened part through its region
// `settings` (<card>.settings), a block of kind "region" around its rows — `prepend` above
// them, `append` under them. The region's elements exist only while the card is open:
// closing it destroys them, and what they showed starts anew next time. They get the card's
// context, and on an own-provider place the card's `scopeId`.
//
//   delegate: SettingsCard {
//       required property var modelData
//       anchor: "card"
//       Layout.fillWidth: true
//       title: modelData.name
//       open: page.openId === modelData.uuid
//       context: ({ networkId: modelData.uuid, name: modelData.name })
//       onToggleRequested: page.openId = open ? "" : modelData.uuid
//       primary: SmallButton { label: "Connect"; … }
//       SwitchRow { … }                          // its own rows: Layout.* apply
//   }
AnchorBlock {
    id: root

    property string title: ""
    property string subtitle: ""
    // In use (connected): the name bold, its line and the border in the accent's colours
    property bool active: false
    property bool open: false
    // A lasting line under the header, in the warning colour ("" none), with a button
    // (`noticeAction`, "" none) that emits noticeActionRequested
    property string notice: ""
    property string noticeAction: ""
    property bool noticeAvailable: true
    property real spacing: 6
    property real hostGap: 6
    // Its own rows, shown while open
    default property alias content: _rows.data
    // Right of the name, level with it
    property alias primary: _primary.data
    // Under `primary`, shown while open
    property alias buttons: _buttons.data
    signal toggleRequested()
    signal noticeActionRequested()

    // The region, the hosts and the frame, for the core's tests
    readonly property alias settingsRegion: _settings
    readonly property alias beforeHost: _before
    readonly property alias afterHost: _after
    readonly property alias frame: _frame

    kind: "card"
    placements: ["before", "after"]
    implicitWidth: _column.implicitWidth
    implicitHeight: _column.implicitHeight

    ColumnLayout {
        id: _column
        width: root.width
        spacing: 0

        AnchorContent {
            id: _before
            block: root
            placement: "before"
            Layout.fillWidth: true
            Layout.bottomMargin: count > 0 ? root.hostGap : 0
        }

        Rectangle {
            id: _frame
            Layout.fillWidth: true
            implicitHeight: _body.implicitHeight + 16
            radius: Theme.settings.cardRadius
            // Opened, a tint over the page's background, not Theme.surface: the buttons inside
            // are Theme.surface at rest, and on a card of the same colour they read as plain text
            color: root.open || _headerArea.lit ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0)
            border.width: Theme.border.width
            border.color: root.active ? Theme.accent : Theme.outline
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            ColumnLayout {
                id: _body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                spacing: root.spacing

                // Click for its opened part. The click area goes under the row, so the
                // buttons take their own clicks.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: _header.implicitHeight

                    PointerArea {
                        id: _headerArea
                        centred: false
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleRequested()
                    }

                    RowLayout {
                        id: _header
                        width: parent.width
                        spacing: 10

                        ColumnLayout {
                            id: _titleBlock
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.title
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: root.active
                                color: Theme.textPrimary
                            }
                            Text {
                                visible: root.subtitle !== ""
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.subtitle
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.active ? Theme.success : Theme.textMuted
                            }
                        }

                        // The primary controls and, opened, the secondary buttons under them,
                        // on one right edge — so the name keeps the left and elides instead of
                        // running under them
                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            spacing: 4

                            // At least as tall as the name and its line, the primary controls
                            // centred in it
                            Item {
                                id: _primarySlot
                                Layout.alignment: Qt.AlignRight
                                implicitWidth: _primary.implicitWidth
                                implicitHeight: Math.max(_primary.implicitHeight, _titleBlock.implicitHeight)

                                Row {
                                    id: _primary
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 10
                                }
                            }

                            ColumnLayout {
                                id: _buttons
                                visible: root.open
                                Layout.alignment: Qt.AlignRight
                                spacing: 4
                            }
                        }

                        // Level with the primary controls, not with the whole stack
                        Text {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredHeight: _primarySlot.implicitHeight
                            verticalAlignment: Text.AlignVCenter
                            text: root.open ? "▾" : "▸"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textMuted
                        }
                    }
                }

                // A lasting line: what needs the user, with its action
                RowLayout {
                    visible: root.notice !== ""
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        // May carry a provider's words: never read as markup
                        textFormat: Text.PlainText
                        text: root.notice
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.warning
                    }
                    SmallButton {
                        visible: root.noticeAction !== ""
                        label: root.noticeAction
                        available: root.noticeAvailable
                        onClicked: root.noticeActionRequested()
                    }
                }

                // The opened part: the region `settings` — its prepend host, the card's own
                // rows, its append host; the hosts build only while the card is open
                AnchorBlock {
                    id: _settings

                    readonly property alias prependHost: _prepend
                    readonly property alias appendHost: _append

                    visible: root.open
                    Layout.fillWidth: true
                    implicitHeight: _region.implicitHeight
                    anchor: "settings"
                    kind: "region"
                    placements: ["prepend", "append"]
                    context: root.context

                    ColumnLayout {
                        id: _region
                        width: _settings.width
                        spacing: root.spacing

                        AnchorContent {
                            id: _prepend
                            block: _settings
                            placement: "prepend"
                            active: root.open
                            spacing: root.spacing
                            Layout.fillWidth: true
                        }

                        ColumnLayout {
                            id: _rows
                            // No room and no spacing with no rows
                            visible: children.length > 0
                            Layout.fillWidth: true
                            spacing: root.spacing
                        }

                        AnchorContent {
                            id: _append
                            block: _settings
                            placement: "append"
                            active: root.open
                            spacing: root.spacing
                            Layout.fillWidth: true
                        }
                    }
                }
            }
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
