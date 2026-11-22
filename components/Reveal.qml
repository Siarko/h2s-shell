import QtQuick
import QtQuick.Layouts
import qs.singletons

// A part that opens on a switch: it slides open downwards and shut upwards — its height
// follows its content, clipped — with the theme's "expand" duration and curve, its content
// fading in and out ("fade"); with reduced motion it opens and shuts at once. Shut, it is
// hidden and takes no room. Its children are laid out in a column at its width.
//
//   Reveal { open: screensaverOn; SchemaSettingEditor { … } }
//
// Only a change of `open` slides: built open, it stands open at once; content that grows
// or shrinks while it is open changes its height at once.
Item {
    id: root

    property bool open: false
    property alias spacing: _column.spacing
    default property alias content: _column.data
    // Open, or still sliding shut: what it holds is on screen
    readonly property bool shown: _progress > 0

    // 0 shut, 1 open; the slide animates this, never the content's height
    property real _progress: open ? 1 : 0
    Behavior on _progress {
        NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") }
    }

    Layout.fillWidth: true
    implicitWidth: _column.implicitWidth
    implicitHeight: Math.round(_column.implicitHeight * _progress)
    visible: shown
    clip: _progress < 1

    ColumnLayout {
        id: _column
        width: root.width
        spacing: 6
        opacity: root.open ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.duration("fade") }
        }
    }
}
