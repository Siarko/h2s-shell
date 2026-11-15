# Lock screen: analysis and rework plan

Written 2026-11-14, after two days of fixes that each exposed another fault. Nothing in
this plan is implemented yet. It replaces patching with: a test bed first, then a pure
state machine with unit tests, then the I/O around it.

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
- Destroying a `WlSessionLock` while locked leaves the session locked and the process
  unable to lock again. A reload whose new `WlSessionLock` starts with `locked: false`
  unlocks the session (observed in the test compositor).
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
  this one. Removing it later is deleting that one event.
- The shell may be locked and unlocked freely inside the isolated test compositor.

## 6. How the work is done

- In a copy, `~/src/h2s-shell-lockwork`: the running shell reloads on every file written
  in `~/src/h2s-shell`, and a reload while locked unlocks the screen. The copy is synced
  back once, at the end.
- Each stage: an implementing agent, then an independent code review, then fixes, then
  the tests run again. A snapshot of the copy is kept from before each stage
  (`~/src/h2s-shell-lockwork.snapshots/`), which is also what the review diffs against —
  the checkout has no git history to diff with.

## 7. The rules (Stage 1): the contract for the driver

`singletons/LockRules.qml` is the specification of the lock; `tests/LockRulesTest.qml` checks
it (by the numbered behaviours of Stage 1, a seeded sweep of 1600 generated event sequences
started from unlocked, locking and locked, and a liveness oracle run from reached states).
Everything below is what Stage 2's driver may rely on, and what it must do for the rules to
hold. It is complete as it stands: the driver needs nothing from earlier versions of it.

### API

- `initial(settings) → state`. `settings`: `{ lockOnSleep` (default true)`, passwordFallback:
  { directory, config }` (the password config when detection names none or fails; the
  driver passes the shipped one, `Quickshell.shellDir + "/pam"`, `"password"`; null: none)`,
  timings` (overrides of `LockRules.timings`; a value that is not a finite number ≥ 0 keeps
  the default, unknown names are dropped)` }`. Everything is copied: the caller's objects are
  not kept.
- `step(state, event, now) → { state, effects, ignored, error? }`. `now` is `Date.now()` when
  the event is handled. `ignored` is `""` when the event was taken; otherwise it says why,
  the returned state is the very object passed in, and there are no effects. Never throws.
  An internal error comes back with `error: true`: as ignored, state unchanged — except a
  `pamCompleted`/`pamStartFailed` for the current conversation, which still ends that
  conversation (`ignored: ""`, `error: true`, a `log` effect at level `error`; the password
  shows "Password check failed, try again", a passive method goes broken). The driver logs
  every `error: true`. States are never mutated: compare with the old one, bind to the new
  one — and then drop the old one (see "Never keep old states").
- `view(state)`: what the views render — `locked, promptSurface` (the surface instance
  showing the prompt, null while asleep)`, promptScreen` (its screen name, "" while asleep;
  information only)`, busy, buttonText, placeholder, answerVisible, error, refusal`
  ("busy" / "empty" / "")`, fieldEpoch` (the field empties whenever it changes)`, methods`
  (`[{ name, visible, waiting, text, isError }]` per passive method). `view()` returns a fresh
  object each call and `methods` is a fresh array: feed it to a `Repeater` through
  `ScriptModel { values: … ; objectProp: "name" }`, never directly (CLAUDE.md).
- `describe(state)`: a JSON-serialisable copy without the secret (`hasSecret` instead), with
  `view` included. **The driver exposes only this** — the IPC `state`, logs, test output.
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
- Tables: `timings`, `limits` (`confirmAttempts` 3, `errorLimit` 5; not overridable),
  `passiveMethods` (`fingerprint`, `u2f`: name, label, hint, eager), `unlockSources`
  (`["logind"]`), `escapeUnlocks` (true — see "Escape"), `namedKeys`, `sleepTimers`,
  `timerNames`, `pamResults`.

### Timings (ms, `LockRules.timings`)

