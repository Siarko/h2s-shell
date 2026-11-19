# Notifications with a progress bar

Status: a plan, for the owner's approval. Nothing here is built. It answers the tracker's
decision "Notifications (2026-11-19)": a module updates one notification's progress instead
of sending new ones (the spec's `value` hint and replacement; the shell is the notification
server); an API feature. With the owner's answers of 2026-11-19 (§4): toasts follow the
display time the sender asks for, and a sender may keep its toast up while a job runs or
bring it back when the job's status changes.

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
cancelled; updates never enter the list as new notifications; nothing floods. And (answer
of 2026-11-19) a toast shows as long as its sender asks — so a long job's toast can stay
on screen for the whole job.

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
  but a replacement never brings a toast back. A toast's "×" and a swipe take the toast
  away only (`NotificationHudItem.qml:202`, `dismiss()` 72–76: it slides out); the entry
  stays in the centre.
- **The display time a sender asks for is ignored.** Every toast that is not critical
  counts down `notifications.toastDuration` (`hud/NotificationHudItem.qml:185`, the
  setting at `singletons/SettingsSchema.qml:253-254`, 1–120 s, default 5); nothing in the
  tree reads the notification's `expireTimeout` (a search for "expire" finds only the
  sender's option, `singletons/Notifier.qml:14,125-126`). Quickshell 0.3.2 has it:
  `Notification.expireTimeout` (a read-only `double` with `expireTimeoutChanged`) and
  `expire()` (its qmltypes, `Quickshell/Services/Notifications`). The spec's
  `expire_timeout`: -1 the server decides, 0 never expires, otherwise milliseconds. So
  `notify-send -t 0`, an app that asks for 0, and an app that asks for 30 s all get 5 s
  today; and the shell's own `Notifier.send({ expireTime })` (and through it a module's
  `notify`, whose options pass through `ModuleRules.moduleNotifyOptions`,
  `singletons/ModuleRules.qml:1738-1751`) sends a value the shell's own server then
  ignores.
- Critical: `isPersistent` (160–162) decides two things today — the toast stays
  (`NotificationHudItem.qml:92`, no timer bar at 204) and the card's red border
  (`NotificationCard.qml:78-80`).
- Only one toast counts down at a time, the oldest that does not stay (`countingToast`,
  156), so a column leaves one by one; how many show at once is the layout's
  (`Hud.qml:123-124`: 1 for "One at a time", `toastColumnSize` for "A column"; each slot
  `slotEnabled`, 175). A toast that stays takes a slot: in the default layout ("queue")
  a critical toast holds every later one back until it is dismissed.
- "Do Not Disturb" does not exist as such: the closest is the setting
  `notifications.toasts` (off: nothing slides in, everything goes to the centre;
  `Notifications.qml:92`, 176–177), which a profile can switch, and the toast screen
  rule (`toastScreen`, 14–24: none while a fullscreen window is there).
- Actions: the card runs an action and asks to be dismissed in the same click
  (`NotificationCard.qml:536-538`, and the default action at 63–71) — even for a
  notification that is `resident` (the spec: stays after an action). Quickshell 0.3.2's
  `Notification` has `resident`, `hints` (a `QVariantMap` with `hintsChanged`) and
  `closed(reason)` (its qmltypes).

**The sender (outgoing).** `singletons/Notifier.qml`

- `send(summary, opts)` (171–198) runs one `notify-send` per notification (the argv:
  `command`, 113–169; every option before `--`). Options include `expireTime` (125–126),
  `replaceId` (134–135) and `hints` (137–151), so a caller could send a `value` already —
  but `send` returns nothing and never learns the id (no `--print-id`), so there is nothing
  to replace.
- Actions and `onDismissed` use `notify-send --wait` in a process of its own (187–197,
  `_dispatch` 202–220, which reads the *first* stdout line as the action).
- In module test mode nothing is sent; each call is recorded (`recordOnly`, `recorded`,
  26–42, 176–184).
- `format: "plain"` makes text from outside safe (`prepared`, `plainText`, 44–108).

**The API.** `api/ModuleHandle.qml:302-306` `notify()` calls `Notifier.send` under the
module's name, through `ModuleRules.moduleNotifyOptions`, which drops a category of the
shell's own (`x-qs-…`). Reference text: `api/Api.qml:218-232` (it names no display time).
API version 1.32 (`ModuleRules.qml:48`).

