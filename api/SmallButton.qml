import QtQuick
import qs.components as Components
import qs.singletons

// The public button (module API 1.4): the shell's button for a module, which picks what
// the button is about and how large it is, never a colour or a number of pixels.
//
//   SmallButton { label: "Connect"; kind: "primary"; onClicked: … }
//   SmallButton { label: "Remove"; kind: "danger"; confirm: true; onClicked: … }
//
// `kind`: "primary" (performs the action), "secondary" (the default: a step in between,
// opens something, "Cancel"), "danger" (stops or removes), "warning" (goes on, but think),
// "success" (a good outcome to take). `size`: "xs", "s", "m" (the default). A word it does
// not know shows as the default and is logged once (ApiElements).
//
// `confirm`: the first click only turns the button into the question, `confirmLabel`,
// with a "×" that takes it back (`cancelTip`); `asked()` says so and `asking` is true
// until it is answered. Set `asking = false` when what the button acts on changes.
// `clicked()` is "do it" either way: the click, or with `confirm` the second one. A
// button that asks shows no `checked`.
//
// A wrapper around the internal buttons (components/SmallButton.qml, DeleteButton.qml):
// what is declared here is all a module can rely on. As wide and tall as the button
// inside; given another width, a button that does not ask takes it and cuts its label.
Item {
    id: root

    property string label
    property bool available: true
    property bool checked: false
    property string tooltip: ""
    property string kind: "secondary"
    property string size: "m"
    property bool confirm: false
    property string confirmLabel: label + "?"
    property string cancelTip: "Cancel"
    property bool asking: false

    signal clicked
    signal asked

    implicitWidth: _inner.item?.implicitWidth ?? 0
    implicitHeight: _inner.item?.implicitHeight ?? 0

    // Only a button that asks can be asking
    onAskingChanged: {
        if (asking && !confirm)
            asking = false;
        else if (confirm && _inner.item)
            _inner.item.asking = asking;
    }
    onConfirmChanged: if (!confirm) asking = false

    Loader {
        id: _inner

        readonly property var kind: ApiElementRules.buttonKind(root.kind)
        readonly property var size: ApiElementRules.textSize(root.size)
        onKindChanged: if (!kind.known) ApiElements.unknown("SmallButton", "kind", root.kind, ApiElementRules.buttonKindDefault)
        onSizeChanged: if (!size.known) ApiElements.unknown("SmallButton", "size", root.size, ApiElementRules.sizeDefault)
        Component.onCompleted: {
            kindChanged();
            sizeChanged();
        }

        sourceComponent: root.confirm ? _asks : _acts
    }

    Component {
        id: _acts

        Components.SmallButton {
            width: root.width
            height: root.height
            label: root.label
            available: root.available
            checked: root.checked
            tooltip: root.tooltip
            kind: _inner.kind.value
            fontSize: Theme[_inner.size.value]
            onClicked: root.clicked()
        }
    }

    Component {
        id: _asks

        Components.DeleteButton {
            label: root.label
            confirmLabel: root.confirmLabel
            cancelTip: root.cancelTip
            available: root.available
            tooltip: root.tooltip
            kind: _inner.kind.value
            fontSize: Theme[_inner.size.value]
            onAskingChanged: root.asking = asking
            onAskingStarted: root.asked()
            onConfirmed: root.clicked()
            Component.onCompleted: asking = root.asking
        }
    }
}
