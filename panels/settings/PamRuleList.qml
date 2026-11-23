import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// One service's sign-in rules as a list of rows (PamRuleRules' row model), tried from the
// top: each row its drag handle, its method, its control word and its details as chips, an
// arrow that opens it and its "×". An opened row offers the control words its method takes,
// with the picked one's explanation, and the method's details; a raw line opens to its text
// and how it reads; the fixed last row ("Password (as the system)") has a lock for a handle,
// does not move, nothing moves below it, and its "×" asks in the Settings modal. "＋ Add a
// row" lists the methods, those the machine lacks off with their reason; a new row opens.
//
// The list is the owner's: every change comes back as `edited(rows)`, the whole new list,
// and `rows` follows. Nothing here reads or writes PAM. What it shows and allows is
// PamRuleViewRules'.
//
//   PamRuleList {
//       title: "sudo"
//       rows: page.sudoRows
//       facts: page.facts
//       result: PamRuleRules.check(page.sudoRows, page.facts)
//       modalHost: page.modalHost
//       onEdited: rows => page.sudoRows = rows
//   }
Item {
    id: root

    // Names the list in the fixed row's removal question
    property string title: ""
    property var rows: []
    // PamRuleRules.check's facts: { system, fingerprint, securityKey, faillockPresent, faillock }
    property var facts: ({})
    // PamRuleRules.check's result for these rows: a row it names gets a red or warning border
    property var result: ({ refusals: [], warnings: [] })
    // Where the fixed row's removal is asked (SettingsModalHost)
    property var modalHost: null
    // Shown only: no handle, arrow, "×" or add row
    property bool readOnly: false
    // The system's own auth lines, shown when the fixed row is opened
    property var systemLines: []

    signal edited(var rows)

    // The rows as a JS array: a list that came back through a signal or a property of
    // another object may be a sequence, which PamRuleRules' edits do not take for a list
    readonly property var _rows: Array.isArray(rows) ? rows : Array.from(rows ?? [])

    // A row's handle is held: the page must not scroll (its Flickable is made non-interactive
    // meanwhile, and the handle keeps the drag from it)
    readonly property bool dragging: _dragIndex >= 0
    // The rows opened, { id: true }
    property var openIds: ({})
    readonly property alias addOpen: _picker.open

    Layout.fillWidth: true
    implicitHeight: _card.height

    KeyedModel {
        id: _keyed
        values: root._rows
        keyProp: "id"
    }

    function toggle(id) {
        openIds = Object.assign({}, openIds, { [id]: openIds[id] !== true });
    }

    // Edits run in the list's scope and last in a handler: the new list may remove the row
    // whose handler called them
    function _change(id, change) {
        edited(PamRuleRules.changeRow(_rows, id, change));
    }

    function _remove(id) {
        edited(PamRuleRules.removeRow(_rows, id, false));
    }

    function _add(method) {
        _picker.open = false;
        const outcome = PamRuleViewRules.added(_rows, method, facts);
        if (!outcome)
            return;
        openIds = Object.assign({}, openIds, { [outcome.id]: true });
        edited(outcome.rows);
    }

    function _askRemoveFixed() {
        if (!modalHost)
            return;
        modalHost.ask(PamRuleViewRules.removeFixedQuestion(title, _rows, facts), answer => {
            if (answer.cancelled || answer.button !== "remove")
                return;
            root.edited(PamRuleRules.removeRow(root._rows, answer.subject.id, true));
        });
    }

    // ── Dragging by the handle ──

    property int _dragIndex: -1
    property int _dropSlot: -1
    property var _flickable: null
    property bool _flickableWasInteractive: true

    function _beginDrag(index) {
        _dragIndex = index;
        _dropSlot = index;
        _flickable = null;
        for (let item = root.parent; item; item = item.parent) {
            if (item.contentY !== undefined && item.flick !== undefined) {
                _flickable = item;
                _flickableWasInteractive = item.interactive;
                item.interactive = false;
                break;
            }
        }
        _autoScroll.begin();
    }

    // The slot for a pointer at sceneY, from the rows' real places: an opened row is taller
    function _track(sceneY) {
        const middles = [];
        for (let i = 0; i < _repeater.count; i++) {
            const row = _repeater.itemAt(i);
            middles.push(row ? row.y + row.lineHeight / 2 : Infinity);
        }
        _dropSlot = PamRuleViewRules.dropSlot(_rows, middles, _rowColumn.mapFromItem(null, 0, sceneY).y);
    }

    function _endDrag(dropping) {
        const from = _dragIndex, slot = _dropSlot;
        _autoScroll.end();
        _dragIndex = -1;
        _dropSlot = -1;
        if (_flickable)
            _flickable.interactive = _flickableWasInteractive;
        _flickable = null;
        const next = dropping ? PamRuleViewRules.dropped(_rows, from, slot) : null;
        if (next)
            edited(next);
    }

    Component.onDestruction: if (_flickable) _flickable.interactive = _flickableWasInteractive

    DragAutoScroll {
        id: _autoScroll
        item: _rowColumn
        onScrolled: root._track(sceneY)
    }

    component Caption: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }

    // A detail chip of a closed row
    component Chip: Rectangle {
        property string text: ""
        implicitWidth: _chipText.implicitWidth + 12
        implicitHeight: _chipText.implicitHeight + 4
        radius: height / 2
        color: Theme.fill
        Text {
            id: _chipText
            anchors.centerIn: parent
            text: parent.text
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXSmall
            color: Theme.textSecondary
        }
    }

    // A whole-number detail that may be unlimited: the field (the settings pages' outlined
    // field, on the sunken colour so it stands out of the row) and "No limit". While no limit
    // is on, the field keeps the last number, dimmed, for when it is turned off again.
    component LimitDetail: RowLayout {
        id: _limit
        property string rowId: ""
        property string method: ""
        property string detail: ""
        property var value: undefined
        readonly property var spec: PamRuleViewRules.range(method, detail)
        readonly property bool unlimited: PamRuleViewRules.unlimited(value)
        property int lastValue: spec ? spec.initial : 0
        function _remember() {
            if (typeof value === "number" && value >= 0)
                lastValue = value;
        }
        onValueChanged: _remember()
        Component.onCompleted: _remember()
        spacing: 8

        Text {
            text: _limit.spec?.label ?? ""
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
        }
        InputField {
            id: _field
            objectName: "field:" + _limit.rowId + "/" + _limit.detail
            implicitWidth: 60
            text: String(_limit.lastValue)
            outlined: true
            fieldColor: Theme.surfaceSunken
            enabled: !_limit.unlimited
            opacity: enabled ? 1 : 0.4
            input.horizontalAlignment: TextInput.AlignHCenter
            input.inputMethodHints: Qt.ImhDigitsOnly
            input.validator: IntValidator { bottom: _limit.spec?.min ?? 0; top: _limit.spec?.max ?? 0 }
            problem: enabled && !input.acceptableInput
            onEditingFinished: {
                const change = PamRuleViewRules.typedChange(_limit.method, _limit.detail, text);
                if (change && change[_limit.detail] !== _limit.value)
                    root._change(_limit.rowId, { details: change });
            }
        }
        Text {
            visible: (_limit.spec?.unit ?? "") !== ""
            text: _limit.spec?.unit ?? ""
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
            opacity: _limit.unlimited ? 0.4 : 1
        }
        Checkbox {
            objectName: "noLimit:" + _limit.rowId + "/" + _limit.detail
            label: "No limit"
            checked: _limit.unlimited
            onToggled: root._change(_limit.rowId, { details: PamRuleViewRules.limitChange(_limit.method, _limit.detail, !_limit.unlimited, _field.text) })
        }
    }

    // One row: its line, and under it what it opens to
    component RuleRow: Rectangle {
        id: _row
        required property string modelData
        required property int index
        readonly property var row: _keyed.byKey[modelData] ?? ({ method: "", details: {} })
        readonly property bool fixed: PamRuleRules.isFixed(row)
        readonly property bool raw: row.method === "raw"
        readonly property bool opened: root.openIds[modelData] === true
        readonly property string opens: PamRuleViewRules.opened(row)
        readonly property string checkState: PamRuleViewRules.rowState(root.result, modelData)
        readonly property real lineHeight: _line.height + 12

        objectName: "row:" + modelData
        width: _rowColumn.width
        implicitHeight: _content.implicitHeight + 12
        height: implicitHeight
        radius: Theme.settings.cardRadius
        color: Theme.surface
        border.width: Theme.border.width
        border.color: checkState === "refused" ? Theme.error : checkState === "warned" ? Theme.warning : Theme.divider
        opacity: root._dragIndex === index ? 0.35 : 1

        // Where the dragged row would drop: above this row, or below it as the last
        Rectangle {
            objectName: "dropLine:" + _row.index
            visible: PamRuleViewRules.dropLineAt(root._dragIndex, root._dropSlot, _row.index)
            anchors { bottom: parent.top; bottomMargin: 1; horizontalCenter: parent.horizontalCenter }
            width: parent.width - 16
            height: 2
            radius: 1
            color: Theme.accent
            z: 10
        }
        Rectangle {
            visible: _row.index === _repeater.count - 1 && PamRuleViewRules.dropLineAt(root._dragIndex, root._dropSlot, _repeater.count)
            anchors { top: parent.bottom; topMargin: 1; horizontalCenter: parent.horizontalCenter }
            width: parent.width - 16
            height: 2
            radius: 1
            color: Theme.accent
            z: 10
        }

        ColumnLayout {
            id: _content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6; leftMargin: 8; rightMargin: 8 }
            spacing: 8

            RowLayout {
                id: _line
                Layout.fillWidth: true
                spacing: 8

                // The handle; the fixed row has a lock and does not move
                Text {
                    id: _handle
                    readonly property bool movable: !_row.fixed && !root.readOnly && PamRuleRules.canMove(_row.row)
                    text: _row.fixed ? PamRuleViewRules.icon("system") : "⠿"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    color: _handleArea.lit && movable ? Theme.textSecondary : Theme.textDisabled
                    horizontalAlignment: Text.AlignHCenter
                    Layout.preferredWidth: 16
                    PointerArea {
                        id: _handleArea
                        objectName: "handle:" + _row.modelData
                        enabled: _handle.movable
                        cursorShape: Qt.SizeVerCursor
                        // Keeps the drag from the settings page's Flickable
                        preventStealing: true
                        onPressed: root._beginDrag(_row.index)
                        onPositionChanged: {
                            if (root._dragIndex < 0)
                                return;
                            const sceneY = mapToItem(null, 0, mouseY).y;
                            root._track(sceneY);
                            _autoScroll.update(sceneY);
                        }
                        onReleased: root._endDrag(true)
                        // A drag taken away ends where it was
                        onCanceled: root._endDrag(true)
                    }
                }
                Pill {
                    objectName: "method:" + _row.modelData
                    label: PamRuleViewRules.icon(_row.row.method) + "  " + PamRuleViewRules.label(_row.row.method)
                    size: "m"
                    fontSize: Theme.fontSizeBody
                    onClicked: if (!root.readOnly) root.toggle(_row.modelData)
                }
                // A raw line shows itself where the word would be
                Text {
                    visible: _row.raw
                    Layout.fillWidth: true
                    Layout.maximumWidth: 420
                    text: String(_row.row.details?.text ?? "").slice(0, PamRuleRules.maxRawLength)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textPrimary
                }
                Pill {
                    objectName: "control:" + _row.modelData
                    visible: !_row.fixed && !_row.raw
                    label: _row.row.control ?? ""
                    picked: true
                    size: "m"
                    tooltip: PamRuleRules.explanation(_row.row.control)
                    onClicked: if (!root.readOnly) root.toggle(_row.modelData)
                }
                Repeater {
                    model: ScriptModel { values: PamRuleViewRules.chips(_row.row, root.facts) }
                    Chip {
                        required property string modelData
                        objectName: "chip"
                        text: modelData
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    objectName: "arrow:" + _row.modelData
                    visible: !root.readOnly
                    text: _row.opened ? "▾" : "▸"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    color: _openArea.lit ? Theme.textPrimary : Theme.textSecondary
                    PointerArea {
                        id: _openArea
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggle(_row.modelData)
                    }
                }
                DeleteButton {
                    objectName: _row.fixed ? "" : "remove:" + _row.modelData
                    visible: !root.readOnly && !_row.fixed
                    label: "×"
                    fontSize: Theme.fontSizeBody
                    cancelTip: "Cancel — keep the row"
                    onConfirmed: root._remove(_row.modelData)
                }
                // The fixed row's "×": what goes with it needs explaining, so the modal asks
                SmallButton {
                    objectName: _row.fixed ? "remove:" + _row.modelData : ""
                    visible: !root.readOnly && _row.fixed
                    label: "×"
                    kind: "delete"
                    fontSize: Theme.fontSizeBody
                    onClicked: root._askRemoveFixed()
                }
            }

            // Opened: the control words its method takes, the picked one explained, its details
            ColumnLayout {
                visible: _row.opened && _row.opens === "rule"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.bottomMargin: 4
                spacing: 6

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: ScriptModel { values: PamRuleViewRules.controlsFor(_row.row.method) }
                        Pill {
                            required property string modelData
                            objectName: "word:" + _row.modelData + "/" + modelData
                            label: modelData
                            picked: _row.row.control === modelData
                            tooltip: PamRuleRules.explanation(modelData)
                            onClicked: if (!picked) root._change(_row.modelData, { control: modelData })
                        }
                    }
                }
                Caption {
                    objectName: "explanation:" + _row.modelData
                    Layout.fillWidth: true
                    color: Theme.textSecondary
                    text: PamRuleRules.explanation(_row.row.control)
                }
                RowLayout {
                    visible: _row.row.method === "fingerprint"
                    spacing: 24
                    LimitDetail {
                        rowId: _row.modelData
                        method: "fingerprint"
                        detail: "timeout"
                        value: _row.row.details?.timeout
                    }
                    LimitDetail {
                        rowId: _row.modelData
                        method: "fingerprint"
                        detail: "tries"
                        value: _row.row.details?.tries
                    }
                }
                Checkbox {
                    objectName: "pin:" + _row.modelData
                    visible: _row.row.method === "securityKey"
                    label: PamRuleRules.methods.securityKey.details.pin.label
                    checked: _row.row.details?.pin === true
                    onToggled: root._change(_row.modelData, { details: { pin: !checked } })
                }
                RowLayout {
                    visible: _row.row.method === "password" && PamRuleRules.detailOffered("password", "counted", root.facts)
                    Layout.fillWidth: true
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: PamRuleRules.methods.password.details.counted.label
                            textFormat: Text.PlainText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                        }
                        Caption {
                            Layout.fillWidth: true
                            text: PamRuleRules.countedHint(root.facts?.faillock ?? null)
                        }
                    }
                    ToggleSwitch {
                        objectName: "counted:" + _row.modelData
                        checked: _row.row.details?.counted === true
                        onToggled: root._change(_row.modelData, { details: { counted: !checked } })
                    }
                }
            }

            // A raw line opened: its text, and how it reads
            ColumnLayout {
                visible: _row.opened && _row.opens === "raw"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.bottomMargin: 4
                spacing: 4
                InputField {
                    objectName: "line:" + _row.modelData
                    Layout.fillWidth: true
                    text: String(_row.row.details?.text ?? "")
                    fontSize: Theme.fontSizeSmall
                    outlined: true
                    fieldColor: Theme.surfaceSunken
                    input.maximumLength: PamRuleRules.maxRawLength
                    onEditingFinished: if (text !== (_row.row.details?.text ?? "")) root._change(_row.modelData, { details: { text: text } })
                }
                Caption {
                    readonly property var reading: PamRuleViewRules.rawReading(_row.row.details?.text ?? "", root.facts)
                    objectName: "reading:" + _row.modelData
                    Layout.fillWidth: true
                    color: reading.problem ? Theme.error : Theme.textMuted
                    text: reading.text
                }
            }

            // The fixed row opened: what it is
            ColumnLayout {
                visible: _row.opened && _row.opens === "fixed"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.bottomMargin: 4
                spacing: 2
                Caption {
                    Layout.fillWidth: true
                    color: Theme.textSecondary
                    text: "The system's own lines, kept as they are."
                }
                Repeater {
                    model: ScriptModel { values: (root.systemLines ?? []).map(line => String(line)) }
                    Caption {
                        required property string modelData
                        Layout.fillWidth: true
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        text: modelData
                    }
                }
            }
        }
    }

    Rectangle {
        id: _card
        width: root.width
        height: _cardColumn.implicitHeight + 12
        radius: Theme.settings.cardRadius
        color: Theme.surfaceSunken
        border.width: Theme.border.width
        border.color: Theme.divider

        Column {
            id: _cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 4

            Column {
                id: _rowColumn
                width: parent.width
                spacing: 4
                Repeater {
                    id: _repeater
                    model: _keyed.model
                    RuleRow {}
                }
            }

            Item {
                id: _addRow
                objectName: "addRow"
                visible: !root.readOnly
                width: parent.width
                height: 30
                Text {
                    anchors.centerIn: parent
                    text: "＋ Add a row"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: _addArea.lit ? Theme.textPrimary : Theme.textSecondary
                }
                PointerArea {
                    id: _addArea
                    centred: false
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: _picker.open = !_picker.open
                }
            }
        }
    }

    // The methods, floating over what is below
    FloatingList {
        id: _picker
        anchorItem: _addRow
        listWidth: Math.min(420, _addRow.width)
        maximumHeight: 360
        onClosed: open = false

        Repeater {
            model: ScriptModel { values: PamRuleRules.addOrder }
            Rectangle {
                id: _option
                required property string modelData
                readonly property var option: PamRuleViewRules.addOptions(root.facts).find(item => item.method === modelData) ?? ({})
                readonly property bool available: option.available === true
                objectName: "add:" + modelData
                width: parent ? parent.width : 0
                height: 44
                radius: Theme.listItem.radius
                color: _optionArea.lit && available ? Theme.surfaceHover : Theme.surfaceHoverClear
                opacity: available ? 1 : 0.5

                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    spacing: 10
                    // One icon column: a fixed box, so a wide glyph does not push its text
                    Item {
                        objectName: "addIcon"
                        Layout.preferredWidth: 24
                        Layout.minimumWidth: 24
                        Layout.maximumWidth: 24
                        implicitHeight: 24
                        Text {
                            anchors.centerIn: parent
                            text: PamRuleViewRules.icon(_option.modelData)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.textSecondary
                        }
                    }
                    ColumnLayout {
                        objectName: "addTexts"
                        Layout.fillWidth: true
                        spacing: 0
                        // Both texts fill the column: else the shorter sits further in
                        Text {
                            Layout.fillWidth: true
                            text: _option.option.label ?? ""
                            textFormat: Text.PlainText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                        }
                        Caption {
                            Layout.fillWidth: true
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                            text: _option.option.note ?? ""
                        }
                    }
                }
                PointerArea {
                    id: _optionArea
                    centred: false
                    anchors.fill: parent
                    cursorShape: _option.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (_option.available) root._add(_option.modelData)
                }
            }
        }
    }
}
