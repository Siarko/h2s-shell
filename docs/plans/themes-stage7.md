# Themes stage 7: radii, borders and spacing as theme tokens

Part of [themes.md](themes.md). Status: **done 2026-10-30, verified on the host** (7a, 7b, 7c); text selection colour added after. Based on an audit of every QML file (183 literal radii, 34 border widths, ~200
spacings, ~250 margins).

## Decisions taken with the user

- Tokens are grouped **by element**: a group per kind of element, a token per property.
  Elements that share a token share its value. Names say exactly what they set
  (`powerMenu.buttonHeight`, not `powerMenu.height`).
- Kept apart on purpose: workspace pills (not bar cells); list items (not buttons — a
  different job, styled separately); the power menu and the lock screen (their own,
  larger style); notifications in the panel and toasts on screen.
- **Buttons by function**: general buttons share `button`; save, cancel and delete
  buttons each have their own group, so they can be told apart.
- **On-screen elements (OSD) each have their own group**: the notification toast (with
  the queue badge, which shares its radius), the volume OSD, the shell's message pill.
  Flat group names in the theme file (`osdToast`, `osdVolume`, `osdMessage`).
- **Borders**, each with a width (0 = none) and its own colour (in `colors`), for: the
  bar, popups (next to their radius), and each on-screen element. Plus shared widths for
  ordinary outlines (1) and selection rings (2).
- Settings window elements get tokens too (may come in handy).
- Outliers that fit a group take its value (small visible changes, accepted): e.g.
  radius-4 panel buttons become 6, the event form's 3/4 radii follow their groups.
- Not tokens: switches, slider tracks and thumbs, dots — derived from their height; the
  colour picker's marks, curve handles, the music cover's mask — tool constants.
