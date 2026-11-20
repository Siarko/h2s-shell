# The notification flow: an analysis

First step of the redesign the owner asked for (2026-11-20, tracker "Next, after the open
questions: an analysis of the whole notification flow"): what kinds of notifications there
are, what can be on one, where and how the shell shows them, and what is already known to be
wrong. A mockup and ideas come later; nothing here is a decision. References are to the core
(this tree) unless they name the Tailscale module (`tailscale/…` =
`~/Projects/h2s-shell-tailscale/module/…`). Line numbers as of `cece99d`.

## 0. The pieces in one paragraph

The shell *is* the notification server (`singletons/Notifications.qml:33-139`, Quickshell's
`NotificationServer`). Every notification except the shell's own "pill" messages is tracked;
the tracked list **is** the notification centre — there is no separate history
(`panels/NotificationPanel.qml:81`) — and the screensaver and lock screen list the same model
(`screensaver/NotificationList.qml:21`). A new one is also queued as a toast (`hudQueue`,
`Notifications.qml:102-103`), shown by up to 15 slots in the HUD (`Hud.qml:153-181`,
`hud/NotificationHudItem.qml`). One card component draws a notification in both the toast and
the centre (`components/NotificationCard.qml`). The outbound side is `singletons/Notifier.qml`
(the shell's and modules' own notifications): plain ones through `notify-send`, progress ones
through `gdbus … Notify` with a handle (`singletons/io/NotificationHandle.qml`). Decisions are
in `NotificationRules.qml` (progress, announce, handle protocol) and `ToastRules.qml` (screen,
timing, room, order).

## 1. Kinds of notifications

### 1.1 By source

| Source | Path in | Notes |
|---|---|---|
| Outside apps (D-Bus) | `NotificationServer.onNotification` (`Notifications.qml:46`) | tracked, timestamped, codes extracted, queued as toast |
| Shell, plain (`Notifier.send`) | one `notify-send` per call (`Notifier.qml:395-424`, argv `140-196`) | comes back in through the shell's own server like an outside app; app name "H2S Shell"; ~30 call sites (Authentication, PrivilegedAction/Runs, network, Stt, Modules, settings) |
| Shell, "pill" (`category: "x-qs-shell"`) | caught first in `onNotification` (`Notifications.qml:47-55`) | **never tracked**: only the summary is copied into `shellQueue`; a bottom-centre pill for 2.5 s (`hud/ShellNotificationHudItem.qml:13-122`); ~23 uses ("Copied…", "Authenticated") |
| Shell, progress handle (`Notifier.send` with `progress`) | `gdbus call … Notify` (`Notifier.qml:261-296`), replaced in place by id | resident, `value` hint, `x-qs-progress-state/-run/-handle`, `x-qs-announce`; clicks and dismissal learned in-process (`Notifications.qml:147-172`) |
| Modules, plain | `module.notify` / `Api.notify` → `ModuleRules.moduleNotifyOptions` → `Notifier.send` (`api/ModuleHandle.qml:310-324`, `api/Api.qml:1162-1176`, `singletons/ModuleRules.qml:1745`) | category and hints starting `x-qs-` dropped (a module never looks like the shell) |
| Modules, progress | `module.notify({progress})` only; `Api.notify` refuses it (`Api.qml:1165-1171`) | never critical (`ModuleRules.qml:1766-1769`); app name forced to the module's; owned and closed when the module goes (`Notifier.qml:336-372`, `ModuleHandle.qml:175`) |

What the Tailscale module sends:
- **Taildrop arrival** — plain, per batch: "File received" / "N files received", body the
  names one per line, `format: "plain"`, actions "Save" / "Save in…" when it can save and
  auto-save is off (`tailscale/TaildropClient.qml:914-923`, offers
  `tailscale/TaildropTransferRules.qml:72-74`).
- **Re-enable** — turning Taildrop on again announces what arrived while off once, through the
  same arrival notification with Save (tracker "Taildrop off", M5; `TaildropClient.qml:901-911`).
- **Transfer progress** — one handle per transfer that runs longer than 3 s (`notifyAfterMs`,
  `TaildropTransferRules.qml:1075`): "Sending 3 files to laptop" / "Saving 2 files", body the
  current file "name · 2 of 3", value = byte share or -1; a stalled file: body "x: No progress
  for N min" and a **Skip** action (`TaildropTransferRules.qml:1123-1186`); end texts "Sent to
  laptop" / "Saved 2 files" / "1 of 3 not sent · reason"; cancelled keeps its running title.
  Announce (toast back once) on first stall, done, failed, or stopped by something other than
  the user. The module setting `taildropNotifications`: "On screen until done" (`whileRunning`)
  or "Briefly, then in the notification list" (`brief`) (`TaildropTransferRules.qml:1078-1091`).
  Dismissing it: the transfer goes on, nothing more sent (`TaildropClient.qml:846-854`).
- **Failures** — "<what> failed" with the reason as body, via the provider's `failed` signal
  (`tailscale/TailscaleClient.qml:122-124`, `components/VpnProvider.qml:124-126`), e.g. the exit
  node per network (`tailscale/NetworkExitClient.qml:143-146`); privileged runs that fail
  (`notifyFailures`, `api/PrivilegedAction.qml:71-187`).

### 1.2 By behaviour

- **Plain** — summary, body, maybe icon/image. Toast with the user's time, entry stays.
- **With actions** — buttons; `default` = clicking the card; an action closes a non-resident
  notification (Quickshell's `invoke`), the toast slides away (`NotificationCard.qml:66-81`).
  The shell's own plain ones with actions run `notify-send --wait`, one process each
  (`Notifier.qml:411-423`); notify-send closes the notification itself after a click
  (tracker, N2 note), and a reload of the shell ends the waiting process, so the callbacks die
  with it (follows from the Process being the shell's).
- **Resident** — stays after any action, default and inline reply included (decision
  2026-11-20; `NotificationRules.qml:50-52`); the toast still leaves (`NotificationHudItem.qml:285`).
- **Urgency** — only *critical* is read (`Notifications.qml:240-242`): red outline everywhere
  (`NotificationCard.qml:88-90`) and its toast stays (`ToastRules.qml:57-58`). *Low* and
  *normal* are treated alike.
- **Images / icons** — app icon in the header; image as square thumbnail or wide preview by
  aspect (`NotificationCard.qml:96-201`); images inside the body are not loaded, shown as a link
  row (`Notifications.qml:39`).
- **Inline reply** — a field and Send on the card (`components/NotificationReply.qml`); the
  HUD window takes the keyboard only on demand (`Hud.qml:21-35`). The shell's own sender cannot
  ask for one (notify-send has no option, `Notifier.qml:28`).
- **Replaced** (same id) — changes in place; summary/body change rings the bell once between
  two openings (`Notifications.qml:109-113`, `388-399`); never brings a toast back, except the
  shell's own sender's announce (`NotificationRules.qml:202-221`, `Notifications.qml:327-351`).
  A value-only change only moves the bar.
- **Expire timeout** — read only for the toast (`ToastRules.qml:55-67`): -1 → the user's time
  ("default", counts one at a time); 0 → stays; positive → that time, ≥1 s ("own", counts by
  itself). Off "Apps choose how long" → all get the user's time. **Entries never expire**: the
  shell never calls `expire()`; an entry leaves only when dismissed or closed by its sender.
- **Transient** hint — sent by Notifier (`Notifier.qml:158-159`, `277-278`) but **not read** by
  the server side: a transient notification stays in the centre like any other.
- **Category** — only `x-qs-shell` is read; `im.received`, `transfer` etc. change nothing.
- **Codes (OTP)** — regexes (`notifications.codePatterns`, default `\d{4,8}`) run over summary +
  plain body on arrival (`Notifications.qml:76-99`); chips to copy on the card
  (`NotificationCard.qml:634-639`). Not re-run on replacement; the default matches years and
  any 4–8 digit number.
- **Orphans** — a running progress notification from an earlier run of the Notifier (a reload)
  is dismissed (`NotificationRules.qml:181-186`, `Notifications.qml:59-62`, `178-183`).
- **Do not disturb** — none as such. What comes closest: "Show toasts" off, the fullscreen rule
  "Don't show", and the centre being open (no toasts while it is). **Sounds** — none anywhere.

## 2. What can be on a notification, and where it shows

Server capabilities (`Notifications.qml:36-44`): body markup and hyperlinks yes, body images
no, action icons yes (advertised; the card draws labels only, `NotificationCard.qml:597-605`),
image yes, actions yes, inline reply yes.

| Field | Toast | Centre | Screensaver / lock |
|---|---|---|---|
| app name | header, bold small | same | first line (alone at "app") |
| app icon | 16 px in header | same | — |
| summary | plain, word-wrapped, whole | same | one line, elided ("title"/"full") |
| body | sanitized rich text (`NotificationMarkup.richText`), links, line breaks kept; **cut at 6 lines** with a fade (`NotificationHudItem.qml:276`) | whole | plain text, **2 lines** ("full") |
| image | thumbnail 44 px or preview ≤120 px | preview ≤160 px | — |
| actions | accent buttons, labels only | same | — |
| default action | click on header/text/image | same | — |
| inline reply | field + Send | same | — |
| progress (`value`, `x-qs-progress-state`) | bar under the text, wave while growing | same | bar ("full" only) |
| critical | red outline, stays | red outline | — (no mark) |
| timestamp | — | hh:mm:ss in header | — |
| codes | chips | chips | — |
| transient, category, resident, low urgency, sound-file, desktop-entry | not shown | not shown | not shown |

Links: http/https/mailto open; any other scheme asks "Not a web or mail link — open it?" with
Open / Copy / Cancel (`NotificationCard.qml:234-239`, `515-574`). Selected text gets a copy
button (`653-684`). The shell's pill shows the summary only, one line (`ShellNotificationHudItem.qml:106-112`).

## 3. Where notifications show, and what each place does

### 3.1 Toasts (top right of one screen)

- **Screen**: `ToastRules.screenFor` (`ToastRules.qml:24-45`): focused screen or a chosen one;
  with a fullscreen window there: show / don't show / another screen. "Nowhere" → panel only,
  and waiting toasts are dropped (`Notifications.qml:22-27`).
- **Layout**: "One at a time, the rest counted" (1 counting slot) or "A column" (2–10). Toasts
  that **stay** (critical, expire 0, a job's `whileRunning`) take no counting slot: they stack
  **above**, at most `maxStayingToasts` (1–5) (`ToastRules.qml:81-90`). Order top to bottom:
  staying newest first, then counting newest first (`ToastRules.qml:109-113`); the oldest
  counting one, at the bottom, is the one whose time runs (`Notifications.qml:225`).
- **One queue** for both kinds (`hudQueue`): a free slot takes the oldest that fits
  (`ToastRules.qml:97-104`), so a staying toast can overtake counting ones and vice versa.
- **Badge**: the waiting count, a tab at the screen edge beside the top toast; a click opens the
  centre (`Hud.qml:210-243`); the toasts move left to make room (`NotificationHudItem.qml:54-55`).
- **Countdown**: a 3 px accent bar pinned to the card's bottom edge shrinks
  (`NotificationCard.qml:643-651`, `Theme.notifTimerHeight`); paused while hovered, replying or
  swiping (`NotificationHudItem.qml:43-49`). "Default" toasts count one at a time; "own" at once;
  staying ones show no bar (`287`).
- **Clicks**: card → default action (then the toast leaves; the entry leaves unless resident);
  button → action (same); "×" or swipe (touch only) → **the toast only** leaves, the entry stays
  (`NotificationHudItem.qml:283`); reply sent → as an action.
- **Lifetime**: until its time runs out, "×"/swipe, an action, its sender closes it, the centre
  is opened (`setHudPanelOpen` clears the queue and slides out **every** toast, staying job
  toasts too: `Notifications.qml:362-368`, `NotificationHudItem.qml:209-215`), toasts switched
  off, or the toast screen becoming "nowhere".
- **The shell's pill**: separate queue, bottom centre, 2.5 s each, click dismisses
  (`ShellNotificationHudItem.qml`). Follows the toast screen but ignores "Show toasts" and the
  open centre; never in the centre or on the lock screen.

### 3.2 The notification centre (bar popup)

- A `ListView` over the tracked list (`NotificationPanel.qml:75-172`): server order (arrival;
  a replaced one keeps its place), **no grouping** by app or kind, no sort, no sections.
- Card as in the toast but body whole, timestamp "hh:mm:ss" (absolute, no date; set on arrival,
  so after a reload the notifications handed over again get the reload's time,
  `Notifications.qml:68-74`), a "dismiss" word instead of "×".
- "dismiss" or swipe → entry gone (`tracked = false`, `129-131`); "Clear all" dismisses every
  entry, resident and running progress ones included (`52-69`, `104-106`), then "All caught up"
  and the popup closes (`214-260`). Modules may put elements under the header
  (`popup.notifications`, `23-28`).
- Opening it marks all seen and empties the toast queue.

### 3.3 The bar's bell (`widgets/NotificationsWidget.qml`)

Accent when the centre holds any notification, badge with the **total** count ("9+")
(`57-82`), rings on `arrived` (a new one, or a seen one replaced) per preset: off / once /
until opened (uses `unreadCount`) / until cleared (`16-38`); no ring with reduced motion. No
separate unread count is shown; no per-entry unread mark in the centre.

### 3.4 Screensaver and lock screen

Same model, read-only cards (`screensaver/NotificationList.qml`, `NotificationPreview.qml`):
no actions, links, images, codes, timestamps, critical mark; `interactive: false` — what does
not fit is cut with no "N more". Detail: "full" (app, title, 2-line body, bar), "title", "app"
(`NotificationPreview.qml:5-10`). Screensaver default "full", top right
(`ScreensaverSurface.qml:85-96`); lock screen default "app", hidden while the password prompt
is up (`LockSurface.qml:183-198`).

### 3.5 Sound

None.

## 4. Settings

Notifications (`singletons/SettingsSchema.qml:250-288`, page `panels/settings/NotificationsSettings.qml`):

| Key | Label | Default |
|---|---|---|
| `notifications.toasts` | Show toasts | true |
| `notifications.followSenderTime` | Apps choose how long | true |
| `notifications.toastDuration` | Show each toast for | 5 s (1–120) |
| `notifications.toastLayout` | Several at once | `queue` (one at a time) / `column` |
| `notifications.toastColumnSize` | Toasts in the column | 3 (2–10) |
| `notifications.maxStayingToasts` | Toasts that stay, at most | 3 (1–5) |
| `notifications.toastScreen` | Show toasts on | "" (focused) |
| `notifications.toastFullscreen` | Fullscreen window there | `show` / `hide` / `elsewhere` |
| `notifications.toastFullscreenScreen` | Which screen | "" (any free) |
| `notifications.codePatterns` | Code patterns | `["\\d{4,8}"]` (`:190`) |

Lock screen (`SettingsSchema.qml:150-185`): `lockscreen.notificationsOnScreensaver` (true),
`lockscreen.screensaverNotificationDetail` (`full`), `lockscreen.notificationsOnLock` (true),
`lockscreen.lockNotificationDetail` (`app`). Bell preset (`singletons/WidgetPresets.qml:29`):
`badge` true, `animation` `once`. Module: `mod.tailscale.taildropNotifications` (`stay`).

## 5. Known problems

From the tracker:
- The analysis itself: probably **two queues** — toasts that count down vs toasts that stay or
  carry a job; whether a progress notification's button closes it (Cancel, Skip) or replaces it
  ("Send now" → a new one with progress only), and whether the `gdbus` path is then still needed.
- Staying toasts: they share the one queue and the one badge with counting toasts; opening the
  centre throws a staying job toast away; toasts off → `whileRunning` means nothing.
- Open points (tracker "Notifications with a progress bar"): a `value` below 0 gives an
  unknown-length bar for any sender, not only the shell's; no test drives a toast through
  `actionInvoked`; a slot taking its next toast in `slideOut.onStopped` animates `x` twice
  (cosmetic); `hintsChanged` before `expireTimeoutChanged` can re-queue an announced toast with
  its old timing (a column briefly one too many); the run token is visible in `/proc/*/cmdline`;
  `shelltest.notificationState()` returns summaries to any user process, also while locked;
  `Api.module(id)` lets a module notify under another's name.

From the mockup review:
- **Doubled bar on a finished/failed toast.** A "brief" job toast (or a `whileRunning` one
  after its end, which switches to the user's time, `NotificationRules.qml:60-62`) shows the
  progress bar (4 px, success/error tone, full at the end; `NotificationCard.qml:486-494`,
  `ThemeBuiltin.qml:117`) under the text and the 3 px accent countdown bar pinned to the card's
  bottom edge (`643-651`). With no actions below, only the padding separates them: two lines
  of similar weight read as one doubled bar, and the countdown is mistaken for the job.
- **Screensaver bodies cut at 2 lines without "…"** (`NotificationPreview.qml:64-77`:
  `maximumLineCount: 2`, `ElideRight`). The body comes from `NotificationMarkup.plainText`,
  which keeps line breaks (`NotificationMarkup.qml:270-283`); probable cause: Qt draws "…" only
  when the last shown line itself overflows, so a cut at a line break shows none. Not verified.
- **Low contrast of action buttons**: `color: Theme.accent` with text `Theme.textPrimary`
  (`NotificationCard.qml:595`, `604`) — light text on a bright accent; the theme has
  `Theme.onAccent` for this (used by the bell's badge, `NotificationsWidget.qml:80`). Buttons
  also bypass `SmallButton` / `ThemeRules.buttonLook` (CLAUDE.md conventions) and `PointerArea`.
- **Click semantics of a progress notification**: its actions keep the entry (resident) while
  the toast leaves; Taildrop offers only "Skip" for a stalled file — no Cancel, and "Send now"
  is deliberately never offered there (`TaildropTransferRules.qml:1108-1111`). A Skip leaves
  the notification running with new text; whether Cancel/Skip should close it and "Send now"
  replace it is open. "Clear all" or "dismiss" ends the notification, not the job — nothing on
  the card says so.

Seen while reading (not yet in the tracker):
- The pill is a third presentation with its own rules (summary only, ignores "Show toasts").
- `transient` and `low` urgency are sent but ignored; entries never expire, so the centre fills
  with one-off messages ("X failed", "Copied" are pills, but "Not authenticated" is a full entry).
- Action icons are advertised but not drawn; the toast's "×" and the centre's "dismiss" differ
  in meaning (toast only vs entry) and in look.
- Plain shell notifications with actions lose their callbacks on a reload (waiting notify-send).
- Codes are extracted once, on arrival; a replacement carrying a code shows no chip.

## 6. Questions the redesign has to answer

1. **Queues**: one queue or two (counting-down vs staying/job)? Each with its own badge, its
   own place on screen (e.g. jobs in a fixed strip), its own limit? What overtakes what?
2. **Jobs as a kind**: is a progress notification a toast at all, or a live row (in the
   centre, a bar widget, a strip) that toasts only at start/stall/end? What does "stays while
   running" mean when the centre opens, toasts are off, or a fullscreen window is up?
3. **Progress actions**: does Cancel/Skip close, update or replace the notification? Does
   "Send now" belong on a notification? Is the `gdbus` path still needed then?
4. **End of a job**: one bar or two (progress vs countdown) — how does a finished toast show its
   remaining time without looking like the job's bar? Does done/failed replace the bar with a
   result line?
5. **Dismiss meanings**: the toast's "×" (toast only) vs the centre's dismiss (entry) vs "Clear
   all" (everything, running jobs too) — what should each do, look like, and say about the job?
6. **The pill**: keep a third presentation for the shell's short confirmations? Should it obey
   "Show toasts" and a do-not-disturb?
7. **Do not disturb / sounds**: a real DND (schedule, per app, critical passes through)? Any
   sound at all?
8. **Centre**: grouping (by app, by kind: jobs / messages / system), order (newest first?),
   relative times and dates, unread marks, expiry of transient and low-urgency entries, a
   limit on history?
9. **Urgency**: what do low and critical change besides staying and the red outline?
10. **Lock and screensaver**: "N more" when cut, the critical mark, an ellipsis on cut bodies,
    codes never shown there (keep)?
11. **Looks**: action buttons through the shared button kinds (contrast), action icons, the
    toast's body cut (6 lines) vs the centre's whole body.

## 7. The owner's direction (2026-11-20)

- **Three toast queues, top to bottom:** critical (red outline), staying (expire 0 from apps and
  jobs set to stay while running), ordinary counting-down toasts. Each queue has its own visible
  limit — critical 1, staying 1 by default, ordinary as today (1 in "One at a time", the column's
  size in "A column") — and its own badge counting what waits; the critical queue's badge has the
  critical outline.
- **Movable toasts (an option):** a staying or critical toast can be grabbed by its title line and
  dropped anywhere on its screen; it then frees its place in its queue. No limit on how many are
  moved out; each closes with its "×", a finished job counts down and goes as usual.
- **Opening the centre** hides only the ordinary toasts; critical, staying and moved-out ones stay.
- **Lock screen and screensaver do not pause** countdowns or queues (notifications would be stale
  after unlocking).
- **"×" on a toast dismisses** the notification (its entry leaves the centre too; a job goes on).
- **Confirmed on the mockup** (`~/src/h2s-mockups/notification-queues-planned/`): new critical and
  staying toasts show while the centre is open; "Show toasts" off drops what waits in all three
  queues; a moved-out toast has an accent outline and a grip; a job that ends while waiting in
  the staying queue shows its result in the ordinary queue.
- **Resident notifications stay** (staying queue) by default; a Notifications setting "Resident
  notification hide" (off by default) makes them count down like ordinary ones, with an info icon
  and a tooltip explaining what "resident" means.

## 8. Plan

Implements §7 as confirmed on the mockup. The queue logic is the mockup's `PlannedRules.js`
(`~/src/h2s-mockups/notification-queues-planned/`), ported into `ToastRules.qml`. The pill,
the centre's list, the bell, the lock screen's cards and the progress actions (§6.2–6.10)
stay as they are.

### 8.1 The views

```
 bar ────────────────────────────────────────────────┐
                              ┌──────────────────┐┌──┐
  critical (red outline)      │ ! Battery 3 %    ││+1│ ← red-outlined badge, red "+1"
                              └──────────────────┘└──┘
                              ┌──────────────────┐┌──┐
  staying                     │ Sending 3 files  ││+2│ ← beside the queue's lowest toast
                              │ ▓▓▓▓▓▓░░░░        │└──┘
                              └──────────────────┘
                              ┌──────────────────┐
  ordinary (1, or the column) │ Mail from Ann     │      no badge: nothing waits there
                              │▔▔▔▔▔▔▔▔▔ countdown│
                              └──────────────────┘
     ┏━━━━━━━━━━━━━━━━━━━┓                         a queue that waits with nothing shown:
     ┃  ═══ (grip)    ×  ┃  moved out: accent       its badge below the stack (36 px)
     ┃ Backup running    ┃  outline, grip; its
     ┃ ▓▓▓▓░░░░░░        ┃  slot above is free
     ┗━━━━━━━━━━━━━━━━━━━┛
```
- Order top to bottom: critical, staying, ordinary, each newest first, a wider gap between
  queues (`stackOrder`). All toasts rest left of the badge column when any badge shows (as
  today). A badge reads "+N", a click opens the centre.
- Countdown: ordinary as today (sender's time at once, the user's time one at a time, oldest
  first); a critical/staying/moved toast that no longer stays (a job ended) counts at once,
  where it is. Hover still holds the countdown.
- A finished job's toast shows no progress bar, only the countdown and a result mark (§8.6).

### 8.2 Rules (`ToastRules.qml`, pure, `tests/ToastRulesTest.qml`)

Port of `PlannedRules.js` over a plain state `{ waiting, shown: {critical, staying,
ordinary: [ids oldest first]}, moved: [{id, queue, x, y}] }`; ids grow with arrival.
- `queueFor({ critical, timingKind })` — critical first; else `"stays"` → staying, else
  ordinary.
- `timing(args)` grows `resident`, `residentHide`, `shellJob`: a resident notification with
  expire -1 stays unless `residentHide`. **Not** for the shell's own progress handles
  (`shellJob`: hint `x-qs-progress-run` present — Notifier makes every handle resident,
  `Notifier.qml:279`, and modules cannot send `x-qs-` hints), or every "brief" job and every
  finished job would stay. Their time stays what the handle sends (0 while running with
  `whileRunning`, -1 otherwise). Expire 0 and positive times as today.
- `limits({ critical 1–3 (1), staying 1–5 (1), layout, columnSize })` — replaces `slots`.
- `enqueue`, `where`, `remove`, `requeue` (a waiting toast whose kind changed moves queue by
  age — a job ending while it waits in staying goes to ordinary; shown and moved keep their
  place), `dropWaiting` (toasts off: every queue's waiting dropped, shown and moved stay).
- `nextToast(state, queue, limits)` → the oldest waiting id of that queue while it has room,
  -1 otherwise, and `show(state, id)` — the pull form of `fill`, for the slot that takes it.
  No overtaking between queues any more: `nextToast(kinds, …)` and the old `stackOrder` go.
- `centreOpened(state)` → `{ state, hidden, dropped }`: only the ordinary queue, shown and
  waiting. While the centre is open, `enqueue` still takes critical and staying ones; an
  ordinary one is not queued (seen in the centre).
- `counting(state, kinds)`, `stackOrder(state)`, `badges(state)` → `{ critical, staying,
  ordinary }` waiting counts, and `badgeLook(queue)` → `{ border: "error"|"outline", label }`
  (the critical badge's outline: `Theme.error`, `Theme.border.selectedWidth`).
- `canMove(state, id, movable)`, `moveOut(state, id, x, y, movable)` (a moved one just changes
  place), `clampToScreen(x, y, w, h, screenW, screenH)` (dropped half off screen → inside).
- `announceEffect(state, id, { toastsOn, centreOpen, alive, queue })` moves here from
  `NotificationRules.announceEffect` (its cases move with it): shown or moved → "restart";
  waiting → "none"; centre open and ordinary → "none"; else "queue".
- `describe` for the log ("1/1 shown, 2 wait"), logged on a change only. Cases: every function on empty/one/full queues, limits clamped (0, 4, NaN, strings),
critical never in staying, resident with/without hide, a shell job resident and brief →
ordinary, a job ending waiting → ordinary / shown → counts in place, centre opened with all
three queues filled, a moved toast freeing its slot, `counting` across queues and moved.

### 8.3 State and the HUD

- `Notifications.qml`: one `toastState` (the rules' shape) replaces `shownToasts`,
  `ownTimeToasts`, `stayingToasts`, `toastRoom`; `hudQueue` stays as a derived list of the
  waiting notification objects (oldest first) so `NotifierTest` keeps its entry point;
  `toastScreens` (id → screen name at show) and `toastDurations` stay. `takeToast(queue)`
  replaces `takeHudNotification`. Late answers lose: a toast is only ever shown from
  `toastState`, never from a stale slot.
- `Hud.qml`: fixed 15 slots → one delegate per toast on this screen (shown, moved, leaving),
  `KeyedModel` of ids (string keys, `byKey` lookup — the ScriptModel rule; a moved toast
  keeps its delegate, so countdown, reply text and swipe state stay). A delegate is created
  at show and destroyed after its slide-out; the leaving ones are kept in a `leaving` list
  until then. Three badges from `badges`/`badgeLook`, each beside its queue's lowest toast.
- Lock and screensaver never pause: nothing pauses today (the HUD keeps counting under the
  lock surface); the plan keeps it so and the lock bed checks it.

### 8.4 "×" and the centre

- "×" (and the touch swipe, its twin) on a toast **dismisses**: `notification.dismiss()`,
  the entry leaves the centre; a job goes on, its handle learns the close (as from the
  centre's "dismiss"). A job's "×" gets a `HoverTip`: "Dismiss. The job goes on."
- An action: unchanged — the toast leaves, a resident entry stays (but see question 1).
- Opening the centre runs `centreOpened`: ordinary toasts slide out and their waiting ones
  drop; critical, staying and moved stay, and new critical/staying ones still show.

### 8.5 Moved-out toasts

- **Where they live.** Proposed: in the HUD's own full-screen overlay window of their
  screen (`Hud.qml`, `WlrLayer.Overlay`), as the same delegate placed at its `moved` x/y,
  with its rectangle added to the window's input mask. One window per screen already
  covers the screen, a drag stays inside one surface (Wayland's implicit pointer grab
  goes to the surface pressed — a small window moved by its own margins under the
  pointer would compute its position from coordinates that shift with each configure),
  and the delegate is not rebuilt, so nothing must be handed over. **First step of the
  slice**: a spike that the mask takes a changing set of regions (`Region { regions:
  <Variants over moved ids>.instances }`). If not, fall back to one small layer-shell
  window per moved toast (top-left anchored on its screen, margins = x/y, keyboard on
  demand), handed over on drop, re-dragged by margins from `margin + scene point`.
- **Drag** by the title line (header row less the "×"), `DragHandler { target: null }`,
  only when `canMove` (option on; critical or staying, shown or moved). On drop:
  `clampToScreen`, then `moveOut` — its queue's slot is free, the next waiting shows.
  Grip: 36×3 bar at the top, `Theme.textMuted`; moved: accent outline (`Theme.accent`,
  `Theme.border.width`). No limit on how many.
- **Ends**: "×" dismisses; an action, its sender closing it, or a finished job's countdown
  (counts at once) removes it. The centre opening and "Show toasts" off leave it.
- **Screen change / restart.** A moved toast stays on its screen while that screen exists;
  new toasts follow `toastScreen` as today. Its screen gone (its HUD destroyed) → back
  into its queue as waiting, by age (`requeue`-like `returnToQueue`, a case). A reload of
  the shell loses positions (not kept in `Config`): what the server hands over again goes
  through its queue like the rest, as today.
- Turning "Movable" off leaves moved ones where they are; it only stops new drags.

### 8.6 Card problems

- **Doubled bar.** On a toast that counts down and whose job ended (done/failed), the
  progress bar is not drawn; the summary gets a result mark before it — "✓" in
  `Theme.success` or "✗" in `Theme.error` (Nerd Font glyphs, the theme's tokens) — and the
  countdown is the only bar. The centre (no countdown) keeps the full toned bar. Rule:
  `NotificationRules.progressView(progress, counting)` → `{ bar, mark }`, cases for each
  state × counting.
- **Action buttons.** Through `SmallButton` with a new kind `"action"` in
  `ThemeRules.buttonLook`: fill `accent` (`accentHover` when hot), label `onAccent`, no
  border; `PointerArea` comes with it. Cases in the theme suite; the card's hand-made
  `Rectangle` + `MouseArea` go.

### 8.7 Settings

| Key | Label | Type, default |
|---|---|---|
| `notifications.criticalToastLimit` | Critical toasts at once | number 1–3, 1 |
| `notifications.stayingToastLimit` | Staying toasts at once | number 1–5, 1 |
| `notifications.movableToasts` | Move toasts by their title | bool, true (mockup; question 3) |
| `notifications.residentHide` | Resident notification hide | bool, false; info icon |

- `notifications.maxStayingToasts` goes. **Migration**: none if unused — this machine's
  `config.json` sets only `codePatterns` (checked 2026-11-20); check the Framework before
  slice 2 (read its config over the deploy path, no change). Unset on both → no migration.
  Set → ask the owner. The default falls from 3 to 1, as §7 asks.
- The info icon: a schema field `info` (generic, any entry) that `SchemaSettingEditor`
  shows as a glyph after the label with a `HoverTip`. Text: "A resident notification is one
  its app keeps until you dismiss it, such as a music player's controls. Off, its toast
  stays on screen; on, it counts down like any other."
- `followSenderTime` stays ("Apps choose how long"). Proposed meaning with the queues: off
  → an outside app's time, 0 included, is replaced by the user's time (ordinary queue);
  critical, resident (by its own setting) and the shell's own jobs (`whileRunning` is the
  user's own choice in the module) are not apps' times and keep their queue (question 2).
- Page: the two limits after "Toasts in the column", then movable, then resident hide; all
  `available: _toastsOn`.

### 8.8 Slices, in order

1. **Queue rules.** §8.2 into `ToastRules.qml` beside the old functions (unused yet).
   Tests: `ToastRulesTest` cases above. No screen.
2. **Three stacks and badges.** §8.3; schema keys for the two limits and resident hide
   (no page yet); resident/shell-job timing; requeue on a change of kind; old `slots`,
   `nextToast`, `stackOrder` and `maxStayingToasts` removed; `shelltest.notificationState`
   gains `toast: { place, queue, duration }` and `badges`. Tests: `NotifierTest` through
   `hudQueue` — 2 critical with limit 1 → one shown, critical badge 1; staying and ordinary
   fill independently; a job waiting in staying ends → ordinary; a resident outside one
   stays, with hide counts; a shell job (resident) "brief" → ordinary. Lock bed
   `notifications.sh` grown: urgency 2 twice → one shown, the other waiting in critical;
   expire 0 + -1 → staying and ordinary both shown. **Owner's eyes**: the stacks, gaps,
   badges, the critical badge's outline. CHANGELOG line.
3. **"×" dismisses, the centre hides only ordinary, announces.** §8.4; `announceEffect`
   moved. Tests: `NotifierTest` — "×" → `tracked` false; centre open → ordinary gone,
   critical/staying shown, a new staying one shows; an announced ordinary while open → none.
   Lock bed: a 2000 ms toast sent, the session locked → its toast gone while locked (waited
   on state), queue moves on; `notificationDismiss`-style "×" over shelltest leaves no entry.
   CHANGELOG line.
4. **Movable toasts.** Spike, then §8.5. Tests: `ToastRulesTest` (`moveOut`, `clampToScreen`,
   `returnToQueue`); `NotifierTest` drags a staying toast by its title (QtTest
   `mousePress/Move/Release` in the suite's window) → moved, its slot takes the next; a
   finished job moved out counts down and leaves; "×" on it dismisses; the HUD destroyed →
   it waits again. **Owner's eyes**: grip, outline, dragging, the input mask (clicks pass
   beside a moved toast). CHANGELOG line.
5. **Settings page.** §8.7: page rows, `movableToasts`, the `info` field and its icon.
   Tests: `SettingsPagesTest` (rows present, availability with toasts off), a schema case
   for `info`. **Owner's eyes**: the page and the tooltip.
6. **Finished job: one bar.** §8.6 first item. Tests: `NotificationRulesTest`
   (`progressView`), `NotifierTest` (a done job's toast has no visible "progress" item, the
   centre's has). **Owner's eyes**.
7. **Action buttons' contrast.** §8.6 second item. Tests: theme suite `buttonLook("action")`
   cases; `NotifierTest` clicks an action through the button. **Owner's eyes** (light and
   dark themes).
8. **Docs.** `docs/FEATURES.md` "Notifications" (three queues, badges, moving, "×", the
   settings), `docs/ARCHITECTURE.md` (the toast state, keyed toasts, the mask), both
   systems alike; CHANGELOG lines checked; minor version on release.

### 8.9 Open questions for the owner

1. A resident notification now stays on screen in the staying queue, but running one of its
   actions still takes the toast away (the entry stays). A music player's "Pause" on its
   staying toast would then make the toast vanish, though the notification is still there
   and the next track change does not bring it back. Should an action on a resident toast
   leave the toast on screen (it goes only with "×", which dismisses it), or take it away
   as today?
2. "Apps choose how long" off today makes every toast use your time, also an app's "stay
   until dismissed". With the queues, should it still turn an app's "stay" into a counting
   toast, while critical ones, resident ones and the shell's own jobs set to "on screen until
   done" keep staying? For example, with it off a backup app asking to stay would count down
   in 5 s, but a Taildrop transfer would still stay until it ends.
3. Moving toasts is an option: should it be on or off when the shell starts fresh? The
   mockup had it on; off, nobody sees the grip until they find the setting.
4. "Fullscreen window there: Don't show" today slides every toast away and drops what waits
   when a fullscreen window appears on the toasts' screen. Should critical, staying and
   moved-out toasts stay over the fullscreen window (only ordinary ones going, as when the
   centre opens), or should everything go, as today? For example, a battery-critical toast
   during a fullscreen game.

### 8.10 The owner's answers (2026-11-20)

1. An action on a resident toast leaves the toast on screen (the spec); only "×" takes it away,
   and "×" dismisses.
2. "Apps choose how long" off turns an app's "stay" into a counting toast; critical, resident
   and the shell's jobs "on screen until done" keep staying. Added: every entry in the centre
   gets a pin button; pinning makes that notification a modal on screen (a moved-out toast,
   placed where the moved-out toasts go, draggable, "×" dismisses). "Modal" is a flag of the
   notification, so any notification can be one — dragging a critical or staying toast out
   sets it too; everything decided earlier for moved-out toasts holds. Unpinning (or "×") ends
   it. The pin is part of the movable-toasts slice (4).
3. Movable toasts on by default.
4. A fullscreen window on the toasts' screen ("Don't show"): only critical toasts stay shown;
   everything else goes as today (modals included — they come back when the fullscreen window
   goes, as the plan's slice 4 decides).
