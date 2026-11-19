# Taildrop: a list of transfers

Status: a plan, for the owner's approval. Nothing here is built. A feature of the module
`h2s-shell-tailscale` (its repository; core untouched except where the notification plan
says). It answers the tracker's decision "Taildrop (2026-11-19)": no fixed time limits on
transfers (sending, or copying received files out of Tailscale's inbox); a list of
transfers with progress; per file "Skip" (stop it, the rest go on) and "Send now" / "Fetch
now" (start the next file beside a stuck one); a transfer with no progress shows "no
progress for N min" and waits for the user; "The program could not be started." kept.
With the owner's answers of 2026-11-19 (§4): those words; the full list in the popup too,
in a second panel beside the first as the calendar does; sending to several devices at
once; a progress notification for every transfer still running after 3 seconds, staying on
screen or shown briefly as a module setting chooses.

Its last slice uses progress notifications from [notification-progress.md](notification-progress.md)
(module API 1.33); everything before it needs nothing new from the shell.

## 1. The problem

Today a send is one `tailscale file cp` for all its files, stopped after 2 minutes without
progress and after 6 hours in all; a save of received files is one script for all of them,
600 s per file, run under the client's change lock. A large file on a slow link is killed
although it was moving; a stuck file takes the whole batch with it; a long save holds the
lock, so Disconnect and every other change wait. Nothing lets the user stop one file and
keep the rest, or go on beside a stuck one; nothing sends to two devices at once.

## 2. What exists today

All paths in the module repository.

**Sending** — `module/TaildropClient.qml`

- The header (14–24) states the rules: one send at a time, outside the change lock; progress
  from the bus's `OutgoingFiles`; Cancel kills it; Disconnect, logout, an account switch and
  the module going away stop it; limits `idleLimitMs` (41, 2 minutes) and
  `TailscaleRules.timeLimits.send` (21600 s; `module/TailscaleRules.qml:123`).
- `send` (133–137): one object `{ state, targetName, targetId, origin, files [{ path, name,
  size, problem, sent, percent, outcome }], message, startedAt, pageCleared, popupCleared }`.
- `sendFiles` (311–366): a user-side `find -P` check (`TaildropRules.checkArgv`,
  `parseCheck`), then one `file cp -- <all paths> <IPv4>:` with the send limit (356–362).
- `_applyProgress` (368–389) maps the bus's entries per file name
  (`TaildropRules.sendProgress`, `module/TaildropRules.qml:308-319`: newest per name for the
  peer, started after the send); `_progressAt` moves on any change.
- `_sendEnded` (391–406): a run that could not start says "Not sent" (404) — not the
  module's "The program could not be started." (`TailscaleRules.qml:2273`).
- `_idleCheck` (443–454): no progress for `idleLimitMs` while the bus is up → "Stalled,
  stopped".
- `_operations` (457–466): Disconnect / logout / account → stopped.
- A second send while one runs is refused (`sendFiles` 312; the popup row's Send is off,
  `TaildropRules.popupRow` 399–432, `canSend: busy !== true`).
- One target: the page picks one device (`TaildropSection.qml:77-93`, `targetId`) for its
  `chosen` files; the popup keeps a choice per device (`popupChoices`, one row each,
  `module/TaildropSendRow.qml`), but only one of them can be sending.

**Receiving** — the bus's `IncomingFiles` (peer → Tailscale's inbox, with `Received` bytes)
show as "Receiving name 40 %" (`TaildropSection.qml:251-252`); the module cannot stop those.
Copying out of the inbox is **not** `tailscale file get`: it is `curl` on the LocalAPI
socket, per file `GET files/<name>` into a private staging directory in the folder, a
rename into place, then `DELETE files/<name>` (`TaildropRules.saveScript`, 566–615; argv
`saveArgv` 617–643; output `parseSave` 645–668). Each request runs under `timeout -k 5
<seconds>` (the script's `run`); the runner's limit is `(files × 2 + 1) × (600 + 10)` s,
at most a day (`TaildropClient.qml:610-615`, `TailscaleRules.runLimits`/`maxRunMs`
2231–2240). The save runs through `client._runLocked("taildrop-save", …)` (615): the change
lock. Auto-save runs on an arrival and once at start (514–561); names it tried and left are
not retried until the next arrival or a manual Save (`_autoTried`).

**Views**

- The page: `module/TaildropSection.qml` — targets, files, Send / Cancel / Clear (186–209),
  the send's state line (210–219), a row per file with its percent or outcome (220–246;
  a `ScriptModel` of rebuilt objects with `objectProp`, the pattern `CLAUDE.md` warns about),
  "Receiving …" (251), Save, the saves' results (286–297).
