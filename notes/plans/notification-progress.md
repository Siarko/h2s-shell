# Notifications with a progress bar

Status: a plan, for the owner's approval. Nothing here is built. It answers the tracker's
decision "Notifications (2026-11-19)": a module updates one notification's progress instead
of sending new ones (the spec's `value` hint and replacement; the shell is the notification
server); an API feature.

The Taildrop transfers list ([taildrop-transfers.md](taildrop-transfers.md)) is the first
user; its notification slice comes after the last slice here.

## 1. The problem

Two senders want a notification that shows how far a job has gone and changes in place:

- **Outside apps over D-Bus** (a browser's download, `rsync` wrappers, `notify-send -r`
  scripts) already send the spec's `value` hint (an int, 0–100) and replace their
  notification by id (`replaces_id`). The shell's server accepts both today and changes the
  notification in place, but the card never shows the value: the bar is lost.
- **A module** has no way at all: `module.notify(...)` sends and forgets. A transfer that
  wants to say "40 %" would send a new notification at every step.

What the owner wants: one notification per job, its bar moving, ended as done, failed or
cancelled; updates never enter the list as new notifications; nothing floods.

## 2. What exists today

**The server (incoming).** `singletons/Notifications.qml`

- `NotificationServer` at 30–118: every new notification is tracked (91), timestamped
  (58–64), searched for codes (69–89) and queued as a toast (92–93). There is no separate
  history: the notification centre (`panels/NotificationPanel.qml:81`, a `ListView` on the
  server's `trackedNotifications`) *is* the list; a notification stays until dismissed.
  The screensaver and lock screen list the same model (`screensaver/NotificationList.qml:21`).
- A replacement (same id) changes the object in place — Quickshell emits no new
  `notification` signal; the shell only listens to `summaryChanged` / `bodyChanged`
  (99–102) to ring the bell once between two openings of the panel (`_replaced`, 225–233).
  So "an update never enters the history" already holds for outside apps.
- Toasts: `hud/NotificationHudItem.qml` takes one notification object from `hudQueue` and
  shows it in a `NotificationCard`, counting down (`Notifications.countingToast`, 151–156);
  a critical one stays (`isPersistent`, 160–162). A replaced notification's toast shows the
  new text live (the card binds `summary` and `body`: `components/NotificationCard.qml:116-117`)
  but a replacement never brings a toast back.
- "Do Not Disturb" does not exist as such: the closest is the setting
  `notifications.toasts` (off: nothing slides in, everything goes to the centre;
  `Notifications.qml:92`, 176–177), which a profile can switch, and the toast screen
  rule (`toastScreen`, 14–24: none while a fullscreen window is there).
- Actions: the card runs an action and asks to be dismissed in the same click
  (`NotificationCard.qml:536-538`, and the default action at 63–71) — even for a
  notification that is `resident` (the spec: stays after an action). Quickshell 0.3.2's
  `Notification` has `resident`, `hints` (a `QVariantMap` with `hintsChanged`) and
  `closed(reason)` (its qmltypes, `Quickshell/Services/Notifications`).

**The sender (outgoing).** `singletons/Notifier.qml`

- `send(summary, opts)` (171–198) runs one `notify-send` per notification (the argv:
  `command`, 113–169; every option before `--`). Options include `replaceId` (134–135) and
  `hints` (137–151), so a caller could send a `value` already — but `send` returns nothing
  and never learns the id (no `--print-id`), so there is nothing to replace.
- Actions and `onDismissed` use `notify-send --wait` in a process of its own (187–197,
  `_dispatch` 202–220, which reads the *first* stdout line as the action).
- In module test mode nothing is sent; each call is recorded (`recordOnly`, `recorded`,
  26–42, 176–184).
- `format: "plain"` makes text from outside safe (`prepared`, `plainText`, 44–108).

**The API.** `api/ModuleHandle.qml:302-306` `notify()` calls `Notifier.send` under the
module's name, through `ModuleRules.moduleNotifyOptions` (`singletons/ModuleRules.qml:1738-1751`),
which drops a category of the shell's own (`x-qs-…`). Reference text: `api/Api.qml:218-232`.
API version 1.32 (`ModuleRules.qml:48`).

**The bar.** `components/ProgressBar.qml` (0–1, below 0 a run of unknown length, theme
tokens `progress`, `track`); public wrapper `api/ProgressBar.qml` with `kind` normal /
success / warning / danger (API 1.31).

**Tests.** `tests/NotifierTest.qml` (pure: `plainText`, `prepared`, `command`; a toast
built in a test window); the lock test bed starts a private session bus
(`tests/lock/lib.sh:449-486`, `stack_start --session-bus`, `notify`, `notification_server_up`)
and `tests/lock/tests/notifications.sh` sends a real notification to the shell's server
there. `gdbus` is in the bed's tools (`tests/lock/tools.nix:89`); `notify-send` is not.
Programs the shell already depends on: `notify-send` (libnotify) and `gdbus` (glib;
`nix/package.nix:39-41`, `install.sh:25-26`).

## 3. Design

### 3.1 What the shell shows (the server side, any sender)

A pure rule reads a notification's progress from its hints:

```
NotificationRules.progress(hints) → { shown, value, state }
  value: hints.value as a number in 0..100 → 0..1; below 0 → -1 (unknown length; the shell's
         own sender only, other daemons clamp it); absent, not a number, NaN → shown false
  state: hints["x-qs-progress-state"]: "running" (default) | "done" | "failed" | "cancelled"
```

`singletons/NotificationRules.qml` is new (pure, `tests/NotificationRulesTest.qml`).

The card (`NotificationCard.qml`) shows a `ProgressBar` under the body when `shown`:
running → the accent, its value; done → full, success colour; failed → full, error colour;
cancelled → no bar. The same card is the toast and the centre's entry, so both show it;
the screensaver and lock screen show it only where they show the body (their detail
setting; `LockViewTest` cases). The bar's own animation smooths a fast sender.

Behaviour around it, all from existing rules unless named:

- **Updates are not news.** A value-only change touches `hints` only: no bell, no toast,
  no new entry. A changed summary or body rings the bell once if the old one was seen
  (`_replaced`, unchanged). The arrival time stays the first one.
- **The end of a job** (state done or failed, shell senders only): a toast again, once,
  if that notification's toast is not on screen — **open question Q1** (recommended).
- **Resident** notifications keep their entry after an action: the card runs the action
  and asks to be dismissed only when the notification is not resident (the toast still
  slides away). A progress notification from the shell's sender is always resident, so
  "Cancel" or "Skip" on it does not make it vanish.
- **Toasts off / no toast screen** (the shell's "Do Not Disturb"): progress notifications
  go to the centre only, like any other; the end-of-job toast is not shown either.
- **Critical** urgency keeps its rule (a toast stays); a module should not use it for
  progress (Api.qml says so).
- **Rate (outside apps).** Each D-Bus call is one property change on one object, drawn at
  the next frame; no limit is added on the server. (A sender that floods is that sender's
  problem; the card's work per update is a binding.)

### 3.2 The sender: a handle

`Notifier.send(summary, opts)` with `opts.progress` present returns a **handle**; without
it, nothing changes (it returns `null`). The handle is a `QtObject` made by `Notifier`
(`singletons/io/NotificationHandle.qml`, I/O only; every decision in `NotificationRules`):

```
handle.open          bool: shown and not closed
handle.state         "starting" | "running" | "done" | "failed" | "cancelled" | "closed"
handle.update({ summary?, body?, progress?, actions?, state? })
                     state "done" | "failed" | "cancelled" ends the job: after it only
                     close() is taken
handle.close()       takes it away (an end state stays in the centre until then, or until
                     the user dismisses it)
opts.onDismissed     called once when the user closes it (not after close())
opts.actions         as today; on a progress notification they stay after a click
```

How it runs (only programs the shell already depends on):

- **Show:** `notify-send --print-id --wait --hint=boolean:resident:true
  --hint=int:value:N --hint=string:x-qs-progress-state:running --hint=string:x-qs-progress-run:<run> …`.
  The first stdout line is the id; a later line is an action (`_dispatch` reads the line
  after the id). The process exits when the notification closes — that is how the handle
  learns it was dismissed, whoever the server is. `--expire-time=0` while running (another
  daemon must not expire it; the shell keeps everything anyway).
- **Update:** a new `notify-send --print-id --wait --replace-id=<id> …` with the whole
  current content (the spec replaces every field, so actions are sent again); when it has
  started, the previous waiter is stopped and its exit ignored. One waiter per handle at
  any time; only the newest waiter's lines count (a click that both hear in the hand-over
  is dispatched once). The same run re-arms the actions after a click: libnotify's `notify-send --wait`
  ends after the first action, so after each action the handle sends its current content
  again with `--replace-id`.
- **Close:** `gdbus call --session --dest org.freedesktop.Notifications
  --object-path /org/freedesktop/Notifications --method
  org.freedesktop.Notifications.CloseNotification <id>`; the waiter then exits; no
  `onDismissed`.
- **Coalescing** (`NotificationRules.nextSend(handleState, change, now)`, pure): at most one
  `notify-send` starting per handle; while one starts, only the newest wanted content is
  kept. A progress-only change is sent at most once per `minUpdateMs` (1000) and only
  when the whole percent moved; a text, action or state change goes at the next free
  moment; an end state always goes. Nothing is sent after `close()` or after the waiter
  reported a dismissal.
- **Late answers lose.** An update before the id is known waits for it (only the newest
  content is kept). An answer whose id is not the handle's means the old one was closed
  meanwhile and the server made a new one: the handle closes the new one at once and goes
  to "closed" (so a dismissed notification never comes back). A close() before the id is
  known closes it when the id arrives.
- **Orphans.** Every progress notification carries `x-qs-progress-run`, a token made once
  per Notifier instance. The server keeps notifications over a reload; at start
  (`Component.onCompleted`) `Notifications` dismisses any tracked notification with
  state "running" whose run token is not the current one (`NotificationRules.orphaned`)
  — its sender is gone, its bar would stand still for ever. After a full restart the
  server's list starts empty anyway.
- **Hints of the shell's own** (`x-qs-progress-state`, `x-qs-progress-run`, `resident` on
  progress) are set by Notifier after the caller's options are read; a module's `x-qs-…`
  hint keys are dropped (`moduleNotifyOptions` grows from the category to every key).
- **Test mode:** nothing runs; `recorded` gets one entry per show, update and close with
  the handle's number (`{ kind: "show" | "update" | "close", handle, summary, body,
  progress, state, … }`), and the handle behaves as if the server answered at once with a
  made-up id. `ModuleTestKit` gains a way to dismiss a recorded handle and to press one of
  its actions, so a module's suite can drive both.

### 3.3 The API (1.33)

`module.notify(summary, options)` and `Api.notify` return the handle when
`options.progress` is a number (0–100, or -1 for a run of unknown length), else `null` as
today. The handle's shape is §3.2's. When the module is turned off, its open handles are
closed (`ModuleHandle` keeps them; closed in its teardown, the same place its runs end).

```
const job = module.notify("Sending photo.jpg", {
    body: "to laptop", format: "plain", progress: 0,
    actions: [{ id: "cancel", label: "Cancel", onTriggered: () => client.cancelSend() }],
    onDismissed: () => job = null
});
job.update({ progress: 40 });
job.update({ state: "done", summary: "Sent photo.jpg", body: "to laptop", actions: [] });
```

**Why a handle and not `id` + `replaces`:** the id comes back from `notify-send` some
milliseconds later, so an `id` API would make every module wait for it and race (the late
answers rule); coalescing, the one-waiter rule, re-arming actions after a click and "never
bring back a dismissed one" would each be written again in every module. The handle keeps
all of it in one tested place, and it serves any module (a download, a backup, a sync), not
Taildrop only. A door stays open: a plain notification could later get a handle too
(updating a "3 files received" count) without changing this shape.

Versioning: a minor (1.33): `api/Api.qml` header and reference, `ModuleRules.apiVersion`,
a `### Module API` line in `CHANGELOG.md`, as the last edit of the slice. The server-side
bar is a shell feature (a CHANGELOG line under Unreleased, no API number).