**The bar.** `components/ProgressBar.qml` (0–1, below 0 a run of unknown length, theme
tokens `progress`, `track`); public wrapper `api/ProgressBar.qml` with `kind` normal /
success / warning / danger (API 1.31).

**Tests.** `tests/NotifierTest.qml` (pure: `plainText`, `prepared`, `command`; a toast
built in a test window), `tests/ToastRulesTest.qml` (the toast screen); the lock test bed
starts a private session bus (`tests/lock/lib.sh:449-486`, `stack_start --session-bus`,
`notify`, `notification_server_up`) and `tests/lock/tests/notifications.sh` sends a real
notification to the shell's server there. `gdbus` is in the bed's tools
(`tests/lock/tools.nix:89`); `notify-send` is not. Programs the shell already depends on:
`notify-send` (libnotify) and `gdbus` (glib; `nix/package.nix:39-41`, `install.sh:25-26`).

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
- **A toast comes back only when the sender asks** (§3.2: "announce"; the shell's own
  sender). Outside apps: a replacement never brings a toast back, as today.
- **Resident** notifications keep their entry after an action: the card runs the action
  and asks to be dismissed only when the notification is not resident (the toast still
  slides away — unless it stays, §3.4). A progress notification from the shell's sender is
  always resident, so "Cancel" or "Skip" on it does not make it vanish.