| name | default | what |
|---|---|---|
| `confirm` | 5000 | wait for the compositor's confirmation of a lock before setting it again |
| `detect` | 5000 | the methods script's answer, else go on without it |
| `prompt` | 10000 | the prompt hides after this without activity |
| `promptSlack` | 50 | a prompt timer this early counts as on time |
| `verify` | 90000 | the longest a submitted password waits for PAM (pending/verifying) |
| `inhibitorFallback` | 4000 | the inhibitor held for the lock's confirmation on the way to sleep |
| `settle` | 1000 | after an abort, before that method may start again |
| `resumeGrace` | 4000 | after a wake, then ask once more for missing passive methods |
| `missedResume` | 60000 | (monotonic) after going down, behave as woken if `resumed` never came |
| `minSuspend` | 5000 | (wall clock) activity this long after PrepareForSleep means a missed wake |
| `retryMin` / `retryMax` / `quickRound` | 500 / 10000 / 20000 | passive retries after failures |
| `errorRetry` | 30000 | a passive method's retry after a PAM Error |

### State

Each region has a `status`.

| region | status | other fields |
|---|---|---|
| `phase` | unlocked / locking / locked | `session` (+1 at every lock and every confirm retry), `source`, `since`, `attempt` (1…`confirmAttempts`) while locking/locked; `lastEnd` when unlocked: authenticated / escape / logind / compositor / denied / unconfirmed |
| `sleep` | awake / suspending / resuming | `since`, `deadline`, `inhibitor`: held / released |
| `methods` | unknown / detecting / known | `generation`, `configs: { password, fingerprint, u2f }` (each `{ directory, config }` or null), `answered`, `waitForAnswer`, `passwordSource`: detected / fallback / none |
| `password` | idle / pending / verifying / asking / failed / unavailable | `conversation: { id, session }`, `config`, `question`, `answerVisible`, `error`, `pamError`, `refusal`, `settling` |
| `passive[name]` | unavailable / idle / running / backoff / paused / broken | `config`, `conversation`, `startedAt`, `delay`, `lastResult`, `errors` (Errors in a row), `brokenBy` (error / asks / start / internal), `message`, `messageIsError`, `settling` |
| `prompt` | — | `surfaces: [{ id, screen }]` (instances, in the order added), `owner` (a surface id; null = asleep), `awakeUntil`, `fieldEpoch` |
| `timers` | — | `{ name: { token, due } }` for every timer running |
| `secret` | — | the typed password from submit until PAM's first hidden prompt (or any exit); else null |
| `serial`, `settings` | — | the id counter (ids, tokens and generations are never reused within a state's life), the settings |

`methods`, `password`, `passive`, `prompt`, `secret` and their timers belong to one lock:
created afresh at each lock, thrown away at each unlock.

### Events (`{ type, …fields }`)

| event | fields | meaning |
|---|---|---|
| `started` | — | once, after `initial()`: takes the inhibitor if wanted |
| `lockRequested` | `source` (ipc, idle, logind, sleep, …) | ignored while locking or locked |
| `unlockRequested` | `source` | unlocks only for a source in `unlockSources`: `"logind"` |
| `compositorLocked` | `session` | `WlSessionLock.secure` became true; `session` = the session of the last `lockCompositor` the driver executed |
| `compositorFinished` | `session` | the compositor ended the lock (locked) or refused it (locking); `session` as above |
| `surfaceAdded` | `surface, screen` | a lock surface instance created; `surface` = the driver's id for that object |
| `surfaceRemoved` | `surface` | that instance destroyed |
| `activity` | `surface` | pointer motion, typing in the field |
| `press` | `surface` | a pointer press (it moves the prompt to that surface) |
| `key` | `surface, key` (one of `namedKeys`, or ""), `text` | a key the surface's key catcher got (the field could not take it) |
| `submit` | `surface, text` | Enter / the button in the field; taken only from `promptSurface` |
| `methodsDetected` | `generation, lines` | the methods script's output |
| `methodsFailed` | `generation, reason` | the script failed |
| `pamMessage` | `method, conversation, message, messageIsError, responseRequired, responseVisible` | PamContext.pamMessage |
| `pamCompleted` | `method, conversation, result` (success / failed / error / maxTries) | PamContext.completed |
| `pamStartFailed` | `method, conversation` | `start()` returned false |
| `prepareForSleep` / `resumed` | — | logind's PrepareForSleep(true / false) |
| `timer` | `name, token` | a timer expired: the token of the start it belongs to |
| `settings` | `values: { lockOnSleep?, passwordFallback? }` | a profile changed them |

Ids are compared strictly (`===`): a conversation id is the number the rules gave in
`startPam`; a surface id is a non-empty string or a finite number the driver chose.

### Effects (`{ type, …fields }`), executed in array order

| effect | fields | the driver |
|---|---|---|
| `lockCompositor` | `session` | sets `WlSessionLock.locked = true`, remembers `session` as the one in force, **then reads `locked` back**: false means Quickshell refused (no ext-session-lock, no surface component, `lock()` failing — all without a signal), and it queues `compositorFinished { session }` |
| `unlockCompositor` | `session, reason, method?` | sets `WlSessionLock.locked = false`. `reason` "retry" is a confirm retry: a `lockCompositor` with the next session follows in the same step |
| `announceLocked` | `locked` | tells the shell: `Profiles.screenLocked` |
| `detectMethods` | `generation` | runs the methods script (killing an older run) and reports its lines with this generation |
| `startPam` | `method, conversation, configDirectory, config` | configures that method's PamContext and starts it; `start()` false → `pamStartFailed` |
| `abortPam` | `method, conversation` | aborts it — only if `conversation` is the adapter's current one, else nothing |
| `respondPam` | `method, conversation, text` | `respond(text)` — only if `conversation` is the adapter's current one, else nothing. **Secret** |
| `startTimer` / `stopTimer` | `name, ms, token` / `name` | (re)starts / stops the single-shot timer of that name |
| `holdInhibitor` / `releaseInhibitor` | — | from now on keep the sleep-delay inhibitor held (re-taken whenever its process exits) / let it go |
| `forwardKey` | `surface, key, text` | hands the key to that surface's field (always the prompt's owner): `text` (printable, possibly several characters; never a control character) is inserted at the cursor; `key` Enter submits, Backspace / Delete delete before / after the cursor, Left / Right / Home / End move it; any other named key does nothing in the field |
| `log` | `level, message` | logs it (never contains typed text) |

