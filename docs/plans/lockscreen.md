# Lock screen: analysis and rework plan

Written 2026-11-14, after two days of fixes that each exposed another fault. Stages 0–2 are
implemented, with the findings of their reviews fixed (section 7 is the current contract). It replaces patching with: a test bed
first, then a pure state machine with unit tests, then the I/O around it.

Sources: a read of Quickshell 0.3.2's source (`src/services/pam/`, `src/wayland/session_lock*`,
`src/io/process.cpp`), an independent review of the lock code, and an experiment that ran a
lock screen end to end in an isolated compositor. "Observed" below means seen running;
"from source" means read, not run.

## 1. What went wrong

### The root cause of "works once"

Quickshell 0.3.2 never emits `lockStateChanged` when a `WlSessionLock` unlocks
(`src/wayland/session_lock.cpp:173-184`: it calls `manager->unlock()` and only then tests
`isLocked()`, which is by then always false). A QML binding to `WlSessionLock.locked`
therefore stays `true` after the first unlock.

The shell hangs everything on that binding (`Lockscreen.locked: _lock.locked`,
`onLockedChanged`). Observed on the running shell: unlocked, and `ipc call lockscreen
status` answers `locked`. Consequences, all confirmed by the trace:

- `LockAuth.begin()` runs only at the first lock of a shell instance. After the first
  successful unlock `_active` is false for good: a typed password is dropped before PAM is
  started (no journal entry, no error shown, the field just empties), and the fingerprint
  conversation is never started.
- `LockAuth.end()` never runs: the fingerprint conversation keeps running after an unlock
  and keeps the reader claimed.
- `promptActive` is never reset on unlock: unlock while the prompt shows, and the next lock
  never wakes — the black screen. This one predates the rework; the packaged version has it.
- `Profiles.screenLocked` stays true; the screensaver never shows again; the "lock after
  screensaver" timer is dead; `ipc status` lies.

The off-screen tests used before missed it because they drove `LockAuth` directly and
never went through a real `WlSessionLock`.

### Facts about Quickshell the design must respect (from source)

- `PamContext` runs `pam_authenticate` only: `account` lines never run.
- `completed` is emitted after the context has already gone inactive; `abort()` emits
  nothing, and kills the child with SIGKILL at the next event-loop pass — no `pam_end`, so
  an aborted `pam_fprintd` may leave the reader claimed for a while.
- `start()` can refuse synchronously (missing config) without any signal; its return value
  must be checked.
- `config`/`configDirectory` cannot change while a conversation is active; the new value is
  silently lost.
- A second `respond()` to one prompt is consumed by the next prompt.
- A lock surface is created per screen and re-created when an output is re-added.
- **Never set `WlSessionLock.locked = false` before `secure`** (the compositor's `locked`
  event). `QSWaylandSessionLock::unlock()` sends `unlock_and_destroy` whenever the lock
  object is not `finished` — also before `locked`, which ext-session-lock-v1 makes a protocol
  error (`invalid_unlock`): a strict compositor kills the client and the session stays locked
  for good, a lenient one unlocks. Setting it false is safe only when no lock object exists
  (every synchronous refusal: no ext-session-lock, no surface component, another lock active
  — `locked` reads false right after being set true) or after `finished` (Quickshell has
  sent `destroy` and reset `locked` itself). The protocol's `destroy` before `locked` is
  reachable only by destroying the `WlSessionLock`, and races with a `locked` in flight.
- Destroying a `WlSessionLock` while locked leaves the session locked and the process
  unable to lock again (the process-wide manager keeps a stale active lock). A reload whose
  new `WlSessionLock` starts with `locked: false` unlocks the session (observed in the test
  compositor) — any file written in the shell's folder triggers one, unless
  `Quickshell.watchFiles` is false (the stop-gap, section 7).
- `IdleMonitor` re-creates its notification on a timeout change by itself.
- `Process`: children are killed when the object is destroyed, but survive a crash.

### Defects found in review (beyond the root cause)

Security:

1. Escape unlocks without authentication (`LockPrompt.qml`, also in the packaged version).
2. Any file written in the checkout while locked reloads the shell and unlocks the screen,
   or leaves it locked with no client (the shell runs from the live checkout).
3. Notifications are shown in full on the lock screen by default, one-time codes included.
4. A shell crash while locked leaves no way back short of a TTY: Hyprland has
   `allow_session_lock_restore` off and the shell is not restarted.
5. `Lockscreen.unlock()` and `LockAuth.authenticated` are public: any QML can unlock.

Correctness:

6. `_paused` and `_broken` survive from one lock to the next; a missed wake signal leaves
   the reader off for good.
7. "Verifying…" can stick: `start()` failing, or the method script never running.
8. The prompt's 10 s sleep aborts a verification in progress.
9. Keys are swallowed: Enter/Backspace right after a key wake; keys on a screen that does
   not own the prompt; focus stolen from the wake item on rejection.
10. The field is cleared whether or not the input was taken — which hid the root cause.
11. The session monitor loops every 10 s when `XDG_SESSION_ID` is unset; the inhibitor is
    not re-acquired if it dies; the 1.5 s fallback can let the machine sleep unlocked.
12. Passive methods answer any prompt with an empty string — failed password attempts in a
    loop if such a config ever reaches a password module.
13. The shipped `pam/password` does not work on NixOS; `nullok` allows a blank password;
    the method script parses `fprintd-list`'s human-readable output.
14. Orphaned `gdbus monitor` processes pile up after crashes.

### What is structurally wrong

- No single owner of the lock state: it lives in `WlSessionLock.locked`, its stale mirror,
  `LockAuth._active`/`_paused`, `promptActive`, each surface's `_awake`, `Profiles`.
