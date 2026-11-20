# Taildrop: the views reworked, a side panel for module pages, Taildrop off

Status: approved by the owner (2026-11-20), with the answers in §8. Nothing here is built.
It reworks §3.6 of [taildrop-transfers.md](taildrop-transfers.md) (built) after the owner's
looks at two mockups: the page's Taildrop part unreadable; files squeezed and not set apart;
problems not standing out; the one-panel popup fine. One core slice (module API 1.34: a side
panel for a module's page, headings with controls), then module slices. Paths: core `api/…`,
`panels/…`; module `module/…` (repository h2s-shell-tailscale).

## 1. What exists today

- **The page** (`module/TaildropSection.qml`, placed at `TailscalePage.qml:531`): all of
  Taildrop in one column — operator line (156–175), target pills (183–207), files chooser,
  pasted paths and drop area (210–297), Send (298–307), waiting files with Save / Open folder
  (316–347), incoming rows (350–360), the transfers list (361–366: per transfer a bold title
  with Cancel or Clear, 97–136, then `TaildropFileRow`s), then the settings: Save to (369–395),
  If the name is taken (401–417), auto-save (418–432), Transfer notifications (434–450).
- **A file's row** (`module/TaildropFileRow.qml`): name, state text (capped at half the
  width, 45–54) and the buttons (Skip, "Send now" / "Fetch now", 55–74) on **one line**
  (36–75), then the bar; rows are not set apart from each other. A stall plus two buttons
  leave the name a few characters ("vi…p4"). The bar stays "normal" while stalled
  (`TaildropTransferRules.fileRow`, `module/TaildropTransferRules.qml:254-283`); failed is
  "danger" with warning-coloured text.
- **Offers and scheduling:** `fileOffers` (222–252): `skip` on queued/active files; `now`
  on a **stalled** file, setting its `extraSlot` so that `schedule` (171–207) gives its pool
  one more slot (164, 182) and the next queued file starts beside it. `transferOffers`
  (373–379): "Cancel" / "Clear". Nothing asks first. `notification` (761–, its actions at
  ~798) reuses `fileOffers`.
- **Popup, two panels** (`module/TailscalePopup.qml:50-65`, `popupSplit` 660–677, more than
  2 files): left, each device's `TaildropSendRow` → `TaildropPopupState` with label, text,
  **Cancel** (54–63), bar; right, `module/TaildropFilesPanel.qml`: per device a header (title
  + Cancel/Clear, 152–186) and its own copy of the file rows (`popupPanel` 679–715).
- **Popup, one panel:** the device line plus the first stalled file as one line with Skip
  and "Send now" (`TaildropPopupState.qml:86-117`); ended: "×" clears (64–74).
  `TaildropRules._popupState` (`module/TaildropRules.qml:419-445`), `popupSave` (605–658).
  The popup's device rows are capsules: a `Rectangle`, `Api.theme.row.radius`,
  `Api.theme.surface` (`TailscalePopup.qml:243-250`).
- **Asking first:** the public `SmallButton` has `confirm`, `confirmLabel`, `cancelTip`,
  `asking` (`api/Api.qml:504-525`; inside, `components/DeleteButton.qml`). The module's
  `module/ConfirmButton.qml` adds `subject` (question dropped when its item changes) and
  drops it when hidden. `ConfirmButton { label: "×"; confirmLabel: "Cancel?" }` draws
  "Cancel? | ×". **No API element is missing for it.**
- **The Wi-Fi side panel** (`panels/settings/NetworkWifiSettings.qml`): "Find networks"
  (162–167), a scrim that closes on a click (425–436), a panel `min(420, 90 %)` wide from the
  right (438–500), title and "Close"; no Escape, no closing on a lock. A module page cannot do
  this: it sits **inside** the window's Flickable (`panels/SettingsWindow.qml:551-574`).
