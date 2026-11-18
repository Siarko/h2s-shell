import qs.components as Components

// Items one after another along the bar (module API 1.7), in a module's bar widget: a row
// on a bar across the screen, a column on a bar at a side, centred across it. Its
// children set no anchors of their own.
//
//   BarRow { anchors.centerIn: parent; spacing: 4; BarText { … } BarText { … } }
//
// Pinned by name: `vertical` (read-only: the bar is at a side) and a Grid's `spacing`.
// The internal row (components/BarRow.qml), not a wrapper: what else it has is not
// promised.
Components.BarRow {}