Timer names, the finite set (`timerNames`): `confirm`, `detect`, `prompt`, `verify`,
`inhibitor`, `missedResume`, `resumeGrace`, `retry:fingerprint`, `retry:u2f`,
`settle:password`, `settle:fingerprint`, `settle:u2f`. The first four and the `retry:`/`settle:`
ones belong to a lock and are stopped when it ends; `sleepTimers` (`inhibitor`,
`missedResume`, `resumeGrace`) outlive it.

Ordering guarantees within one step:

- A step that enters the lock (from unlocked, by `lockRequested` or `prepareForSleep`) begins
  with `lockCompositor`, then `announceLocked(true)`, before anything else — the sleep
  region's timers included.
- A step that leaves the lock emits every `abortPam` and lock `stopTimer` before
  `unlockCompositor`, and `announceLocked(false)` after it.
- A confirm retry is `unlockCompositor { session: old, reason: "retry" }` followed by
  `lockCompositor { session: new }`.
- A method is never aborted and started in the same step; a timer is never started twice in
  one step; a `startTimer` for a running timer replaces it (no `stopTimer` first).

### What the driver must guarantee

- **One step at a time; commit before effects.** The driver stores the new state *before*
  running the step's effects. Events raised while effects run (a refused `start()`, a signal
  emitted synchronously from inside `respond()`, `abort()` or the lock's setter) are queued
  and handled after the current step's effects, in the order raised — never re-entered.
- **Compositor events carry the session** of the last `lockCompositor` executed. Quickshell
  emits `secureStateChanged` synchronously inside the unlock effect: that report is
  `compositorFinished` with the old session, and the rules ignore it once a new lock has
  begun. A refusal shows only as `secureStateChanged` with `secure` still false, or as
  `locked` reading false right after being set; both become `compositorFinished { session }`.
  `WlSessionLock.locked` is read only right after setting it true (reliable in that
  direction; only the unlock notify is broken, section 1), never through a binding.
