# Changelog

Notable changes to the shell, newest first. Versions follow semantic versioning:
**major** for changes that need a config migration or change behaviour people rely on,
**minor** for features, **patch** for fixes. The number lives in
`singletons/Version.qml`; each release is tagged `v<number>` in git.

Add an entry under **Unreleased** with each user-visible change; a release renames that
section to the new version and date.

## [Unreleased]

### Fixed
- The count of waiting toasts showed on every screen; it shows on the toasts' screen.
- Music: skipping a paused track (the buttons or a swipe) no longer starts it playing in
  players that do so against MPRIS, such as Spotify — the shell pauses it again.
- `launch.sh --restart` (`h2s-shell --restart`) closes every running copy of the shell, not
  only its own folder's: restarting the package's copy with a checkout running
  (`H2S_SHELL_DIR`) left two shells.
- On-screen keyboard: it shows when you tap a text field in a popup opened by touch and
  hides when you tap anywhere else, as in a browser; tapping it keeps the popup and the
  field. The same for the reply field on a notification. A popup opened by touch closes on
  a tap outside it, and that tap no longer goes on to the window beneath. Fields say what
  they are — digits for dates and times, password for passwords — so the keyboard can pick
  its layout; a tap anywhere on a field's box focuses it. In the settings window the
  keyboard hides after a field too, with Qt 6.12.
- Calendar: the + and refresh icons take a tap from around them, not only on the glyph.
- A hover popup no longer closes when the pointer goes back from it onto its bar widget.
- Touch: a tap on a bar widget opens its popup even when the widget opens it on hover —
  such a popup opened by a finger used to stay open for good. A popup opened by a tap
  closes on a tap outside it and the bar, and takes the keyboard (a text field in it gets
  typing, the on-screen keyboard too) without the pointer over it. Popups opened by the
  mouse behave as before; one opening on hover does so 60 ms later.
- Settings: the list of pages scrolls when the window is too short for it (a small
  laptop screen); the pages at the bottom could not be reached.
- Bluetooth stays off after a restart when you left it off. BlueZ powers the adapter on
  whenever it starts; the shell now puts back the state it was last in.
- Google Calendar: losing the network (e.g. right after waking the laptop) no longer signs
  you out; only a sign-in Google itself has expired or revoked asks for a new login.