- **Toasts off / no toast screen** (the shell's "Do Not Disturb"): progress notifications
  go to the centre only, like any other; no toast stays and none comes back.
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
handle.update({ summary?, body?, progress?, actions?, state?, announce? })
                     state "done" | "failed" | "cancelled" ends the job: after it only
                     close() is taken. announce: true brings its toast back once (below)
handle.close()       takes it away (an end state stays in the centre until then, or until
                     the user dismisses it)
opts.toast           "brief" (default) | "whileRunning" — how long its toast shows (below)
opts.onDismissed     called once when the user closes it (not after close())
opts.actions         as today; on a progress notification they stay after a click
```

**How long the toast shows** (§3.4 makes the server follow it):

- `"brief"`: every show and update says `--expire-time=-1`: the user's "Show each toast
  for" time, then the toast goes; the entry stays in the centre with its moving bar.
- `"whileRunning"`: `--expire-time=0` while the state is starting or running — the toast
  stays on screen for the whole job, its bar moving, until the user takes it away ("×",
  a swipe) or the job ends; the update that ends the job says `-1`, so the end shows for
  the user's time and then the toast goes (the entry stays in the centre). Taken away by
  the user, the toast does not come back by itself (the job goes on; the entry is in the
  centre) — only an `announce` brings it back.
- **announce** (`update({ ..., announce: true })`, any mode): the update carries
  `x-qs-announce:<n>`, a number the handle raises at each announce; the server, seeing it
  change, shows the toast again — or, while it is on screen, starts its time again
  (`NotificationRules.announced(previous, hints)`, pure). With toasts off, no toast
  screen, or the centre open, nothing slides in (the rules of §3.1). A module uses it for
  a change of status the user should see (Taildrop: started, stalled, done, failed).

How it runs (only programs the shell already depends on):

- **Show:** `notify-send --print-id --wait --expire-time=<per mode> --hint=boolean:resident:true
  --hint=int:value:N --hint=string:x-qs-progress-state:running --hint=string:x-qs-progress-run:<run> …`.
  The first stdout line is the id; a later line is an action (`_dispatch` reads the line
  after the id). The process exits when the notification closes — that is how the handle
  learns it was dismissed, whoever the server is.
- **Update:** a new `notify-send --print-id --wait --replace-id=<id> …` with the whole
  current content (the spec replaces every field, so actions and the expire time are sent
  again); when it has started, the previous waiter is stopped and its exit ignored. One
  waiter per handle at any time; only the newest waiter's lines count (a click that both
  hear in the hand-over is dispatched once). The same run re-arms the actions after a
  click: libnotify's `notify-send --wait` ends after the first action, so after each action
  the handle sends its current content again with `--replace-id`.
- **Close:** `gdbus call --session --dest org.freedesktop.Notifications
  --object-path /org/freedesktop/Notifications --method
  org.freedesktop.Notifications.CloseNotification <id>`; the waiter then exits; no
  `onDismissed`.
- **Coalescing** (`NotificationRules.nextSend(handleState, change, now)`, pure): at most one
  `notify-send` starting per handle; while one starts, only the newest wanted content is
  kept. A progress-only change is sent at most once per `minUpdateMs` (1000) and only
  when the whole percent moved; a text, action, state or announce change goes at the next
  free moment (two announces coalesced are one); an end state always goes. Nothing is sent
  after `close()` or after the waiter reported a dismissal.
- **Late answers lose.** An update before the id is known waits for it (only the newest
  content is kept). An answer whose id is not the handle's means the old one was closed
  meanwhile and the server made a new one: the handle closes the new one at once and goes
  to "closed" (so a dismissed notification never comes back). A close() before the id is
  known closes it when the id arrives.
- **Orphans.** Every progress notification carries `x-qs-progress-run`, a token made once
  per Notifier instance. The server keeps notifications over a reload; at start
  (`Component.onCompleted`) `Notifications` dismisses any tracked notification with
  state "running" whose run token is not the current one (`NotificationRules.orphaned`)
  — its sender is gone, its bar would stand still for ever (and a "whileRunning" toast
  would stay for ever). After a full restart the server's list starts empty anyway.
- **Hints of the shell's own** (`x-qs-progress-state`, `x-qs-progress-run`,
  `x-qs-announce`, `resident` on progress) are set by Notifier after the caller's options
  are read; a module's `x-qs-…` hint keys are dropped (`moduleNotifyOptions` grows from the
  category to every key). On a progress notification `expireTime` is the handle's (from
  `toast`); a caller's own `expireTime` is ignored there.
- **Test mode:** nothing runs; `recorded` gets one entry per show, update and close with
  the handle's number (`{ kind: "show" | "update" | "close", handle, summary, body,
  progress, state, toast, expireTime, announce, … }`), and the handle behaves as if the
  server answered at once with a made-up id. `ModuleTestKit` gains a way to dismiss a
  recorded handle and to press one of its actions, so a module's suite can drive both.

### 3.3 The API (1.33)

`module.notify(summary, options)` and `Api.notify` return the handle when
`options.progress` is a number (0–100, or -1 for a run of unknown length), else `null` as
today. The handle's shape is §3.2's, `options.toast` and `update({ announce })` included.
When the module is turned off, its open handles are closed (`ModuleHandle` keeps them;
closed in its teardown, the same place its runs end).

```
const job = module.notify("Sending photo.jpg", {
    body: "to laptop", format: "plain", progress: 0, toast: "whileRunning",
    actions: [{ id: "cancel", label: "Cancel", onTriggered: () => client.cancelSend() }],
    onDismissed: () => job = null
});
job.update({ progress: 40 });
job.update({ state: "done", summary: "Sent photo.jpg", body: "to laptop", actions: [], announce: true });
```

The reference also states, for every `notify` (1.33): `options.expireTime` (milliseconds;
0 stays until closed; absent: the user's time) is now followed by the shell's toasts
(§3.4) unless the user turned that off.

**Why a handle and not `id` + `replaces`:** the id comes back from `notify-send` some
milliseconds later, so an `id` API would make every module wait for it and race (the late
answers rule); coalescing, the one-waiter rule, re-arming actions after a click and "never
bring back a dismissed one" would each be written again in every module. The handle keeps
all of it in one tested place, and it serves any module (a download, a backup, a sync), not
Taildrop only. A door stays open: a plain notification could later get a handle too
(updating a "3 files received" count) without changing this shape.

Versioning: a minor (1.33): `api/Api.qml` header and reference, `ModuleRules.apiVersion`,
a `### Module API` line in `CHANGELOG.md`, as the last edit of slice N3. The server-side
bar and the display time are shell features (CHANGELOG lines under Unreleased, no API
number).

Docs: `docs/FEATURES.md` "Notifications" (the bar, resident actions, the display time,
toasts that stay) and the external tools table (`notify-send`, `gdbus` now also for
notifications); `docs/ARCHITECTURE.md` "Modules" (notify returns a handle with progress;
`toast` and `announce`).

### 3.4 Toasts follow the sender's display time (any sender)

Decided by the owner (2026-11-19): the shell respects the expire timeout a sender asks
for; "Show each toast for" becomes the default for senders that leave it to the server.

A pure rule, in `singletons/ToastRules.qml` (suite `tests/ToastRulesTest.qml`):

```
ToastRules.duration({ expireTimeout, critical, defaultSeconds, followSender }) → ms, or 0 (stays)
  critical                         → 0 (as today)
  followSender false               → defaultSeconds × 1000 (today's behaviour)
  expireTimeout -1 (or < 0, absent, NaN) → defaultSeconds × 1000
  expireTimeout 0                  → 0: stays until the user takes it away, or the sender
                                     closes or replaces it with another time
  expireTimeout > 0                → that time, at least 1 s (a shorter one is not seen)
```

- **The toast, not the entry.** The time is how long the *toast* shows. The entry stays
  in the centre until dismissed, as every notification does today; the shell does not call
  `expire()` (that would remove the entry, which the shell's list never does by itself).
- **A toast that stays is always dismissable:** its "×" and a swipe take the toast away
  (the entry stays), as a critical toast's do today. Hovering pauses a counting toast as
  today. A toast that stays shows no timer bar.
- **Replacement.** When a shown notification's `expireTimeout` changes (a sender's
  update), its toast takes the new time: to 0 it stops counting; from 0 (or to another
  positive time) it counts the new time from full. `expireTimeoutChanged` drives it; the
  rule is `ToastRules.duration` again.
- **Who counts.** Only toasts with the user's default time take part in "the oldest counts
  down, the others wait" (`countingToast`), as today, so a column of ordinary toasts still
  leaves one by one. A toast with a sender's own time counts by itself, at once, and holds
  no other up; a toast that stays never counts (critical's rule, generalised:
  `persistentToasts` becomes "toasts with a time of their own"). `isPersistent` splits in
  two: `isCritical` (the red border) and the toast's duration (`ToastRules.duration`).
- **Slots** (Q5, answered): a toast that stays does not hold the layout's slots; toasts that
  stay stack above them, at most `notifications.maxStayingToasts` (default 3); more wait in
  the queue, counted. `ToastRules.slots(layout, columnSize, staying, maxStaying)`.
- **A setting, to keep the old way:** `notifications.followSenderTime` (bool, default
  true; label "Apps choose how long", hint "Off: every toast shows for the time below.";
  shown in Settings → Notifications above "Show each toast for", available while toasts
  are on). "Show each toast for" gets the hint "When the app does not say." A new key with
  a default: no migration. Per profile, like the other toast settings.
- **What changes for apps today.** Most send -1 (`notify-send` without `-t` does): no
  change for them. Apps that ask for a time get it: `notify-send -t 0` now stays until
  taken away; an app asking for 30 s shows 30 s. The shell's own notifications send
  nothing (-1) except where a caller passes `expireTime` (none in the tree today).

**Versioning.** This changes how long some toasts show, for every app. `CLAUDE.md` makes a
change to behaviour people rely on a major. Recommended: **a minor** (the next 2.x.0):
the owner asked for it, the spec says a server should follow the sender, apps that leave
it to the server (most) see no change, and one switch ("Apps choose how long", off) gives
back exactly today's behaviour. The CHANGELOG line says so plainly: "Toasts now show as
long as the app asks (an app asking for 0 stays until closed); Settings → Notifications →
Apps choose how long, off, keeps every toast at your time." *(The plan's choice; the owner
may call it a major.)*

