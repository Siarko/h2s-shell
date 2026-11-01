# Plan: the bar at any screen edge (TODO 11.4)

## Decisions (2026-11-01)

- **Setting `bar.edge`** is a profile setting (layout, like the bar's sections), not a
  theme token. Default `top`: nothing changes on the host until it is set.
- **In stages**, each committed and checked on the host before the next.
- **Theme tokens keep their keys** and are read relative to the bar's edge: `topOffset` is
  the gap to the screen's edge, `left`/`right` margins and paddings are the bar's start and
  end, the `Top*` corners are the ones at the screen's edge and the `Bottom*` ones face the
  desktop. A theme looks the same at every edge; no migration. Only labels change.
- **The HUD is not moved** (toasts, launch warning, shell messages): its placement becomes
  customisable in other items.
- The same bar on every monitor, as today.

## Geometry in one place: `singletons/BarGeometry.qml`

Pure functions, tested (`tests/BarGeometryTest.qml`): the edge facing the desktop, whether
an edge is vertical, the physical corner radii from the edge-relative tokens, where a popup
joins the bar (its window's margin) and how long a popup's content may get. `Bar.qml` and
`panels/Popup.qml` read it instead of the tokens' top-edge meaning.

## Stage A — the bottom edge (done, 2026-11-01)

1. `bar.edge` in `SettingsSchema` (`top`, `bottom`), on the Bar page above the sections.
2. `Bar.qml`: anchored to its edge, its shape offset from that edge, corners mirrored.
3. `Popup.qml`: anchored to the bar's edge, opening away from it — the clip grows from the
   bar, the content is held against the bar, the ears and the outline are mirrored. The
   panels inside are not changed (only their background is).
4. The music visualiser's mask takes all four of the background's corners.
5. Bar shape page: labels that do not name the top.

## Stage B — a vertical bar, left or right

1. Sections as columns; a widget's grow-in animation and cell margins along the bar's axis.
2. `BarWidget`: its thickness from the bar, its length from its content.
3. Each widget gets `vertical` and lays itself out for it (a row-or-column layout replaces
   the `Row`s); per-widget designs drawn as mock-ups first: the clock in two lines,
   workspaces in a column without the window title, music and dictation as an icon,
   percentages under their icon.
4. `Popup.qml`: placed by the widget's `y`, opening sideways (width animated), ears above
   and below the join.
