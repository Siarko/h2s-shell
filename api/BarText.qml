import qs.components as Components

// Text on the bar (module API 1.7), in a module's bar widget: plain text on a bar across
// the screen; on a bar at a side it runs as the user set for every widget, turned or with
// its letters one under another. Always shown as written.
//
//   BarText { text: name; font.family: Api.theme.fontFamily; font.pixelSize: Api.theme.fontSizeBody; color: Api.theme.textPrimary }
//
// Pinned by name: `text`, `font`, `color`, `alignment` (where it sits in a fixed length),
// `elide`, `length` (a fixed length along the text, -1 its own), `leadingGap` (space
// before it along the bar). The internal text (components/BarText.qml), not a wrapper:
// what else it has is not promised.
Components.BarText {}
