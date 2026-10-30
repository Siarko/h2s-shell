# Themes stage 7: radii, borders and spacing as theme tokens

Part of [themes.md](themes.md). Status: **token set agreed with the user 2026-10-30, not
started.** Based on an audit of every QML file (183 literal radii, 34 border widths, ~200
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

- A border on a popup has to follow its curved corners where it meets the bar
  (PopupCurve), and meet the bar's own border there: to be designed.
- Parts and order of work: consolidating hand-written buttons, pills, the slider tooltip,
  switches and fields into shared components first (7a), then the tokens (7b), then the
  Popups and Notifications pages and the Bar page's additions (7c).
