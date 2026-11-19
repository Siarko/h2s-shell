# Taildrop: a list of transfers

Status: a plan, for the owner's approval. Nothing here is built. A feature of the module
`h2s-shell-tailscale` (its repository; core untouched except where the notification plan
says). It answers the tracker's decision "Taildrop (2026-11-19)": no fixed time limits on
transfers (sending, or copying received files out of Tailscale's inbox); a list of
transfers with progress; per file "Skip" (stop it, the rest go on) and "Fetch in parallel"
(start the next file beside a stuck one); a transfer with no progress shows "no progress for
N min" and waits for the user; "The program could not be started." kept.

Its last slice uses progress notifications from [notification-progress.md](notification-progress.md)
(module API 1.33); everything before it needs nothing new from the shell.

## 1. The problem

Today a send is one `tailscale file cp` for all its files, stopped after 2 minutes without
progress and after 6 hours in all; a save of received files is one script for all of them,
600 s per file, run under the client's change lock. A large file on a slow link is killed
although it was moving; a stuck file takes the whole batch with it; a long save holds the
lock, so Disconnect and every other change wait. Nothing lets the user stop one file and
keep the rest, or go on beside a stuck one.

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
- The bar popup: `module/TaildropSendRow.qml` under each device (files chosen, Send, one bar
  for the whole send with Cancel, the result; `TaildropRules.popupRow`), and in
  `module/TailscalePopup.qml:288-320` the waiting count, Save and the last save's line.
- IPC (`module/Main.qml:212-240`, `docs/ipc.md` "Taildrop"): `taildrop` (JSON), `sendFile`,
  `cancelSend`, `saveReceived`.

**Docs that state the limits:** `docs/features.md:214` ("A send with no progress for 2
minutes is stopped. A send lasts 6 hours at most."), `docs/privileges.md:118-119` (the
limits table), `docs/architecture.md:157,178` (`timeout` for each file of a save).

**Stand-ins** (`module/tests/stand-in/`): `tailscale` `file cp` checks the files and, per
file, appends `OutgoingFiles` lines to `TS_FAKE_BUS_FILE` (started, half with
`TS_FAKE_SEND_DELAY`, finished; `TS_FAKE_SEND_FAIL`, `TS_FAKE_SEND_REFUSE`); `curl` serves
the inbox (`GET`/`DELETE files/…`) at once; `timeout` is the real one. Suites:
`module/tests/TaildropTest.qml` (rules), `TaildropLiveTest.qml` (the client on the
stand-ins, a scenario per directory, `idleLimitMs` and `timeLimits` shortened).

**The module API needs nothing new:** `CommandRunner` takes `timeoutMs: 0` (no limit) and
hands output line by line (`onStdout`); `runLimits(0)` already means "no limit" for the
event stream; `ProgressBar`, `SmallButton`, `Pill` are public; a list keyed by strings is a
Quickshell `ScriptModel` of keys, which a module may use.

## 3. Design

### 3.1 Transfers, files, states

A **transfer** is one batch: a send of chosen files to one device, or a save of waiting
files. A transfer holds **files**; each file is one process. The client keeps
`transfers` (newest first, at most 20 kept after they end) and the views read them. Every
decision is in a new pure file, `module/TaildropTransferRules.qml` (suite
`module/tests/TaildropTransferTest.qml`); `TaildropClient` only runs what it decides.

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
`extraSlot` (the user pressed "Fetch in parallel" on it).

**Stalled** (`stalledFor(file, now) → minutes or 0`): running, and `bytes` has not grown for
`stallMs` (2 minutes, a client property the suites shorten). The row says "No progress for
N min" (N whole minutes since `progressAt`, from 2, moving once a minute) and offers Skip and
"Fetch in parallel". Nothing is stopped by time. A file that moves again drops the line by
itself.

Without the bus (the event stream down) a send has no progress to see: its files count as
not moving, so after 2 minutes they say so too — honest from where the module stands.

### 3.2 Scheduling and "Fetch in parallel"

Two pools, sends and saves, each scheduled by `schedule(files) → keys to start`:

- slots = 1 + the number of running files with `extraSlot`, at most `maxParallel` (4);
- queued files start in order while fewer than `slots` run;
- never two files of the same name to the same device at once (the bus tells sends apart
  by peer and name only).

**"Fetch in parallel"** on a stalled file sets its `extraSlot`: the next queued file starts
beside it; the stuck one keeps running (it may still finish). When it ends, its slot ends
with it. Offered only while the file is stalled, files wait behind it, and `slots` is below
`maxParallel`.

**Skip** on a running or queued file: its process gets TERM (KILL after 5 s, the runner's
`cancel()`); the next file starts. Sends: what the peer keeps of a part-sent file is
Tailscale's (assumed: a partial it drops or resumes later; checked on a real machine).
Saves: the staging copy is removed by the script's trap, the file **stays waiting** in the
inbox, and auto-save does not try it again until the next arrival or a manual Save (as
`_autoTried` today).

**Cancel** on a transfer: Skip for every file not ended. The transfer's line says
"Cancelled".

**A second transfer** while one runs is queued behind it in its pool, not refused (the
popup's Send stays on). *(The plan's choice; today a second send is refused.)* An arrival
while a save runs adds the new waiting files to that save's queue.

### 3.3 Sending, per file, no limit

- The `find -P` check stays, once for the whole transfer.
- Each file: `tailscale file cp -- <path> <IPv4>:` (`TailscaleRules.commandFor("fileCp")`
  with one path), `timeoutMs: 0`, as the user, outside the change lock, as today.
- Progress: `_applyProgress` unchanged in spirit — `sendProgress` per file, but matched
  also by the file's own start time (a killed earlier attempt's unfinished bus entry for the
  same name never counts).
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