- Transitions happen as side effects of property-change handlers, so correctness depends
  on notify semantics — which are broken here.
- One long-lived `LockAuth` reused across locks, with hand-kept reset lists.
- Policy in the views: the surface decides when to cancel a password; the prompt clears
  its field without knowing the outcome.
- Decisions mixed with I/O (parsing `gdbus` lines in `onRead`, retry policy in
  `onCompleted`), so none of it could be unit-tested — and none was.

## 2. Can it be tested without the real screen? Yes.

Observed: a second Hyprland runs nested in a headless labwc, in a private
`XDG_RUNTIME_DIR`, with no seat, no DRM, no real input and no D-Bus. Nothing appears on
the real screen and the real session cannot be reached from inside. In it:

- a Quickshell `WlSessionLock` locks for real (`hyprctl -j locked`);
- a small persistent virtual keyboard/pointer client types and moves the pointer while
  locked (one-shot tools such as `wtype` lose the first key);
- `grim` takes screenshots of the locked output;
- PAM runs from test configs: a "password" stack accepting one known test password, and a
  "passive" stack that blocks until a trigger file says ok or fail (a stand-in for the
  fingerprint reader);
- outputs can be added and removed while locked; the lock client can be killed; the
  config can be reloaded while locked.

The working script and its parts are in the session scratch directory and must be moved
into the repo (stage 0). The real shell also starts inside it; locking it there was not
tried (it needs permission to run that one command).

Cannot be simulated: real fprintd and security keys, suspend/resume and logind's signals,
real DRM hotplug/DPMS, real input devices, `pam_unix` with the real password.

## 3. Target structure

1. `singletons/LockRules.qml` — pure, like `PolkitRules`. `initial()`, and
   `step(state, event, now) -> { state, effects }` on plain objects that are replaced,
   never mutated. Plus the parsers: `parseMethods`, `parseLogind`, `parseSessionPath`,
   `retryDelay`.
2. `singletons/Lockscreen.qml` — the driver and the only owner of state. `dispatch(event)`
   with a queue: events raised while effects run are queued, never re-entered. Binds
   `WlSessionLock.locked` declaratively to the state, and keeps the phase across a reload
   (`PersistentProperties`). Never reads `_lock.locked` through a binding; the compositor's
   word arrives as events from `secureStateChanged`. `unlock` is not public.
3. Thin adapters that only turn I/O into events and effects into I/O: one PAM method (one
   `PamContext`, conversations tagged with an id, a refused `start()` reported), the
   logind monitor (backoff, "no session" said once), the sleep inhibitor (re-held whenever
   it exits while wanted), the method detector (timeout, generation number). Created per
   lock and destroyed at unlock, so destruction is the cleanup.
4. Surfaces as views of the state: the prompt shows where the state says its owner is;
   they send `activity`, `key`, `submit`; the field empties when the state says the input
   was taken. No Escape.

State, in independent parts: phase (unlocked / locking / locked, with a session number),
sleep (awake / suspending / resuming with a deadline), methods (unknown / detecting /
known), password (idle / pending / verifying / asking / failed / unavailable), each
passive method (unavailable / idle / running / backoff / paused / broken), prompt (owner,
awake until).

## 4. Stages

Each stage ends with its tests green; no stage is "done" on reasoning alone.

**Stage 0 — test bed.** Move the compositor harness into `tests/lock/` (script, input
client, PAM test stacks), runnable as one command, exit code non-zero on failure. Make it
start the real shell with test PAM stacks; that needs one seam in the shell: where the
method list comes from (an environment variable naming a methods script, read once at
start). First test written is the regression: lock, unlock by password, lock again, unlock
again — it must fail on today's code.

**Stage 1 — the rules, with unit tests** (`tests/LockRulesTest.qml`, in `tests.qml`):

- only a successful PAM completion of the current session and conversation unlocks; no
  other event sequence does (a sweep over generated sequences);
- stale completions and messages are ignored;
- leaving `locked` aborts every running method and stops every timer;
- lock → authenticate → unlock → lock equals the first lock (the regression);
- input not taken is refused with a reason; a refused `start()` and a failed or timed-out
  detection end in a visible error, never in "verifying";
- the prompt's time-out cancels a question, never a verification;
- exactly one prompt owner; a key on another screen is forwarded, never lost;
- sleep: lock before sleep, nothing started while suspending, re-detection on wake, a
  missed wake recovers, the inhibitor released only after the compositor's confirmation
  or the fallback;
- the retry-delay table; the parsers on real `gdbus monitor` and script output.

**Stage 2 — driver and adapters.** Replace `LockAuth` and the logic in `Lockscreen` with
the driver and adapters. Remove Escape. Harness tests: several lock/unlock cycles by
password and by the passive stack, wrong password, a question after the password, output
removed and re-added while locked, lock requests while locked.

**Stage 3 — views.** Rewrite `LockSurface`/`LockPrompt` as views. Harness tests with real
typed keys: wake by key and by pointer, Enter and Backspace right after waking, typing
during the fade, two outputs.

**Stage 4 — failure and recovery.** Reload while locked keeps the lock (harness test);
the shell killed while locked can be restarted and re-locks (`allow_session_lock_restore`,
a restart of the shell by Hyprland); orphaned helpers are cleaned up at start.

**Stage 5 — the system side.** PAM configs and the NixOS module (no `nullok`, no reliance
on `account`, the fingerprint config independent of the global switch), the method script
(D-Bus instead of parsing `fprintd-list`, a timeout), the logind monitor without
`XDG_SESSION_ID`. Report the Quickshell bug upstream.

**Stage 6 — the real machine, once.** What no harness covers, as a short checklist for
the owner: real password, real fingerprint, lid close and open, hibernation, power key.
Logging of every auth event (never the secret) goes in before this, so a failure there is
read from the log rather than guessed.

