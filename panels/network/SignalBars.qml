import QtQuick
import qs.singletons

// A Wi-Fi signal strength, 0–100, as four bars: "▰▰▰▱". The colour and size are the
// owner's.
Text {
    property int strength: 0

    text: strength >= 75 ? "▰▰▰▰" : strength >= 50 ? "▰▰▰▱" : strength >= 25 ? "▰▰▱▱" : "▰▱▱▱"
    font.family: Theme.fontFamily
}
