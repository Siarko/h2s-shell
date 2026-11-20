# Taildrop: the views reworked, and a side panel for module pages

Status: a plan, for the owner's approval. Nothing here is built. It answers the owner's look
at a mockup of today's views (2026-11-20): the settings page's Taildrop part is unreadable,
the popup's files panel has too many buttons and squeezes file names, problems do not stand
out; the one-panel popup is fine. It reworks §3.6 of [taildrop-transfers.md](taildrop-transfers.md)
(built). One core slice (module API 1.34: a side panel for a module's page), then module
slices. Paths: core `api/…`, `panels/…`; module `module/…` (repository h2s-shell-tailscale).

## 1. What exists today

- **The page** (`module/TaildropSection.qml`, placed at `TailscalePage.qml:531`): all of
  Taildrop in one column — operator line (156–175), target pills (183–207), files chooser,
  pasted paths and drop area (210–297), Send (298–307), waiting files with Save / Open folder
  (316–347), incoming rows (350–360), the transfers list (361–366: per transfer a bold title
  with Cancel or Clear, 97–136, then `TaildropFileRow`s), then the settings: Save to (369–395),
  If the name is taken (401–417), auto-save (418–432), Transfer notifications (434–450). No
  separation between one device's transfer and the next.
- **A file's row** (`module/TaildropFileRow.qml`): name, state text (capped at half the
  width, 45–54) and the buttons (Skip, "Send now" / "Fetch now", 55–74) all on **one line**
  (36–75), then the bar. A stall ("No progress for 3 min") plus two buttons leave the name a
  few characters ("vi…p4"). The bar stays "normal" while stalled
  (`TaildropTransferRules.fileRow`, `module/TaildropTransferRules.qml:254-283`); failed is
  "danger" with warning-coloured text.
- **Offers:** `fileOffers` (222–252): `skip` "Skip" on queued/active files; `now` "Send now"
  / "Fetch now" on a stalled file when its extra slot would start a waiting file
  (`schedule` decides). `transferOffers` (373–379): "Cancel" / "Clear". Neither asks first.
  `notification` (761–) reuses `fileOffers`' labels for its actions.
- **Popup, two panels** (`module/TailscalePopup.qml:50-65`, `TaildropTransferRules.popupSplit`
  660–677, more than 2 files): left, each device's `TaildropSendRow` → `TaildropPopupState`
  with label, text, **Cancel** (54–63) and a bar; right, `module/TaildropFilesPanel.qml`: per
  device a header (title + Cancel/Clear, 152–186) and the file rows, headers only 6 px apart
  (149), no rule between devices (`popupPanel`, 679–715).
- **Popup, one panel:** the same device line plus the first stalled file as one line
  "a.txt · No progress for 3 min" with Skip and "Send now" (`TaildropPopupState.qml:86-117`);
  ended: "×" clears without asking (64–74). `TaildropRules._popupState`
  (`module/TaildropRules.qml:419-445`), `popupSave` (605–658).
- **Asking first, available today:** the public `SmallButton` has `confirm`, `confirmLabel`,
  `cancelTip`, `asking` (`api/Api.qml:504-525`; inside it is `components/DeleteButton.qml`:
  the button turns into the question with a "×" that takes it back). The module's
  `module/ConfirmButton.qml` is that button plus `subject` (the question dropped when what it
  acts on changes) and dropped when hidden. So `ConfirmButton { label: "×"; confirmLabel:
  "Cancel?" }` already draws "Cancel? | ×". **No API element is missing for the ask-first
  "×".**
- **The Wi-Fi side panel** (`panels/settings/NetworkWifiSettings.qml`): opened by "Find
  networks" (162–167), a scrim over the page that closes it on a click (425–436), a panel
  `min(420, 90 %)` wide sliding from the right (438–500) with a title and "Close". It does
  not close on Escape or a lock. It is the page's own code; a module page cannot do this: the
  page sits **inside** the window's Flickable (`panels/SettingsWindow.qml:551-574`), so
  anything a module draws scrolls with the page and cannot cover the page area.
