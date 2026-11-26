import QtQuick
import qs.singletons

// Marks a control that asks for an administrator's password (polkit) — a lock in the
// theme's `privileged` colour — or one not allowed at all. `need` is polkit's answer for
// the action: "auth" (asks: the lock), "no" (not allowed: the lock crossed, muted), "yes"
// or "" (nothing to mark: hidden). `remembered` is what polkit keeps for the shell's
// process (RememberedAdmin.remembered, a module's module.privileged.remembered), for a
// control that runs through the shell's queue: while kept, a mark that asks shows an open
// lock, dimmed, its tooltip the time left.
Text {
    id: root

    property string need: "auth"
    property var remembered: null

    // Until when no password is needed (RememberRules.markKeptUntil), 0: as `need` says
    readonly property real keptUntilMs: RememberRules.markKeptUntil(need, remembered)
    readonly property bool kept: keptUntilMs > 0

    visible: need === "auth" || need === "no"
    // Nerd Font: a lock; an open lock; a no-entry sign
    text: need === "no" ? "\uf05e" : kept ? "\uf09c" : "\uf023"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBody
    color: need === "no" ? Theme.textMuted : Theme.privileged
    opacity: kept ? 0.5 : 1

    MouseArea {
        id: _area
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // The tooltip's clock: read when the tooltip opens, then once a second while it is open.
    // Opening it also reads again what polkit keeps (a forget elsewhere shows at once)
    property real _now: 0
    readonly property bool _counting: root.kept && _area.containsMouse && root.visible && (root.Window.window?.visible ?? false)
    on_CountingChanged: {
        if (_counting) {
            _now = _clock();
            _refreshKept();
        }
    }
    // A suite's or a mockup's seams: what reads it again, and the wall clock in ms
    property var _refreshKept: () => RememberedAdmin.refresh()
    property var _clock: () => Date.now()

    Timer {
        interval: 1000
        repeat: true
        running: root._counting
        onTriggered: root._now = root._clock()
    }

    HoverTip {
        target: root
        shown: _area.containsMouse
        text: root.need === "no" ? "Not allowed for this user"
            : root.kept ? RememberRules.keptTip(root.keptUntilMs, root._now)
            : "Asks for an administrator's password"
    }
}
