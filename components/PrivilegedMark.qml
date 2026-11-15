import QtQuick
import qs.singletons

// Marks a control that asks for an administrator's password (polkit) — a lock in the
// theme's `privileged` colour — or one not allowed at all. `need` is polkit's answer for
// the action: "auth" (asks: the lock), "no" (not allowed: the lock crossed, muted), "yes"
// or "" (nothing to mark: hidden).
Text {
    id: root

    property string need: "auth"

    visible: need === "auth" || need === "no"
    // Nerd Font: a lock; a no-entry sign
    text: need === "no" ? "\uf05e" : "\uf023"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBody
    color: need === "no" ? Theme.textMuted : Theme.privileged

    MouseArea {
        id: _area
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    HoverTip {
        target: root
        shown: _area.containsMouse
        text: root.need === "no" ? "Not allowed for this user" : "Asks for an administrator's password"
    }
}