- **The page** (`TaildropSection.qml`): the per-file send rows and the saves' result lines
  become one **Transfers** list. A transfer: a title line ("To laptop · 3 files", "Saving
  2 files"), Cancel while running, Clear when ended. A file: its name (plain text, elided
  in the middle), a `ProgressBar` (normal while running, -1 while its size is unknown;
  success full when sent/saved; danger full when failed; none when skipped, cancelled or
  left), a short text ("40 %", "No progress for 3 min", "Sent", "Saved as photo (1).jpg",
  "Skipped", "Left waiting · name taken", why it failed), and Skip / "Fetch in parallel"
  where §3.2 offers them. "Receiving …" (the peer → inbox stage) shows as rows without
  buttons. The list is a `ScriptModel` of keys (`<transfer id>/<file index>`), each
  delegate looking its file up by key — never rebuilt objects as rows.
- **The popup**: the row under a device keeps one bar for the transfer (as today) and its
  Cancel; when a file of it stalls, one line under it: "photo.jpg: No progress for 3 min"
  with Skip and "Fetch in parallel". The received-files part shows a running save as
  "Saving 2 of 5" with a bar, the same stall line, and the last result as today.
  **Open question Q3.**
- **IPC**: `taildrop` JSON gains `transfers`; new `skipFile <transfer> <index>`,
  `parallelFile <transfer> <index>`, `cancelTransfer <transfer>`; `cancelSend` stays (the
  running sends). `docs/ipc.md`.

### 3.7 Progress notifications (after the notification plan's slice 3)