- **"Admin console"** — each opens login.tailscale.com: `CertSection.qml:78` (`/admin/dns`),
  `ServeSection.qml:99` (`/admin/dns` or `/admin/acls`, `ServeRules.qml:264-273`),
  `TailscalePopup.qml:365` (`/admin/machines`); also `LockSection.qml:46` (the machine's page),
  `SharingSection.qml:189` and `TailscalePage.qml:442` ("Open the admin console"), the hint at
  `SharingSection.qml:186`. None opens anything else. The device's own web interface is the
  switch "Web interface" (`SharingSection.qml:243`, port 5252).
- **Receiving** today: tailscaled accepts every file a tailnet peer sends into its own inbox;
  the module shows the count, notifies per arrival (`TaildropClient.qml:834-845`) and
  auto-saves when that is on (68–107, 514–561). With auto-save off the arrival notification
  offers "Save" (`TaildropClient.qml:849`), as do the popup's received part
  (`TailscalePopup.qml` "tailscalePopupSave") and the page (`TaildropSection.qml:331-336`);
  each saves into the settings' folder. The module API's chooser has a folder mode
  (`module.chooseFiles({ mode: "folder" })`, `api/Api.qml:869-872`, 1.17), already used by
  "Save to … Choose…" (`TaildropClient.qml:342-350`).
- **The page's layout:** the settings rows are the module's own `RowLayout`s, a label then
  its control (a dropdown right after the label, `TaildropSection.qml:401-417, 434-450`). The
  public `SettingsRow` (`api/SettingsRow.qml`) already puts its controls at the right end. The
  public `SectionTitle` is a plain bold `Text` (`panels/settings/SectionTitle.qml`): nothing
  can stand on its line. The Wi-Fi page's switch in its heading is that page's own code
  (`NetworkWifiSettings.qml:106-125`).

## 2. Can this computer refuse incoming files? (read-only findings)

- **No pref, no CLI flag:** `tailscale set --help` (1.104.7 here) has nothing for Taildrop;
  `tailscale file` has only `cp` and `get`; the prefs (`fixtures/prefs-rich.json`) have no
  such key; the LocalAPI's `files/` serves only listing, `GET` and `DELETE`.
- **The tailnet's admin:** the "Send files" setting (capabilities `cap/file-sharing`,
  `cap/file-sharing-target` and `cap/file-send` in the binary and in our status fixtures,
  `fixtures/status-exit-node.json:55,71`) — on or off for the whole tailnet, or per target
  through the tailnet policy. Not this computer's choice.
- **The daemon's environment:** `tailscaled` 1.104.7 contains the knob `TS_DISABLE_TAILDROP`
  (beside "Taildrop disabled; no storage directory"): set in tailscaled's service
  environment (root, a daemon restart) it presumably turns Taildrop off there — not verified.
- **So:** a real refusal exists only as a system setting of the daemon, not as a runtime
  pref. The plan's option is honest and module-only (§4.1); the daemon setting is neither
  written nor offered (§8.2).

## 3. Words and behaviour (all views)

- **One "×" for stopping, always asking.** Per file: "×" → "Cancel? | ×"; the second click
  stops that file, the rest go on (today's Skip). Per group (a device's sends, the saves):
  "×" → "Cancel? | ×", stops all its files. Tooltips: "Cancel this file", "Cancel all
  files". The trigger stands at the right end of its line, so the question grows leftwards
  and a quick double click lands on the "×" that takes it back. Kind `danger`. A stopped
  file reads "Cancelled" (the state `skipped` stays internal). "×" on every file (decided).
- **"×" without asking only where nothing stops:** a chosen file taken off the list, a popup
  choice dropped. An ended group's "×" (one-panel popup) becomes "Clear".