Docs: `docs/FEATURES.md` "Notifications" (the bar, resident actions, the end toast) and
the external tools table (`notify-send`, `gdbus` now also for notifications);
`docs/ARCHITECTURE.md` "Modules" (notify returns a handle with progress).

### 3.4 Not in this plan

- A plain notification's handle (above, a door).
- Grouping several jobs into one notification.
- A server-side rate limit for outside apps.

## 4. Open questions for the owner

**Q1. When a long job ends, does its toast come back?**
Situation: a module's job runs for twenty minutes. Its toast went after a few seconds; the
notification sits in the centre with its bar. Example: "Sent photo.jpg · to laptop" turns
done while you work in another window — today you would see it only by opening the
centre (the bell rings once, because the text changed).
- (a) **Recommended:** done and failed both show the toast again, once; cancelled (you
  pressed Cancel) does not.
- (b) Only failed shows the toast again.
- (c) Never; the bell is enough.
What changes: one rule in `NotificationRules` (which end states bring a toast), a line in
`docs/FEATURES.md`. With toasts off nothing slides in either way.

(Decided by the plan, the owner may overrule: dismissing a running progress notification
takes it away for good — the job goes on, the module is told (`onDismissed`) and sends no
more updates. Outside apps do as they do: by the spec a sender's next update may bring it
back.)