One progress notification per transfer that is still running after 3 seconds (a short one
makes none): "Sending 3 files to laptop" / "Saving 2 files", its bar the transfer's share
of bytes (-1 while unknown), the body the current file's name. A stalled file: the body
says "photo.jpg: No progress for 3 min" and the actions are Skip and "Fetch in parallel"
(resident: the notification stays after a click). The end: "Sent to laptop", "Saved 2
files", "1 of 3 not sent · <reason>" as done or failed; Cancel → cancelled. Dismissing it
leaves the transfer running. **Open question Q4.** The arrival notification ("File
received") is unchanged.

## 4. Open questions for the owner

**Q2. The words on the two buttons and the stall line.**
Situation: the decision names "Skip" and "Fetch in parallel"; "fetch" fits copying a
received file, less a send. Example: a send of three videos to the laptop, the first stuck
at 40 % for 3 minutes; its row says "No progress for 3 min" and offers two buttons.
- (a) **Recommended:** "Skip" everywhere; "Fetch in parallel" on received files, "Send in
  parallel" on sends; the line "No progress for 3 min" (shown from 2 min, whole minutes).
- (b) "Fetch in parallel" on both.
- (c) Other words.
What changes: three strings in `TaildropTransferRules` and the features doc.

**Q3. Where the list lives.**
Situation: the page has room for every file; the popup is small and shows one row per
device. Example: you send 10 files from the popup; file 4 stalls.
- (a) **Recommended:** the full list on the Tailscale page; the popup keeps one bar per
  device, and a stalled file shows there as one line with Skip and "Fetch in parallel" (so
  nothing makes you open the settings window to act).
- (b) The full list in the popup too (a scrolling part under the devices).
- (c) The list on the page only; the popup shows "No progress" and a link to the page.
What changes: `TaildropSendRow.qml` and the popup's received part (slice 6); (b) adds a
list there.

**Q4. Progress notifications for transfers** (after the notification plan).
Situation: a transfer that runs for minutes is visible only in the popup or on the page.
Example: you start saving a 4 GB video and close the popup.
- (a) **Recommended:** on for every transfer still running after 3 seconds, with Skip and
  "Fetch in parallel" on it when a file stalls; no setting.
- (b) The same, with a switch on the Tailscale page (on by default).
- (c) Only when a file stalls (a notification asking for a decision), nothing for progress.
What changes: slice 7's rules; (b) adds one stored setting.

## 5. Slices

All in the module repository, on a work branch, tested against a core tree nobody edits
(`H2S_SHELL_DIR=<core tree> tests/run.sh <suites>` while iterating; all the module's suites
and the core's `tests/run-all.sh --quick` before the commit), on the Arch machine; the
module's suites again on the NixOS machine before the merge. A module minor (0.7.0) and a
CHANGELOG line per user-visible slice; each slice updates the docs it makes untrue
(`docs/features.md`, `docs/privileges.md`, `docs/architecture.md`, `docs/ipc.md`).
Reviewer: a second agent with the diff only. Slices 1–6 need nothing from the shell
(manifest `api` stays 1.32); slice 7 needs core API 1.33.

| # | Slice | Changes | Tests | Reviewer looks at |
|---|---|---|---|---|
| 1 | **The transfer rules** (D1) | `module/TaildropTransferRules.qml` (new): file states, `stalledFor`, `schedule` (slots, extra slots, same name per device), what Skip / parallel / Cancel offer, the texts, a transfer's totals, `parseSaveLine`, the per-file save argv; no caller yet | `TaildropTransferTest` (new): every state's offers; stall at 1:59 / 2:00 / 3:10; slots with 0–5 extra; the same-name rule; a late token; save lines (progress, outcomes, junk) | that every later decision is here; names and words match §3 |
| 2 | **Sends per file, without time limits** (D2) | `TaildropClient`: transfers for sends, one `file cp` per file through `schedule`, `timeoutMs: 0`, stall instead of stop, Skip, parallel, Cancel, queued second send, "The program could not be started."; `TailscaleRules.timeLimits.send` goes; the page's existing rows show the stall text and get Skip; IPC; stand-in `tailscale`: `TS_FAKE_SEND_STALL=<name>` (that file stops after its first bus line and holds until killed) | `TaildropLiveTest` scenarios: two files, the first stalls → the stall text after a shortened `stallMs` → Skip → the second sent, the first `skipped`; parallel → the second starts while the first holds, then both end; Cancel → both stopped, no stray process; a second send queued and run after; a program that cannot start → the sentence; Disconnect cancels; a late bus line for a skipped file changes nothing | no limit left anywhere for sends; the kill of one file never touches another; late answers |
| 3 | **Saves per file, with progress, outside the lock** (D3) | `TaildropRules.saveScript` per file with progress lines and no `timeout`; `TaildropClient`: save transfers through `schedule`, not `_runLocked`, Skip (left in the inbox, not retried automatically), parallel, stall, logout/account cancel; stand-in `curl`: `TS_FAKE_FETCH_DELAY` (writes in steps) and `TS_FAKE_FETCH_STALL=<name>` (writes half, holds) | `TaildropTest` (the script's argv); `TaildropLiveTest`: progress lines reach the file; a stalled file → Skip → the next saved, the skipped one still in the inbox and not retried by auto-save; parallel; a change (Connect) runs while a save holds; the staging folder gone after Skip; adversarial names as today | the script's safety steps unchanged (diff them); no `DELETE` before the rename; the lock no longer taken |
| 4 | **The transfers list on the page** (D4) | `TaildropSection.qml`: one list (keys), bars, texts, Skip, "Fetch in parallel", Cancel, Clear; the old per-file rows and result lines go | a UI suite (`TailscaleUiTest` or a new `TaildropListTest`) on a stand-in client: rows per state, buttons offered, a row keeps its identity when the list changes (keys), plain text names | the KeyedModel rule; theme tokens; public elements only |
| 5 | **The popup on transfers** (D5) | `TaildropRules.popupRow` and `TaildropSendRow.qml` from transfers; the stall line with its buttons; the popup's received part ("Saving 2 of 5", bar, stall line) | `TaildropTest` (`popupRow` cases), the UI suite's popup cases | the row's label and action from one decision |
| 6 | **Docs and the real machine** (D6) | `docs/features.md`, `privileges.md`, `architecture.md`, `ipc.md` checked against the code as a whole; the release line | — ; on a real tailnet, by the owner or the lead (no agent changes the real Tailscale): a real send, Skip mid-file, what the peer keeps; two files in parallel to one device; a save of a large file; the bus's entry for a killed send | that no text still names a time limit |
| 7 | **Progress notifications for transfers** (D7, after core N3) | manifest `api` 1.33; `TaildropTransferRules` (when a transfer gets a notification, its texts and actions); `TaildropClient` keeps one handle per transfer | `TaildropTransferTest` (the rules); `TaildropLiveTest` with the test kit's recorded handles: none for a short send, one for a long one, updates coalesced, stall → actions, Skip pressed through the kit → that file skipped, dismissed → transfer goes on | one handle per transfer; closed at module stop |

Order: 1 → 2 → 3 → 4 → 5 → 6; 7 after 6 and after the notification plan's slice 3.
Slices 2 and 3 are independent of each other after 1 (one agent at a time: they share
`TaildropClient.qml`). Slice 6 holds the module's release.

## 6. Verified, assumed, hard

**Verified in the code:** §2 with its lines; the runner's `timeoutMs: 0` and line output
(`api/Api.qml` in the core, CommandRunner 1.8); the stand-ins' behaviour as described.

**Assumed, checked where named:**
- `tailscale file cp` with one file per run behaves as with several (it sends them one by
  one; slice 2 on stand-ins, slice 6 for real).
- Killing a `file cp` ends the transfer on the peer; what the peer keeps (slice 6).
- Two `file cp` runs to one device at once both work (slice 6).
- The LocalAPI's `GET files/<name>` can be read by two `curl`s at once (slice 6).

**Hard:** the end of "no limit" — a file that never moves and a user who never looks would
keep a process forever. That is the decision (the user decides); the stall line, the popup
line and (slice 7) the notification are what keeps it from being silent.
