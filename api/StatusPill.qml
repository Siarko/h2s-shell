import QtQuick
import qs.components as Components
import qs.singletons

// The public status pill (module API 1.35): a pill that sums up a state — an icon (a glyph
// of the shell's icon font; "" none) and a one-line label, then its parts, each an icon and
// a short text (a count) in its kind's colour with its tip over it on hover (HoverTip's
// rules). A click flips `expanded` while there are parts: the parts one per line under a
// rule, icon and `line` in the part's colour; `toggled(expanded)` reports it. The owner may
// set `expanded` too.
//
//   StatusPill { icon: ""; label: "Sending 1/6"
//                parts: [{ icon: ""; text: "3"; kind: "muted"; tip: "3 queued" }] }
//
// `kind`: "normal" (the default: the icon in the accent, the label in the text colour),
// "muted", "success", "warning", "danger" — the icon's and the label's colour. `parts`:
// [{ icon, text, kind, tip, line }], kinds the same words; a `line` left empty is the tip
// (or the text without one). Texts plain, one line, cut past 80 characters; past 12 parts
// the rest are dropped. A word it does not know shows as "normal"; that, and dropped parts,
// are logged once (ApiElements). The words: ApiElementRules.statusKinds, statusParts.
//
// A wrapper around the internal pill (components/StatusPill.qml): what is declared here is
// all a module can rely on. As large as the pill inside; it fills no width.
Item {
    id: root

    property string icon
    property string label
    property string kind: "normal"
    property var parts: []
    property alias expanded: _inner.expanded

    signal toggled(bool expanded)

    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.StatusPill {
        id: _inner

        readonly property var kindWord: ApiElementRules.statusKind(root.kind)
        onKindWordChanged: if (!kindWord.known) ApiElements.unknown("StatusPill", "kind", root.kind, ApiElementRules.statusKindDefault)
        readonly property var checked: ApiElementRules.statusParts(root.parts)
        onCheckedChanged: {
            for (const word of checked.unknownKinds)
                ApiElements.unknown("StatusPill", "parts.kind", word, ApiElementRules.statusKindDefault);
            if (checked.dropped > 0)
                ApiElements.once("StatusPill.parts>" + ApiElementRules.statusPartCap,
                                 "[Api] StatusPill: more than " + ApiElementRules.statusPartCap + " parts; the rest are not shown");
        }
        Component.onCompleted: {
            kindWordChanged();
            checkedChanged();
        }

        width: root.width
        height: root.height
        icon: ApiElementRules.iconText(root.icon)
        label: ApiElementRules.oneLine(root.label)
        kind: kindWord.known ? root.kind : ApiElementRules.statusKindDefault
        parts: checked.parts
        onToggled: expanded => root.toggled(expanded)
    }
}