- **"Admin console"** — every one opens Tailscale's admin console at login.tailscale.com:
  `CertSection.qml:78` (`/admin/dns`), `ServeSection.qml:99` (a problem's URL: `/admin/dns`
  or `/admin/acls`, `ServeRules.qml:264-273`), `TailscalePopup.qml:365` (`/admin/machines`).
  Not in the owner's list but the same: `LockSection.qml:46` ("Admin console", the machine's
  page), `SharingSection.qml:189` and `TailscalePage.qml:442` ("Open the admin console"),
  the hint at `SharingSection.qml:186` ("…in the admin console"). None opens anything else.
  The device's own web interface is the switch "Web interface" (`SharingSection.qml:243`,
  port 5252, its URL opened at 264).

## 2. Words and behaviour (all views)

- **One "×" for stopping, always asking.** Per file: "×" → "Cancel? | ×"; the second click
  stops that file, the rest go on (today's Skip). Per transfer group (a device's sends, the
  saves): "×" → "Cancel? | ×", stops all its files. Tooltips before the click: "Cancel this
  file", "Cancel all files". The trigger stands at the right end of its line, so the button
  grows leftwards and a quick double click lands on the "×" that takes it back. Kind
  `danger` (stops). A stopped file reads "Cancelled" (the state `skipped` stays internal).
- **"×" without asking only where nothing stops:** a chosen file taken off the list, a
  popup choice dropped. An ended transfer's "×" (one-panel popup today) becomes "Clear", so
  a "×" in a transfer always means "stop, after asking".
- **"Send now" / "Fetch now"**, in plain words: a device's files go one at a time. When one
  stops moving (no progress for 2 min), the files behind it wait. "Send now" starts the next
  waiting file beside the stuck one; the stuck one keeps going and may still finish (a large
  file at 90 % is not lost). "×" on the stuck file instead gives up on it, and the next file
  starts too. **With one file listed** (or the stuck file the last of its device) nothing
  waits behind it, so "Send now" never shows (`fileOffers` already asks `schedule`); the only
  choice is to wait or "×" — which with one file is the same as cancelling the transfer:
  that is why Skip and Cancel became one "×". The plan keeps "Send now", only on the stalled
  file's second line, after the warning text (Q2).
- **A file name is always visible:** its own line, nothing beside it. State text and
  buttons go on the line under it; a long reason elides there, never the name.
