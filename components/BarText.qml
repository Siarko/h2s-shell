import QtQuick
import qs.singletons

// Text on the bar. On a bar across the screen it is plain text; on a bar at a side it
// runs as bar.verticalText says, the same for every widget (BarLayout): turned — to read
// down a bar at the right, up a bar at the left, as book spines do — or its letters upright
// one under another. A single character — an icon, a digit — stays upright either way.
Item {
    id: root

    property string text: ""
    property alias font: _text.font
    property alias color: _text.color
    // Where the text sits in a fixed length longer than it: AlignLeft at its start (after
    // the gap), AlignRight at its end, AlignHCenter in the middle — whichever way it runs
    property int alignment: Text.AlignLeft
    // Elided at that end when a fixed length cuts it; stacked letters show the text's end
    // with ElideLeft and its start otherwise, without an ellipsis
    property int elide: Text.ElideNone
    // A fixed length along the text's own direction, the gap before it included (-1: its
    // own); clipped to it — e.g. a preview growing in
    property real length: -1
    // Space before the text along the bar: on its left, or above it at a side, whichever
    // way the text reads
    property real leadingGap: 0

    // "plain", "rotated" or "stacked"; a single character at a side is one stacked letter,
    // so a fixed length still runs down the bar
    readonly property string mode: !BarLayout.vertical ? "plain"
        : _characters.length <= 1 ? "stacked" : BarLayout.verticalText
    readonly property bool _stacked: mode === "stacked"
    readonly property bool _rotated: mode === "rotated"
    // Turned the other way, reading up: its right end is then its top
    readonly property bool _readsUp: _rotated && BarLayout.edge === "left"

    // The text's characters, a glyph outside the basic plane (a Nerd Font icon) kept whole:
    // QML's Array.from splits a string into UTF-16 halves, not characters. Only on a bar at
    // a side, the one place they are used.
    readonly property var _characters: {
        if (!BarLayout.vertical)
            return [];
        const characters = [];
        for (let i = 0; i < text.length; i++) {
            const code = text.charCodeAt(i);
            const pair = code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length;
            characters.push(pair ? text.substr(i++, 2) : text[i]);
        }
        return characters;
    }

    // The text's own length along its direction, the gap included, and its thickness across
    readonly property real _naturalLength: _stacked ? _text.implicitHeight + leadingGap : _text.implicitWidth
    readonly property real _along: length >= 0 ? length : _naturalLength
    readonly property real _across: _stacked ? _text.implicitWidth : _text.implicitHeight

    implicitWidth: mode === "plain" ? _along : _across
    implicitHeight: mode === "plain" ? _across : _along
    clip: length >= 0

    // Where the letters go: after the gap when stacked, so a cut column keeps it — the
    // whole item otherwise, the gap being the text's own padding
    Item {
        id: _room
        y: root._stacked ? root.leadingGap : 0
        width: root.width
        height: root._stacked ? Math.max(0, root.height - root.leadingGap) : root.height
        clip: root._stacked && root.length >= 0

        Text {
            id: _text
            text: root._stacked ? root._characters.join("\n") : root.text
            width: root._stacked ? implicitWidth : root._along
            height: implicitHeight
            // Read up, the text's left end is at the bottom: its start and end swap
            horizontalAlignment: root._stacked ? Text.AlignHCenter
                : !root._readsUp || root.alignment === Text.AlignHCenter ? root.alignment
                : root.alignment === Text.AlignRight ? Text.AlignLeft : Text.AlignRight
            elide: root._stacked ? Text.ElideNone : root.elide
            leftPadding: root._stacked || root._readsUp ? 0 : root.leadingGap
            rightPadding: root._readsUp ? root.leadingGap : 0
            // Clockwise, reading down the bar; at the left, the other way, reading up.
            // Turned about its corner and put back by whole lengths, so it stays on the
            // pixels it is laid out on (turned about its middle it could land half a pixel off)
            rotation: !root._rotated ? 0 : root._readsUp ? -90 : 90
            transformOrigin: Item.TopLeft
            x: !root._rotated ? (root._stacked ? Math.round((root.width - width) / 2) : 0)
                : root._readsUp ? 0 : root.width
            y: root._rotated ? (root._readsUp ? root.height : 0) : root._stacked ? _stackedY : 0
            // Stacked letters in their room: placed as `alignment` says when they fit, else
            // the end shown (ElideLeft) or the start
            readonly property real _stackedY: {
                const room = _room.height;
                if (height > room)
                    return root.elide === Text.ElideLeft ? room - height : 0;
                if (root.alignment === Text.AlignHCenter)
                    return Math.round((room - height) / 2);
                return root.alignment === Text.AlignRight ? room - height : 0;
            }
        }
    }
}
