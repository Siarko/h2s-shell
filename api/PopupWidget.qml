import qs.components as Components

// The base type of a module's bar widget (module API 1.7): a cell on the bar that opens
// the popup its manifest names, by click or by hover as the user set for the widget's
// type. A module's widget extends it; its children are the cell's content.
//
//   PopupWidget { widgetType: "example"; property var module: null; BarText { text: "…" } }
//
// Pinned by name: `widgetType` (the manifest's widget type), `popup` (set by the bar),
// `popupOpen` (its popup shows, opened from this entry: not when another entry of the same
// type opened it; an entry built in the place of the one that opened it, same type and
// preset, takes it over), `interactive` (false: the cell takes no input —
// its content has click targets of its own), and the signals `clicked`, `hover(status)`,
// `scrolled(delta)`, `scrollNotch(direction)`, `middleClicked`. The bar needs the object
// itself, so this is the internal widget (components/PopupWidget.qml), not a wrapper:
// what else it has is not promised.
Components.PopupWidget {}
