# Taildrop: the views reworked, a side panel for module pages, Taildrop off

Status: a plan, for the owner's approval. Nothing here is built. It answers the owner's look
at a mockup of today's views (2026-11-20: the page's Taildrop part unreadable, the popup's
files panel with too many buttons and squeezed names, problems that do not stand out; the
one-panel popup fine) and at the mockup of this plan's first version (same day: the four
settings stay on the page; "Send now" moves to every waiting file; each file in a capsule,
the same file list in the side panel and the popup's files panel; a way to turn Taildrop
off on this computer). It reworks §3.6 of [taildrop-transfers.md](taildrop-transfers.md)
(built). One core slice (module API 1.34: a side panel for a module's page), then module
slices. Paths: core `api/…`, `panels/…`; module `module/…` (repository h2s-shell-tailscale).

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
  auto-saves when that is on (68–107, 514–561).

## 2. Can this computer refuse incoming files? (read-only findings)

- **No pref, no CLI flag:** `tailscale set --help` (1.104.7 here) has nothing for Taildrop;
  `tailscale file` has only `cp` and `get`; the prefs (`fixtures/prefs-rich.json`) have no
  such key; the LocalAPI's `files/` serves only listing, `GET` and `DELETE`.
- **The tailnet's admin:** the "Send files" setting (capabilities `cap/file-sharing`,
  `cap/file-sharing-target` and `cap/file-send` in the binary and in our status fixtures,
  `fixtures/status-exit-node.json:55,71`) — on or off for the whole tailnet, or per target
  through the tailnet policy. Not this computer's choice.