- Left out: a generic spacing scale for layouts (the ~350 `spacing` and margin lines
  that are layout, not an element's look).

## The token set

Defaults keep today's look, except where a group absorbs an outlier.

### Bar
| Element | Property (today) | Token |
|---|---|---|
| Bar | border (new: 0) | `bar.borderWidth` + colour `barBorder` |
| Bar cell | corner radius (5) | `capsule.radius` |
| Bar cell | horizontal padding (8) | `capsule.horizontalPadding` |
| Bar cell | top and bottom margin in the bar (5) | `bar.cellVerticalMargin` |
| Bar sections | space between widgets (5) | `bar.widgetSpacing` |
| Tray icon highlight | corner radius (5) | `capsule.radius` |
| Workspace pill | corner radius (4) | `workspace.pillRadius` |
| Workspace pill | horizontal padding (4) | `workspace.pillHorizontalPadding` |
| Workspace pill | height (22) | `workspace.pillHeight` |
| Workspace pills | space between them (4) | `workspace.pillSpacing` |

(The bar's height, offsets, margins, padding and corners are already `bar.*`.)

### Popups
| Element | Property (today) | Token |
|---|---|---|
| Popup frame | corner radius (20) | `popup.radius` |
| Popup frame | padding around the content (10) | `popup.contentPadding` |
| Popup frame | border (new: 0) | `popup.borderWidth` + colour `popupBorder` |
| Rows and cards in popups (networks, VPN, Bluetooth, events) | corner radius (6) | `row.radius` |
| Rows in popups | horizontal padding (8; hardware 12, events 14) | `row.horizontalPadding` |
| Menu and list items (tray menu, audio devices, link speed, dropdown rows, graph range) | corner radius (4; event form 3) | `listItem.radius` |
| Dropdowns (settings, event form) | corner radius (6; event form 4) | `dropdown.radius` |
| Power menu | button corner radius (8) | `powerMenu.buttonRadius` |
| Power menu | button height (44) | `powerMenu.buttonHeight` |

### Buttons
| Element | Property (today) | Token |
|---|---|---|
| General buttons: `SmallButton`; Network VPN, rescan, connect, forget, hidden network; Bluetooth scan, pair, connect, forget; calendar account connect / disconnect | corner radius (6; Network VPN/rescan and Bluetooth 4) | `button.radius` |
| General buttons | horizontal padding (7) | `button.horizontalPadding` |
| General buttons | vertical padding (4) | `button.verticalPadding` |
| General buttons | minimum height (24; Bluetooth 20, calendar 28) | `button.minHeight` |
| Save buttons (`SmallButton` primary: Save, Save all; the event form's Save) | corner radius (6; event form 4) | `saveButton.radius` |
| Cancel buttons (the event form's Cancel, drafts' Cancel) | corner radius (6; event form 4) | `cancelButton.radius` |
| Delete buttons (`DeleteButton`, with its attached ×) | corner radius (6) | `deleteButton.radius` |
| Icon buttons (pin, reset, ×) | corner radius (4) | `iconButton.radius` |

Save, cancel and delete take the general button's padding and height unless that proves
too coarse.

### Pills and fields
| Element | Property (today) | Token |
|---|---|---|
| `Pill` and its copies; the event form's end and weekday choices | corner radius (6; event form 3) | `pill.radius` |
| Pills | horizontal padding (7) | `pill.horizontalPadding` |
| Pills | minimum height (22) | `pill.minHeight` |
| Text fields (settings, Network, the event form and times, hardware labels, curve coordinates) | corner radius (6; event form 4, hardware 3, curves 5) | `field.radius` |
| Text fields | horizontal padding (8; event form 6) | `field.horizontalPadding` |

### Notifications in the panel
| Element | Property (today) | Token |
|---|---|---|
| Notification card | corner radius (8) | `notificationCard.radius` |
| Notification card | padding (8) | `notificationCard.padding` |
| Card controls (actions, reply, send, chips, copy) | corner radius (5; copy 6) | `notificationCard.controlRadius` |
| Lock-screen notification preview | corner radius (8) | `notificationCard.radius` |

### On-screen elements (OSD)
| Element | Property (today) | Token |
|---|---|---|
| Notification toast | corner radius (8) | `osdToast.radius` |
| Notification toast | padding (10) | `osdToast.padding` |
| Notification toast | width (360) | `osdToast.width` |
| Notification toast | gap to the screen edge (16) | `osdToast.screenGap` |
| Notification toasts | space between them (8) | `osdToast.spacing` |
| Notification toast | border (new: 0) | `osdToast.borderWidth` + colour `osdToastBorder` |
| Toast queue badge | corner radius (6 → shares the toast's 8) | `osdToast.radius` |
| Toast queue badge | width (36) | `osdToast.badgeWidth` |
| Volume OSD | corner radius (6) | `osdVolume.radius` |
| Volume OSD | padding (10) | `osdVolume.padding` |
| Volume OSD | border (new: 0) | `osdVolume.borderWidth` + colour `osdVolumeBorder` |
| Shell message pill ("Settings saved") | corner radius (half its height) | `osdMessage.radius` (a number, or full) |
| Shell message pill | border (new: 0) | `osdMessage.borderWidth` + colour `osdMessageBorder` |

The toast's card controls take `notificationCard.controlRadius`.

### Other
| Element | Property (today) | Token |
|---|---|---|
| Tooltips (`HoverTip`, the slider's tooltip) | corner radius (4) | `tooltip.radius` |
| Tooltips | padding (8 / 6) | `tooltip.horizontalPadding`, `tooltip.verticalPadding` |
| Settings pages | margin (14) | `settings.pageMargin` |
| Settings sidebar items and the selected mark | corner radius (6) | `settings.sidebarItemRadius` |
| Settings tabs | corner radius (6) | `settings.tabRadius` |
| Settings tabs | horizontal padding (12) | `settings.tabHorizontalPadding` |
| Settings cards (lists, condition editor, profile cards) | corner radius (6; profiles 8) | `settings.cardRadius` |
| Calendar day cells, the week frame | corner radius (4) | `calendar.dayRadius` |
| Checkboxes | corner radius (3) | `checkbox.radius` |
| Lock screen card | corner radius (16) | `lock.cardRadius` |
| Lock screen field and button | corner radius (8) | `lock.controlRadius` |
| Lock screen field and button | height (40) | `lock.controlHeight` |
| Ordinary outlines (fields, lists, tooltips, pills) | width (1) | `border.width` |
| Selection rings (colour swatches, curve handles, an event's colour edge) | width (2) | `border.selectedWidth` |

## Open

- Parts and order of work: consolidating hand-written buttons, pills, the slider tooltip,
  switches and fields into shared components first (7a), then the tokens (7b), then the
  Popups and Notifications pages and the Bar page's additions (7c).

## Progress

*7a, consolidation, 2026-10-30, verified on the host:* `components/ToggleSwitch.qml` replaces
the 8 switch copies; the slider's tooltip is a `HoverTip`; the settings choices, preset
pills and the event form's end and weekday choices are `Pill`s; the Network, Bluetooth,
calendar-account, "+ Add" and preset Rename buttons are `SmallButton`s, which gained
`kind` (normal, save, cancel, delete — for the per-function groups) and `checked` (a
toggle that is on), replacing `primary`. Forgetting a network or a device and
disconnecting the Google account go through `DeleteButton`. Removed as unused:
`SettingBool`, `SettingOptions`, `SettingIntInput`, `SettingsGroup`. Left as they are,
for 7b to decide: the event form's Save and Cancel (Save is coloured by `confirm` /
`confirmSecondary`, adding vs editing), the settings tabs, the notification card's
controls. Still to do in 7a: a shared text field.

*7a, text fields, 2026-10-30, verified on the host:* `components/InputField.qml` (box,
placeholder, focus and problem outline, height from the text, password with an eye whose
state the owner may keep) in place of the hand-made fields: the schema editor's text,
number and list fields, the theme and font pages, widget settings, presets, Wi-Fi
(password per network, hidden network), the condition editor, the curve editor, the
colour picker's hex, the event form, `SettingInputRow`. Left as they are: inline edits
without a box (a profile's name, a hardware label), the notification reply
(`notificationCard`), the lock screen (`lock`). The event form's `TimeField` rewritten:
one `Segment` component for hours and minutes, the user's completion rules (an hour digit
is the hour, a minute digit the tens), per-segment placeholders, Up/Down stepping.

**Text selection colour** (asked for by the user 2026-10-30): to analyse — whether one
selection colour (and selected-text colour) fits everywhere, or some places need another
(e.g. the lock screen's glass, fields on the accent). Today every TextInput uses Qt's
default palette highlight, except a few that set `selectionColor: Theme.accent`.

*Floating lists, 2026-10-30, verified on the host (the user: a dropdown's list must not
take room in the layout):* `components/FloatingList.qml` (moves to the window's top, or to an
ancestor named "overlayHost" — the popup's panel, where clicks reach it; opens upwards
without room below; a press elsewhere closes it) and `components/Dropdown.qml` (a button
with the current choice and a FloatingList of options, with optional colour dots). Used
by the event form's frequency and calendar, the Bar page's and the hardware sources'
"+ Add" pickers, and the Theme setting's suggestions. The settings window's own pickers
already floated.

*7b, tokens, 2026-10-30, verified on the host:* the 24 shape groups in `Theme.builtin` (today's
values) and `ThemeRules.shapeGroups` (tested: each group has built-in tokens), read as
`Theme.<group>.<token>`; `resolve` keeps only the groups the built-in theme has. Bar
tokens `cellVerticalMargin`, `widgetSpacing`, `borderWidth` (on the Bar page). Border
colours `barBorder`, `capsuleBorder` (added: the bar cell has a border too),
`popupBorder`, `osdToastBorder`, `osdVolumeBorder`, `osdMessageBorder`. Wired: the shared
components (by kind for buttons: `saveButton`, `cancelButton`, `deleteButton` radii; save
buttons coloured `confirm`, a new kind `saveChange` `confirmSecondary` — the user: save
buttons take their function's colours), the bar, workspace pills, the tray highlight,
the popup frame and curves, rows and list items, dropdowns, the power menu, notification
cards (toast and panel apart), toasts' width, gaps, spacing and badge, the volume OSD, the
message pill (-1: fully round), tooltips, the settings pages' margins, tabs and cards,
calendar days, checkboxes, the lock screen, every literal border width. Round shapes
(slider tracks and thumbs, dots) are derived from their size. Borders drawn: the bar's,
only along the edge facing the desktop (the user's call), outside the bar — a shape like
the bar's, grown on that side, behind it — so the bar keeps its height (drawn inside, it
took room from the content) and a popup, in a window above, covers it where it joins the
bar (inside, it left a line between them). The side derives from `Bar.screenEdge`, top
for now, so it follows the bar when it can move (TODO 11.4). Bar cells, toasts and their badge, the volume OSD, the message pill. The popup's border
waits for its design. The event form's Save and Cancel are `SmallButton`s
(`submitKind`).

*Popup border, 2026-10-30, verified on the host (design A, the user's pick):* one line around
the popup's shape, open at the top where it joins the bar: down each ear's curve, the
sides, the rounded bottom — so the bar's border, which the popup covers between its
ears, carries on into it. A `Shape` with a `PathSvg` computed from the popup's width, the
clip's (animated) height, the radius and which ears show; offset half a line inwards so
all of it shows (the ears' arcs grow by half a line, the bottom corners shrink). Where
an ear is off (the popup at the bar's end) the line goes straight up the side.

*7c, pages, 2026-10-30, verified on the host:* `ThemeRules.shapeTokenInfo` (label, use,
slider range per token; tested to cover every token of every shape group and reach the
built-in values); `panels/settings/ShapeSections.qml` (a group's sliders with origin,
Reset, Undo, as drafts) and `ShapeSettings.qml` (a page of them with Save / Cancel).
Pages (ids): `popups` (popup, rows, list items, dropdowns, power menu), `controls`
(buttons by kind, icon buttons, pills, fields, check boxes, tooltips, outlines),
`notifications_appearance` (toasts, panel cards, volume OSD, messages),
`other_appearance` (settings window, calendar, lock screen), `widgets_appearance` (bar
cells, workspace pills — the user: the Bar page is about the bar only). The split into these pages (rather than only Popups and
Notifications, as first written) was proposed on 2026-10-30, for the user to confirm.

The popup's border meets the bar's (the user: it did not quite join): with a border on the
bar, the popup's line starts with a straight piece along the middle of the bar's border,
from the popup's edge, then turns down into the ear's curve — the popup covers that piece
of the bar's border, and this carries it on.

Tray icons have their own group `tray` (`pillRadius` 5, `pillWidth` 24, `iconSize` 18,
`pillSpacing` 4), as workspace pills do (the user: every widget with pills inside); no
other widget has any. The shape pages draw a line between their sections.

*Text selection colour, 2026-10-30, verified on the host:* analysed — every selectable text
(fields, the time field, the event description, notification text and reply, inline name
edits, the lock screen's password, the settings sidebar's version) sits on a dark, solid
theme background, or the lock screen's glass where an opaque selection reads too, so one
pair of colours fits all: `selection` and `selectedText`, base colours (Colors → Text),
default `#008000` (the dark accent) with white (the user's pick), replacing Qt's default
navy (`#000080`) that all but one place fell back on. Per-element variants can come later
if a place needs its own.