### 3.5 Not in this plan

- A plain notification's handle (above, a door).
- Grouping several jobs into one notification.
- A server-side rate limit for outside apps.
- A replacement from an outside app bringing its toast back (outside apps cannot announce;
  the spec leaves it to the server, and today's "never" stays).

## 4. Open questions for the owner

**Answered (2026-11-19):**

- *Q1, whether a long job's end brings its toast back* — replaced by a broader decision:
  the shell follows the sender's display time (§3.4), the user's time is the default; a
  sender's handle chooses "brief" or "whileRunning" and may announce a change of status,
  which brings its toast back (§3.2). The end of a job is one such change: the module
  decides whether to announce it. Slice N4 ("a job's end brings its toast back") becomes
  "a sender's announce brings its toast back".

(Decided by the plan, the owner may overrule: dismissing a running progress notification
— in the centre, not a toast's "×" — takes it away for good: the job goes on, the module
is told (`onDismissed`) and sends no more updates. Outside apps do as they do: by the spec
a sender's next update may bring it back.)

- *Q5, a toast that stays in the "One at a time" layout* — (a), with the number
  configurable: a toast that stays does not take the layout's slots (those are for toasts
  that count down; "One at a time": 1, "A column": its size); toasts that stay stack above
  them, at most `notifications.maxStayingToasts` (int, 1–5, default 3, label "Toasts that
  stay, at most", per profile like the other toast settings; a new key, no migration);
  more go on waiting in the queue, counted. Critical toasts follow the same rule (today
  they block).

## 5. Slices

Every slice: one change with its test; the named suites while iterating, `tests/run-all.sh`
before the commit, on the Arch machine; the lock-bed scenarios also on the NixOS machine
(over SSH, `nix` tools) before the merge. Reviewer: a second agent with the diff only.

| # | Slice | Changes | Tests | Reviewer looks at |
|---|---|---|---|---|
| 1 | **The card shows a sender's progress** (N1) | `singletons/NotificationRules.qml` (`progress`), `NotificationCard.qml` (the bar; an action on a resident notification does not dismiss its entry), `panels/NotificationPanel.qml` if the dismissal sits there, the lock/screensaver card under its detail rule; `docs/FEATURES.md`; CHANGELOG (shell feature) | `NotificationRulesTest` (new: absent, 0, 40, 100, 150, -5, "40", NaN, the four states); a card built in `NotifierTest` with a stand-in notification object (`hints: { value: 40 }` → a bar at 0.4; no hint → none; resident + action → no dismiss request); `LockViewTest` cases; the lock bed: new `tests/lock/tests/notification-progress.sh` — `gdbus` Notify with `value` 10, then `replaces_id` with 60, then the shell's state over the `shelltest` IPC (a new `notificationState()` in `Bar.qml`: id, summary, progress) shows one entry at 60. **First step of the slice**: this scenario proves Quickshell 0.3.2 passes the `value` hint into `hints` and updates it on replacement; if it does not, stop and report (an upstream draft under `notes/upstream/`) | the rule's edges; that nothing else (bell, toast, timestamps) changed for replaced notifications; theme tokens only |
| 2 | **Toasts follow the sender's display time** (N5) | `ToastRules` (`duration`; `slots` with the staying limit), `Notifications.qml` (`isPersistent` split into `isCritical` and the duration; "toasts with a time of their own" instead of `persistentToasts`), `NotificationHudItem.qml` (the countdown's duration from the rule; a change of `expireTimeout` while shown), `Hud.qml` (slots per Q5), `NotificationCard.qml` (red border from `isCritical`), `SettingsSchema` (`notifications.followSenderTime`, `notifications.maxStayingToasts`, the hint on `toastDuration`), `panels/settings/NotificationsSettings.qml`; `docs/FEATURES.md` "Notifications"; CHANGELOG line (§3.4's words) and the version note | `ToastRulesTest`: `duration` (-1, absent, NaN, 0, 500 → 1000, 30000, critical, setting off with each) and `slots` (each layout with 0–6 staying, limits 1, 3, 5); `NotifierTest` toasts through `hudQueue` with stand-in notification objects: 0 stays and shows no timer bar, its "×" takes the toast and leaves the entry; a positive time counts by itself while an ordinary toast waits its turn; a change 0 → -1 while shown starts counting; the setting off → today's behaviour. The lock bed, `notifications.sh` grown: `gdbus` Notify with expire 0 → the toast still up after the user's time (waited on the shell's state over `shelltest`, which gains the toast's duration), expire 2000 → gone after it, -1 → the user's time. **First step of the slice**: the scenario reads what Quickshell 0.3.2 puts in `expireTimeout` for -1, 0 and 2000 (milliseconds or seconds: the qmltypes give only `double`); the rule takes the unit found | every path to a toast takes its time from the rule; a toast that stays can always be taken away; nothing removes an entry from the centre by time; toasts off / no screen unchanged |
| 3 | **Notifier's progress handle** (N2) | `singletons/io/NotificationHandle.qml` (new), `Notifier.qml` (`send` with `progress` returns it; `toast` → the expire time per state; `announce` → `x-qs-announce`; `command` takes print-id, replace-id, the shell's hints; `_dispatch` after an id line; test-mode records), `NotificationRules` (`nextSend`, `orphaned`, the expire time for a mode and state), `Notifications.qml` (orphans at start); `tests/lock/tools.nix` (libnotify), the Arch list in `docs/ARCHITECTURE.md` "Where the test tools come from" and `tests/system/arch/test-tools.sh` | `NotifierTest`: argv for show, update, a value, the hints, the expire time per mode and state (whileRunning: 0 running, -1 at the end; brief: -1), nothing after `--` but text; `NotificationRulesTest`: `nextSend` (coalesced progress, text at once, end state always, announces coalesced, nothing after close, an update before the id, a foreign id → close), `orphaned`; test mode records show/update/close. The real path, against stand-ins only: a lock-bed scenario on the private bus (real `notify-send` and `gdbus`, the shell's own server), driven by a test function on the bed's `locktest` IPC (`tests/lock/seams/TestSeams.qml`): show at 0 with whileRunning → the toast stays past the user's time; ten updates in a burst → at most a few `notify-send` runs and the last value shown; done → the toast counts down and goes, the entry stays; an action pressed (through `shelltest`) after an update reaches its callback and the entry stays; dismissed → `onDismissed`, a later update sends nothing; close() → gone, no `onDismissed`; a reload → the orphan dismissed | the one-waiter rule (no double callbacks, no stray processes: `pgrep` after the scenario); late answers; that plain `send` is byte-for-byte as before |
| 4 | **A sender's announce brings its toast back** (N4) | `NotificationRules.announced`, `Notifications.qml` (on `hintsChanged`: a new `x-qs-announce` re-queues the object once if its toast is not shown, or asks the shown toast to start its time again), `NotificationHudItem.qml` (that restart) | `NotificationRulesTest` (`announced`: first value, same value, raised, absent); `NotifierTest` through `hudQueue`: announce with the toast gone → it comes back once; on screen → its time starts again, no second toast; toasts off, no toast screen, the centre open → nothing; an outside app's plain replacement → nothing (as today); the lock bed (N2's scenario grown): an announced update brings the toast back | once only; the toast rules (off, screen, centre) respected; a module cannot set the hint itself (`x-qs-` keys from modules are dropped) |
| 5 | **`notify` returns the handle** (N3, API 1.33) | `api/ModuleHandle.qml` and `Api.qml` (`notify` returns it; `toast`, `announce`; `expireTime` followed — the reference text), `ModuleRules.moduleNotifyOptions` (drops every `x-qs-` hint key; checks `progress` and `toast`), `ModuleHandle` closes its handles on teardown, `tests/ModuleTestKit.qml` (recorded handles, dismiss, press an action), the fixture module `tests/fixtures/modules/good` (a progress notification on its IPC); `docs/ARCHITECTURE.md` "Modules"; the version lines | `ModuleRulesTest` (options: a bad `toast` → "brief"), `GoodApiTest` (a handle in test mode: show, update, announce, done, close, dismissed through the kit, closed when the module is turned off; `toast` and `announce` in the records); the lock bed `modules.sh` (or a new scenario) — the fixture module's progress notification on the private bus, the module turned off → its notification gone | the API text against the code; agnostic shape; the version lines together |

Order: N1 → N5 → N2 → N4 → N3 (table rows 1–5). N1 and N5 are useful alone (outside
apps); N5 does not need N1 and may go first. N3 is last so API 1.33 names the whole
handle at once. Taildrop's notification slice needs N3 (manifest `api` 1.33).

## 6. Verified, assumed, hard

**Verified in the code:** everything in §2 with its line; Quickshell 0.3.2's qmltypes list
`Notification.hints` (with `hintsChanged`), `resident`, `closed(reason)`, `expireTimeout`
(a `double`, `expireTimeoutChanged`), `expire()`, and the server's `extraHints`;
`notify-send` (libnotify 0.8.8) has `--print-id`, `--replace-id`, `--wait`, typed
`--hint`, `--expire-time`.

**Assumed, checked in the slice named:**
- Quickshell puts every client hint into `hints` (not only those named in `extraHints`) and
  replaces `hints` on a `replaces_id` call (N1, first step).
- Quickshell keeps a replaced notification's object and emits no new `notification` signal
  (the code at `Notifications.qml:99-102` relies on it already; N1's scenario shows it).
- The unit of `expireTimeout` (the spec's milliseconds, or seconds) and how -1 arrives; and
  that a replacement updates it with `expireTimeoutChanged` (N5, first step).
- `notify-send --print-id --wait` prints the id before it waits, and with `--replace-id` its
  `--wait` follows that id's actions and closing (N2's scenario).
- Stopping a `notify-send --wait` closes nothing on the server (N2).

**Hard:** the one-waiter hand-over (start the new waiter, then stop the old, ignore its
exit) is where double callbacks or a lost click could hide; N2's review looks there. In
N5, the toast's countdown is shared state (`countingToast`) across slots and screens: a
toast whose time changes while shown, or leaves while counting, must not leave the next
one waiting for ever (the `Component.onDestruction` case of today, again).