- **The daemon's environment:** `tailscaled` 1.104.7 contains the knob `TS_DISABLE_TAILDROP`
  (beside "Taildrop disabled; no storage directory" and "file sharing not enabled by
  Tailscale admin"). Set in tailscaled's service environment it turns Taildrop off in the
  daemon — assumed, from the name and the strings: that peers then see this device as no
  target and a send to it fails is **not verified** (it needs a daemon restart; the owner or
  the lead checks it on a real machine, slice M7). It is system configuration, root-owned:
  NixOS `systemd.services.tailscaled.environment.TS_DISABLE_TAILDROP = "true";` (declarative,
  nothing the module can write); Arch a systemd drop-in for `tailscaled.service` with
  `Environment=TS_DISABLE_TAILDROP=true` and a restart of tailscaled.
- **So:** a real refusal exists only as a system setting of the daemon, not as a runtime
  pref. The plan's option is honest and module-only (§4.1); the system setting is
  documented in `docs/features.md` for both systems, and Q2 asks whether the module should
  also offer it.

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
  waiting, so no "Send now" appears. When the shell's limit of files at once (4) is reached,
  the button shows unavailable with the tooltip "4 files are going already"; a file of the
  same name already going to that device (Tailscale tells them apart by name) shows it
  unavailable, "A file of this name is going".
- **A file name is always visible:** first line of its capsule, nothing beside it. State,
  bar and buttons go under it.
- **A problem** (stalled, failed, refused) → bar `kind: "warning"`, text `Api.theme.warning`;
  a device or saves line with such a file takes the warning bar and tone. Failed files move
  from "danger" to "warning".
- **"Web console"** replaces "Admin console" / "Open the admin console" in the six places
  and the hint ("…in the web console"); tooltip "login.tailscale.com" (Q1 on the switch
  "Web interface").
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

**The page** — summary row, the four settings (decided), the new switch:

```
Taildrop
2 sending · 1 file waiting                              [Files…]   ← drop files here too
Taildrop on this computer                                    (o)
Save to  /home/user/Downloads                  [Choose…] [Default]
If the name is taken  [Keep both ▾]
Save incoming files automatically                            (o)
Transfer notifications  [On screen until done ▾]
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
│                      │ 2 files waiting · f.bin, g.bin   [Save] [Open folder]
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
it is about the computer, not a profile), the switch "Taildrop on this computer" on the page.
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
Rules: `TaildropRules.offState(enabled, waitingCount)` → `{ summary, tone, panelNote,
canSend, notifyArrivals, autoSave }` (pure), read by the client and the views.

## 5. Rules (module, pure, with cases)

`module/TaildropTransferRules.qml`:
- `schedule` → a queued file with `forced: true` starts now whatever its pool's slots, still
  within the limit across pools and never beside a file of the same name to the same device;
  `extraSlot` (a slot borrowed by a stalled file) goes.
- `fileOffers` → `[{ action: "cancel" | "now", label, available, tooltip, confirm,
  confirmLabel }]`: `cancel` "×" / "Cancel?" on queued and active files; `now` "Send now" /
  "Fetch now" on a queued file that `schedule` would not start this tick, `available` false
  with its reason as tooltip when the limit or the same name holds it. Nothing extra on a
  stalled file. The views render exactly these.
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
`offState` (§4.1). The client: `nowFile` sets `forced` on a queued file (IPC `nowFile` and
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

## 7. Slices

Core on a work branch (`tests/run-unit.sh <suites>` while iterating, `tests/run-all.sh`
before the commit); module against a core tree nobody edits (`H2S_SHELL_DIR=… tests/run.sh
<suites>`, all three runners before the commit). Module minor 0.8.0 (with 0.7.0 if that is
not released yet), a CHANGELOG line per user-visible slice. Reviewer: a second agent with
the diff only.

| # | Slice | Changes | Tests |
|---|---|---|---|
| C1 | **SidePanel, API 1.34** (core) | §6 | `ApiElementRulesTest` (widths per size and page width, unknown size → "m" logged once, close events); new `SidePanelTest` (headless): content built on open, destroyed after close; Close, click beside, Escape, a second panel → `closed("replaced")`, frame destroyed → "page", lock seam → "lock"; tall content scrolls, title stays; a Dropdown inside opens over it, Escape closes its list first; outside a page frame `open` returns false; `ApiElementsTest`; `VersionTest`/`ModuleRulesTest` 1.34; the kit's `pageFrame` in the fixture module `good` |
| M1 | **The rules** | §5 | `TaildropTransferTest`: `schedule` with `forced` (starts beside a running file, not past the limit, not beside the same name, a stalled file borrows nothing); offers per state (queued: × + "Send now"; running: ×; stalled: × only; one file: no "now"; limit reached: "now" unavailable with its tooltip; save → "Fetch now"); `fileRow` tones; `transferOffers`; `fileList` rule flags; `pageSummary`; `sendButton`; `notification` actions. `TaildropTest`: `_popupState` cases; `TaildropLiveTest`: "Send now" on a queued file → both run on the stand-ins, the first untouched |
| M2 | **Capsules and one file list** | `TaildropFileCard`, `TaildropFileList` (keyed, `_ready`), `TaildropFilesPanel` on it; split device rows without buttons, warning bars | UI suite (`TaildropListTest`/`TailscaleUiTest`): a 40-character name whole beside a stall; first "×" asks, nothing stopped; second stops only that file; the question's "×" takes it back; header "×" stops all; question dropped when the file ends; "Send now" on a queued capsule starts it; a rule between groups, none above the first; capsules keep identity as the list changes |
| M3 | **The one-panel popup** | `TaildropPopupState` per §4 | `TailscaleUiTest`: one file → name alone; a stall → two warning lines, no "Send now" on it; a queued second file → its "Send now"; "×" asks then cancels; "Clear" clears |
| M4 | **The side panel on the page** | manifest `api` 1.34; `TaildropPanel.qml` on `TaildropFileList`; `TaildropSection` → summary row, "Files…", drop, the settings | `TaildropListTest` in `ModuleTestKit.pageFrame`: "Files…" opens it; summary per state; a drop on the row adds and opens; Escape and lock close it; Send → "×" while running; the page itself has no file rows |
| M5 | **Taildrop off** | setting `mod.tailscale.taildrop`, `offState`, the client (no arrival notification, no auto-save, no send, no new progress notifications), the views per §4.1; `docs/features.md` with the system setting for NixOS and Arch | `TaildropTest` (`offState`: on, off, off with files waiting); `TaildropLiveTest`: off → an arrival on the stand-in bus makes no notification (kit's record) and no save; `sendFile` refused with "Taildrop is off"; a running send goes on; on again → auto-save back as it was; UI: switch, summary text, panel note, no "Send file…" in the popup |
| M6 | **"Web console"** | six labels, the hint, tooltip; `docs/features.md` | a `TailscaleUiTest` case: no "Admin console" text in page and popup objects |
| M7 | **Docs and a look** | `docs/features.md`, CHANGELOG, release line | the owner or the lead on a screen: page, panel, both popups, light/dark, a small screen; on a real tailnet: `TS_DISABLE_TAILDROP` in tailscaled's environment — does a peer then fail to send here, and how does the module read it (§2) |
| C2 | **Wi-Fi on the same drawer** (core, after M7) | `NetworkWifiSettings` on `components/SideDrawer.qml`: Escape, closing on lock | a `SidePanelTest` case on the internal drawer; the Wi-Fi page by hand |

Order: C1 → M1 → M2 → M3 → M4 → M5 → M6 → M7, C2 last. M1–M3, M5 and M6 need nothing new
from the core; M4 needs C1 merged. One agent at a time on the module (M2 and M3 share
`TaildropPopupState.qml`; M2 and M4 the file list).

## 8. The owner's answers (2026-11-20)

1. **"Web interface" is renamed** to a name that says this computer's settings are shared in
   the tailnet; "Web console" stays for the button that opens Tailscale's site. The words
   (the owner's to approve): "Share this computer's settings" (switch), its hint naming the
   port 5252. A module slice (with M6, "Web console") changes `SharingSection.qml:243`, the
   docs and the IPC/docs that name it.
2. **No daemon setting:** the module's soft switch is enough; `TS_DISABLE_TAILDROP` is not
   written, offered or documented as an action (M7 drops its check).