## 5. Decisions (the owner's, 2026-11-14)

- Notifications on the lock screen default to "app only" (it stays a setting).
- Lock before sleep stays on by default.
- `loginctl unlock-session` (logind's Unlock signal) unlocks: the emergency way in from
  another console, and what the tests use.
- **Escape keeps unlocking for now**, against section 1: the owner uses it while testing.
  It is an explicit, named event in the rules (not a side door in a view), so the tests
  can say exactly which events unlock: an accepted authentication, logind's Unlock, and
  this one. Removing it later is deleting that one event. What it does, plainly: at an
  awake prompt a press of Escape unlocks — from any screen, with a question pending, during
  a check, while the machine is going to sleep; on a sleeping prompt it only wakes it, so
  two separate presses unlock; a held Escape's repeats count for nothing.
- The shell may be locked and unlocked freely inside the isolated test compositor.

## 6. How the work is done

- In a copy, `~/src/h2s-shell-lockwork`: the running shell reloads on every file written
  in `~/src/h2s-shell`, and a reload while locked unlocks the screen. The copy is synced
  back once, at the end.
- Each stage: an implementing agent, then an independent code review, then fixes, then
  the tests run again. A snapshot of the copy is kept from before each stage
  (`~/src/h2s-shell-lockwork.snapshots/`), which is also what the review diffs against —
  the checkout has no git history to diff with.

## 7. The rules and the driver: the contract

`singletons/LockRules.qml` is the specification of the lock; `tests/LockRulesTest.qml` checks
it (by the numbered behaviours of Stage 1, a seeded sweep of 1600 generated event sequences
started from unlocked, locking and locked, and a liveness oracle run from reached states, in
three worlds: a compositor that confirms, one that never answers, and a detected password
config that cannot start). Everything below is what the driver (`singletons/Lockscreen.qml`)
relies on and must do for the rules to hold, as Stages 1 and 2 implement it, with the
findings of the Stage 2 reviews fixed. It is complete as it stands.

### The compositor rule (fail closed)

ext-session-lock-v1 makes `unlock_and_destroy` a protocol error (`invalid_unlock`) until the
compositor has sent `locked`, and Quickshell sends exactly that whenever
`WlSessionLock.locked` is set false on a lock object that is neither confirmed nor finished
(section 1). A strict compositor then kills the client — the session stays locked with no way
back but a TTY; a lenient one unlocks. So:

- **`unlockCompositor` is emitted only for a session the compositor confirmed**
  (`compositorLocked` taken for it). Every unit test checks this on every step it takes.
- A lock is never set again or given up while unconfirmed: no retry, no "unconfirmed" end.
  A late confirmation is only reported (`timings.confirm`, a warning once, `view.notice`).
- An unlock decided while `locking` — an accepted authentication, logind's Unlock, Escape —
  is **pending**: the phase becomes `unlocking`, every conversation and lock timer is wound
  down as for an unlock, and `phase.pending` records `{ reason, method }`. At
  `compositorLocked` for that session the unlock is carried out (`unlockCompositor`, then
  `announceLocked(false)`); at `compositorFinished` the lock simply ends (`lastEnd`
  "denied", nothing to unlock). While pending, input, logind's Unlock and PAM events are
  ignored ("unlock pending"); a new `lockRequested` or a `prepareForSleep` cancels the
  pending unlock — the latest word is "stay locked" — and the lock goes on as a fresh one on
  the same compositor lock (same session, surfaces kept, methods asked again, a new
  authentication needed; nothing set again or announced).
- PAM conversations run from the start of `locking`, not only after the confirmation, so a
  late confirmation can never strand the owner: what they type is checked at once, and a
  success shows "Unlocking…" until the compositor's word. (Why from the start rather than
  after the first time-out: with a normal compositor the two cannot be told apart — it
  confirms in milliseconds; with a slow one, a password typed at once gets its verdict at
  once instead of "Verifying…" for five seconds and then the verdict; and one rule less.
  Passive methods still never start while suspending.)
- The driver checks it again: an `unlockCompositor` on a lock that is `locked` but not
  `secure` is refused and logged as an error.

### API

- `initial(settings) → state`. `settings`: `{ lockOnSleep` (default true)`, passwordFallback:
  { directory, config }` (the password config when detection names none or fails, and the
  other config to try when the detected one could not be used; null: none)`, timings`
  (overrides of `LockRules.timings`; a value that is not a finite number ≥ 0 keeps the
  default, unknown names are dropped)` }`. Everything is copied: the caller's objects are not
  kept.
- `step(state, event, now) → { state, effects, ignored, error? }`. `now` is `Date.now()` when
  the event is handled. `ignored` is `""` when the event was taken; otherwise it says why,
  the returned state is the very object passed in, and there are no effects. Never throws.
  An internal error comes back with `error: true`: as ignored, state unchanged — except a
  `pamCompleted`/`pamStartFailed` for the current conversation, which still ends that
  conversation, its result NOT believed (fail closed, also for a success): the password
  shows "Password check failed, try again" (verify timer stopped by reconcile), a passive
  method backs off as after a PAM Error (counted against `errorLimit`; not broken for the
  lock by one fault); only if ending it throws as well, the minimum — the password failed,
  the passive method broken (`brokenBy` "internal"). The error's text, in `ignored` and in
  the `log` effect, never contains the secret. The driver logs every `error: true`. States
  are never mutated: compare with the old one, bind to the new one — and then drop the old
  one (see "Never keep old states").