- **Tag PAM events** with the method and the conversation id from the `startPam` that
  started that conversation. After `abortPam` the adapter may go on reporting with the old
  id: the rules ignore it. The adapter drops `abortPam`/`respondPam` whose conversation is not
  its current one (a late effect must not abort or answer the next conversation). Results are
  mapped to `success`/`failed`/`error`/`maxTries`.
- **Timers**: one single-shot timer per name; `startTimer` (re)starts it with `ms`, from when
  the effect runs; `stopTimer` cancels it; at expiry dispatch `{ type: "timer", name, token }`
  with the token of the start that set it. Monotonic timers (Qt's) are right: the
  missed-resume timer is meant to stand still while the machine sleeps. Firing a little early
  is harmless (the prompt re-arms; `timings.promptSlack`).
- **Surfaces are instances.** Each lock surface object gets an id of its own when created
  (a counter in the driver; never reused within a shell instance), sends
  `surfaceAdded { surface, screen }` before any input and `surfaceRemoved { surface }` when
  destroyed. Quickshell destroys surfaces with `deleteLater()` and creates new ones at once,
  so a screen may have two instances for a moment, and the new one's `surfaceAdded` may come
  before the old one's `surfaceRemoved` (an output re-added, unlock and lock in one pass, a
  reload). Every input event names the instance it came from; input from an instance not
  known is ignored.
- **Views** render `view(state)` only. The prompt shows on the instance `promptSurface` and
  nowhere else (also when two instances share a screen). The field is cleared when
  `fieldEpoch` changes (never on its own when submitting); `forwardKey` is applied to the
  field. The surface's key catcher sends every key as `key` (its name if it is one of
  `namedKeys` — Return and the keypad's Enter are both "Enter" — else `key: ""`, and the
  character in `text`); the field sends `submit` and `activity` on typing; a pointer press
  anywhere on a surface sends `press`, plain motion `activity`.
- **Never expose the state**: only `describe()`, `describeEvent()`, `describeEffect()`.
- **Never keep old states or effects.** The secret lives in `state.secret` from submit to
  PAM's first hidden prompt, and travels in the `respondPam` effect (and a typed answer in
  `respondPam`, a key's character in `forwardKey`). Any old state kept around keeps the
  secret with it: the driver holds the current state only, drops each step's effects once
  run, and logs only through the describe functions.
- **Methods script**: no timeout of its own needed — the rules time out (`detect`, 5 s).
- **Reload (Stage 4)**: `initial()` resets `serial`, so ids, tokens and generations start
  again from 1. If the phase is carried over a reload, every adapter (PAM contexts, timers,
  the detector) must be destroyed and re-created with the new state, so that nothing tagged
  under the old serial can report into the new one.

### Decisions taken in Stage 1, and why

- **Escape** unlocks at an awake prompt, for now (the owner's decision, section 5). It is
  routed only through the `key` event — which already requires a known surface and an awake
  prompt — in one marked block in `_key`, switched by `escapeUnlocks`; it is no
  `unlockRequested` source. On a sleeping prompt it only wakes it and is not forwarded.
  Removing it is deleting that block and the property. The events that end a lock are
  exactly: a `pamCompleted` success of the current conversation, `unlockRequested("logind")`,
  the Escape key at an awake prompt, and — not unlocks by anyone — `compositorFinished` of
  the current session and the confirm timer's last expiry. The sweep asserts it.
- **Keys on another surface are forwarded to the owner**, not a reason to move the prompt: the
  half-typed text lives in the owner's field. Motion elsewhere only extends the owner's
  time. A **press** on a surface that does not own the prompt moves it there (the owner's
  decision): the field starts empty (`fieldEpoch` +1), a question is kept, a verification
  goes on. When the owner's instance goes away the prompt goes, awake, to the newest other
  instance on the same screen (its successor), else to the first surface left (`fieldEpoch`
  +1); with none left it sleeps.
- **A passive method asked for input** (`responseRequired`) is aborted and marked broken for
  the lock at once, never answered: a passive config that asks is a password module or
  pam_u2f's interactive mode, and the empty answer the old code gave every round was a failed
  password attempt each time (faillock). The cost: an interactive pam_u2f config does not
  work.
- **An empty password is never sent** (refusal "empty"): `nullok`, and an Enter forwarded
  right after waking. An empty *answer* to a question is sent.
- **The typed password answers only a hidden prompt**; a first prompt that shows its answer
  drops the password and is asked as a question.
- **Conversations start only once the compositor confirmed the lock**; detection starts at
  the lock request. A password typed earlier is held (`pending`).
- **A lock the compositor does not confirm** within `confirm` (5 s) is set again under a new
  session, up to `confirmAttempts` (3) attempts in all, then given up: `lastEnd`
  "unconfirmed", a warning, the secret dropped, and the next lock request locks again.
  Together with the driver's read-back of `locked`, no refusal leaves the phase in `locking`.
- **The verify timer** (90 s) runs exactly while the password is `pending` or `verifying`;
  at expiry the conversation is aborted (settle, then a new submit starts afresh), the
  password shows "Password check timed out", the field is usable. A question waiting for the
  user stops it; the answer arms it afresh.
- **During a re-detection** the password uses a config known from an earlier answer.
  Passive methods keep using the earlier configs too (an eager retry starts at once), except
  during the lock's first detection and the one after a wake, whose answer is awaited (after
  a wake, that answer is the trusted one). A re-detection that no longer names a method
  stops it: aborted if running, its retry stopped if backing off, unavailable; a broken
  method stays broken.