- The bar popup: `module/TailscalePopup.qml`, one column, `implicitWidth:
  Api.theme.popupWidth("tailscale", 320)` (44), scrolling past `availableHeight` (45–49),
  its Repeaters built a tick after the panel (`_ready`, `Qt.callLater`, 52–58);
  `module/TaildropSendRow.qml` under each device (files chosen, Send, one bar for the whole
  send with Cancel, the result; `TaildropRules.popupRow`), and at 288–320 the waiting
  count, Save and the last save's line.
- IPC (`module/Main.qml:212-240`, `docs/ipc.md` "Taildrop"): `taildrop` (JSON), `sendFile`,
  `cancelSend`, `saveReceived`.

**Settings:** the manifest's `settings` (`module/module.json`, one today:
`mod.tailscale.openLoginInBrowser`), read with `module.value(key)` and written with
`module.setValue` from the page (`TailscalePage.qml:212-213`); the manifest takes bool,
enum (with `options`), number and string settings (`singletons/ModuleManifestRules.qml:39`
in the core).

**Docs that state the limits:** `docs/features.md:214` ("A send with no progress for 2
minutes is stopped. A send lasts 6 hours at most."), `docs/privileges.md:118-119` (the
limits table), `docs/architecture.md:157,178` (`timeout` for each file of a save).

**Stand-ins** (`module/tests/stand-in/`): `tailscale` `file cp` checks the files and, per
file, appends `OutgoingFiles` lines to `TS_FAKE_BUS_FILE` (started, half with
`TS_FAKE_SEND_DELAY`, finished; `TS_FAKE_SEND_FAIL`, `TS_FAKE_SEND_REFUSE`); `curl` serves
the inbox (`GET`/`DELETE files/…`) at once; `timeout` is the real one. Suites:
`module/tests/TaildropTest.qml` (rules), `TaildropLiveTest.qml` (the client on the
stand-ins, a scenario per directory, `idleLimitMs` and `timeLimits` shortened).

**The module API needs nothing new before the notification slice:** `CommandRunner` takes
`timeoutMs: 0` (no limit) and hands output line by line (`onStdout`); `runLimits(0)`
already means "no limit" for the event stream; `ProgressBar`, `SmallButton`, `Pill` are
public; a list keyed by strings is a Quickshell `ScriptModel` of keys, which a module may
use. The popup's second panel needs nothing either (§3.6).

## 3. Design

### 3.1 Transfers, files, states

A **transfer** is one batch: a send of chosen files to one device, or a save of waiting
files. Sending the same files to three devices makes three transfers (§3.2). A transfer
holds **files**; each file is one process. The client keeps `transfers` (newest first, at
most 20 kept after they end) and the views read them. Every decision is in a new pure
file, `module/TaildropTransferRules.qml` (suite `module/tests/TaildropTransferTest.qml`);
`TaildropClient` only runs what it decides.

A file's state:

```
queued → starting → running → sent | saved | left | failed | skipped | cancelled
                    (running: stalled is derived, not a state)
```