- **A problem** (stalled, failed, refused) → the bar `kind: "warning"` and the text
  `Api.theme.warning`; a device or saves line whose files include one takes the warning
  bar and tone too. Failed files move from "danger" to "warning" (the owner's rule).
- **"Web console"** replaces "Admin console" and "Open the admin console" in all six places
  and the hint ("…in the web console"); tooltip "login.tailscale.com". The device's own
  "Web interface" switch keeps its name (Q4).
- **Notifications** keep their actions ("Skip", "Send now") for now: a notification cannot
  ask first; their words belong to the pending notification flow analysis (tracker).

## 3. The views

**The page** (`TailscalePage.qml`, Taildrop part): one summary row, the settings, a rule.

```
Taildrop
2 sending · 1 file waiting                              [Files…]   ← drop files here too
Save to  /home/user/Downloads                  [Choose…] [Default]
If the name is taken  [Keep both ▾]
Save incoming files automatically                            (o)
Transfer notifications  [On screen until done ▾]
```
The summary is one rule (`pageSummary`): empty when nothing happens, else
"2 sending", "Saving 1 of 3", "3 files waiting", joined by " · "; warning tone when a file
stalls or failed ("No progress on 1 file"). Not the operator: today's line and button stay
here. Dropping files on the row adds them to the send list and opens the panel. The
settings stay on the page (they are settings, not transfers; Q1).

**The side panel** (`module/TaildropPanel.qml`, new, inside the API's `SidePanel`, size "l"):

```
┌──────── page, dimmed ────────┬ Taildrop ──────────────────────── [Close] ┐
│                              │ [laptop] [phone] (tablet) (desk · offline)│
│                              │ [Choose files…] [Paste paths or drop] [Add]
│                              │ report.pdf                              × │
│                              │ notes.txt                               × │
│                              │ [Send to 2 devices]   (running, none chosen: × → "Cancel?")
│                              │ ───────────────────────────────────────── │
│                              │ 2 files waiting · f.bin, g.bin            │
│                              │ [Save] [Open folder]                      │
│                              │ photo.jpg                                 │
│                              │ Receiving · 40 %                          │
│                              │ ▓▓▓▓▓▓░░░░░░░░░                           │
│                              │ ───────────────────────────────────────── │
│                              │ To laptop · 3 files                     × │
│                              │ a.txt                                     │
│                              │ Sent                                      │
│                              │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ success                   │
│                              │ b.txt                                     │
│                              │ 40 %                                    × │
│                              │ ▓▓▓▓▓░░░░░░░░░░                           │
│                              │ ───────────────────────────────────────── │
│                              │ To phone · 2 files                      × │
│                              │ video.mp4                                 │
│                              │ No progress for 3 min        Send now   × │  warning
│                              │ ▓▓▓▓░░░░░░░░░░░ warning                   │
│                              │ ───────────────────────────────────────── │
│                              │ Saving 2 files                          × │ …
└──────────────────────────────┴───────────────────────────────────────────┘
```
Send flow as decided: files, devices (pills), Send; while sends started there run and no
file is chosen, the same place shows "×" → "Cancel?" (all running sends). A 1-px rule
(`Api.theme.divider`) under the send part, the receive part and **each device's group**.

**Popup, two panels** — left: device rows without buttons for their sends (one line of
state and the bar; the "×" lives in the files panel). Right: a rule above every header but
the first, the header bold, file rows as on the panel.

```
 Tailscale  Tailnet only [Disconnect] │ laptop                         × │
 Devices                              │ a.txt                            │
 ● laptop  100.64.0.9   [Send file…]  │ Sent                             │
   3 files · 46 %                     │ ▓▓▓▓▓▓▓▓▓▓▓▓ success             │
   ▓▓▓▓▓░░░░░                         │ b.txt                            │
 ● phone   100.64.0.9   [Send file…]  │ 40 %                           × │
   2 files · No progress    (warning) │ ▓▓▓▓░░░░░░░                      │
   ▓▓░░░░░░░░ warning                 │ ──────────────────────────────── │
 Saving 1 of 2                        │ phone                          × │
   ▓▓▓▓░░░░░░                         │ video.mp4                        │
 [Settings…]          [Web console]   │ No progress for 3 min Send now × │
                                      │ ▓▓▓░░░░░░░ warning               │
```

**Popup, one panel** (kept; the general rules applied):

```
 ● laptop   100.64.0.9          [Send file…]
   2 files                       20 %    ×      ← a count: text and "×" on its line
   ▓▓░░░░░░░░ warning (a file stalls)
   a.txt                                        ← the stalled file: its name alone
   No progress for 3 min      Send now   ×      warning
 ● phone … video.mp4                            ← one file: its name alone, then
   No progress for 3 min      Send now   ×        its text and "×" under it
```

## 4. Rules (module, pure, with cases)

`module/TaildropTransferRules.qml`:
- `fileOffers` → `[{ action: "cancel" | "now", label, confirm, confirmLabel, tooltip }]`:
  `cancel` "×" / "Cancel?" / "Cancel this file" on queued and active files; `now` as today.
  The view renders exactly these (label, question and action one decision).
- `fileRow` → adds `tone` ("normal" | "success" | "warning" | "muted"); stalled → bar
  `warning`, tone warning; failed → bar `warning`; skipped → "Cancelled".
- `transferOffers` → "×"/"Cancel?"/"Cancel all files" (confirm) while running, "Clear" ended.
- `popupPanel` → headers carry `rule: true` (all but the first) and the new offers.
- `popupDevice` / `popupSave` → `problem: true` when a shown file stalls or failed (warning
  bar and tone); `popupSave`'s `canCancel` offer as transferOffers'.
- `pageSummary(transfers, waitingCount, options)` (new) → `{ text, tone }`.
- `sendButton` → `{ action: "send" | "cancel", label, available, confirm, confirmLabel,
  targetIds, cancelIds }`: Send with files chosen; "×" asking while sends from the page run
  and nothing is chosen.
- `notification` → maps `cancel` back to its own "Skip" label (no change on screen).
`module/TaildropRules.qml`: `_popupState` → `cancel` offer as above, `split` → no offers,
`nameLine` (the label is a file name: text and "×" go under it), "Clear" instead of "×".

## 5. Module API 1.34: `SidePanel` (core slice C1)

A public element any module may use on its settings page: a panel sliding in from the
right over the page area, with the module's own content from public elements.

Reference text outline (`api/Api.qml`, public elements, after HoverTip):
```
//   SidePanel              (1.34) a panel from the right over a module's settings page:
//                          open (the owner sets true; the panel sets it false when it
//                          closes itself), title (one line, plain), size: "s" | "m" (the
//                          default) | "l" — the theme's widths, never wider than 90 % of
//                          the page area; closed(reason) — reason "close" (its Close
//                          button), "outside" (a click on the dimmed page beside it),
//                          "escape", "replaced" (another SidePanel opened), "page" (the
//                          page changed, the window closed, the module went away), "lock"
//                          (the session locked). Its one child, written inside it, is
//                          its content (`content`, a Component): built when it opens,
//                          destroyed when it has closed, laid out at the panel's inner
//                          width; the panel scrolls it below a fixed title line when it is
//                          taller — the content must not scroll itself. One open at a time
//                          per window. Written anywhere in a module's page tree; elsewhere
//                          (a popup panel, an anchor, the bar) it does not open: `open`
//                          goes back to false, logged once. Takes no room where written.
//                          In module test mode the test kit's page frame hosts it
//                          (ModuleTestKit.pageFrame), and setSessionLocked closes it.
```
Core work: an internal `components/SideDrawer.qml` (scrim, slide with `Theme.duration
("slide")`, reduce-motion, Close, Escape with key focus taken on open and given back, a
Dropdown's list closes before the panel); the module page frame (`SettingsWindow.qml`
`_modulePageComp`) gets a layer outside its Flickable that hosts it; `api/SidePanel.qml`
finds that host by walking up its parents (no name a module could use); widths in `Theme`
(`settings.sidePanel`: s 320, m 420, l 520, scaled); decisions (`width`, which event closes)
in `ApiElementRules`; `ModuleRules.apiVersion` "1.34"; CHANGELOG `### Module API` line;
`docs/ARCHITECTURE.md` "Modules" names the element; `tests/ApiElementsTest.qml` pins it.

## 6. Slices

Core on a work branch (`tests/run-unit.sh <suites>` while iterating, `tests/run-all.sh`
before the commit); module against a core tree nobody edits (`H2S_SHELL_DIR=… tests/run.sh
<suites>`, all three runners before the commit). Module minor 0.8.0 (or with 0.7.0 if that
is not released yet), a CHANGELOG line per user-visible slice. Reviewer: a second agent
with the diff only.

| # | Slice | Changes | Tests |
|---|---|---|---|
| C1 | **SidePanel, API 1.34** (core) | §5 | `ApiElementRulesTest` (widths per size and page width, unknown size → "m" logged once, close events); new `SidePanelTest` (headless): opens on `open`, content built then destroyed after close; Close, click beside, Escape, a second panel → first `closed("replaced")`, page frame destroyed → "page", lock seam → "lock"; content taller than the window scrolls, title stays; a Dropdown inside opens over it and Escape closes the list first; outside a page frame `open` returns to false; `ApiElementsTest`; `VersionTest`/`ModuleRulesTest` for 1.34; the test kit's `pageFrame` in the fixture module `good` (run-modules) |
| M1 | **The rules** | §4 in both rules files; IPC `skipFile` keeps its name (`docs/ipc.md`: "cancels one file") | `TaildropTransferTest`: offers per state with label, question, tooltip; "Send now" absent with one file and with the stuck file last; `fileRow` tones and warning bars (stalled, failed); `transferOffers`; `popupPanel` rules flags; `pageSummary` (idle → "", sending, saving, waiting, a stall → warning); `sendButton` (none, files chosen, sends running and none chosen → cancel); `notification` still "Skip". `TaildropTest`: `_popupState` (`nameLine` for one file, no offers when split, "Clear") |
| M2 | **The file row and the files panel** | `TaildropFileRow`: name line alone, second line text + `ConfirmButton` "×" (subject = file key) + "Send now", warning bar; `TaildropFilesPanel`: rule above headers, header "×" asking; `TaildropSendRow`/`TaildropPopupState` in split: no buttons, warning bar | `TaildropListTest`/`TailscaleUiTest` popup cases: a 40-character name stays whole beside a stall at the panel width (text width check); first "×" click asks, nothing stopped; second stops only that file; "×" of the question takes it back; a header "×" stops all; question dropped when the file ends; a rule between two devices, none above the first; split device rows have no buttons |
| M3 | **The one-panel popup** | `TaildropPopupState`: stall as two lines (name; warning text, "Send now", "×"), device "×" asking, "Clear", `nameLine` | `TailscaleUiTest`: one file → name alone on its line; a stall → two lines in warning, bar warning; "×" asks then cancels; "Clear" clears |
| M4 | **The side panel on the page** | manifest `api` 1.34; `module/TaildropPanel.qml` (send flow, received part, transfers by device with rules); `TaildropSection` reduced to the summary row with "Files…" and drop, the settings | `TaildropListTest` moved to the panel inside `ModuleTestKit.pageFrame`: "Files…" opens it, summary text and tone per state, a drop on the row adds the files and opens it, Escape and lock close it, the list keeps row identity (keys), Send → "×" while running; `TailscaleUiTest` page: no transfer rows on the page itself |
| M5 | **"Web console"** | the six labels and the hint, tooltip; `docs/features.md` | a `TailscaleUiTest` case: no "Admin console" text left in the page and popup objects; grep in review |
| M6 | **Docs and a look** | `docs/features.md` (panel, words, "×"), CHANGELOG, release line | the owner or the lead looks at the page, the panel and both popup layouts on a screen (theme light/dark, a small screen) |
| C2 | **Wi-Fi on the same drawer** (core, after M6) | `NetworkWifiSettings` uses `components/SideDrawer.qml`: gains Escape and closing on lock | a `SidePanelTest` case on the internal drawer; the Wi-Fi page by hand |

Order: C1 → M1 → M2 → M3 → M4 → M5 → M6, C2 last. M1–M3 and M5 need nothing new from the
core (they may start before C1 is merged); M4 needs C1 merged. One agent at a time on the
module (M2 and M3 share `TaildropPopupState.qml`).

## 7. Open questions for the owner

1. **Settings on the page or in the panel?** The plan moves everything that sends,
   receives and lists files into the panel, and leaves the four settings on the page: "Save
   to", "If the name is taken", "Save incoming files automatically", "Transfer
   notifications". Example: to change the download folder you would not open the panel.
   Should those four go into the panel too, so the page shows only "Taildrop · 2 sending
   [Files…]"?
2. **Keep "Send now" / "Fetch now"?** It appears only on a stalled file that has others
   waiting behind it (never with one file), on its warning line. Example: video.mp4 at 90 %
   has not moved for 3 min and song.ogg waits: "Send now" sends song.ogg while video.mp4
   keeps trying; "×" would give up video.mp4. The plan keeps it. Drop it, so a stall offers
   only "×"?
3. **The per-file "×" always visible?** The plan shows "×" on every queued or running file
   (one glyph each, Skip and "Send now" gone from normal rows). Example: 10 files to one
   device → 10 small "×". Should queued files show it only under the pointer (or a tap),
   keeping it always on running and stalled files?
4. **"Web console" beside "Web interface"?** "Web console" opens Tailscale's site
   (login.tailscale.com); the sharing section's switch "Web interface" serves this
   computer's own Tailscale settings to the tailnet on port 5252. Example: on the page,
   "Web console" under Serve and "Web interface" under Sharing read alike. Keep both
   names, or rename the switch (e.g. "Settings over the tailnet")?
