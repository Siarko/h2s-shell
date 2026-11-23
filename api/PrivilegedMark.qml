import QtQuick
import qs.components as Components
import qs.singletons

// The public mark (module API 1.5) beside a control that asks for an administrator's
// password. `need` is polkit's answer for what the control does: "auth" (asks: the lock),
// "no" (not allowed), "yes" or "" (nothing to mark). An answer it does not know shows the
// lock — never nothing — and is logged once (ApiElements).
//
//   PrivilegedMark { need: client.need }
//
// (1.39) `remembered`: the module's `module.privileged.remembered`, beside a control that
// runs through module.privileged.start. While it is kept, a mark whose need is "auth" shows
// an open lock, dimmed, its tooltip the time left; anything else leaves the mark as `need`
// says.
//
//   PrivilegedMark { need: client.need; remembered: module.privileged.remembered }
//
// With nothing to mark it is hidden and takes no room. A module that sets `visible`
// itself decides alone whether the element is there: the mark inside still shows only
// when there is something to mark, and the element left empty has no size — but a layout
// keeps its spacing around it, so such a condition names the need too.
//
// A wrapper around the internal mark (components/PrivilegedMark.qml): what is declared
// here is all a module can rely on.
Item {
    id: root

    property string need: "auth"
    property var remembered: null

    visible: ApiElementRules.markShown(need)
    implicitWidth: _inner.shown ? _inner.implicitWidth : 0
    implicitHeight: _inner.shown ? _inner.implicitHeight : 0

    Components.PrivilegedMark {
        id: _inner

        readonly property var needWord: ApiElementRules.markNeed(root.need)
        readonly property bool shown: ApiElementRules.markShown(root.need)
        onNeedWordChanged: if (!needWord.known) ApiElements.unknown("PrivilegedMark", "need", root.need, ApiElementRules.markNeedDefault)
        Component.onCompleted: needWordChanged()

        width: root.width
        height: root.height
        need: needWord.value
        remembered: root.remembered
    }
}