- `left`: a save whose name was taken with the policy "Leave waiting" (today's "skipped"
  outcome, renamed so it does not clash with the user's Skip).
- `skipped`: the user's Skip — the file's process stopped (or a queued file never started).
- `cancelled`: Cancel on the transfer, Disconnect (sends), logout / account switch (both),
  the module going away.
- `failed`: the reason in one short sentence; a run that could not start says "The
  program could not be started." (sends and saves alike).

Each file keeps `bytes`, `size` (-1 unknown), `progressAt` (the last time `bytes` grew, or
its start), `token` (its run; an answer with an old token is dropped — late answers lose),
`extraSlot` (the user pressed "Send now" / "Fetch now" on it).

**Stalled** (`stalledFor(file, now) → minutes or 0`): running, and `bytes` has not grown for
`stallMs` (2 minutes, a client property the suites shorten). The row says "No progress for
N min" (N whole minutes since `progressAt`, from 2, moving once a minute) and offers Skip and
"Send now" (a send) or "Fetch now" (a save). Nothing is stopped by time. A file that moves
again drops the line by itself.

Without the bus (the event stream down) a send has no progress to see: its files count as
not moving, so after 2 minutes they say so too — honest from where the module stands.

### 3.2 Scheduling, several devices, "Send now" / "Fetch now"

Decided by the owner (2026-11-19): sending to several devices at once is part of the
design. Scheduling is **per device**, so sends to different devices run side by side.

Pools: one per target device for sends, one for saves. `schedule(files) → keys to start`:

- a pool's slots = 1 + the number of its running files with `extraSlot`;
- queued files start in order while fewer than its slots run;
- across all send pools at most `maxParallel` (4) files run at once (a fifth device's
  transfer waits for a free one; the saves' pool has its own `maxParallel`);
- never two files of the same name to the same device at once (the bus tells sends apart
  by peer and name only) — within one pool by construction.

**"Send now" / "Fetch now"** on a stalled file sets its `extraSlot`: the next queued file
of its pool starts beside it; the stuck one keeps running (it may still finish). When it
ends, its slot ends with it. Offered only while the file is stalled, files of its pool wait
behind it, and the limit leaves room (`maxParallel`).

**Skip** on a running or queued file: its process gets TERM (KILL after 5 s, the runner's
`cancel()`); the next file starts. Sends: what the peer keeps of a part-sent file is
Tailscale's (assumed: a partial it drops or resumes later; checked on a real machine).
Saves: the staging copy is removed by the script's trap, the file **stays waiting** in the
inbox, and auto-save does not try it again until the next arrival or a manual Save (as
`_autoTried` today).

**Cancel** on a transfer: Skip for every file not ended. The transfer's line says
"Cancelled".

**A second transfer** to a device with one running is queued behind it in that device's
pool, not refused (the popup's Send stays on); to another device it starts at once.
*(The plan's choice; today a second send is refused.)* An arrival while a save runs adds
the new waiting files to that save's queue.

**Several devices.** On the page the target pills choose several devices (each a toggle;
the Send button says "Send to laptop" or "Send to 3 devices"): one transfer per device,
the same files, the `find -P` check once for all. In the popup each device keeps its own
choice as today (`popupChoices`), so sending to three devices there is choosing on three
rows; with sends no longer refused they all run. The IPC's `sendFile <path> <device>`
stays one device per call.

### 3.3 Sending, per file, no limit

- The `find -P` check stays, once for the whole send (all its devices).
- Each file: `tailscale file cp -- <path> <IPv4>:` (`TailscaleRules.commandFor("fileCp")`
  with one path), `timeoutMs: 0`, as the user, outside the change lock, as today.
- Progress: `_applyProgress` unchanged in spirit — `sendProgress` per file and peer, but
  matched also by the file's own start time (a killed earlier attempt's unfinished bus entry
  for the same name never counts).
- `idleLimitMs`, `_idleCheck`'s stop and `timeLimits.send` go; "Stalled, stopped" and "Took
  too long, stopped" go.
- Disconnect, logout, an account switch: running and queued sends cancelled, as today.

### 3.4 Saving, per file, with progress, outside the lock

- The save script becomes **one run per file** (the same steps and checks as today: folder
  absolute, not a link, the user's, writable; a private staging directory; `mv -T`, `-n`
  unless "Replace"; `DELETE` only after the rename), without `timeout` (no `$3`/`$4`), with
  `timeoutMs: 0`.
- Progress: while `curl` runs, the script prints `progress\t<bytes>` when the staging
  file's size changed, checked once a second (`wc -c`); `parseSaveLine(line)` (pure) reads
  it. `size` comes from the listing (`Size`). The final line is today's outcome line.
- Not under the change lock any more: a stuck save never blocks Disconnect or settings.
  Saves stop at logout and account switch (another profile's inbox), not at Disconnect
  (the inbox is local).
- `timeout` is no longer used by Taildrop (`docs/architecture.md:178` changes; the
  certificate script still uses it).

### 3.5 What happens on a restart

The shell's runner ends every run with the shell or the module (setpriv). After a restart
or the module turned off and on the list starts empty: sends that were running are not
resumed (the user sends again); received files that were not copied are still waiting in
the inbox and show as waiting (auto-save, when on, starts on them as today). A save killed
hard may leave a `.tailscale-receiving.XXXXXX` folder in the save folder — as today; not in
this plan. *(The plan's choice: the list is not kept across restarts.)*

### 3.6 The views

Public elements and theme tokens only; the module decides its looks.

**A file's row** (the same everywhere): its name (plain text, elided in the middle), a
`ProgressBar` (normal while running, -1 while its size is unknown; success full when
sent/saved; danger full when failed; none when skipped, cancelled or left), a short text
("40 %", "No progress for 3 min", "Sent", "Saved as photo (1).jpg", "Skipped", "Left
waiting · name taken", why it failed), and Skip / "Send now" / "Fetch now" where §3.2
offers them. Label and action come from one rule (`TaildropTransferRules.fileOffers`).

- **The page** (`TaildropSection.qml`): the per-file send rows and the saves' result lines
  become one **Transfers** list. A transfer: a title line ("To laptop · 3 files", "Saving
  2 files"), Cancel while running, Clear when ended, then its files' rows. "Receiving …"
  (the peer → inbox stage) shows as rows without buttons. The list is a `ScriptModel` of
  keys (`<transfer id>/<file index>`), each delegate looking its file up by key — never
  rebuilt objects as rows. The target pills choose several devices (§3.2).
- **The popup — two panels, as the calendar's** (decided by the owner, 2026-11-19).
  `TaildropTransferRules.popupSplit(transfers, popupKept) → bool`: more than 2 files in
  total in the transfers the popup shows (running, queued, or ended and not cleared from
  the popup; sends to every device and the running save together — one file each to three
  devices is 3). Then the popup is two panels side by side: the existing panel on the left
  (devices, exit nodes, …; under a device only its choice line — files picked and Send —
  and its transfer's one-line state with one bar and Cancel), a 1-px rule
  (`Api.theme.divider`), and on the right the **files panel**: a header per target device
  (its name, plain text, with the transfer's Cancel or Clear), its files' rows under it;
  the running or last save under a header "Received files". The files panel scrolls on its
  own within `availableHeight`. With 2 files or fewer the popup stays one panel and the
  rows sit under the device rows (and the received part's "Saving 2 of 5" with its bar and
  stall line) as before. The popup grows and shrinks between the two as files come and go;
  the shell animates the resize.
  *How:* the calendar's two panels are its own content — `panels/Calendar.qml:14` sets
  `implicitWidth` to both panels and the rule, 72–118 a `Row` of `EventsPanel`, a 1-px
  `Rectangle` and `MonthGrid` — and `panels/Popup.qml` sizes any panel by its content's
  `implicitWidth` (165), handles a change of it (256–257) and animates the new length
  (270–276). A module's `popupPanel` is that content (`api/Api.qml:551-579`), so
  `TailscalePopup.qml` does the same with a `Row` and `implicitWidth: popupWidth("tailscale",
  320) + 1 + popupWidth("tailscaleTransfers", 300)` when split. **No API gap; no core
  slice; the manifest's `api` stays 1.32 for it.** The files panel's Repeater is a
  `ScriptModel` of keys, built after `_ready` like the panel's others (the Repeater crash
  rules); the panel itself is created by the core under its `Qt.callLater` rule as today.
- **IPC**: `taildrop` JSON gains `transfers`; new `skipFile <transfer> <index>`,
  `nowFile <transfer> <index>` ("Send now" / "Fetch now"), `cancelTransfer <transfer>`;
  `cancelSend` stays (all running sends). `docs/ipc.md`.

### 3.7 Progress notifications (after the notification plan's slice N3)

Decided by the owner (2026-11-19): a progress notification for every transfer still
running after 3 seconds (a short one makes none), with Skip and "Send now" / "Fetch now" on
it when a file stalls; how it shows is a module setting.

- **What it says:** "Sending 3 files to laptop" / "Saving 2 files", its bar the transfer's
  share of bytes (-1 while unknown), the body the current file's name. A stalled file: the
  body says "photo.jpg: No progress for 3 min" and the actions are Skip and "Send now" (or
  "Fetch now"), on the first stalled file (resident: the notification stays after a click).
  The end: "Sent to laptop", "Saved 2 files", "1 of 3 not sent · <reason>" as done or
  failed; Cancel → cancelled. Dismissing it leaves the transfer running. The arrival
  notification ("File received") is unchanged.
- **The setting** `mod.tailscale.taildropNotifications` (the manifest's `settings`, enum,
  per profile; on the Tailscale page under Taildrop; label "Transfer notifications"):
  - `"stay"` — **default** (recommended: what the owner described first; the toast shows
    the job without a click, and the core's Q5 answer keeps it from holding other toasts
    back): "On screen until done". The handle's `toast: "whileRunning"`: the toast stays
    for the whole transfer, its bar moving, and goes the user's time after the end.
  - `"brief"` — "Briefly, then in the notification list": `toast: "brief"`: the toast shows
    for the user's time, then the notification stays and moves in the notification centre.
  - In both, a **change of status** is announced (`update({ announce: true })`): a file
    stalls, the transfer is done, it failed. In "brief" each brings a new toast; in "stay"
    it brings the toast back if the user had taken it away. Started is the first toast
    itself; a file moving again, Skip and Cancel (the user's own act) announce nothing.
  - A change of the setting applies to transfers that start after it.
- `TaildropTransferRules.notification(transfer, now, mode) → { wanted, summary, body,
  progress, state, actions, toast, announce }` (pure); `TaildropClient` keeps one handle per
  transfer and closes them at module stop (the core closes them anyway).

## 4. Open questions for the owner

**Answered (2026-11-19):**

- *Q2, the words:* "Skip"; "Send now" on sends, "Fetch now" on received files; the stall
  line "No progress for N min" (shown from 2 min, whole minutes).
- *Q3, where the list lives:* the full list in the popup too, laid out like the calendar
  popup: more than 2 files in total (across all devices) → two panels side by side, the
  files panel on the right with a header per target device; 2 or fewer → the rows under the
  device rows. Sending to several devices at once is part of the design (§3.2: per-device
  scheduling; several devices on the page, a choice per device in the popup).
- *Q4, progress notifications:* (a) for every transfer still running after 3 seconds, with
  Skip / "Send now" / "Fetch now" on a stall; plus the module setting of §3.7 ("stay" or
  "brief", status changes announced), from the owner's answer to the notification plan's
  Q1.

No open questions in this plan. It follows the notification plan's Q5 (a toast that stays
in the "One at a time" layout): with that plan's recommended answer, the default "stay"
holds no other toast back; with (b) the owner may prefer "brief" as this setting's
default — one line in the manifest.

## 5. Slices

All in the module repository, on a work branch, tested against a core tree nobody edits
(`H2S_SHELL_DIR=<core tree> tests/run.sh <suites>` while iterating; all the module's suites
and the core's `tests/run-all.sh --quick` before the commit), on the Arch machine; the
module's suites again on the NixOS machine before the merge. A module minor (0.7.0 for the
list, 0.8.0 for the notifications) and a CHANGELOG line per user-visible slice; each slice
updates the docs it makes untrue (`docs/features.md`, `docs/privileges.md`,
`docs/architecture.md`, `docs/ipc.md`). Reviewer: a second agent with the diff only. All
slices but the last need nothing from the shell (manifest `api` stays 1.32); the last
needs core API 1.33.

| # | Slice | Changes | Tests | Reviewer looks at |
|---|---|---|---|---|
| 1 | **The transfer rules** (D1) | `module/TaildropTransferRules.qml` (new): file states, `stalledFor`, `schedule` (per-device pools, extra slots, `maxParallel` across pools, same name per device), `fileOffers` (Skip / "Send now" / "Fetch now" / Cancel, label with action), the texts, a transfer's totals, `popupSplit`, `parseSaveLine`, the per-file save argv; no caller yet | `TaildropTransferTest` (new): every state's offers and words (a send → "Send now", a save → "Fetch now"); stall at 1:59 / 2:00 / 3:10; slots with 0–5 extra; two devices run side by side, a fifth waits for `maxParallel`; the same-name rule; a late token; `popupSplit` (2 files → no; one file each to three devices → yes; cleared ones not counted; a running save counted); save lines (progress, outcomes, junk) | that every later decision is here; names and words match §3 |
| 2 | **Sends per file, per device, without time limits** (D2) | `TaildropClient`: transfers for sends, one `file cp` per file through `schedule`, `timeoutMs: 0`, stall instead of stop, Skip, "Send now", Cancel, a second send queued (same device) or run (another device), several devices from one request (one transfer each), "The program could not be started."; `TailscaleRules.timeLimits.send` goes; the page's existing rows show the stall text and get Skip; IPC; stand-in `tailscale`: `TS_FAKE_SEND_STALL=<name>` (that file stops after its first bus line and holds until killed), bus lines per peer | `TaildropLiveTest` scenarios: two files, the first stalls → the stall text after a shortened `stallMs` → Skip → the second sent, the first `skipped`; "Send now" → the second starts while the first holds, then both end; Cancel → both stopped, no stray process; a second send to the same device queued and run after; a send to two devices → both running at once, each its own progress; a program that cannot start → the sentence; Disconnect cancels all; a late bus line for a skipped file changes nothing | no limit left anywhere for sends; the kill of one file never touches another; progress never crosses devices; late answers |
| 3 | **Saves per file, with progress, outside the lock** (D3) | `TaildropRules.saveScript` per file with progress lines and no `timeout`; `TaildropClient`: save transfers through `schedule`, not `_runLocked`, Skip (left in the inbox, not retried automatically), "Fetch now", stall, logout/account cancel; stand-in `curl`: `TS_FAKE_FETCH_DELAY` (writes in steps) and `TS_FAKE_FETCH_STALL=<name>` (writes half, holds) | `TaildropTest` (the script's argv); `TaildropLiveTest`: progress lines reach the file; a stalled file → Skip → the next saved, the skipped one still in the inbox and not retried by auto-save; "Fetch now"; a change (Connect) runs while a save holds; the staging folder gone after Skip; adversarial names as today | the script's safety steps unchanged (diff them); no `DELETE` before the rename; the lock no longer taken |
| 4 | **The transfers list on the page** (D4) | `TaildropSection.qml`: one list (keys), bars, texts, Skip, "Send now" / "Fetch now", Cancel, Clear; the old per-file rows and result lines go | a UI suite (`TailscaleUiTest` or a new `TaildropListTest`) on a stand-in client: rows per state, buttons offered with their words, a row keeps its identity when the list changes (keys), plain text names | the KeyedModel rule; theme tokens; public elements only |
| 5 | **Several devices from the page** (D8) | `TaildropSection.qml`: the target pills as toggles, the Send button's label ("Send to laptop" / "Send to 3 devices") and its action from one rule (`TaildropTransferRules.sendButton`); `TaildropClient` `targetIds` instead of `targetId` (a device gone from the tailnet drops out of the choice) | `TaildropTransferTest` (`sendButton`: none, one, three, one unavailable); the UI suite: three picked → three transfers, the files chosen once; `TaildropLiveTest`: the `find -P` check runs once | label and action from one decision; nothing sent to a device no longer there |
| 6 | **The popup on transfers, in two panels** (D5) | `TaildropRules.popupRow` and `TaildropSendRow.qml` from transfers (the stall line with Skip / "Send now" while one panel); the popup's received part ("Saving 2 of 5", bar, stall line); `TailscalePopup.qml`: `popupSplit` → a `Row` of the existing panel, a rule and a new `module/TaildropFilesPanel.qml` (a header per device, its file rows; "Received files"; its own scroll), `implicitWidth` of both | `TaildropTest` (`popupRow` cases); the UI suite's popup cases: 2 files → one panel, rows under the device; one file each to three devices → two panels, three headers, the device rows show only their one-line state; a cleared transfer → back to one panel; the files panel's rows keep their identity (keys); names as plain text | the row's label and action from one decision; the Repeater rules (keys, `_ready`); theme tokens; that nothing in it needs the core |
| 7 | **Docs and the real machine** (D6) | `docs/features.md`, `privileges.md`, `architecture.md`, `ipc.md` checked against the code as a whole; the release line (0.7.0) | — ; on a real tailnet, by the owner or the lead (no agent changes the real Tailscale): a real send, Skip mid-file, what the peer keeps; two files in parallel to one device; one file to two devices at once; a save of a large file; the bus's entry for a killed send | that no text still names a time limit |
| 8 | **Progress notifications for transfers** (D7, after core N3) | manifest `api` 1.33 and the setting `mod.tailscale.taildropNotifications`; `TaildropTransferRules.notification`; `TaildropClient` keeps one handle per transfer; the page's setting row; `docs/features.md`; the release line (0.8.0) | `TaildropTransferTest` (the rule: none before 3 s, texts, actions on a stall, `toast` per mode, announce on stall / done / failed, none on Skip / Cancel / moving again); `TaildropLiveTest` with the test kit's recorded handles: none for a short send, one for a long one, updates coalesced, "stay" → `whileRunning` in the record, "brief" → `brief` and an announce at the stall, Skip pressed through the kit → that file skipped, dismissed → transfer goes on | one handle per transfer; closed at module stop; the setting read where the handle is made |

Order: D1 → D2 → D3 → D4 → D8 → D5 → D6 (table rows 1–7); D7 after D6 and after the
notification plan's slice N3. D2 and D3 are independent of each other after D1 (one agent
at a time: they share `TaildropClient.qml`). D8 needs D2 (sends to several devices) and D4
(the page's list). D6 holds the module's 0.7.0 release.

## 6. Verified, assumed, hard

**Verified in the code:** §2 with its lines; the runner's `timeoutMs: 0` and line output
(`api/Api.qml` in the core, CommandRunner 1.8); the stand-ins' behaviour as described; the
calendar's two panels and the popup's sizing by content (§3.6, core lines named there); a
module's popup panel is that content (`api/Api.qml:551`), and `Api.theme.popupWidth` and
`Api.theme.divider` are public (`singletons/Theme.qml:516`, `api/ThemeTokens.qml:33`).

**Assumed, checked where named:**
- `tailscale file cp` with one file per run behaves as with several (it sends them one by
  one; D2 on stand-ins, D6 for real).
- Killing a `file cp` ends the transfer on the peer; what the peer keeps (D6).
- Two `file cp` runs to one device at once both work; runs to two devices at once both
  work (D6).
- The LocalAPI's `GET files/<name>` can be read by two `curl`s at once (D6).
- A popup twice as wide still fits a small screen at a side bar (the popup's own limits;
  D5's UI suite at a 1366-px screen, and by eye).

**Hard:** the end of "no limit" — a file that never moves and a user who never looks would
keep a process forever. That is the decision (the user decides); the stall line, the popup
line and (D7) the notification are what keeps it from being silent.