- **"Send now" / "Fetch now" on every waiting file.** A device's files go one at a time;
  the others wait ("Queued"). Each waiting file has "Send now" (a save's: "Fetch now"): it
  starts that file at once, beside what runs, without waiting for its turn. Example: two
  files to the phone — video.mp4 sends, song.ogg shows "Queued · Send now"; a click and both
  go. A stalled file offers only its "×" and its warning line ("No progress for 3 min"):
  going on beside it is "Send now" on a file behind it. With one file there is nothing
  waiting, so no "Send now" appears. The user's choice ignores the limit of 4 files at once.
  The one exception: a file of the same name already going to that device (Tailscale tells
  sends apart by peer and name, so the two would collide) — the button is greyed, tooltip
  "A file of this name is going there".
- **"Save" and "Save in…"** wherever received files are offered for saving — the arrival
  notification's actions, the popup's received part, the side panel's waiting files — while
  "Save incoming files automatically" is off: "Save" saves into the settings' folder as
  today; "Save in…" opens the folder chooser (the API's, folder mode, title "Save received
  files in") and saves this one batch there, the setting unchanged. A cancelled or blocked
  chooser saves nothing (its note shows as for "Choose…"). The per-file save script takes the
  folder of its transfer, with every safety step as today (absolute, not a link, the user's,
  writable, a private staging folder, `mv -T`, `DELETE` after the rename). With auto-save on,
  only "Save" (for what auto-save left).
- **A file name is always visible:** first line of its capsule, nothing beside it. State,
  bar and buttons go under it.
- **A problem** (stalled, failed, refused) → bar `kind: "warning"`, text `Api.theme.warning`;
  a device or saves line with such a file takes the warning bar and tone. Failed files move
  from "danger" to "warning".
- **"Web console"** replaces "Admin console" / "Open the admin console" in the six places
  and the hint ("…in the web console"); tooltip "login.tailscale.com"; the switch
  "Web interface" is renamed (§8.1).
- **Notifications** cannot ask first: their actions stay "Skip" on a stalled file and
  "Send now", which now starts the transfer's first waiting file (the same effect as
  before); their words belong to the pending notification flow analysis (tracker).

## 4. The views

**A file's capsule** (`module/TaildropFileCard.qml`, replacing `TaildropFileRow`; the one
file list `module/TaildropFileList.qml` — group headers, rules, capsules, keyed — used by
the side panel and the popup's files panel alike; full parity):

```
╭──────────────────────────────────────╮   ╭──────────────────────────────────────╮
│ video.mp4                            │   │ song.ogg                             │
│ No progress for 3 min              × │   │ Queued              [Send now]   × │
│ ▓▓▓▓▓░░░░░░░░░░░░░░ warning          │   ╰──────────────────────────────────────╯
╰──────────────────────────────────────╯     (no bar while queued)
```
`Rectangle`, `Api.theme.row.radius`, `Api.theme.surface`, inner margins from the small type
(as the popup's device rows); a few pixels between capsules; text tones per §3.

**The page** — the switch in the heading (as the Wi-Fi page's), the summary row, the four
settings (decided); every control — button, switch, dropdown — at the right end of its row
(public `SettingsRow`s):

```
Taildrop                                                     (o)   ← Taildrop on this computer
2 sending · 1 file waiting                              [Files…]   ← drop files here too
Save to /home/user/Downloads                   [Choose…] [Default]
If the name is taken                                [Keep both ▾]
Save incoming files automatically                            (o)
Transfer notifications                     [On screen until done ▾]
```
The summary is one rule (`pageSummary`): empty when nothing happens, else "2 sending",
"Saving 1 of 3", "3 files waiting", joined by " · "; warning tone on a stall or a failure
("No progress on 1 file"). Not the operator: today's line and button stay. Dropping files
on the row adds them to the send list and opens the panel. Off: §4.1.

**The side panel** (`module/TaildropPanel.qml`, inside the API's `SidePanel`, size "l"):

```
┌──── page, dimmed ────┬ Taildrop ─────────────────────────────── [Close] ┐
│                      │ [laptop] [phone] (tablet) (desk · offline)        │
│                      │ [Choose files…] [Paste paths or drop files] [Add] │
│                      │ report.pdf                                      × │
│                      │ notes.txt                                       × │
│                      │ [Send to 2 devices]  (sends running, none chosen: × → "Cancel?")
│                      │ ───────────────────────────────────────────────── │
│                      │ 2 files waiting · f.bin, g.bin                    │
│                      │              [Save] [Save in…] [Open folder]      │
│                      │ ╭ photo.jpg ╌ Receiving · 40 % ╌ bar ╮             │
│                      │ ───────────────────────────────────────────────── │
│                      │ To laptop · 3 files                             × │
│                      │ ╭ a.txt ╌ Sent ╌ bar success ╮                    │
│                      │ ╭ b.txt ╌ 40 %  × ╌ bar ╮                         │
│                      │ ╭ c.txt ╌ Queued  [Send now] × ╮                  │
│                      │ ───────────────────────────────────────────────── │
│                      │ To phone · 2 files                              × │
│                      │ ╭ video.mp4 ╌ No progress for 3 min  × ╌ bar warning ╮
│                      │ ╭ song.ogg ╌ Queued  [Send now] × ╮               │
│                      │ ───────────────────────────────────────────────── │
│                      │ Saving 2 files                                  × │ …
└──────────────────────┴───────────────────────────────────────────────────┘
```
(`╭ a ╌ b ╌ c ╮` = one capsule, its lines in order.) A 1-px rule (`Api.theme.divider`)
under the send part, the receive part and each group.

**Popup, two panels** — left: device rows without buttons for their sends (state line and
bar). Right: `TaildropFileList` as in the panel, groups titled by device, "Received files".

```
 Tailscale  Tailnet only [Disconnect] │ laptop                          × │
 ● laptop  100.64.0.9   [Send file…]  │ ╭ a.txt ╌ Sent ╌ bar ╮            │
   3 files · 46 %   ▓▓▓▓░░░           │ ╭ b.txt ╌ 40 %  × ╌ bar ╮         │
 ● phone   100.64.0.9   [Send file…]  │ ╭ c.txt ╌ Queued [Send now] × ╮   │
   2 files · No progress  (warning)   │ ───────────────────────────────── │
   ▓▓░░░░ warning                     │ phone                           × │
 Saving 1 of 2   ▓▓▓▓░░               │ ╭ video.mp4 ╌ No progress… × ╌ bar╮
 [Settings…]          [Web console]   │ ╭ song.ogg ╌ Queued [Send now] × ╮│
```

**Popup, one panel** — as it is (the owner: fine), with the general rules: the device line's
Cancel → asking "×", an ended "×" → "Clear", the stalled file's line in two lines (its name
alone; the warning text and "×" — no "Send now" on it; a waiting second file gets its "Send
now" on its own line "song.ogg · Queued [Send now]"), bars in warning on a problem. One file
to a device: its name alone, its text and "×" under it.

### 4.1 Taildrop off on this computer

A module setting `mod.tailscale.taildrop` (manifest `settings`, bool, default true, global:
it is about the computer, not a profile): the switch in the "Taildrop" heading (tooltip
"Taildrop on this computer"; the switch shows the state, no extra row).
Off:
- no sending: the panel's send part, the popup's "Send file…" and its choices go; IPC
  `sendFile` answers "Taildrop is off" (running sends are not stopped by the switch; their
  "×" stays);
- no notification for incoming files, no auto-save (the auto-save switch shows off and
  unavailable, its own setting kept for when Taildrop is on again), no progress notifications
  for new transfers;
- the page's summary row says, in muted text, "Off · Tailscale still accepts files" and, when
  files wait, "Off · 2 files in Tailscale's inbox"; "Files…" still opens the panel, which
  shows only the received part: "Taildrop is off here. Tailscale still accepts files sent to
  this computer and keeps them in its inbox until saved." with Save and the waiting names;
- the popup's received part shows the waiting count without a Save button only when files
  wait (so they are not forgotten), else nothing; the bar widget's badge for waiting files
  goes.
Rules: `TaildropRules.offState(enabled, waitingCount)` → `{ summary, tone, panelNote, canSend, notifyArrivals, autoSave }`.

## 5. Rules (module, pure, with cases)

`module/TaildropTransferRules.qml`:
- `schedule` → a queued file with `forced: true` starts now whatever its pool's slots and
  the limit across pools (forced files count toward the limit for the others), never beside
  a file of the same name to the same device; `extraSlot` (a slot borrowed by a stalled
  file) goes.
- `fileOffers` → `[{ action: "cancel" | "now", label, available, tooltip, confirm,
  confirmLabel }]`: `cancel` "×" / "Cancel?" on queued and active files; `now` "Send now" /
  "Fetch now" on every queued file, `available` false only while a same-named file goes to
  that device (tooltip "A file of this name is going there"). Nothing extra on a stalled
  file. The views render exactly these.
- `saveOffers(autoSave, waitingCount, operation)` (new; `saveOffer` folds into it) →
  `[{ action: "save" | "saveIn", label, available }]`: "Save" and, with auto-save off,
  "Save in…"; used by the notification, the popup and the panel alike.
- `saveFileArgv` → the folder comes from the save transfer (`transfer.folder`: the settings'
  folder, or the one chosen by "Save in…"), checked by the same `folderProblem`.
- `fileRow` → adds `tone`; stalled and failed → bar `warning`; skipped → "Cancelled".
- `transferOffers` → "×"/"Cancel?"/"Cancel all files" while running, "Clear" once ended.
- `fileList(transfers, view)` (renamed from `popupPanel`, also for the panel) → keys and
  byKey, headers with `rule` (all but the first) and the offers above.
- `popupDevice` / `popupSave` → `problem` (warning bar and tone); their stall line without
  "now"; a waiting file's "Send now" line in the one-panel popup.
- `pageSummary(transfers, waitingCount, options)` (new) → `{ text, tone }`.
- `sendButton` → `{ action: "send" | "cancel", label, available, confirm, confirmLabel,
  targetIds, cancelIds }`: "×" asking while page sends run and nothing is chosen.
- `notification` → "Skip" on the stalled file, "Send now" → the transfer's first waiting file.
`module/TaildropRules.qml`: `_popupState` (asking "×", none when split, `nameLine`, "Clear");
`offState` (§4.1), `chosenFolder` reused for "Save in…". The client: `save(origin, folder)`
(a folder only from the chooser);  `nowFile` sets `forced` on a queued file (IPC `nowFile` and
`skipFile` keep their names; `docs/ipc.md` says what they do now).

## 6. Module API 1.34: `SidePanel` (core slice C1)

Reference text outline (`api/Api.qml`, public elements, after HoverTip):
```
//   SidePanel              (1.34) a panel from the right over a module's settings page:
//                          open (the owner sets true; the panel sets it false when it
//                          closes itself), title (one line, plain), size: "s" | "m" (the
//                          default) | "l" — the theme's widths, never wider than 90 % of
//                          the page area; closed(reason) — "close" (its Close button),
//                          "outside" (a click on the dimmed page), "escape", "replaced"
//                          (another SidePanel opened), "page" (the page changed, the
//                          window closed, the module went away), "lock" (the session
//                          locked). Its one child is its content (`content`, a Component):
//                          built when it opens, destroyed when it has closed, laid out at
//                          the panel's inner width; the panel scrolls it below a fixed
//                          title line — the content must not scroll itself. One open per
//                          window. Anywhere in a module's page tree; elsewhere (a popup
//                          panel, an anchor, the bar) it does not open: `open` goes back to
//                          false, logged once. Takes no room where written. In module test
//                          mode the test kit's page frame hosts it (ModuleTestKit.pageFrame);
//                          setSessionLocked closes it.
```
Core work: internal `components/SideDrawer.qml` (scrim, slide with `Theme.duration("slide")`,
reduce-motion, Close, Escape with key focus taken on open and given back, a Dropdown's list
closed before the panel); a layer outside the module page frame's Flickable
(`SettingsWindow.qml` `_modulePageComp`) that hosts it; `api/SidePanel.qml` finds the host by
walking up its parents (no name a module could use); widths in `Theme`
(`settings.sidePanel`: s 320, m 420, l 520, scaled); `width` and closing decisions in
`ApiElementRules`; `ModuleRules.apiVersion` "1.34"; CHANGELOG `### Module API`;
`docs/ARCHITECTURE.md` "Modules"; `tests/ApiElementsTest.qml` pins it.

**A heading with controls (1.34, same slice):** the public `SectionTitle` and `Heading` take
children — controls at the right end of the title's line (`controls`, as `SettingsRow`'s;
none: as today). Reference line: `SectionTitle, Heading (1.34): the children written inside
are controls at the right end of the title's line (a switch for the section, its buttons)`.
Rows with a control at the end need nothing new: the public `SettingsRow` does it (M4).

## 7. Slices

Core on a work branch (`tests/run-unit.sh <suites>` while iterating, `tests/run-all.sh`
before the commit); module against a core tree nobody edits (`H2S_SHELL_DIR=… tests/run.sh
<suites>`, all three runners before the commit). Module minor 0.8.0 (with 0.7.0 if that is
not released yet), a CHANGELOG line per user-visible slice. Reviewer: a second agent with
the diff only.

| # | Slice | Changes | Tests |
|---|---|---|---|
| C1 | **SidePanel and headings with controls, API 1.34** (core) | §6 | `ApiElementRulesTest` (widths per size and page width, unknown size → "m" logged once, close events); new `SidePanelTest` (headless): content built on open, destroyed after close; Close, click beside, Escape, a second panel → `closed("replaced")`, frame destroyed → "page", lock seam → "lock"; tall content scrolls, title stays; a Dropdown inside opens over it, Escape closes its list first; outside a page frame `open` returns false; `SectionTitle`/`Heading` with a `ToggleSwitch` inside: at the right end, without children unchanged; `ApiElementsTest`; `VersionTest`/`ModuleRulesTest` 1.34; the kit's `pageFrame` in the fixture module `good` |
| M1 | **The rules** | §5 | `TaildropTransferTest`: `schedule` with `forced` (starts beside a running file, past the limit of 4 too, never beside the same name; a stalled file borrows nothing); offers per state (queued: × + "Send now"; running: ×; stalled: × only; one file: no "now"; limit reached: "now" still available; same name going: greyed with its tooltip; save → "Fetch now"); `fileRow` tones; `transferOffers`; `fileList` rule flags; `pageSummary`; `sendButton`; `notification` actions. `TaildropTest`: `_popupState` cases; `TaildropLiveTest`: "Send now" on a queued file → both run on the stand-ins, the first untouched |
| M2 | **Capsules and one file list** | `TaildropFileCard`, `TaildropFileList` (keyed, `_ready`), `TaildropFilesPanel` on it; split device rows without buttons, warning bars | UI suite (`TaildropListTest`/`TailscaleUiTest`): a 40-character name whole beside a stall; first "×" asks, nothing stopped; second stops only that file; the question's "×" takes it back; header "×" stops all; question dropped when the file ends; "Send now" on a queued capsule starts it; a rule between groups, none above the first; capsules keep identity as the list changes |
| M3 | **The one-panel popup** | `TaildropPopupState` per §4 | `TailscaleUiTest`: one file → name alone; a stall → two warning lines, no "Send now" on it; a queued second file → its "Send now"; "×" asks then cancels; "Clear" clears |
| M4 | **The side panel on the page** | manifest `api` 1.34; `TaildropPanel.qml` on `TaildropFileList`; `TaildropSection` → summary row, "Files…", drop, the settings on public `SettingsRow`s (controls at the right end) | `TaildropListTest` in `ModuleTestKit.pageFrame`: "Files…" opens it; summary per state; a drop on the row adds and opens; Escape and lock close it; Send → "×" while running; the page itself has no file rows |
| M5 | **Taildrop off** | setting `mod.tailscale.taildrop`, `offState`, the client (no arrival notification, no auto-save, no send, no new progress notifications), the views per §4.1, the switch in the `SectionTitle`; `docs/features.md` (what off does, that Tailscale still accepts files) | `TaildropTest` (`offState`: on, off, off with files waiting); `TaildropLiveTest`: off → an arrival on the stand-in bus makes no notification (kit's record) and no save; `sendFile` refused with "Taildrop is off"; a running send goes on; on again → auto-save back as it was; UI: the switch in the heading, summary text, panel note, no "Send file…" in the popup |
| M8 | **"Save in…"** | `saveOffers`; `saveFileArgv` with the transfer's folder; client `save(origin, folder)` through the chooser (folder mode); the arrival notification's actions, the popup's received part, the panel | `TaildropTransferTest` (`saveOffers`: auto-save on/off, nothing waiting, account changing); `TaildropTest` (argv with another folder; a relative, linked or foreign folder refused as today); `TaildropLiveTest`: "Save in…" with the kit's chooser answering a folder → the files land there, the settings' folder unchanged; cancelled → nothing saved; the notification's "Save in…" action through the kit's record → the chooser asked; UI: both buttons with auto-save off, only "Save" with it on |
| M6 | **"Web console"** | six labels, the hint, tooltip; `docs/features.md` | a `TailscaleUiTest` case: no "Admin console" text in page and popup objects |
| M7 | **Docs and a look** | `docs/features.md`, CHANGELOG, release line | the owner or the lead on a screen: page, panel, both popups, light/dark, a small screen |
| C2 | **Wi-Fi on the same drawer** (core, after M7) | `NetworkWifiSettings` on `components/SideDrawer.qml`: Escape, closing on lock; its heading on the internal heading with controls | a `SidePanelTest` case on the internal drawer; the Wi-Fi page by hand |

Order: C1 → M1 → M2 → M3 → M4 → M5 → M6 → M8 → M7, C2 last. M1–M3, M6 and M8 need nothing
new from the core; M4 and M5 (the heading's switch) need C1 merged. One agent at a time on the module (M2 and M3 share
`TaildropPopupState.qml`; M2 and M4 the file list).

## 8. The owner's answers (2026-11-20)

1. **"Web interface" is renamed** to a name that says this computer's settings are shared in
   the tailnet; "Web console" stays for the button that opens Tailscale's site. The words
   (the owner's to approve): "Share this computer's settings" (switch), its hint naming the
   port 5252. A module slice (with M6, "Web console") changes `SharingSection.qml:243`, the
   docs and the IPC/docs that name it.
2. **No daemon setting:** the module's soft switch is enough; `TS_DISABLE_TAILDROP` is not
   written, offered or documented as an action (M7 drops its check).

## 9. Status pills, standard statuses, the bar wave (approved 2026-11-20)

The spec is the approved mockup `h2s-mockups/taildrop-status-pills/` (`Mockup.qml`,
`shots/full.png`): its pills, capsules and wave are drawn there from theme tokens and become
real code here. Where §3–§8 say otherwise, this section wins.

### 9.1 The nine statuses (module, one table)

Every file is in exactly one status; each has one icon (a glyph of the shell's icon font)
and one colour wherever it shows — pills, the capsule (icon before the state text), popup
lines:

| Status | Icon | Colour | Capsule text | Pill tip / line |
|---|---|---|---|---|
| sending | ↑ U+F062 | accent | "Sending · 40 %" | "1 sending" |
| receiving | ↓ U+F063 | accent | "Receiving · 40 %" | "1 receiving" |
| saving | download U+F019 | accent | "Saving · 70 %" | "1 saving to the folder" |
| inbox | tray U+F01C | muted | "In inbox" | "2 in Tailscale's inbox" |
| queued | clock U+F017 | muted | "Queued" | "3 queued" |
| stalled | ⚠ U+F071 | warning | "No progress for 3 min" | "1 with no progress for 3 min" |
| failed | ✕ circle U+F057 | **error (danger)** — was warning | the reason ("Not readable") | "1 failed · Not readable" |
| cancelled | ⊘ U+F05E | muted | "Cancelled" | "1 cancelled" |
| done | ✓ U+F00C | success | "Sent" / "Saved" | "5 done" |

Taildrop off: ⏻ U+F011, muted. Accent statuses keep their capsule text secondary and the
expanded line primary (the mockup); the others take their colour.

### 9.2 The page's summary row

Two pills, then "Files…" (top-aligned, so an expanded pill grows down beside it):
- **"↑ Sending X/Y"** — X files sent of Y files in the sends that are still shown (not
  cleared from the page); **"↓ Receiving X/Y"** — X saved of Y to save (receiving, in the
  inbox, saving, saved). After the label, each status present as icon + number in its
  colour, in the order sending, receiving, saving, inbox, queued, stalled, failed,
  cancelled, done; each with a tooltip ("3 queued").
- A click on a pill with statuses expands it: one status per line under a rule, icon and
  line in its colour ("⚠ 1 with no progress for 3 min", "✕ 1 failed · Not readable" — the
  reason when the failed files share one, else "2 failed"); a second click collapses it.
- A pill with no transfers disappears; neither → muted "No transfers".
- Finished: "✓ Sent 5/5" in success; with failures "Sent 4/5 ·" + its "✕ 1" part, lead icon
  secondary. Receiving likewise ("✓ Saved 3/3").
- Taildrop off: one muted pill "⏻ Off · 2 in inbox" ("Off" with none waiting), replacing
  both; `offState.summary` gives its text. `statusPills` replaces `pageSummary` (§5).

### 9.3 The wave on bars that move (core)

A bar in progress gets a band of light passing through its filled part every 300 ms (the
owner's number), as the core chart's heartbeat (`components/HistoryChart.qml`: a lighter
band of the fill's colour, clipped to the fill). No wave on a stalled bar, a full or empty
one, a run of unknown length, a hidden bar, or with `Theme.reduceMotion`.
Decision: **opt-in** — `wave: bool` (false by default) on the internal
`components/ProgressBar.qml` and on the public `ProgressBar` (module API 1.35). The bar
does not judge "moving" itself: the owner says it (Taildrop: sending, receiving, saving;
never stalled). Whether it runs is a rule, `ApiElementRules.progressWaves(wave, value,
reduceMotion)` (true only for 0 ≤ value < 1). The period is a Theme duration role
`progressWave` 300 (in ThemeRules' animation roles, editable; reduced motion removes it);
the band crosses the fill once per period, its animation stopped while it does not run.
**The notification card's bar** waves while its job is running and its value grew in the
last 10 s (`NotificationRules.progressWave(state, grewAt, now)`) — a stalled sender's value
stands still, so the wave stops without a new notification option. Its colour stays the
normal one (notifications carry no colour).

### 9.4 What the public API lacks for the pills (core, 1.35)

- `Pill` (1.5) is one choice among several: label, picked, tooltip, size, textSize,
  clicked. No icon, no colour, no inner parts with their own tooltips, no expanded state.
  Not stretched: its meaning stays "a choice".
- `HoverTip` (1.31) exists publicly; the new pill uses it per part, nothing to add.
- So a new public element **`StatusPill`**, agnostic (any module summing up a state).
  Reference text outline (`api/Api.qml`, public elements, after SidePanel):
```
//   StatusPill             (1.35) a pill that sums up a state: icon (a glyph of the shell's
//                          icon font; "" none), label (one line), kind: "normal" (the
//                          default: icon accent, label text) | "muted" | "success" |
//                          "warning" | "danger" — the icon's and label's colour; parts:
//                          [{ icon, text, kind, tip, line }] — after the label, each an
//                          icon and a short text (a count) in its kind's colour, its tip
//                          over it on hover (HoverTip's rules); expanded (the owner may set
//                          it; a click flips it while there are parts): the parts one per
//                          line under a rule — icon and `line` ("" → text and tip) in the
//                          part's colour; toggled(expanded). Texts plain, one line, cut
//                          past 80 (oneLine); unknown kinds → "normal", logged once; past
//                          12 parts the rest dropped, logged once. Fills no width.
//                          StatusPill { icon: ""; label: "Sending 1/6"
//                                       parts: [{ icon: ""; text: "3"; kind: "muted";
//                                                 tip: "3 queued" }] }
```
  Inside: `components/StatusPill.qml` (the mockup's StatusPill on Theme tokens, parts by a
  `KeyedModel` keyed by index, `PointerArea` for hover and click); the part list made
  plain and capped in `ApiElementRules.statusParts`.
- A capsule draws its status icon itself from theme tokens: no public icon element.

### 9.5 Progress notifications (module)

Body "holiday-photos.zip · 2 of 3" — the file under way and its place among the transfer's
files; a stall "video.mp4: No progress for 3 min". No "Send now" in notifications; a stall
offers only "Skip" (supersedes §5 `notification`). The bar stays normal.

### 9.6 Slices

| # | Slice | Changes | Tests |
|---|---|---|---|
| C3 | **ProgressBar wave and StatusPill, API 1.35** (core) | §9.3, §9.4; `ModuleRules.apiVersion` "1.35"; CHANGELOG `### Module API` 1.35 and an Unreleased line for the card's wave; `docs/ARCHITECTURE.md` "Modules" | `ApiElementRulesTest`: `progressWaves` (off, value <0, 0, 1, NaN, reduced motion), `statusParts` (plain/one line, cap logged once, unknown kind); `NotificationRulesTest`: `progressWave` (grew 2 s / 11 s ago, done, failed, cancelled); `ThemeRulesTest` the new role; headless suite: the band moves within two periods with `wave`, none without, hidden or reduced; `StatusPill` parts in order with a tooltip each, click expands, second collapses, no parts → no expand; card bar waves while running, stops when the value stands; `ApiElementsTest` pins both; `VersionTest`/`ModuleRulesTest` 1.35 |
| M10 | **Module rules** | `statuses` table (§9.1); `fileStatus(file, transfer, now, stallMs)` → one key; `statusPills(transfers, incoming, waitingCount, offState, now)` → `{ pills: [{ key, icon, label, kind, parts }], none }`; `fileRow` → `status`, `wave`, failed `danger`; popup lines → `status`; `notification` → body and "Skip" only; `pageSummary` removed | `TaildropTransferTest`: each file state → one status (stall by `progressAt` vs `stallMs`); counts add up to Y, no file twice; X/Y for sends and saves; finished, finished with a failure, shared/mixed reasons; a pill vanishes, "No transfers"; off with 0 and 2 waiting; `fileRow` wave per status; notification body "2 of 3", stall body, actions never "Send now" |
| M11 | **Module views** | manifest `api` 1.35; summary row on `StatusPill`s; capsule icon before the state text in its colour; bars `kind` per status and `wave`; popup lines with icons; failed in danger | UI suites: pills per state in `ModuleTestKit.pageFrame`, a part's tooltip text, click expands/collapses, "Files…" on the first line; a capsule's icon and colour per status; stalled bar `wave` false, sending true; popup failed line in danger |
| M12 | **Docs and the mockup on the real code** | `docs/features.md` (statuses, pills, wave), module CHANGELOG, release line; the mockup rebuilt on the real `StatusPill`, `ProgressBar.wave` and module rules, shots taken again | the owner or the lead compares the new shots with the approved ones: light/dark, a small screen |

Order: C3 → M10 → M11 → M12. M10 needs nothing new from the core and may run beside C3's
review; M11 needs C3 merged. Module: its next minor version.