- **No password config known at submit**: the methods script is asked again first; only if
  that answer has none either (and there is no fallback) does the password show "Password
  check is not available".
- **Detection failing or timing out** keeps this lock's last answer — its passive configs and
  a password config the script named — and takes the password fallback where it named none;
  the warning says which.
- **Retries**: first quick failure 500 ms, doubling to 10 s; a round of 20 s or more resets to
  500 ms; MaxTries waits 10 s at once (somebody trying and failing). A PAM **Error** (which
  Quickshell reports for every code but success, auth error and max tries — a device not
  plugged in included) waits `errorRetry` (30 s); the `errorLimit`-th (5th) Error in a row
  breaks the method for the lock — bounding the PAM children and warnings of a config that
  can never work to five per lock, while two and a half minutes of retries cover a device
  that is slow to appear. Any other result resets the count. An eager method broken by
  Errors gets one more try each time somebody comes back to the prompt (a security key
  plugged in when they sit down); another Error breaks it again at once. Every abort within
  a lock is followed by a `settle:<method>` timer (1 s) before that method may start again.
- **Broken is cleared by a wake from sleep** (not by a re-detection within the lock), which
  also resets the Error counts.
- **Sleep**: the inhibitor is held while awake with lockOnSleep, released at
  `compositorLocked` or after `inhibitorFallback` (4 s, under logind's 5 s
  InhibitDelayMaxSec), and released at once when going down already locked or when the lock
  ends during the suspend. Re-taken after every wake. A lost `resumed` is recovered 60 s
  (monotonic) after going down, at activity at least 5 s (wall clock) after PrepareForSleep,
  or by the next PrepareForSleep — which is then a missed wake followed by a new sleep, and
  locks again if unlocked. A `resumed` without a PrepareForSleep still re-detects and restarts
  running passive methods. Four seconds after a wake, a lock still without a passive method
  asks once more (the old `_afterWake`).
- **The prompt timer is not restarted on every pointer move**: activity moves `awakeUntil`;
  at expiry the timer re-arms for what is left — never more than `prompt` (a wall clock set
  back would otherwise keep the prompt awake for as long as it was set back).
- **Idle and screensaver stay in the driver.** `IdleMonitor` is a Wayland object, and its
  outcome is just `lockRequested("idle")`. Bind `enabled`/`timeout` declaratively — it
  re-creates its notification on a timeout change by itself, so `_applyMonitors()`'s toggling
  goes. `screensaverVisible`, the "lock after the screensaver" timer and the screensaver
  commands are the driver's too; the rules take only `lockOnSleep` and `passwordFallback`.

### Known limits

- A second PrepareForSleep after a missed wake locks again, but the inhibitor is not re-taken
  while suspending (logind only waits for inhibitors held when it sent the signal): that
  sleep may begin before the compositor confirms.
- A hung *passive* conversation stays "running" (nothing is lost: the password works beside
  it); only a wake or a re-detection that drops the method restarts it.
- `initial()` always starts unlocked: keeping the phase across a reload is Stage 4.