- Music: the popup no longer opens short and grows to its height after.
- A popup closed before it had appeared (another screen's opening at that moment) no
  longer stays open for good, its widget lit and deaf to clicks.
- Bar popups: each opens on its own bar's screen. They went to the screen with the focus,
  which at the top happened to be the bar's.
- After a review of the day's changes:
  - Music: the ring round the cover no longer stays hidden for good when the cover fails
    to load or its colours cannot be read; no small copy of the last cover shows where
    the next has none; the cover's colours are read only when they are used.
  - Music: dictation pauses every player that plays, hidden ones too, and resumes them.
  - Music: the player list shows while any player is hidden, even with no other.
  - Music: the ring round the cover is no longer cut at the top, and a glow no longer
    spills outside the popup in any layout; the edge layouts follow the popup's real
    edges at the bar's end.
  - Music: cava keeps running through pauses instead of restarting each time.
  - Music: a player's icon given as a file path shows.
  - Notifications widget: a reload of the shell no longer makes every notification
    unread (the bell rang until the panel was opened).
  - Notifications widget: a notification its sender replaces (same id: a download's
    progress, what is playing) counts as new and rings — once, if the panel was opened
    since; further updates before the panel is opened again do not ring.
  - Hiding a player never writes into a profile that is not in effect.
- Popups under the middle of the bar (the calendar's top half) took no clicks: the hidden
  launch warning banner still caught them, over every popup there.
- Music panel: the seek bar shows. It had been there all along, 0 px tall.
- Music panel: playerctld no longer shows as a second copy of the last player used.
- Music panel: showing a paused player while another plays, the visualiser falls flat
  instead of moving to the other's sound — smoothly, at the visualiser's frame rate, in
  half a second (it fell in 10 steps a second, for up to two seconds).
- Notifications: replying from the notification works. Apps that can take a reply (chat
  apps, say) now get a reply field on the card — in the panel and on the toast — with
  their own hint text; Enter or Send sends it, Escape clears it. A toast takes the
  keyboard only while its reply field is under the pointer or being written, and does
  not count down meanwhile. The field never showed before, and the shell did not tell
  apps it could take replies.

### Added
- Wallpaper transitions, set in the theme (Appearance → Animations): a switch to a
  workspace with its own image slides the way the workspaces go (or changes as a new image
  does); a new image fades, zooms, slides, wipes, opens as a circle, dissolves or
  pixelates. Two animation roles time and ease them, with curves from the library.
- Wallpapers drawn by the shell (Settings → Wallpaper; off by default): an image, or a
  folder (subfolders to a chosen depth) chosen by you, at random — at start, every so
  often, or on Shuffle (`ipc call wallpaper shuffle`) — or by weekday; one everywhere, per
  monitor or per workspace, faded in on a change. Picked from the folder's thumbnails:
  the images to use, one per monitor or workspace, one per day, and monitors or
  workspaces that keep theirs while the rest are drawn. A warning when another program
  (hyprpaper, swww) draws a wallpaper too.
- Notifications: where toasts show — the screen with the focused workspace, as before, or
  a chosen screen — and what a fullscreen window on that screen changes: show anyway,
  don't show (the notification goes to the panel only), or show on another screen, a
  chosen one or any without a fullscreen window. The shell's own messages follow them.
  Settings → Notifications.
- Battery widget: a colour of its own while plugged in (charging, full on the charger),
  over the colour thresholds; empty keeps the thresholds. Widget settings → Charging.
- Battery widget settings: clicking a colour's swatch opens a colour picker under it, as on
  the Colors page; typing the hex still works.
- Calendar: a click or a tap on the month or the year shows the year's twelve months; the
  arrows (or a swipe) move by years there and a month goes to it — moving by years no
  longer needs the wheel over the year.
- Curves settings: two fingers zoom the curve's graph, as the wheel does.
- Touch and mouse alike: buttons, icons, rows and bar cells show their hover look when
  tapped (it holds a moment after the finger lifts, so a tap is seen), and small controls
  take a click or a tap a little past their edge — at least 36 px round them, the theme's
  new Appearance → Controls → Targets — without changing how anything looks. A tap on
  the bar's edge above a cell now reaches it.
- Notifications: swipe a card sideways with a finger to dismiss it — a toast in the HUD
  (its countdown waits while the finger is down) or a card in the notifications panel. A
  short swipe lets it go back. The mouse still selects text by dragging.
- Calendar: swipe the month grid with a finger to change the month — left for the next,
  right for the one before. The grid follows the finger with the month it brings in
  beside it, events and all, and slides on from where you let go; a tap still selects a
  day.
- Music panel: a new track slides in sideways — the next from the right, the previous
  from the left — and a change of player slides vertically, a player lower in the list
  coming in from below (before, a change of player slid sideways and a new track only
  faded its title in). With a finger: swipe the cover left or right to skip the track
  (⏭/⏮ shows in the gap, lit once far enough), up or down to change the player, whose
  view follows the finger in.
- Calendar: the "Today" button's line is kept when it is hidden, so the grid stays the
  same size — its days no longer jump when you move to or from the current month.
- On-screen keyboard: a popup no longer draws under it. While the keyboard is up, a popup
  by a bar at the top ends above it, and its content moves within it — by itself to keep
  the field being typed in in sight, or by a drag or the wheel. A drag no longer counts as
  a tap off the field, so scrolling keeps the keyboard.
- Bar: a battery widget. An icon showing the charge in tens, charging or not; the
  percentage left or right of it, or not at all; and colour thresholds — any number, each a
  charge and a hex colour, the icon taking the colour of the lowest one the charge is at or
  below. Per preset, in the widget's settings. It opens a popup: the charge, charging or
  not, time left and the power drawn; the system power profile, to change by hand — it
  stays until the shell's profiles next want another one, and the popup says which; and the
  history as UPower records it — the charge over 6 h, 24 h or 7 days with the time on the
  charger shaded, and the power drawn beneath; and beside it, as on Android, use per app
  since the last full charge — estimated from each app's CPU and GPU time while on
  battery, the screen and the rest as "System and screen". Dragging across the graph picks
  a stretch of time, and the list shows the use within it; a tap, or ×, goes back.
- Google Calendar: no OAuth client of your own needed — the shell carries one (a client
  entered in the settings still takes its place). The sign-in uses PKCE and checks its
  `state`, since the client's secret is public.
- Installing: `install.sh` for Arch (the packages, then a checkout where Quickshell looks
  for its config), and a Nix flake for NixOS — an `h2s-shell` command carrying every
  program the shell calls, and a module (`programs.h2s-shell.enable`) adding the font and
  the services its widgets read. `launch.sh` now works from wherever the shell lies.
- Profiles: "Tablet mode" as a condition, for convertibles. Hyprland tells the shell when
  the device folds (two switch bindings, see the README); `ipc call tablet set|toggle`
  sets it by hand.
- A banner under the bar when no Nerd Font is installed — the icons are its glyphs and
  show as empty boxes without one — saying how to install it.
- Bar: it can stand at the left or right of the screen too. The widgets stack down it and
  popups open sideways from it; text is turned — read down a bar at the right, up a bar
  at the left — or written as letters one under another (Behaviour → Bar → Text on a
  vertical bar, the same for every widget). A single character, such as an icon, stays
  upright.
- Bar: it can stand at the bottom of the screen (Behaviour → Bar → Position, per
  profile); popups then open upward from it. The Bar shape page names the edge offset
  and corners by the screen's edge and the desktop side, so a theme looks the same at
  either edge.
- Music panel: changing player slides the cover, its visualiser and the track sideways —
  a player further down the list comes in from the right, one further up from the left —
  each view keeping its own player, so the cover turns and the ring moves only for a
  player that is playing. Not with reduced motion.
- Music panel: the player list shows each player's application icon, and two buttons
  beside each: play — pausing every other listed player, so switching between, say,
  Spotify and a browser is one click (pause while it plays) — and hide. Hidden players
  (a phone's, through KDE Connect, say) go under a "Hidden" expander over the list, to be
  shown again with the eye beside them; they are never picked by themselves. The list
  is kept per profile ("media.hiddenPlayers", also in Settings → Media).
- Music: the visualiser can go around the cover (Settings → Media → Layout, "Around
  cover") — waveform, rays, dots or glow following the cover's shape, bass at the bottom.
  Two glow styles, in every layout: Glow, light reaching as far as each band; Even glow,
  one halo pulsing with the bass. The cover's rounding is a slider, from square to a
  circle (33 %, the old look, by default), and it can turn while playing, either way, up
  to 360° a second (off by default; never with reduced motion).
- Music: two more visualiser layouts glued to the popup's edges, growing inward only —
  Horizontal (bottom) along the bottom edge, Vertical (sides) down both sides — cut to the
  popup's rounded corners. The old two are now Horizontal (centered) and Vertical
  (centered), unchanged.
- Music: around the cover, the visualiser can take its colours from the cover (Settings →
  Media, "Colours from the cover", off by default): two or three, read from each cover as
  it loads, running round it — the visualiser fades in once they are known, never
  first in the theme's colour. A grey cover keeps the theme's colour.
- Themes: a colour of its own for the music visualiser (Appearance → Colours → Music).
  Until a theme sets it, it follows the accent, as the visualiser always did.
- Settings: a slider whose range goes both ways (the cover's rotation) is filled from
  its resting value, marked on the track, rather than from its left end.
- Notifications widget: a badge on the bell with how many notifications wait ("9+" past
  nine), and the bell rings when one comes — lifted, shaken in the air, put back. Its
  preset (Bar → Content → Notifications) turns the badge off and picks the ringing: off,
  once for each notification, until opened (again every few seconds until the panel is
  opened) or until cleared (again every few seconds while any notification is left). Not
  with reduced motion.
- Notifications: formatting in the text — bold, italic, underline, line breaks — and
  links: web and mail links in the accent colour open on a click; any other kind (a file,
  an app's own) is in the warning colour and asks first, with Open, Copy and Cancel. An
  image in the text is never loaded: it is a tinted row of its own with an image icon,
  linking to it, its address shown under its description. Hovering a link shows where
  it goes. Other tags are dropped, their text kept; the body is read by a small
  parser, so tags of any shape (self-closing, quoted ">" in attributes, comments) are
  understood. Codes are found in the text, not in link addresses.
- Settings, General: an icon theme for the shell — its notifications, tray and every
  other icon, picked from a list of the installed themes. Automatic, the default, is the
  system's icon theme if it is installed, else the first one found; a row of sample icons
  under the list shows the theme picked before it is applied. It applies when the shell
  restarts, which a "Restart to apply" button next to it does. The shell now starts
  through `scripts/launch.sh` (Hyprland's autostart calls it), as Quickshell takes the
  icon theme only at launch. Before, the shell had none: app icons loaded, status icons
  such as warnings did not.
- A banner under the bar when the shell was started directly (`qs`, `qs -c default`)
  rather than through `scripts/launch.sh`: the icon theme setting cannot apply then, and
  it says why and how to start the shell instead. It restarts nothing by itself, so the
  arguments the shell was started with are never dropped; × closes it for that run.
- Calendar: events can span several days. The event form has a start and an end date
  (DD.MM.YYYY, typed like the times: digits only where they make a date, "." moves on,
  Up and Down step, a day past the month's end becomes its last); moving the start takes
  the end along, an end before the start becomes the start. A timed event ending earlier
  in the day than it starts goes on past midnight.
- Calendar: going into a date field arms the calendar for it — the next day clicked fills
  it (the start, then the end), and a hint says which; the event's days are shaded in the
  grid while the form is open. Without an armed date a click only moves the calendar,
  and an event being edited stays in the list while other days are looked at.
- Calendar grid: an event spanning days is a bar in its colour above the day numbers,
  running through its days — on into the next week's row, keeping its place, rounded
  where it starts and ends — instead of a dot on each day; up to three stacked. Under the
  number, a dot for each single-day event, in the event's colour (two rows of four at
  most), instead of one accent dot for the day.

### Changed
- Popups slide out from under the bar as a whole, and back under it, instead of being
  uncovered by a growing cut; the curves joining them to the bar stay until only the
  popup's rounded end is left.
- Popups grow and shrink with a panel's own animation (an expander opening a list of
  devices, say) frame by frame, instead of trailing behind it.
- Music: the player list and the controls stay in view while the popup changes size —
  opening, or coming from another panel — and the cover between them is cut to the room
  left.
- Calendar: an event card's edit and delete buttons are larger, on a button's background
  so it is clear what is clicked, and level with the event's title instead of the middle
  of the card; editing is a pencil icon instead of the tiny "✏" character.
- Notifications: each picture has its place. The app's icon stays small in the header;
  a square image (an avatar, album art, an app's logo sent as an image) is a rounded
  thumbnail beside the title and text; a wide or tall one (a screenshot) a preview across
  the card. It used to be one image for everything, centred under the text — app logos
  included.
- Notifications: clicking a notification that has a default action (opening the chat it
  came from, say) runs it — the header, the text or the image; such a card lights up
  under the pointer, which is a hand over it, the text included. The text can still be
  selected by dragging, and a click that clears a selection only clears it. The default
  action used to be an empty button.

### Fixed
- Tooltips no longer fail to open when what they say changes at the moment they are
  asked to show.
- Screensaver: notification previews show the text, no longer the body's HTML drawn
  as is (which could load images from the network).
- Wi-Fi: a password typed into an open network row stays with that network when the
  list refreshes; it used to jump to whichever network took the row's place.
- Wi-Fi: a network seen through several access points — on two bands, or a mesh — is one
  row, with its strongest signal and every band it is on, instead of a row for each.
- Notifications: an icon the icon theme lacks shows nothing instead of a purple
  checkerboard.
- Notifications: a toast whose button was clicked keeps its content while it slides
  away; it used to empty first, as the notification closes the moment its action runs.
- Toasts no longer stop counting down after the shell reloads its files: a toast removed
  by the reload stayed first in line, and the ones after it waited for it for ever.
- Calendar: events of a read-only calendar (a holiday calendar, say) have no edit and
  delete buttons, which Google would refuse anyway, and new events can only go to
  calendars that can be written to.
- Calendar: editing an event keeps its dates. It used to move to the day selected in the
  calendar — a multi-day event edited from its second day became a one-day event there,
  and one going past midnight could not be saved at all.
- Calendar: an event's times are sent with the time zone offset of its own date, not
  today's, so an event across the end of summer time no longer lands an hour off.
- A tray menu opening with no menu open comes in from the bar like every other popup;
  it used to slide in sideways, as when switching from another icon's menu.

## [2.0.0] - 2026-10-31

Themes: the shell's look — colours, fonts, shapes, animations and the bar's geometry —
moved out of the profiles into theme files, edited in the settings window's new Appearance
tab. Major because the bar's geometry is migrated out of the profiles into themes, and
`qs ipc call settings openPage` now takes a page's id.

### Added
- Curves page: the graph pans and zooms freely — drag its background to move around,
  scroll to zoom in at the pointer (up to 20×), double-click off the curve to fit it
  again — for working on fine detail.
- Text selection colours in themes (Colors → Text: Selection, Selected text), used by every
  field and selectable text: the default is the dark accent with white text, instead of
  Qt's navy that most fields fell back on.
- Themes set the shape of every kind of element — corner radii, padding, spacing, border
  widths — by kind: bar cells, workspace pills, popups, rows, list items, dropdowns,
  buttons (general, save, cancel, delete, icon), pills, fields, notification cards and
  toasts, the volume OSD, the message pill, tooltips, the settings window, calendar days,
  checkboxes, the lock screen (docs/plans/themes-stage7.md). New: borders along the
  bar's edge facing the desktop (following it if the bar moves to another edge), around
  popups — one line down their curved ears, sides and bottom, open where they join the
  bar, so it carries on from the bar's — and around bar cells, toasts, the volume OSD and
  the message pill, each with its own width and colour (none by default). The Bar page sets the cells' margin, the widgets' spacing and
  the bar's border.
- Theme files: `~/.config/h2s_shell/themes/<name>.json` sets colours and fonts over the
  built-in look, can `extend` another theme and take colours from a palette file
  (`colorsFrom`, e.g. from matugen). The setting "Theme" picks one per profile; files are
  watched, so an edit applies at once.
- Animations by role: every animation takes its duration and curve from the theme
  (`durations`, `curves`: hover, state, expand, popup, enter, exit, move, slide, fade,
  value, heartbeat, pop, pulse, spin, …). Per profile: "Animation speed" and "Reduce
  motion", for now on the General page with the theme name.
- Colours change smoothly under the pointer (bar cells, tray icons, buttons, list rows,
  sliders, links — the "hover" animation role), and the workspace buttons fade between
  focused, active and hovered ("state").
- Switching to a profile with another theme (Power save on battery, say) slides the bar
  into its new shape ("slide"); the space kept free for windows changes at once.
- The notification bell fades to the accent and jumps when a notification arrives; the
  dictation icon fades between its states; volume sliders and the volume OSD follow the
  volume keys smoothly ("value"), while dragging stays immediate.
- Changing theme fades the colours over ("themeChange"), also when a theme file is changed
  by another program, such as matugen; edits from the settings apply at once.
- Tray icons grow in when an application adds one ("enter"); networks and Bluetooth
  devices found by a scan fade in, and re-sorted networks slide to their place ("move").
- Settings: the mark of the selected page slides to the new one and the page fades in;
  page names highlight under the pointer.
- Calendar: months slide past each other, the new one coming from its side, and the selected day and
  week move smoothly. Music: a new track's title and cover fade in.
- When a profile change adds or removes widgets on the bar, they grow in and shrink away
  ("enter", "exit"), and the widgets beside them slide over. The lock screen fades in,
  and waking it fades the notifications out and the password prompt in.
- A curves library, `~/.config/h2s_shell/curves.json`: named cubic Béziers
  (`"springy": [0.3, 1.6, 0.4, 0.9]`) that a theme's `curves` can use by name, alongside
  Qt's own (OutQuad, OutBack, …). Watched, like themes; an unknown curve falls back to
  OutQuad and is reported.
- Settings → Curves: an editor for the curves library — a graph with two draggable control
  points (scroll to zoom), exact numbers, a looping preview against a second curve with
  a dot following each curve on the graph, new curves blank or copied from Qt's, rename
  (themes using the curve follow), delete (asking first), and where each curve is used.
  Curves can have more points: double-click the curve to add one, select a point to
  type its position, remove it, or switch off "Smooth" for a corner there.
- Settings has two tabs: Behaviour, whose pages edit a profile (picked at the top of the
  sidebar, which also says which theme that profile uses, a click away), and Appearance,
  whose pages edit a theme (picked the same way, starting at the edited profile's theme,
  saying which profiles use it, with "Preview" to try the theme on the whole shell while
  editing it — saved nowhere, the theme list locked meanwhile, ended by "Stop preview",
  leaving Appearance or closing the window). Appearance's first page, Themes, shows who
  uses the picked theme and what is wrong with it, sets what it extends, and makes a
  new theme (extending it, or as a copy), renames it (themes and profiles follow) or
  deletes it (asking first; profiles using it go back to the default theme). Curves moved
  into the group.
- Settings → Appearance → Colors: every base colour of the picked theme, by group, with
  what it is for and where its value comes from (set here, inherited, a palette, built
  in), and a colour picker (saturation and brightness, hue, opacity, hex). Changes are
  drafts, kept in `~/.config/h2s_shell/theme-drafts/` until saved — across restarts too:
  the page has Save and Cancel, a banner offers to save or throw away all of a theme's
  changes, ✎ marks the pages and themes with unsaved changes, and Preview shows a theme
  with its changes (also the theme in use, when it has some). Reset returns a colour to
  the inherited value; Undo takes back one colour's unsaved change.
- Settings → Appearance → Fonts: the theme's font family, picked from the installed fonts
  (searchable, each shown in itself), and its 13 sizes, each with a sample, a slider,
  where its value comes from, Reset and Undo; drafts like colours. Warns when the bar's
  larger icons would not fit its cells.
- Settings → Appearance → Bar: the bar's size, margins and corners, moved from the Bar page
  (which keeps the widgets) into the theme's pages, as drafts with Reset and Undo.
- Settings → Appearance → Animations: each animation role's duration and curve (a
  popup's two), from the curves library or Qt's, with where each comes from, Reset, Undo
  and a preview that plays it; drafts like the other theme pages.
- Settings → Appearance: Widgets (bar cells, workspace pills, tray icons), Popups, Controls,
  Notifications and Other pages — every shape token of the theme (radii, padding,
  sizes, border widths) with a slider, where its value comes from, Reset and Undo, as
  drafts. Border colours are in Colors → Borders.

### Changed
- Calendar: deleting a single event asks on its ✕ button, which turns into "Delete?"
  with a × to cancel, like every other delete; an event of a series still offers what
  to delete.
- One checkbox everywhere: the calendar list in the calendar settings uses the event
  form's look (14 px, a muted outline when unchecked), and every checkbox takes the
  keyboard focus on Tab and toggles with Space.
- Popups, the calendar and the settings window's sidebar grow with the theme's text size;
  each popup's width (and all of them at once) can be widened or narrowed in Appearance →
  Popups → Widths, shown with the width it comes to. Wi-Fi rows grow with their content,
  the events header gives way when narrow, and the event form's repeat row wraps instead
  of running out of its card.
- Save buttons take the confirm colour (adding) or the second confirm colour (saving a
  change), as the event form's did; the event form's buttons are the shared ones. Profile
  cards have the common card radius (6), the toast queue badge the toast's (8).
- Dropdowns and pickers float over the content instead of pushing it down: the event
  form's repeat frequency and calendar, the Bar page's "+ Add widget", the hardware
  sources' "+ Add source", the Theme setting's suggestions. They open upwards when there
  is no room below, and a click elsewhere closes them.
- Text fields are one shared component everywhere (settings, Wi-Fi, the event form, the
  colour and curve editors): the same look, focus outline and placeholder; password
  fields have an eye to show what is typed.
- The event form's time fields: "HH" and "MM" placeholders in their own segments; one
  minute digit means tens ("3" → 30), one hour digit that hour ("1" → 01), also when
  clicking away; an hour that can only be one digit moves straight on ("7" → 07); Up and
  Down step the value; Backspace in empty minutes goes back to the hours.
- Buttons, pills and switches are shared components everywhere: the Network, Bluetooth
  and calendar settings buttons, the preset and choice pills, the event form's choices,
  every on/off switch, the slider's tooltip. Small changes follow: Network VPN, scan and
  Bluetooth buttons have the common rounded corners and height; a running scan shows as
  a filled button; disconnecting is red under the pointer.
- Forgetting a Wi-Fi network or a Bluetooth device, and disconnecting the Google account,
  ask first, like every other delete.
- Settings pages are named by id: `qs ipc call settings openPage` takes a page's id
  (`profiles`, `bar_appearance`, …), not its label.
- Ready for larger fonts: buttons, pills, fields, icon buttons, Bluetooth device cards,
  event cards and calendar rows grow with their text instead of letting it spill out
  (today's sizes are the minimum, so nothing changes at the default sizes); long names in
  the settings sidebar and label columns are cut with "…"; the notification bell and
  the small symbols (×, ✓, ▾) take their font from the theme.
- A click anywhere in the settings window or a popup — the background too — takes the
  focus from a text field; before, only clicking another control did. (It watches clicks
  without a cursor of its own, so controls keep their pointing-hand cursor.)
- The "Theme" setting suggests the theme files as you type (and "default"), and warns
  when the name has no file.
- Deleting a profile, a widget preset or a curve asks the same way everywhere: the button
  turns into a red question with a "×" attached to cancel.
- Animations of a kind share one timing: expanding and collapsing takes 150 ms everywhere
  (was 120–200), a notification card arrives in 250 ms (was 200), the password field's
  colour changes in 150 ms (was 120).
- The bar's geometry (height, reserved space, offset, margins, padding, corners) is part
  of the theme instead of a profile setting. Each profile that had its own geometry gets
  a theme named after it with those values (Power save's extends Full's), so the bar
  looks as before. The sliders on the Bar page edit the theme of the profile being
  edited — and so every profile that uses it.
- Colours are named by role and come only from the theme: one red, one green and one
  blue where there were several shades (the disconnect buttons, the lock screen's error
  and the calendar's connection status change shade slightly).

### Fixed
- Bluetooth: Scan scans. `bluetoothctl scan on` exits at once in recent BlueZ, and the
  scan ended with it, so nothing was ever found and "Scanning…" never showed.
- Curves page: the preview's second square moves with the curve compared with; both used
  to move with the curve being edited.
- Music visualiser: the right channel of the vertical layout stays at the panel's edge
  when popups are made wider or narrower; the channels' order no longer depends on how
  often the canvases happened to repaint.
- The notifications popup ends 16 px above the bottom of the screen, whatever the bar's
  height; it used to assume a 40 px bar and, with a taller one, run past the edge.
- Scrolling by notches (sliders, the music widget's next/previous track, the music
  panel's player) went the wrong way on the first notch, and on the first notch after
  turning the wheel back.
- Wi-Fi list: an open network and its typed password stay with that network; after a scan
  or a connection they used to jump to whichever network took its place in the list.
- The calendar's and the hardware popup's left curved corner no longer shows a faint seam
  next to the panel (the popup now comes to rest on whole pixels; while moving it does
  not, which made it jump at the bar's end).
- Notifications on the lock screen and screensaver have the same padding below as above.
- Switching from a taller popup to a shorter one animates the height too; the panel's
  background used to drop to the new height at once.
- Numbers no longer spill out of their columns: a slider's value ("3000 ms"), the
  track's times, mixer volumes, the volume OSD's "100%", the hex and coordinate fields.
- The lock screen never came on: locking and unlocking were lost when its settings
  became per profile.
- The screensaver's first fade after start keeps its full duration.
- Settings: the selected page's mark always slides (it sometimes jumped), and the Bar page
  no longer logs binding loops while editing a profile whose theme is not in use.
- The first opening of a popup no longer loses part of its animation: panels are
  compiled in the background after start, and new content renders once before the
  animation starts (the calendar dropped a third of its frames).
- Moving from one widget's popup to another's: the popup no longer crawls after its
  size at the right end of the bar, and the new content fades in as the popup moves
  instead of jumping in first.
- No more warnings in the log when an app stops playing with the sound popup open.

## [1.1.0] - 2026-10-29

### Added
- Toast settings, per profile: show toasts at all, how long each stays, and one at a time
  or a column of them (with how many). A column shows the newest on top, and only the
  oldest counts down, so they leave one at a time.
- Notification privacy on the screensaver and the lock screen, separately and per
  profile: show notifications in full, title only, or the app alone.

### Fixed
- The screensaver's start and end commands now run — they could be set but nothing ran
  them. They follow idle time rather than the screensaver's visibility, so locking the
  screen does not count as coming back, and they can differ per profile.
- Popups stay under the bar when it does not reach the screen edges, stopping short of
  its rounded ends; switching between popups of different widths keeps the edge they
  are held against and animates the width instead of jumping.
- A binding loop when a profile switched the system power profile.

## [1.0.0] - 2026-10-29

The first numbered version: the shell as it stands after the 2026-10 cleanup, which
began in February 2026 as a single Hyprland bar.

### Added
- **Shell profiles.** Every setting can differ per profile — named sets of overrides that
  apply while their conditions hold (on battery, battery level, power profile, screen
  locked, fullscreen window, open popup), layered in list order. New configs start with
  Full and Power save. A setting can be pinned as global, and some (debug switches, the
  dictation socket) always are. The settings window picks the profile every page edits
  and shows where each value comes from.
- **Performance settings:** polling rates for hardware, temperatures, disk and network,
  GPU load sampling, a graph heartbeat, the visualizer frame rate, and the system power
  profile — all per profile.
- **Widget presets** (formerly "widget profiles"): a shared library of widget settings,
  with usages, rename and delete; clock, hardware and workspaces may appear more than
  once in a section.
- History graphs for every hardware source and for network throughput (download and
  upload), with a heartbeat wave on each sample.
- Every GPU is listed with its own load, VRAM and temperature.
- Calendar load errors are shown in the panel, with a retry.
- `qs ipc call settings open | openPage <page> | toggle | close`, and
  `qs ipc call profiles simulate | clearSimulation | status`.
- The shell's version in the settings sidebar.

### Changed
- The config moved into profiles; settings from older configs are migrated once, with a
  backup next to the config.
- Network state follows NetworkManager's events instead of polling `nmcli`, and the
  hardware sources read `/proc` and `/sys` directly instead of spawning `cat`.
- One settings window for the whole shell instead of one per monitor.

### Fixed
- Months of random crashes: no live arrays bound to `Repeater.model`, and popup content
  is created after its window.
- The shell freezing while the calendar loaded, token refresh, all-day events, Wi-Fi
  names containing colons, notification action buttons, and many smaller issues — see
  the git history and `docs/TODO.md`.

### Security
- The Google client secret no longer appears on a process command line.
- The config directory is restricted to its owner (700, files 600).
- Workspace names are escaped in Hyprland dispatches.
