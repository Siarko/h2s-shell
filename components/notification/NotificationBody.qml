import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// A notification card's body (NotificationCard): the body's markup made safe, its links
// (opened, or asked about by the card) with where each goes on hover, selectable text, and
// a box that caps it at the card's bodyMaxLines lines; a longer body scrolls inside it, by a
// wheel, a touchpad or a finger, with a fade at the edge where there is more.
Item {
    id: _bodyBox

    // The card it is the body of (NotificationCard)
    required property Item card
    // The text, for the card: its lines decide whether the body is cut
    readonly property alias edit: _bodyEdit
    // How it shows under the card's cap (NotificationRules.bodyView)
    readonly property var view: NotificationRules.bodyView(card._body.length > 0 ? _bodyEdit.lineCount : 0,
        card.bodyMaxLines, _bodyEdit.implicitHeight)
    // How far a cut body is scrolled, in pixels from its start
    property real offset: 0
    readonly property real _hidden: Math.max(0, _bodyEdit.implicitHeight - height)
    // More of a cut body above or below what shows: a fade at that edge
    readonly property bool moreAbove: view.cut && offset > 0.5
    readonly property bool moreBelow: view.cut && offset < _hidden - 0.5

    function scrollBy(delta) {
        offset = NotificationRules.bodyScroll(offset, delta, _bodyEdit.implicitHeight, height);
    }
    // Another text, cap or size: still within the text (a new notification starts at the
    // top: the card sets it)
    onViewChanged: scrollBy(0)
    onHeightChanged: scrollBy(0)

    // Colours for the body's links and image rows (NotificationMarkup.richText): plain
    // "#rrggbb" — the image row's tint mixed with the card, as Qt's table background takes
    // no alpha
    readonly property var _markupColors: ({
        link: Theme.accent.toString(),
        unusualLink: Theme.warning.toString(),
        imageRow: Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.12)).toString(),
        imageGlyph: Theme.accent.toString(),
        address: Theme.textMuted.toString()
    })

    readonly property var _imageLinks: NotificationMarkup.imageLinks(card._body)
    Layout.fillWidth: true
    visible: _bodyBox.card._body.length > 0
    // A line's height as the text lays it out (taller than the font's line
    // spacing, which would cut the last line that fits)
    implicitHeight: view.height
    clip: view.cut

    TextEdit {
        id: _bodyEdit
        selectionColor: Theme.selection
        selectedTextColor: Theme.selectedText
        // The body's markup, made safe: formatting, links, image rows
        // (NotificationMarkup)
        textFormat: TextEdit.RichText
        text: NotificationMarkup.richText(_bodyBox.card._body, _bodyBox._markupColors)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        anchors.left: parent.left
        anchors.right: parent.right
        y: -_bodyBox.offset
        // A word longer than the line is broken, not cut off at the side
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        readOnly: true
        selectByMouse: true

        // A selection made in a cut body (dragged past its edge, or by keys) keeps its moving
        // end in view
        onCursorRectangleChanged: {
            if (!_bodyBox.view.cut || selectedText === "")
                return;
            const rect = cursorRectangle;
            if (rect.y < _bodyBox.offset)
                _bodyBox.offset = rect.y;
            else if (rect.y + rect.height > _bodyBox.offset + _bodyBox.height)
                _bodyBox.scrollBy(_bodyBox.offset + _bodyBox.height - rect.y - rect.height);
        }

        onSelectedTextChanged: {
            if (selectedText !== "")
                _bodyBox.card._activeEdit = _bodyEdit;
            else if (_bodyBox.card._activeEdit === _bodyEdit)
                _bodyBox.card._selectionClearedAt = Date.now();
        }

        // Text stays selectable by dragging, but over a link, or on a card
        // that is clicked, the pointer is a hand, not a text cursor
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: _bodyBox.card._defaultAction !== null || _bodyEdit.hoveredLink !== ""
                ? Qt.PointingHandCursor : Qt.IBeamCursor
        }

        // A link clicked: rich text takes that click itself and reports it
        // here — opened, or asked about — and it is not the card's default
        // action
        onLinkActivated: link => _bodyBox.card._openLink(link)

        // On the text itself: the text takes the press for selecting, so a
        // handler further up never sees the click. A handler of the same item
        // sees it first, and a drag (a selection) is no tap. Not on a link.
        TapHandler {
            enabled: _bodyBox.card._defaultAction !== null
            onTapped: eventPoint => {
                if (_bodyEdit.linkAt(eventPoint.position.x, eventPoint.position.y) === "")
                    _bodyBox.card._activateDefault();
            }
        }

        // Where a link goes, on hover — a link's text can say anything
        HoverTip {
            target: _bodyEdit
            // Not on an image row's link: the row shows its address
            shown: _bodyEdit.hoveredLink !== "" && !_bodyBox._imageLinks.includes(_bodyEdit.hoveredLink)
            text: _bodyEdit.hoveredLink
            // Room for an address, broken anywhere when it is longer
            maxWidth: 420
            delay: 300
            // Over the line of the link under the pointer, at the pointer
            anchorRect: {
                const point = _bodyHover.point.position;
                const line = _bodyEdit.positionToRectangle(_bodyEdit.positionAt(point.x, point.y));
                return Qt.rect(point.x, line.y, 0, line.height);
            }
        }

        HoverHandler {
            id: _bodyHover
        }
    }

    // A wheel or a touchpad over a cut body scrolls it. Where it cannot move further that
    // way the list it stands in (the centre's) moves instead: a handler that takes the
    // wheel passes none of it on, so the list would stop under the pointer
    WheelScroll {
        target: null
        enabled: _bodyBox.view.cut
        onWheel: event => {
            const delta = step(event);
            const before = _bodyBox.offset;
            _bodyBox.scrollBy(delta);
            if (_bodyBox.offset === before)
                _bodyBox._scrollList(delta);
        }
    }

    // The nearest Flickable around the card (the centre's list), null in a toast
    function _list() {
        for (let item = card.parent; item; item = item.parent) {
            if (item instanceof Flickable)
                return item;
        }
        return null;
    }
    // A list's contentY moved to `contentY`, within its ends
    function _placeList(list, contentY) {
        const top = list.originY - list.topMargin;
        const bottom = list.originY + list.contentHeight + list.bottomMargin - list.height;
        list.contentY = Math.max(top, Math.min(Math.max(top, bottom), contentY));
    }
    function _scrollList(delta) {
        const list = _list();
        if (list)
            _placeList(list, list.contentY - delta);
    }

    // A finger dragged up or down scrolls it; what of the drag goes past the body's end
    // moves the list it stands in, as the wheel does. Over the text, holding only the
    // handler: a press still reaches the text and its links; a sideways drag is the card's
    // swipe
    Item {
        anchors.fill: parent
        z: 1
        enabled: _bodyBox.view.cut

        SwipeGesture {
            // Kept once it scrolls: the list moves through it, it does not take the drag over
            xAxis.enabled: false
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            property real _startOffset: 0
            property var _startList: null
            property real _startListY: 0
            onActiveChanged: {
                if (!active)
                    return;
                _startOffset = _bodyBox.offset;
                _startList = _bodyBox._list();
                _startListY = _startList ? _startList.contentY : 0;
            }
            onDeltaYChanged: {
                if (!active)
                    return;
                _bodyBox.offset = NotificationRules.bodyScroll(_startOffset, deltaY, _bodyEdit.implicitHeight, _bodyBox.height);
                const beyond = (_startOffset - deltaY) - _bodyBox.offset;
                if (_startList)
                    _bodyBox._placeList(_startList, _startListY + beyond);
            }
        }
    }

    // A cut body fades into the card over a line at each edge where more of it is hidden
    Rectangle {
        objectName: "bodyFadeTop"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: _bodyEdit.implicitHeight / Math.max(1, _bodyEdit.lineCount)
        visible: _bodyBox.moreAbove
        gradient: Gradient {
            GradientStop { position: 0.0; color: _bodyBox.card.color }
            GradientStop { position: 1.0; color: Qt.rgba(_bodyBox.card.color.r, _bodyBox.card.color.g, _bodyBox.card.color.b, 0) }
        }
    }
    Rectangle {
        objectName: "bodyFadeBottom"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: _bodyEdit.implicitHeight / Math.max(1, _bodyEdit.lineCount)
        visible: _bodyBox.moreBelow
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(_bodyBox.card.color.r, _bodyBox.card.color.g, _bodyBox.card.color.b, 0) }
            GradientStop { position: 1.0; color: _bodyBox.card.color }
        }
    }
}
