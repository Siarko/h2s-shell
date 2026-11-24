import QtQuick
import qs.components

// A mockup showing a pill at a height of its own: tests/pill-sizes.sh must not read it
Pill {
    size: "huge"
    implicitHeight: 40
    property int minimumHeight: 40
}
