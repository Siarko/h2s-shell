# Plan: wallpapers managed by the shell

Requested 2026-11-11 (TODO 11.33), first for the Framework 12, where nothing sets a
wallpaper today (Hyprland's default shows). On the host a script does it:
`~/tools/wallpaper_selector.sh` (desktop entry "Wallpaper Roulette") picks one random file
from `~/Pictures/wallpapers` per monitor and hands it to hyprpaper, which Hyprland starts.
The shell's feature replaces both where it is turned on; on the host it stays off until
the user decides.

Out of scope for now (later, separately): the wallpaper as the lock screen's background,
and matugen colours from it (TODO 11.7).

## How it is drawn

The shell draws the wallpaper itself: one layer-shell surface per screen on the
**background** layer, no external daemon.

- Per-workspace wallpapers switch with the workspace, cross-faded (the theme's durations),
  which a script around hyprpaper could only do by listening to events and reloading.
- Settings are ordinary schema keys, so they are **per profile** like every other setting
  (one fixed wallpaper on battery, say).
- Only what is shown is decoded, at the screen's size (`sourceSize`): the current image of
  each screen, and the next one during a fade. Workspace wallpapers not on screen are paths
  only.
- Turned off, the shell draws nothing. Turned on next to another wallpaper daemon, both
  draw on the background layer and either may win — the setting's hint says so.

## Settings and the flow

1. **Enabled** — off by default.
2. **Source** — a file or a folder.
   - A **file**: the same image everywhere; everything below is off.
   - A **folder**: searched with its subfolders **down to a depth** (a setting, default 2);
     images only (jpg, jpeg, png, webp, bmp). Optionally a **chosen subset** of its images
     (picked from the thumbnails); none chosen means all.
3. **Fit** — cover (fill, cropped), contain (whole image, a background colour around it),
   centre (actual size), tile. Background colour for contain/centre.
4. **Scope** — one everywhere, one per monitor (by port, as the toasts), one per
   workspace (workspace numbers; special workspaces have none and keep the monitor's
   current image).
5. **Mode** —
   - **Fixed**: a wallpaper chosen per slot of the scope (the one, each monitor, or each
     workspace) from the thumbnails. Not every slot has to be chosen: a slot without one
     takes the first chosen (the lowest workspace number, the first monitor in the
     compositor's order).
   - **Random**: drawn at start, every **interval** (a setting, off = only at start and on
     demand), and on demand; per the scope. **No repeats**: drawn without replacement from
     the pool, so two monitors or workspaces never share an image while others are left;
     reshuffled when the pool runs out. **Pinned slots**: chosen monitors or workspaces keep
     a fixed wallpaper while the rest are drawn (a workspace's pin before its monitor's,
     whatever the scope).
   - **By weekday**: a wallpaper per day of the week, the same everywhere, changing at
     midnight. Pinned slots as in random.
6. **Shuffle now** — draws again (random) or re-reads the folder (any mode): a button in the
   settings, `ipc call wallpaper shuffle` (for a Hyprland keybind), later perhaps a bar
   widget.

A missing file (deleted, a drive not mounted) falls back like an unchosen slot; with
nothing left the shell draws the background colour and logs once.

## Picking with thumbnails

A grid of the folder's images (async `Image`, small `sourceSize`, cached), usable by
finger as well as mouse. Two uses: choosing the subset (toggle each image) and assigning
an image to a slot (pick a slot — the one, a monitor, a workspace — then an image). The
folder is listed by a `find -maxdepth` Process in the singleton, not by the page.
Thumbnails are decoded by Qt from the full images: 137 images of the Framework's folder,
some 4K, take a moment the first time the page opens; a thumbnail cache on disk is left
for later if that proves slow.

## Code

- `singletons/WallpaperRules.qml` — pure: which file each screen shows, given the
  settings, the screens, their active workspaces, the pool, the draw and the date. Tested
  case by case in `tests/WallpaperRulesTest.qml` (fallbacks, no repeats, pinned slots,
  weekday, missing files).
- `singletons/Wallpapers.qml` — state and I/O: the folder listing, the current draw, the
  interval and midnight timers, the IPC handler.
- `wallpaper/WallpaperSurface.qml` — the background-layer window per screen, with the
  fade.
- Schema keys `wallpaper.*`; the structured ones (subset, fixed assignments, pinned slots,
  weekdays) as custom editors, overridden as a whole like the bar sections.
- `panels/settings/WallpaperSettings.qml` — the page, gating options with `available:`.

## Stages

1. Drawing: the surface, enabled, a single file, fit and background colour. Verified on
   the Framework.
2. A folder: listing with depth, random per scope, no repeats, interval, shuffle (button
   and IPC).
3. Thumbnails: the grid, the subset, fixed assignments, pinned slots.
4. By weekday.
5. Optional: a bar widget to shuffle.

## Decided (2026-11-11)

- By weekday: one wallpaper per day, the same everywhere; pinned slots for exceptions.
- Random: drawn again at every start of the shell.
- Another program drawing a wallpaper (found in `hyprctl layers -j`, background level, not
  our namespace `h2s-wallpaper`): a warning on the settings page only.
- Paths: a field, plus "Choose a folder…" / "Choose an image…" buttons opening Qt's
  dialog (a window of its own on the host; to be seen on the Framework).
- Thumbnails load lazily (a GridView creates only the visible ones).
- Fixed choices (`wallpaper.assignments`) and pins (`wallpaper.pinned`) are separate
  settings, so switching the mode does not turn one into the other.

## Progress

- 2026-11-11: stages 1 and 2 — the surface with the fade, the rules (all modes, tested,
  weekday and pins included), the listing, the draw, interval, midnight, shuffle (button
  and IPC), the warning, the page without the thumbnails.
- 2026-11-11: stages 3 and 4 — the thumbnail grid (a GridView: only the thumbnails in
  view exist), the subset, fixed choices, pins and the weekdays on the page, one grid
  for all: pick a place, then click thumbnails. Checked on the Framework by touch.
  Left: stage 5 (a bar widget to shuffle), optional.
- 2026-11-12: the page rebuilt mode first (the user's choice): the source, then "How
  images are chosen" as three cards (By me, At random, By day) with only that mode's
  section beneath — its places, which open the thumbnails for that one place with a
  title and Done; the images to draw from only at random; exceptions (pins) shown as the
  pinned places plus Add — then Look (fit, background). Alternatives kept as a
  throwaway prototype (`prototype-wallpaper.qml`, not committed): a sentence of
  choices, a screens map (one rule, places that differ), a summary with steps.
- 2026-11-12: transitions, in the theme (group `wallpaper`: `transition`,
  `workspaceTransition`; roles `wallpaper`, `wallpaperWorkspace` with library curves). A
  workspace switch slides the way the numbers go, or changes as a new image; a new image
  fades, zooms, slides, or runs the shader (wipe, circle, dissolve, pixelate) only for the
  change. Circle, pixelate and slide checked on the Framework.
- 2026-11-12: a workspace switch showed its wallpaper about a second late — decoding:
  measured on the Framework, a 4K JPEG at screen size 180 ms, a 19 MB PNG 586 ms (37 of
  the folder's 137 are PNG); Hyprland's workspace event reaches Quickshell within 25 ms.
  The surface now decodes the nearest workspaces' images ahead (up to four, kept in Qt's
  pixmap cache and shared with the image shown), and the random draw covers the existing
  workspaces and the ones beside those shown, so there is something to preload.
- 2026-11-12: copies resized to the screen (the user's idea): vipsthumbnail, at low
  priority, a JPEG Q92 per image, screen size and fit in `~/.cache/h2s_shell/wallpapers`,
  named by WallpaperRules.screenCopyName (path, modification time and size, physical
  pixels, fit), 300 MB at most, oldest first. Measured on the Framework at screen size:
  JPEG 80 ms, BMP 50 ms, PPM 23 ms (16 MB each), PNG 323 ms, the 19 MB original PNG 586 ms;
  WebP does not load there at all (no Qt plugin) — the copies fix that too. ~/.cache
  rather than /tmp: /tmp is RAM on the host but disk on the Framework, never cleared.
  libvips joins the dependencies (install.sh, nix/package.nix).

