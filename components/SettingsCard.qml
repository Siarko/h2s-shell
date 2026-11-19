import QtQuick
import QtQuick.Layouts
import qs.singletons

// A framed item on a settings page that opens (a saved network, a VPN), as an anchor block
// (components/AnchorBlock.qml). Its root is a plain column: the `before` host, its body — the
// frame: a header (the name and a line under it — the line keeps its height when empty —,
// on the right its buttons in one row on the name's line, closed and open: `primary`, then
// `buttons`, then `lastButtons`, the one that removes the item; each at its own width, a
// hidden one takes no room) and a notice line; opened, its own rows (the content) — the `after`
// host. The parent sees one item, so it serves as a Repeater's delegate; a card repeated per
// item is named by its kind (`anchor: "card"`), its item in `context`.
//
// A card takes nothing inside itself: modules reach it through its regions, blocks of kind
// "region". `settings` (<card>.settings) is around its rows — `prepend` above them,
// `append` under them; its elements exist only while the card is open: closing it destroys
// them, and what they showed starts anew next time. `actions` (<card>.actions) is in the
// buttons' row, closed and open — `prepend` before the card's own `buttons`, `append` after
// them and before `lastButtons`; it takes the public SmallButton only (the table's `takes`),
// each at its own width, at most a third of the card (a longer label is cut), in the row's
// size; the card's own buttons keep their room, the modules' buttons get what is left of
// `buttonRoom` and are cut on the right beyond it. `title` (<card>.title) is on the name's
// line, closed and open — `append`, right after the name: its elements side by side in the
// one order, each as tall as the line (given its height, cut to it), at most `titleMaxWidth`
// (a quarter of the card) all together, cut on the right; room is kept for them, so the name
// is cut first, and they stay inside the name's part of the header, never over the card's own
// parts. Regions get the card's context, and on an own-provider place the card's `scopeId`.
//
// Repeated per item, it stands on a KeyedModel (its modelData the item's key), so that it
// keeps its item — and its region's elements — while other items come and go:
//
//   KeyedModel { id: _networks; values: page.networks; keyProp: "uuid" }
//   Repeater {
//       model: _networks.model
//       delegate: SettingsCard {
//           required property string modelData
//           readonly property var network: _networks.byKey[modelData] ?? ({})
//           anchor: "card"
//           Layout.fillWidth: true
//           title: network.name ?? ""
//           open: page.openId === network.uuid
//           context: ({ networkId: network.uuid, name: network.name })
//           onToggleRequested: page.openId = open ? "" : network.uuid
//           primary: SmallButton { label: "Connect"; … }
//           SwitchRow { … }                      // its own rows: Layout.* apply
//       }
//   }
//
// The notice's button is available while `noticeAvailable`, bound to the page's busy state
// (NetworkProfileCard: `noticeAvailable: !busy`).
//
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
    // Whether the notice's button can be clicked (bind it to the page's busy state)
    property bool noticeAvailable: true
    property real spacing: 6
    property real hostGap: 6
    // Its own rows, shown while open
    default property alias content: _rows.data
    // On the name's line, right of the name: the first of the card's buttons (the main one,
    // and the lock beside it)
    property alias primary: _primary.data
    // After `primary`, in the same row: the card's other buttons
    property alias buttons: _buttons.data
    // After those and the modules' buttons, last: the one that removes the item ("Forget")
    property alias lastButtons: _lastButtons.data
    // Between two buttons of the row
    readonly property real buttonGap: 6
    // The most a module's button in `actions` may be: a third of the card; a longer label is
    // cut
    readonly property real buttonMaxWidth: Math.floor(width / 3)
    // The most the modules' elements on the name's line take, all together: a quarter of the
    // card
    readonly property real titleMaxWidth: Math.floor(width / 4)
    // The most the buttons' row may take: what the name's part leaves — its least is the room
    // kept for the elements on the name's line — beside the arrow
    readonly property real buttonRoom: Math.max(0, _header.width - _arrow.implicitWidth - 2 * _header.spacing - _title.Layout.minimumWidth)
    // The most the primary controls may take: the room the card's other buttons leave (a
    // question asked there is cut to it)
    readonly property real primaryRoom: Math.max(0, Math.floor(buttonRoom) - _buttonsGap - _buttons.implicitWidth - _lastGap - _lastButtons.implicitWidth)
    signal toggleRequested()
    signal noticeActionRequested()

    // The regions, the hosts, the frame and the buttons' groups, for the core's tests
    readonly property alias settingsRegion: _settings
    readonly property alias actionsRegion: _actions
    readonly property alias titleRegion: _titleRegion
    readonly property alias buttonRow: _buttonRow
    readonly property alias buttonGroup: _buttons
    readonly property alias lastButtonGroup: _lastButtons
    readonly property alias beforeHost: _before
    readonly property alias afterHost: _after
    readonly property alias frame: _frame
    readonly property alias titleText: _title

    kind: "card"
    placements: ["before", "after"]

    // A module's button in `actions` that sets no size of its own is the row's size, as the
    // card's own are (the public SmallButton's `defaultSize`); one that sets `size` keeps it
    readonly property var _buttonProperties: ({ defaultSize: "m" })

    // The header's line: as tall as the name and the line under it, or the buttons if taller
    readonly property real _slotHeight: Math.max(_buttonRow.implicitHeight, _titleBlock.implicitHeight)
    // The gap before each group of the row: only for a group that shows, after one that does
    readonly property bool _primaryShown: _primary.implicitWidth > 0
    readonly property real _prependGap: _actionsPrepend.implicitWidth > 0 && _primaryShown ? buttonGap : 0
    readonly property real _buttonsGap: _buttons.implicitWidth > 0 && (_primaryShown || _actionsPrepend.implicitWidth > 0) ? buttonGap : 0
    readonly property real _appendGap: _actionsAppend.implicitWidth > 0
        && (_primaryShown || _actionsPrepend.implicitWidth > 0 || _buttons.implicitWidth > 0) ? buttonGap : 0
    readonly property real _lastGap: _lastButtons.implicitWidth > 0
        && (_primaryShown || _actionsPrepend.implicitWidth > 0 || _buttons.implicitWidth > 0 || _actionsAppend.implicitWidth > 0) ? buttonGap : 0
    // The card's own buttons keep their width; the modules' get what is left of the room
    readonly property real _ownButtonsWidth: _primary.implicitWidth + _buttonsGap + _buttons.implicitWidth + _lastGap + _lastButtons.implicitWidth
    readonly property real _prependRoom: Math.max(0, buttonRoom - _ownButtonsWidth - _prependGap)
    readonly property real _appendRoom: Math.max(0, _prependRoom - Math.min(_actionsPrepend.implicitWidth, _prependRoom) - _appendGap)

    // A button that names no vertical alignment of its own is centred on the row (a
    // horizontal one it names is kept)
    function _alignCentre(items) {
        for (const child of items) {
            if ((child.Layout.alignment & Qt.AlignVertical_Mask) === 0)
                child.Layout.alignment = child.Layout.alignment | Qt.AlignVCenter;
        }
    }
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
            // Only for what was built and shows: a refused or failed element has no size
            Layout.bottomMargin: implicitHeight > 0 ? root.hostGap : 0
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
                            // The name, and after it the region `title`: room is kept for
                            // its elements on the right (the padding), so the name is cut
                            // first. On the left as the card is laid out, a right-to-left name
                            // too (Qt would put it on the right, under the elements)
                            Text {
                                id: _title
                                Layout.fillWidth: true
                                Layout.minimumWidth: rightPadding
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                text: root.title
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: root.active
                                color: Theme.textPrimary
                                rightPadding: _titleRegion.width > 0 ? _titleRegion.width + _titleRegion.gap : 0

                                AnchorBlock {
                                    id: _titleRegion

                                    readonly property alias appendHost: _titleAppend
                                    readonly property real gap: 6

                                    // Right after the name as drawn: its whole width, or what is
                                    // left of the line beside the elements — on its right end
                                    // when it is drawn on the right after all (a mirrored layout)
                                    x: (_title.effectiveHorizontalAlignment === Text.AlignLeft
                                        ? Math.max(0, Math.min(_title.implicitWidth, _title.width) - _title.rightPadding)
                                        : _title.width - _title.rightPadding) + gap
                                    // A quarter of the card at most; the name's part of the header
                                    // is never narrower than the room kept for it (the name's
                                    // minimum width), so it covers none of the card's own parts
                                    width: Math.min(_titleAppend.implicitWidth, root.titleMaxWidth)
                                    height: _title.height
                                    clip: true
                                    anchor: "title"
                                    kind: "region"
                                    placements: ["append"]
                                    context: root.context

                                    AnchorContent {
                                        id: _titleAppend
                                        block: _titleRegion
                                        placement: "append"
                                        inline: true
                                        elementHeight: _title.height
                                        maxElementWidth: root.titleMaxWidth
                                        height: _title.height
                                    }
                                }
                            }
                            // Shown empty too: the header keeps its height
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.subtitle
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.active ? Theme.success : Theme.textMuted
                            }
                        }

                        // The buttons, in one row on the name's line, closed and open: the
                        // primary controls, then the region `actions` — its prepend host,
                        // the card's own buttons, its append host (the modules' buttons), then
                        // the button that removes the item, last whatever a module adds. Each
                        // at its own width, `buttonGap` apart; a group with nothing shown
                        // takes no room and no gap. Layouts, not positioners: each button gets
                        // a whole width, so its edges stand on whole pixels. Never wider than
                        // the room the name's part leaves (`buttonRoom`): the name is cut
                        // first; a module's buttons beyond the room are cut on the right
                        RowLayout {
                            id: _buttonRow
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredHeight: root._slotHeight
                            Layout.maximumWidth: root.buttonRoom
                            // A layout fills by default: this one keeps to its buttons
                            Layout.fillWidth: false
                            spacing: 0

                            // The groups as tall as the line: a button that names a vertical
                            // alignment of its own keeps it
                            RowLayout {
                                id: _primary
                                Layout.fillWidth: false
                                Layout.fillHeight: true
                                Layout.maximumHeight: Infinity
                                spacing: 10
                                onChildrenChanged: root._alignCentre(children)
                            }

                            AnchorBlock {
                                id: _actions

                                readonly property alias prependHost: _actionsPrepend
                                readonly property alias appendHost: _actionsAppend

                                Layout.fillHeight: true
                                Layout.maximumHeight: Infinity
                                implicitWidth: _actionRow.implicitWidth
                                implicitHeight: _actionRow.implicitHeight
                                anchor: "actions"
                                kind: "region"
                                placements: ["prepend", "append"]
                                context: root.context

                                RowLayout {
                                    id: _actionRow
                                    width: _actions.width
                                    height: _actions.height
                                    spacing: 0

                                    AnchorContent {
                                        id: _actionsPrepend
                                        block: _actions
                                        placement: "prepend"
                                        inline: true
                                        spacing: root.buttonGap
                                        maxElementWidth: root.buttonMaxWidth
                                        elementProperties: root._buttonProperties
                                        clip: width < implicitWidth
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.leftMargin: root._prependGap
                                        Layout.maximumWidth: root._prependRoom
                                    }

                                    RowLayout {
                                        id: _buttons
                                        Layout.fillWidth: false
                                        Layout.fillHeight: true
                                        Layout.maximumHeight: Infinity
                                        Layout.leftMargin: root._buttonsGap
                                        spacing: root.buttonGap
                                        onChildrenChanged: root._alignCentre(children)
                                    }

                                    AnchorContent {
                                        id: _actionsAppend
                                        block: _actions
                                        placement: "append"
                                        inline: true
                                        spacing: root.buttonGap
                                        maxElementWidth: root.buttonMaxWidth
                                        elementProperties: root._buttonProperties
                                        clip: width < implicitWidth
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.leftMargin: root._appendGap
                                        Layout.maximumWidth: root._appendRoom
                                    }

                                    RowLayout {
                                        id: _lastButtons
                                        Layout.fillWidth: false
                                        Layout.fillHeight: true
                                        Layout.maximumHeight: Infinity
                                        Layout.leftMargin: root._lastGap
                                        spacing: root.buttonGap
                                        onChildrenChanged: root._alignCentre(children)
                                    }
                                }
                            }
                        }

                        // Level with the buttons' row
                        Text {
                            id: _arrow
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredHeight: root._slotHeight
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
            // Only for what was built and shows: a refused or failed element has no size
            Layout.topMargin: implicitHeight > 0 ? root.hostGap : 0
        }
    }
}
