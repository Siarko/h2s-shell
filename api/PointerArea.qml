import qs.components as Components

// The MouseArea of a module's own control that looks different under the pointer (module
// API 1.7): `lit` is true under the pointer, while pressed, and for a moment after a tap,
// so a finger's tap shows too. The hover look of a module's own element comes from `lit`,
// never from `containsMouse`.
//
//   PointerArea { id: area; onClicked: … }      color: area.lit ? Api.theme.surfaceHover : Api.theme.surface
//
// Pinned by name: `lit`, `centred` (true: centred on its parent and at least the theme's
// least target across and down; false: placed by its own anchors — rows of a list that
// touch), `reach` (how far past its parent it reaches at least), and a MouseArea's own
// properties and signals. The internal area (components/PointerArea.qml), not a wrapper:
// what else it has is not promised.
Components.PointerArea {}
