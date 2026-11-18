import QtQuick
import qs.components as Components

// The public switch (module API 1.5): on or off, as in the settings. A click gives
// `toggled()`; the owner changes `checked` (it follows the value it shows, which may
// change elsewhere). With `enabled: false` (every item's own property) a click does
// nothing.
//
//   ToggleSwitch { checked: badge; onToggled: badge = !badge }
//
// A wrapper around the internal switch (components/ToggleSwitch.qml): what is declared
// here is all a module can rely on. As large as the switch inside unless given another
// size.
Item {
    id: root

    property alias checked: _inner.checked

    signal toggled

    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.ToggleSwitch {
        id: _inner

        width: root.width
        height: root.height
        onToggled: root.toggled()
    }
}