- `view(state)`: what the views render — `locked` (locking, locked or unlocking)`, unlocking`
  (an unlock waits for the compositor)`, promptSurface` (the surface instance showing the
  prompt, null while asleep)`, promptScreen` (its screen name, "" while asleep; information
  only)`, busy` (verifying, pending, or unlocking)`, buttonText` ("Unlock", "Verifying…",
  "Unlocking…")`, placeholder, answerVisible, error, notice` ("Waiting for the compositor to
  confirm the lock" once the confirmation is late, else "")`, refusal` ("busy" / "empty" /
  "")`, fieldEpoch` (the field empties whenever it changes)`, methods` (`[{ name, visible,
  waiting, text, isError }]` per passive method). `view()` returns a fresh object each call
  and `methods` is a fresh array: feed it to a `Repeater` through `ScriptModel { values: … ;
  objectProp: "name" }`, never directly (CLAUDE.md).
- `describe(state)`: a JSON-serialisable copy without the secret (`hasSecret` instead) and
  without what changes at each keystroke or pointer move — no `prompt.awakeUntil`, no
  `serial`, `timers` as the sorted list of the names running (no tokens) — since the IPC
  `state` is readable by every process of the user, and those would time each key typed.
  `view` is included. **The driver exposes only this** — the IPC `state`, logs, test output.
  `describeEvent(event)` and `describeEffect(effect)` are what may be logged of events and
  effects: any `text` is replaced by `"<redacted>"`, a `key` is kept only when it is one of
  `namedKeys`.
