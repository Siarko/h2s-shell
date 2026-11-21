import QtQuick
import QtQuick.Layouts
import qs.singletons

// A framed item on a settings page that opens (a saved network, a VPN), as an anchor block
// (components/AnchorBlock.qml). Its root is a plain column: the `before` host, its body — the
// frame: a header (the name and a line under it — the line keeps its height when empty —,
// the arrow at the right, and its buttons in one row, closed and open: `primary`, then
// `buttons`, then `lastButtons`, the one that removes the item; each at its own width, a
// hidden one takes no room) and a notice line; opened, its own rows (the content) — the `after`
// host. The row stands on the name's line when it fits there beside the name's least and the
// arrow, else on a line of its own under the name, right-aligned; wider than the card, the
// primary controls take that line alone and the rest stand under them (`buttonPlace`). Its
// area takes the clicks that miss a button: only the rest of the header opens the card. The
// parent sees one item, so it serves as a Repeater's delegate; a card repeated per item is
// named by its kind (`anchor: "card"`), its item in `context`.
//
// A card takes nothing inside itself: modules reach it through its regions, blocks of kind
// "region". `settings` (<card>.settings) is around its rows — `prepend` above them,
// `append` under them; its elements exist only while the card is open: closing it destroys
// them, and what they showed starts anew next time. `actions` (<card>.actions) is in the
// buttons' row, closed and open — `prepend` before the card's own `buttons`, `append` after
// them and before `lastButtons`; it takes the public SmallButton only (the table's `takes`),
// each at its own width, at most a third of the card (a longer label is cut), in the row's
// size; the card's own buttons keep their room, the modules' buttons get what is left of a
// line (`buttonRoom`) and are cut on the right beyond it. `title` (<card>.title) is on the name's
// line, closed and open — `append`, right after the name: its elements side by side in the
// one order, each as tall as the line (given its height, cut to it), at most `titleMaxWidth`
// (a quarter of the card) all together, cut on the right; room is kept for them, so the name
// is cut first (and the buttons move under it sooner), and they stay inside the name's part of
// the header, never over the card's own parts. Regions get the card's context, and on an
// own-provider place the card's `scopeId`.
//
// The card's own parts of the name's line: `leading` before the name, centred on the name and
// its line (a module's icon), and `titleItems` right after the name, before the region
// `title` (marks with their tips); room is kept for both as for the region's elements. The
// name's colour and weight are `titleColor` and `titleBold`.
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
    // The name's colour and weight
    property color titleColor: Theme.textPrimary
    property bool titleBold: active
    // Before the name, centred on it and its line: the item's face (a module's icon)
    property alias leading: _leading.data
    // Right after the name, before the modules' elements there: the card's own (marks)
    property alias titleItems: _titleItems.data
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
    // How the buttons' row stands, from its width alone: "nameLine" — on the name's line, when
    // it fits beside the name's least (`nameMinimumWidth` and the room kept for the elements on
    // the name's line) and the arrow; "ownLine" — on a line of its own under the name and its
    // line, right-aligned, when it fits the card's width; "twoLines" — still wider (a long
    // question asked by the primary button): the primary controls on that line alone, the
    // other buttons on a line under them
    readonly property string buttonPlace: _rowWidth <= _lineRoom + 0.01 ? "nameLine" : _rowWidth <= buttonRoom + 0.01 ? "ownLine" : "twoLines"
    // The least the name keeps on its line before the buttons move under it: a few characters
    readonly property real nameMinimumWidth: Math.ceil(_nameMetrics.averageCharacterWidth * 6)
    // The most a line of buttons may take: the card's width inside its margins
    readonly property real buttonRoom: Math.max(0, Math.floor(_header.width))
    // The most the primary controls may take: a whole line (on a line alone if need be; a
    // question asked there wraps beyond it)
    readonly property real primaryRoom: buttonRoom
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
    readonly property alias leadingItem: _leading
    readonly property alias titleItemsRow: _titleItems

    kind: "card"
    placements: ["before", "after"]

    // A module's button in `actions` that sets no size of its own is the row's size, as the
    // card's own are (the public SmallButton's `defaultSize`); one that sets `size` keeps it
    readonly property var _buttonProperties: ({ defaultSize: "m" })

    readonly property bool _onNameLine: buttonPlace === "nameLine"
    // The header's line: as tall as the name and the line under it, or the buttons on it if
    // taller
    readonly property real _slotHeight: _onNameLine ? Math.max(_buttonRow.implicitHeight, _titleBlock.implicitHeight) : _titleBlock.implicitHeight
    // The room on the name's line for the buttons: what the name's least and the arrow leave
    readonly property real _lineRoom: Math.max(0, _header.width - _arrow.implicitWidth - 2 * _header.spacing - _title.Layout.minimumWidth - _leadingWidth)
    // The room `leading` takes before the name: none when empty
    readonly property real _leadingWidth: _leading.implicitWidth > 0 ? Math.ceil(_leading.implicitWidth) + _header.spacing : 0
    // The gap between the primary controls and the rest, on one line
    readonly property bool _primaryShown: _primary.implicitWidth > 0
    readonly property real _actionsGap: _primaryShown && _actions.implicitWidth > 0 ? buttonGap : 0
    // The row's width on one line
    readonly property real _rowWidth: _primary.implicitWidth + _actionsGap + _actions.implicitWidth
    // The gap before each group after the primary controls: only for a group that shows, after
    // one that does
    readonly property real _buttonsGap: _buttons.implicitWidth > 0 && _actionsPrepend.implicitWidth > 0 ? buttonGap : 0
    readonly property real _appendGap: _actionsAppend.implicitWidth > 0
        && (_actionsPrepend.implicitWidth > 0 || _buttons.implicitWidth > 0) ? buttonGap : 0
    readonly property real _lastGap: _lastButtons.implicitWidth > 0
        && (_actionsPrepend.implicitWidth > 0 || _buttons.implicitWidth > 0 || _actionsAppend.implicitWidth > 0) ? buttonGap : 0
    // The card's own buttons keep their width; the modules' get what is left of a line
    readonly property real _ownButtonsWidth: _buttons.implicitWidth + _buttonsGap + _lastGap + _lastButtons.implicitWidth
    readonly property real _prependRoom: Math.max(0, buttonRoom - _ownButtonsWidth)
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
                // buttons take their own clicks; the row's own area takes the clicks that miss
                // a button (its gaps, the lock), so a near miss does nothing
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

                    // Its hover too, with the plain arrow: the pointer in a gap of the row
                    // is not over the header, so the card is not tinted for a click that
                    // does nothing
                    MouseArea {
                        objectName: "buttonRowArea"
                        hoverEnabled: true
                        cursorShape: Qt.ArrowCursor
                        x: _buttonRow.x
                        y: _buttonRow.y
                        width: _buttonRow.width
                        height: _buttonRow.height
                    }

                    // The name and its line on the left, the arrow at the right; the buttons
                    // where `buttonPlace` puts them: on the name's line between the two, or
                    // under both, right-aligned. Placed by hand: the row changes lines
                    Item {
                        id: _header
                        readonly property real spacing: 10
                        width: parent.width
                        implicitHeight: root._onNameLine ? root._slotHeight : _buttonRow.y + _buttonRow.implicitHeight

                        // The card's own item before the name, centred on the name and its line
                        Row {
                            id: _leading
                            x: 0
                            y: Math.round((_titleBlock.implicitHeight - height) / 2)
                        }

                        ColumnLayout {
                            id: _titleBlock
                            x: root._leadingWidth
                            // The rest of the name's line: up to the buttons on it, else up to
                            // the arrow
                            width: Math.max(0, Math.floor((root._onNameLine ? _buttonRow.x : _arrow.x) - _header.spacing - x))
                            spacing: 1
                            // The name, and after it the region `title`: room is kept for
                            // its elements on the right (the padding), so the name is cut
                            // first. On the left as the card is laid out, a right-to-left name
                            // too (Qt would put it on the right, under the elements)
                            Text {
                                id: _title
                                Layout.fillWidth: true
                                Layout.minimumWidth: rightPadding + root.nameMinimumWidth
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                text: root.title
                                textFormat: Text.PlainText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: root.titleBold
                                color: root.titleColor
                                rightPadding: _itemsRoom + (_titleRegion.width > 0 ? _titleRegion.width + _titleRegion.gap : 0)

                                // Where the name ends as drawn: its whole width, or what is left
                                // of the line beside what follows it — on its right end when it
                                // is drawn on the right after all (a mirrored layout)
                                readonly property real _nameEnd: effectiveHorizontalAlignment === Text.AlignLeft
                                    ? Math.max(0, Math.min(implicitWidth, width) - rightPadding) : width - rightPadding
                                readonly property real _itemsRoom: _titleItems.implicitWidth > 0 ? Math.ceil(_titleItems.implicitWidth) + _titleRegion.gap : 0

                                // The card's own items right after the name, as tall as its line
                                RowLayout {
                                    id: _titleItems
                                    x: _title._nameEnd + _titleRegion.gap
                                    height: _title.height
                                    spacing: _titleRegion.gap
                                }

                                AnchorBlock {
                                    id: _titleRegion

                                    readonly property alias appendHost: _titleAppend
                                    readonly property real gap: 6

                                    // Right after the name and the card's own items
                                    x: _title._nameEnd + _title._itemsRoom + gap
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

                        // The buttons: the primary controls, then the region `actions` — its
                        // prepend host, the card's own buttons, its append host (the modules'
                        // buttons), then the button that removes the item. Each at its own
                        // width, `buttonGap` apart; a group with nothing shown takes no room and
                        // no gap. Layouts, not positioners: each button gets a whole width, so
                        // its edges stand on whole pixels. On one line, or ("twoLines") the
                        // primary controls on a line of their own above the rest, each line
                        // right-aligned. A module's buttons beyond a line's room are cut on
                        // the right
                        GridLayout {
                            id: _buttonRow
                            x: Math.round(root._onNameLine ? _arrow.x - _header.spacing - width : _header.width - width)
                            y: root._onNameLine ? 0 : Math.ceil(_titleBlock.implicitHeight + root.spacing)
                            width: Math.min(Math.ceil(implicitWidth), root.buttonRoom)
                            height: root._onNameLine ? root._slotHeight : implicitHeight
                            columns: 2
                            columnSpacing: 0
                            rowSpacing: root.buttonGap

                            // The groups as tall as their line: a button that names a vertical
                            // alignment of its own keeps it
                            RowLayout {
                                id: _primary
                                Layout.row: 0
                                Layout.column: 0
                                Layout.alignment: Qt.AlignRight
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

                                Layout.row: root.buttonPlace === "twoLines" ? 1 : 0
                                Layout.column: root.buttonPlace === "twoLines" ? 0 : 1
                                Layout.alignment: Qt.AlignRight
                                Layout.leftMargin: root.buttonPlace === "twoLines" ? 0 : root._actionsGap
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

                        // On the name's line, level with the buttons on it
                        Text {
                            id: _arrow
                            x: _header.width - implicitWidth
                            height: root._slotHeight
                            verticalAlignment: Text.AlignVCenter
                            text: root.open ? "▾" : "▸"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textMuted
                        }
                    }

                    FontMetrics {
                        id: _nameMetrics
                        font: _title.font
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
