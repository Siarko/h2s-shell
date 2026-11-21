import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// A notification card's body (NotificationCard): the body's markup made safe, its links
// (opened, or asked about by the card) with where each goes on hover, selectable text, and
// a box that cuts it at the card's bodyMaxLines lines under a fade (a toast).
Item {
    id: _bodyBox

    // The card it is the body of (NotificationCard)
    required property Item card
    // The text, for the card: its lines decide whether the body is cut
    readonly property alias edit: _bodyEdit

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
    implicitHeight: _bodyBox.card.bodyCut
        ? _bodyBox.card.bodyMaxLines * _bodyEdit.implicitHeight / _bodyEdit.lineCount : _bodyEdit.implicitHeight
    clip: _bodyBox.card.bodyMaxLines > 0

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
        anchors.top: parent.top
        // A word longer than the line is broken, not cut off at the side
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        readOnly: true
        selectByMouse: true

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

    // A cut body fades out into the card over its last line
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: _bodyEdit.implicitHeight / Math.max(1, _bodyEdit.lineCount)
        visible: _bodyBox.card.bodyCut
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(_bodyBox.card.color.r, _bodyBox.card.color.g, _bodyBox.card.color.b, 0) }
            GradientStop { position: 1.0; color: _bodyBox.card.color }
        }
    }
}