- `running(state) → { conversations: [{ method, conversation }], timers, lockTimers }`.
- Parsers: `parseMethods(lines)` (array or string → `{ method: { directory, config } }`,
  junk skipped, first line per method wins), `parseLogind(line, sessionPath)` (→ one of the
  events below or null; Lock/Unlock only on `sessionPath`, the shell's own session),
  `parseSessionPath(output)` (→ path, or "" for an error or nothing),
  `retryDelay(previousDelay, roundMilliseconds, result, timings?)` (→ ms after a `failed` or
  `maxTries` round, null otherwise; `timings` is the table to use — the rules pass the
  state's `settings.timings`, left out it is `LockRules.timings`).
- Tables: `timings`, `limits` (`errorLimit` 5, `revivals` 3; not overridable),
  `passiveMethods` (`fingerprint`, `u2f`: name, label, hint, eager), `unlockSources`
  (`["logind"]`), `escapeUnlocks` (true — see "Escape"), `namedKeys`, `sleepTimers`,
  `timerNames`, `pamResults`.

The driver's small pure helpers are `singletons/LockIoRules.qml` (tested in
`tests/LockIoRulesTest.qml`): `serialQueue(handle, onError)` (one event at a time),
`runStep(result, hooks)` (commit, then prepare / publish / each effect / finish, each guarded
on its own: a view that fails to publish cannot keep `lockCompositor` from running),
`passwordFallback(facts)` and `fallbackFacts(lines)` (below), `keyName`, `editField`,
`detectionEvent`, `restartDelay`.

### Timings (ms, `LockRules.timings`)

| name | default | what |
|---|---|---|
| `confirm` | 5000 | after this without the compositor's confirmation: a warning (once) and `view.notice`; nothing else changes |
| `detect` | 5000 | the methods script's answer, else go on without it |
| `prompt` | 10000 | the prompt hides after this without activity |
| `promptSlack` | 50 | a prompt timer this early counts as on time |
| `verify` | 90000 | the longest a submitted password waits for PAM (pending/verifying) |
| `inhibitorFallback` | 4000 | the inhibitor held for the lock's confirmation on the way to sleep |
| `settle` | 1000 | after an abort, before that method may start again |
| `resumeGrace` | 4000 | after a wake, then ask once more for missing passive methods |
| `missedResume` | 60000 | (monotonic) after going down, behave as woken if `resumed` never came |
| `minSuspend` | 5000 | (monotonic, a timer) activity after this much running time since PrepareForSleep means a missed wake |
| `redetect` | 30000 | a FAILED detection is asked again when somebody comes back to the prompt, at most this often |
| `retryMin` / `retryMax` / `quickRound` | 500 / 10000 / 20000 | passive retries after failures |
| `errorRetry` | 30000 | a passive method's retry after a PAM Error |

### State

Each region has a `status`.

| region | status | other fields |
|---|---|---|
| `phase` | unlocked / locking / locked / unlocking | `session` (+1 at every lock), `confirmLate` (the confirm timer expired; locking/unlocking), `pending` (`{ reason, method }` while unlocking, else null), `lastEnd` when unlocked: authenticated / escape / logind / compositor / denied |
| `sleep` | awake / suspending / resuming | `inhibitor`: held / released, `minSuspendPassed` (suspending: the minSuspend timer has run) |
| `methods` | unknown / detecting / known | `generation`, `configs: { password, fingerprint, u2f }` (each `{ directory, config }` or null), `answered` (the script answered once in this lock), `lastResult` (answered / failed / ""), `askedAt` (wall clock of the last request), `waitForAnswer`, `passwordSource`: detected / fallback / none |
| `password` | idle / pending / verifying / asking / failed / unavailable | `conversation: { id, session }`, `config`, `avoid` (a config that could not be used in this lock, or null), `question`, `answerVisible`, `error`, `pamError`, `refusal`, `settling` |
| `passive[name]` | unavailable / idle / running / backoff / paused / broken | `config`, `conversation`, `startedAt`, `delay`, `lastResult`, `errors` (Errors in a row), `revivals` (this lock and wake), `brokenBy` (error / asks / start / internal), `message`, `messageIsError`, `settling` |
| `prompt` | — | `surfaces: [{ id, screen }]` (instances, in the order added), `owner` (a surface id; null = asleep), `awakeUntil`, `fieldEpoch` |
| `timers` | — | `{ name: { token } }` for every timer running |
| `secret` | — | the typed password from submit until PAM's first hidden prompt (or any exit); else null |
| `serial`, `settings` | — | the id counter (ids, tokens and generations are never reused within a state's life), the settings |

`methods`, `password`, `passive`, `prompt`, `secret` and their timers belong to one lock:
created afresh at each lock, thrown away at each unlock — and at a pending unlock, except the
prompt's surfaces (still there; the prompt stays where it was to say "Unlocking…").

### Events (`{ type, …fields }`)

| event | fields | meaning |
|---|---|---|
| `started` | — | once, after `initial()`: takes the inhibitor if wanted |
| `lockRequested` | `source` (ipc, idle, logind, sleep, …) | locks from unlocked; cancels a pending unlock; ignored while locking or locked |
| `unlockRequested` | `source` | unlocks only for a source in `unlockSources`: `"logind"` (pending while locking) |
| `compositorLocked` | `session` | `WlSessionLock.secure` became true; `session` = the session of the last `lockCompositor` the driver executed |
| `compositorFinished` | `session` | the compositor ended the lock (locked) or refused it (locking, unlocking); `session` as above |
| `surfaceAdded` | `surface, screen` | a lock surface instance created; `surface` = the driver's id for that object; `screen` non-empty |
| `surfaceRemoved` | `surface` | that instance destroyed |
| `activity` | `surface` | pointer motion |
| `press` | `surface` | a pointer press (it moves the prompt to that surface) |
| `key` | `surface, key` (one of `namedKeys`, or ""), `text`, `autoRepeat` | every key pressed on the surface; `autoRepeat` true for a held key's repeats |
| `submit` | `surface, text` | Enter / the button in the field; taken only from `promptSurface` |
| `methodsDetected` | `generation, lines` | the methods script's output |
| `methodsFailed` | `generation, reason` | the script failed |
| `pamMessage` | `method, conversation, message, messageIsError, responseRequired, responseVisible` | PamContext.pamMessage |
| `pamCompleted` | `method, conversation, result` (success / failed / error / maxTries) | PamContext.completed |
| `pamStartFailed` | `method, conversation` | `start()` returned false (or the adapter refused a start while a conversation ran) |
| `prepareForSleep` / `resumed` | — | logind's PrepareForSleep(true / false) |
| `timer` | `name, token` | a timer expired: the token of the start it belongs to |
| `settings` | `values: { lockOnSleep?, passwordFallback? }` | a profile, or the driver's fallback probe, changed them |

Ids are compared strictly (`===`): a conversation id is the number the rules gave in
`startPam`; a surface id is a non-empty string or a finite number the driver chose.

### Effects (`{ type, …fields }`), executed in array order

| effect | fields | the driver |
|---|---|---|
| `lockCompositor` | `session` | sets `WlSessionLock.locked = true`, remembers `session` as the one in force, **then reads `locked` back**: false means Quickshell refused (no ext-session-lock, no surface component, `lock()` failing — all without a signal, and in each case before any lock object exists); it sets `locked = false` again (which sends nothing then, and clears Quickshell's target so the next lock is not a no-op) and queues `compositorFinished { session }` |
| `unlockCompositor` | `session, reason, method?` | only for a confirmed session (the compositor rule); sets `WlSessionLock.locked = false` — refused, with an error, if the lock is not `secure` |
| `announceLocked` | `locked` | tells the shell (`Profiles.screenLocked`); true: turns Quickshell's file watching off (`Quickshell.watchFiles = false`: no reload while locked, see "Reload") and asks for the password fallback again; false: restores file watching as it was |
| `detectMethods` | `generation` | runs the methods script (killing an older run) and reports its lines with this generation |
| `startPam` | `method, conversation, configDirectory, config` | configures that method's PamContext and starts it; `start()` false → `pamStartFailed` |
| `abortPam` | `method, conversation` | aborts it — only if `conversation` is the adapter's current one, else nothing |
| `respondPam` | `method, conversation, text` | `respond(text)` — only if `conversation` is the adapter's current one, else nothing. **Secret** |
| `startTimer` / `stopTimer` | `name, ms, token` / `name` | (re)starts / stops the single-shot timer of that name |
| `holdInhibitor` / `releaseInhibitor` | — | from now on keep the sleep-delay inhibitor held (re-taken whenever its process exits) / let it go |
| `forwardKey` | `surface, key, text` | hands the key to that surface's field (always the prompt's owner): `text` (printable, possibly several characters; never a control character) is inserted at the cursor; `key` Enter submits, Backspace / Delete delete before / after the cursor, Left / Right / Home / End move it; any other named key does nothing in the field |
| `log` | `level, message` | logs it (never contains typed text) |

Timer names, the finite set (`timerNames`): `confirm`, `detect`, `prompt`, `verify`,
`inhibitor`, `missedResume`, `resumeGrace`, `minSuspend`, `retry:fingerprint`, `retry:u2f`,
`settle:password`, `settle:fingerprint`, `settle:u2f`. The first four and the `retry:`/`settle:`
ones belong to a lock and are stopped when it ends (all but `confirm` already when an unlock
becomes pending; `confirm` runs while the compositor's word is awaited and not yet late);
`sleepTimers` (`inhibitor`, `missedResume`, `resumeGrace`, `minSuspend`) outlive it.

Ordering guarantees within one step:

- A step that enters the lock (from unlocked, by `lockRequested` or `prepareForSleep`) begins
  with `lockCompositor`, then `announceLocked(true)`, before anything else — the sleep
  region's timers included. `lockCompositor` is emitted nowhere else.
- A step that leaves the lock emits every `abortPam` and lock `stopTimer` before
  `unlockCompositor` (when there is one: not when the compositor ended or refused the lock),
  and `announceLocked(false)` after it. A step that makes an unlock pending emits the aborts
  and stops, and neither of the two.
- A method is never aborted and started in the same step; a timer is never started twice in
  one step; a `startTimer` for a running timer replaces it (no `stopTimer` first).

### What the driver must guarantee

- **One step at a time; commit before effects.** The driver stores the new state *before*
  running the step's effects (`LockIoRules.runStep`). Events raised while effects run (a
  refused `start()`, a signal emitted synchronously from inside `respond()`, `abort()` or the
  lock's setter) are queued and handled after the current step's effects, in the order
  raised — never re-entered. Publishing the view, creating and destroying the per-lock
  adapters and each effect are guarded each on its own: one that throws is logged and the
  rest still run.
- **Compositor events carry the session** of the last `lockCompositor` executed. Quickshell
  emits `secureStateChanged` synchronously inside the unlock effect: that report is
  `compositorFinished` with the old session, and the rules ignore it once a new lock has
  begun. A refusal shows only as `secureStateChanged` with `secure` still false, or as
  `locked` reading false right after being set; both become `compositorFinished { session }`.
  `WlSessionLock.locked` is read only right after setting it true (reliable in that
  direction; only the unlock notify is broken, section 1), and before an unlock (with
  `secure`, for the check above), never through a binding.
- **Tag PAM events** with the method and the conversation id from the `startPam` that
  started that conversation. After `abortPam` the adapter may go on reporting with the old
  id: the rules ignore it. The adapter drops `abortPam`/`respondPam` whose conversation is not
  its current one (a late effect must not abort or answer the next conversation), and refuses
  (`pamStartFailed`) a `startPam` while its context is still active rather than aborting and
  starting in one pass. Results are mapped to `success`/`failed`/`error`/`maxTries`.
- **Timers**: one single-shot timer per name; `startTimer` (re)starts it with `ms`, from when
  the effect runs; `stopTimer` cancels it; at expiry dispatch `{ type: "timer", name, token }`
  with the token of the start that set it. Monotonic timers (Qt's) are right: the
  missed-resume and min-suspend timers are meant to stand still while the machine sleeps.
  Firing a little early is harmless (the prompt re-arms; `timings.promptSlack`).
- **Surfaces are instances.** Each lock surface object gets an id of its own when it
  registers (a counter in the driver; never reused within a shell instance), sends
  `surfaceAdded { surface, screen }` before any input and `surfaceRemoved { surface }` when
  destroyed; a screen without a name gets a generated one (`screen-<id>`). Quickshell
  destroys surfaces with `deleteLater()` and creates new ones at once, so a screen may have
  two instances for a moment, and the new one's `surfaceAdded` may come before the old one's
  `surfaceRemoved` (an output re-added, unlock and lock in one pass, a reload). Every input
  event names the instance it came from; input from an instance not known is ignored.
- **Views** render `view(state)` only. The prompt shows on the instance `promptSurface` and
  nowhere else (also when two instances share a screen). The field is cleared when
  `fieldEpoch` changes (never on its own when submitting); `forwardKey` is applied to the
  field. The field never takes focus: the surface's key catcher sends every key as `key`
  (its name if it is one of `namedKeys` — Return and the keypad's Enter are both "Enter" —
  else `key: ""` and the character in `text`; `autoRepeat` from the key event), and it comes
  back as `forwardKey` — also to the surface it came from. So the field sends `submit`
  (Enter forwarded, or the button) and no `activity` on typing: the `key` event already
  extends the prompt's time. A pointer press anywhere on a surface sends `press`, plain
  motion `activity`; pointer events in a surface's first 300 ms are dropped (the surface
  appearing under a resting pointer is not somebody moving it); keys never are. What a key
  event does not carry is not typed: dead keys, compose and input methods are a later stage.
- **Never expose the state**: only `describe()`, `describeEvent()`, `describeEffect()`.
- **Never keep old states or effects.** The secret lives in `state.secret` from submit to
  PAM's first hidden prompt, and travels in the `respondPam` effect (and a typed answer in
  `respondPam`, a key's character in `forwardKey`). Any old state kept around keeps the
  secret with it: the driver holds the current state only, drops each step's effects once
  run, and logs only through the describe functions.
- **Methods script**: no timeout of its own needed — the rules time out (`detect`, 5 s).
- **The password fallback** is chosen from the machine, as `scripts/lock-auth-methods.sh`
  chooses the password config — `LockIoRules.passwordFallback({ shellDirectory,
  systemDirectory, systemConfigReadable, nixos })`: `<system dir>/h2s-shell-password` when
  readable, else on NixOS `<system dir>/login`, else the shipped `pam/password`. The driver
  passes the shipped one to `initial()`, probes the two facts (`test -r`, `test -e
  /etc/NIXOS`) at start and at every lock, and sends a `settings` event when the answer
  differs. The system directory is `/etc/pam.d`, or `H2S_LOCK_SYSTEM_PAM_DIR` (the test bed's
  seam; the methods script honours it too).
- **Reload.** Quickshell reloads the shell when a file of it changes, and a reload's new
  `WlSessionLock` takes the old lock over with `locked` unbound (false) and unlocks with no
  authentication (demonstrated). Stop-gap until Stage 4: `Quickshell.watchFiles` is false from
  `announceLocked(true)` to `announceLocked(false)` (`QS_DISABLE_FILE_WATCHER` aside, the
  file watcher is the only reload trigger besides `Quickshell.reload()`, which nothing in the
  shell calls). Edits made while locked take effect at the next file change after the
  unlock. Carrying the lock across a reload (Stage 4): `initial()` resets `serial`, so ids,
  tokens and generations start again from 1; if the phase is carried over, every adapter
  (PAM contexts, timers, the detector) must be destroyed and re-created with the new state,
  so that nothing tagged under the old serial can report into the new one.

### What other QML in the shell can reach

Same-process QML is not a security boundary; the driver only keeps the obvious doors shut.
`Lockscreen` exposes `view`, `locked`, `screensaverVisible`, `lock(source)`, the surface
functions and the IPC. The state, the event queue, the dispatch function and the surface
registry live in the closure `_build()` makes, not in properties; `_api` holds only the
operations above. The surface functions take the `LockSurface` object itself and act only for
one registered by `addSurface` (which accepts only a `LockSurface` instance, once, while a lock
is in force) — no guessable ids. Still reachable: a QML component that gets hold of a
`LockSurface` (or creates one) can send its input — Escape at an awake prompt included;
`Lockscreen.children` lists the singleton's child objects (the logind monitor, the adapters,
the timers), whose signals other QML can emit — the driver accepts from each only the event
types it may raise (the logind monitor's include logind's Unlock); and, like any process of
the user, QML can run `loginctl unlock-session`, which is an accepted unlock by the owner's
decision. Defect 5 is therefore narrowed, not closed: the guarantee is against mistakes, not
against code running in the shell.

### Decisions, and why

- **Escape** (the owner's decision, section 5) unlocks at an awake prompt. It is routed only
  through the `key` event, in one marked block in `_key`, switched by `escapeUnlocks`; it is
  no `unlockRequested` source. On a sleeping prompt it only wakes it and is not forwarded. A
  held key's auto-repeats are ignored ("repeated Escape"), so holding Escape on a sleeping
  prompt does not wake it and then unlock. Plainly: two separate presses unlock (the first
  wakes, the second unlocks); it works from any surface (not only the one showing the
  prompt), with a question pending, during a verification, and while suspending; while
  locking it is a pending unlock like any other. "At an awake prompt" was kept as the only
  condition rather than tightened, deliberately: this is a testing door slated for deletion,
  and every extra rule around it is more to delete. Removing it is deleting that block and
  the property. The events that end a lock are exactly: a `pamCompleted` success of the
  current conversation, `unlockRequested("logind")`, a pressed Escape at an awake prompt (all
  three pending while locking, carried out at `compositorLocked`), and — not unlocks by
  anyone — `compositorFinished` of the current session. The sweep asserts it.
- **Keys on another surface are forwarded to the owner**, not a reason to move the prompt: the
  half-typed text lives in the owner's field. Motion elsewhere only extends the owner's
  time. A **press** on a surface that does not own the prompt moves it there (the owner's
  decision): the field starts empty (`fieldEpoch` +1), a question is kept, a verification
  goes on. When the owner's instance goes away the prompt goes, awake, to the newest other
  instance on the same screen (its successor; an older one there is being destroyed), else
  to the first surface left (`fieldEpoch` +1); with none left it sleeps.
- **A passive method asked for input** (`responseRequired`) is aborted and marked broken for
  the lock at once, never answered: a passive config that asks is a password module or
  pam_u2f's interactive mode, and the empty answer the old code gave every round was a failed
  password attempt each time (faillock). The cost: an interactive pam_u2f config does not
  work.
- **An empty password is never sent** (refusal "empty"): `nullok`, and an Enter forwarded
  right after waking. An empty *answer* to a question is sent.
- **The typed password answers only a hidden prompt**; a first prompt that shows its answer
  drops the password and is asked as a question.
- **Conversations start as soon as the methods are known, also while locking** (the
  compositor rule, above); detection starts at the lock request. A password typed earlier is
  held (`pending`).
- **The verify timer** (90 s) runs exactly while the password is `pending` or `verifying`
  (armed and stopped by reconcile only); at expiry the conversation is aborted (settle, then a
  new submit starts afresh), the password shows "Password check timed out", the field is
  usable. A question waiting for the user stops it; the answer arms it afresh.
- **During a re-detection** the password uses a config known from an earlier answer.
  Passive methods keep using the earlier configs too (an eager retry starts at once), except
  during the lock's first detection and the one after a wake, whose answer is awaited (after
  a wake, that answer is the trusted one). A re-detection that no longer names a method
  stops it: aborted if running, its retry stopped if backing off, unavailable; a broken
  method stays broken.
- **No password config known at submit**: the methods script is asked again first; only if
  that answer has none either (and there is no fallback) does the password show "Password
  check is not available".
- **A password config that cannot be used** — `start()` refused, or PAM's Error — is noted
  (`password.avoid`) and the methods are asked again; the next attempt (the next submit)
  takes the other config there is: the fallback after the detected one, the detected one
  after the fallback. A wrong password (failed, MaxTries) is no reason to change config.
  Without this a dead detected config was retried at every submit for the rest of the lock.
- **Detection failing or timing out** keeps this lock's last answer — its passive configs and
  a password config the script named — and takes the password fallback where it named none;
  the warning says which.
- **Asking the script again** when somebody comes back to the prompt happens only when the
  last detection FAILED (or timed out), at most every `redetect` (30 s). A clean answer
  without a method means it is not offered (no reader, no finger enrolled, no key registered)
  and is not asked again at every wake of the prompt (it used to be, on every machine
  without a reader). The wake's grace period still asks once after a wake from sleep (the
  reader's service may not have answered in the first moments).
- **Retries**: first quick failure 500 ms, doubling to 10 s; a round of 20 s or more resets to
  500 ms; MaxTries waits 10 s at once (somebody trying and failing). A PAM **Error** (which
  Quickshell reports for every code but success, auth error and max tries — a device not
  plugged in included) waits `errorRetry` (30 s); the `errorLimit`-th (5th) Error in a row
  breaks the method. Any other result resets the count. Somebody coming back to the prompt
  cuts an eager method's backoff short (a security key plugged in now) — not a MaxTries
  wait — and gives an eager method broken by Errors one more round, at most `revivals` (3)
  times; another Error breaks it again at once. So the Error rounds of a config that can
  never work are bounded by `errorLimit` + `revivals` per lock and wake. Every abort within a
  lock is followed by a `settle:<method>` timer (1 s) before that method may start again.
- **Broken is cleared by a wake from sleep** (not by a re-detection within the lock), which
  also resets the Error and revival counts.
- **Sleep**: the inhibitor is held while awake with lockOnSleep, released at
  `compositorLocked` or after `inhibitorFallback` (4 s, under logind's 5 s
  InhibitDelayMaxSec), and released at once when going down already locked or when the lock
  ends during the suspend (a pending unlock keeps it until the confirmation or the fallback).
  Re-taken after every wake, never while suspending. A lost `resumed` is recovered 60 s
  (monotonic) after going down, at activity after `minSuspend` (a monotonic timer: an NTP
  step forward while going down does not turn the lid's hand into a wake), or by the next
  PrepareForSleep — which is then a missed wake followed by a new sleep, and locks again if
  unlocked. A `resumed` without a PrepareForSleep still re-detects and restarts running
  passive methods. Four seconds after a wake, a lock still without a passive method asks
  once more (the old `_afterWake`).
- **The prompt timer is not restarted on every pointer move**: activity moves `awakeUntil`;
  at expiry the timer re-arms for what is left — never more than `prompt` (a wall clock set
  back would otherwise keep the prompt awake for as long as it was set back).
- **Idle and screensaver stay in the driver.** `IdleMonitor` is a Wayland object, and its
  outcome is just `lockRequested("idle")`. `enabled`/`timeout` are bound declaratively (it
  re-creates its notification on a timeout change by itself). `screensaverVisible`, the
  "lock after the screensaver" timer and the screensaver commands are the driver's too; the
  rules take only `lockOnSleep` and `passwordFallback`.

### Known limits

- **A compositor that never confirms and never refuses** leaves the lock `locking` for good:
  the owner can authenticate, and the unlock stays pending ("Unlocking…") for good; logind's
  Unlock waits the same way; a crash or kill of the shell leaves the session locked
  (section 1). Nothing better is protocol-clean through Quickshell 0.3.2: ext-session-lock-v1
  does allow `destroy` on a lock that was never confirmed ("the client gave up"), but it races
  with a `locked` already on its way (then `invalid_destroy`), and Quickshell reaches it only
  by destroying the `WlSessionLock` object, which leaves its process-wide manager believing a
  lock is active — the shell could never lock again. Not implemented. The owner's way out is a
  TTY (or a compositor-side recovery). With a compositor that confirms, a confirmation late
  by any amount is handled.
- A second PrepareForSleep after a missed wake locks again, but the inhibitor is not re-taken
  while suspending (logind only waits for inhibitors held when it sent the signal): that
  sleep may begin before the compositor confirms.
- A hung *passive* conversation stays "running" (nothing is lost: the password works beside
  it); only a wake or a re-detection that drops the method restarts it.
- `initial()` always starts unlocked: keeping the phase across a reload is Stage 4. Until
  then file watching is off while locked (above) — a reload by other means
  (`Quickshell.reload()`) would still unlock.
- If even ending a conversation throws on an internal error, the verify timer may be left
  running; its expiry is then ignored (the password is no longer pending).

### Stage 2: how the driver is built (as implemented)

- **No public `dispatch`.** `Lockscreen._build()` keeps the state, the queue, the surface
  registry and the timers in its closure and returns the operations (`lock`, `addSurface`,
  `removeSurface`, `input`, `lockOnSleepChanged`, `describe`), kept in `_api`. The adapters'
  and the WlSessionLock's signals are connected to it there. See "What other QML in the
  shell can reach".
- **Events are made plain JS objects** (a JSON round trip) as they are dispatched: an array
  passed through a QML signal's `var` argument comes out as a list wrapper that
  `Array.isArray` rejects, and `parseMethods` then read the methods script's lines as none.
  (`fallbackFacts` accepts array-likes for the same reason.)
- **`view` is replaced only when it changed** (compared as JSON), not at every pointer move.
- **A `start()` that fails because the PAM helper could not be forked** has already emitted
  `completed(Error)` inside `start()`; the adapter then reports that completion and no
  `pamStartFailed` (which the rules would ignore anyway).
- **The methods script**: exit status 0 is an answer, also with no lines (the rules take the
  fallback); any other exit, a signal, or a script that cannot be started is
  `methodsFailed` with the reason.
- **Per-lock adapters** (`singletons/lock/LockScope.qml`) are created when a step's new state
  leaves `unlocked`, before its effects run, and destroyed after the effects of the step that
  returns to `unlocked` (a pending unlock keeps them until then).
- **IPC `state`** is `describe(state)` plus `driver: { secure, sessionInForce, surfaces,
  screensaverVisible, inhibitorRunning, logindSession, lockScope, watchFiles,
  passwordFallbackKnown }`.
- **The test bed's seams**, each inert unless set: `H2S_LOCK_AUTH_METHODS` (read by the
  methods script), `H2S_LOCK_TOOLS` (a directory with stand-ins for `gdbus` and
  `systemd-inhibit`: the test bed has no system bus, and the launcher puts the real gdbus
  first on PATH, so PATH could not serve), `H2S_LOCK_SYSTEM_PAM_DIR` (where the system-wide
  configs are looked for, so that a test shell's password fallback is never the machine's
  real PAM stack).