## 5. Slices

Every slice: one change with its test; the named suites while iterating, `tests/run-all.sh`
before the commit, on the Arch machine; the lock-bed scenarios also on the NixOS machine
(over SSH, `nix` tools) before the merge. Reviewer: a second agent with the diff only.

| # | Slice | Changes | Tests | Reviewer looks at |
|---|---|---|---|---|
| 1 | **The card shows a sender's progress** (N1) | `singletons/NotificationRules.qml` (`progress`), `NotificationCard.qml` (the bar; an action on a resident notification does not dismiss its entry), `panels/NotificationPanel.qml` if the dismissal sits there, the lock/screensaver card under its detail rule; `docs/FEATURES.md`; CHANGELOG (shell feature) | `NotificationRulesTest` (new: absent, 0, 40, 100, 150, -5, "40", NaN, the four states); a card built in `NotifierTest` with a stand-in notification object (`hints: { value: 40 }` → a bar at 0.4; no hint → none; resident + action → no dismiss request); `LockViewTest` cases; the lock bed: new `tests/lock/tests/notification-progress.sh` — `gdbus` Notify with `value` 10, then `replaces_id` with 60, then the shell's state over the `shelltest` IPC (a new `notificationState()` in `Bar.qml`: id, summary, progress) shows one entry at 60. **First step of the slice**: this scenario proves Quickshell 0.3.2 passes the `value` hint into `hints` and updates it on replacement; if it does not, stop and report (an upstream draft under `notes/upstream/`) | the rule's edges; that nothing else (bell, toast, timestamps) changed for replaced notifications; theme tokens only |
| 2 | **Notifier's progress handle** (N2) | `singletons/io/NotificationHandle.qml` (new), `Notifier.qml` (`send` with `progress` returns it; `command` takes print-id, replace-id, the shell's hints; `_dispatch` after an id line; test-mode records), `NotificationRules` (`nextSend`, `orphaned`), `Notifications.qml` (orphans at start); `tests/lock/tools.nix` (libnotify), the Arch list in `docs/ARCHITECTURE.md` "Where the test tools come from" and `tests/system/arch/test-tools.sh` | `NotifierTest`: argv for show, update, a value, the hints, nothing after `--` but text; `NotificationRulesTest`: `nextSend` (coalesced progress, text at once, end state always, nothing after close, an update before the id, a foreign id → close), `orphaned`; test mode records show/update/close. The real path, against stand-ins only: a lock-bed scenario on the private bus (real `notify-send` and `gdbus`, the shell's own server), driven by a test function on the bed's `locktest` IPC (`tests/lock/seams/TestSeams.qml`): show at 0, ten updates in a burst → at most a few `notify-send` runs and the last value shown; an action pressed (through `shelltest`) after an update reaches its callback and the entry stays; dismissed → `onDismissed`, a later update sends nothing; close() → gone, no `onDismissed`; a reload → the orphan dismissed | the one-waiter rule (no double callbacks, no stray processes: `pgrep` after the scenario); late answers; that plain `send` is byte-for-byte as before |
| 3 | **`notify` returns the handle** (N3, API 1.33) | `api/ModuleHandle.qml` and `Api.qml` (`notify` returns it; the reference text), `ModuleRules.moduleNotifyOptions` (drops every `x-qs-` hint key; checks `progress`), `ModuleHandle` closes its handles on teardown, `tests/ModuleTestKit.qml` (recorded handles, dismiss, press an action), the fixture module `tests/fixtures/modules/good` (a progress notification on its IPC); `docs/ARCHITECTURE.md` "Modules"; the version lines | `ModuleRulesTest` (options), `GoodApiTest` (a handle in test mode: show, update, done, close, dismissed through the kit, closed when the module is turned off); the lock bed `modules.sh` (or a new scenario) — the fixture module's progress notification on the private bus, the module turned off → its notification gone | the API text against the code; agnostic shape; the version lines together |
| 4 | **A job's end brings its toast back** (N4, only with Q1 (a) or (b)) | `NotificationRules` (which end states toast), `Notifications.qml` (re-queue the object once when its state hint turns done/failed and its toast is not shown) | `NotificationRulesTest`; a `NotifierTest` case through `hudQueue` | toasts off and no toast screen respected; once only |

Order: 1 → 2 → 3 → 4. Slice 1 is useful alone (outside apps). Taildrop's notification slice
needs slice 3 (manifest `api` 1.33).

## 6. Verified, assumed, hard

**Verified in the code:** everything in §2 with its line; Quickshell 0.3.2's qmltypes list
`Notification.hints` (with `hintsChanged`), `resident`, `closed(reason)`, and the server's
`extraHints`; `notify-send` (libnotify 0.8.8) has `--print-id`, `--replace-id`, `--wait`,
typed `--hint`.

**Assumed, checked in the slice named:**
- Quickshell puts every client hint into `hints` (not only those named in `extraHints`) and
  replaces `hints` on a `replaces_id` call (slice 1, first step).
- Quickshell keeps a replaced notification's object and emits no new `notification` signal
  (the code at `Notifications.qml:99-102` relies on it already; slice 1's scenario shows it).
- `notify-send --print-id --wait` prints the id before it waits, and with `--replace-id` its
  `--wait` follows that id's actions and closing (slice 2's scenario).
- Stopping a `notify-send --wait` closes nothing on the server (slice 2).

**Hard:** the one-waiter hand-over (start the new waiter, then stop the old, ignore its
exit) is where double callbacks or a lost click could hide; slice 2's review looks there.
