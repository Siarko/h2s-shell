# Lock screen: analysis and rework plan

Written 2026-11-14, after two days of fixes that each exposed another fault. Stages 0–5 are
implemented, with the findings of their reviews fixed (section 7 is the current contract);
Stage 6, the one check on the real machine, is prepared (`lockscreen-real-machine.md`). It replaces patching with: a test bed
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
  `Quickshell.watchFiles` is false (section 7). Stage 4, from source and observed: on a
  (soft) reload `WlSessionLock::onReload` takes the old instance's lock manager over and
  `realizeLockTarget(old)` either unlocks (target false) or, with the target already true,
  keeps the lock and makes NEW surfaces for every screen (`updateSurfaces(false)` before
  `updateSurfaces(true, old)`, so the reuse of the old windows never happens): one more
  `get_lock_surface` per output on the same lock while the old surfaces still exist —
  Hyprland 0.57 accepts it (no `duplicate_output`, observed with its debug log). A
  reloaded singleton's children get their old instances by position
  (`ReloadPropagator::onReload`), in declaration order, and `PersistentProperties` copies
  its values before `reloaded`. A hard reload (`reload(true)`) hands nothing over.
  `QuickshellSettings::reset()` sets `watchFiles` back to true at every reload. The old
  `WlSessionLock`'s destructor logs "Session lock object was destroyed without unlocking"
  even when its manager was handed over (harmless). Reload triggers in 0.3.2: the file
  watcher and `Quickshell.reload(hard)` — no IPC command.
- Quickshell's crash handler (`src/crash/handler.cpp`, `launch/main.cpp`) catches SIGSEGV,
  SIGABRT, SIGFPE, SIGILL, SIGBUS and SIGTRAP and restarts the shell **in the same process**
  (`execve` of `/proc/self/exe`, same pid, the environment kept, only the config path
  passed on) — unless it crashed within 10 s of starting: then it exits with 255. Observed
  once in four full harness runs: the relaunched process came back with an EMPTY config
  path (`Launching config: ""`, "Could not open config file") and exited with 255 — the
  launcher's restart then took over (`restart-crash-locked` accepts both). SIGKILL,
  SIGTERM and the OOM killer are not caught. `qs kill` quits cleanly (exit 0); SIGTERM has
  no handler (death by signal). Either way the `WlSessionLock` is destroyed, not unlocked:
  the session stays locked, and Hyprland shows "lockscreen app died".
- Hyprland 0.57: with `misc:allow_session_lock_restore` off (its default) a new lock while
  a dead client's lock stands is refused (`finished`) — and the client that asked is killed:
  Hyprland destroys the refused lock at once, and Quickshell, which sends `get_lock_surface`
  right after asking for the lock, gets `wl_display#1: error 0: invalid object` (observed).
  With it on, the new lock is given and the session never shows unlocked in between.
  `hyprctl keyword` is gone with the Lua config ("unknown request"); `hyprctl eval '<lua>'`
  sets an option at runtime.
- `IdleMonitor` re-creates its notification on a timeout change by itself — and that is
  broken (found in Stage 3, observed): it deletes the old notification before creating the
  new one, which often lands at the same address, so the property holding it does not
  change and `isIdle`, bound to the old one, stays false for good. Every monitor of the
  shell starts with the default timeout and gets the configured one when the profiles are
  read: the screensaver and the idle lock never came. The driver makes a new monitor for
  every change instead (`singletons/lock/IdleWatch.qml`).
- `Process`: children are killed when the object is destroyed, but survive a crash.

### Defects found in review (beyond the root cause)

Security:

1. Escape unlocks without authentication (`LockPrompt.qml`, also in the packaged version).
   (Kept on purpose as the owner's testing door through the real-machine check; removed
   2026-11-15, section 5.)
2. Any file written in the checkout while locked reloads the shell and unlocks the screen,
   or leaves it locked with no client (the shell runs from the live checkout). (Stage 2: no
   reload from file changes while locked; Stage 4: a reload while locked keeps the lock.)
3. Notifications are shown in full on the lock screen by default, one-time codes included.
   (Stage 3: "app only" by default, the owner's decision; a seeded config still holding
   the old default moves to it once.)
4. A shell crash while locked leaves no way back short of a TTY: Hyprland has
   `allow_session_lock_restore` off and the shell is not restarted. (Stage 4: the launcher
   restarts it and it locks again; the Hyprland setting is the owner's to switch on.)
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
13. The shipped `pam/password` does not work on NixOS (Stage 5 found this wrong for the
    password: see "Stage 5" at the end; true for the fingerprint and key configs); `nullok` allows a blank password;
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
during the fade, two outputs. (Done: the key catcher became an input-method-enabled text
input, so dead keys, Compose and input methods type; the 300 ms pointer rule became "only
real motion counts"; Caps Lock is said on the prompt; notifications are plain text, "app
only" by default; harness tests for composition, AltGr, Caps Lock, the keypad, key repeat,
non-ASCII bytes reaching PAM, two outputs, the fade-in over a desktop window, scaled and
small outputs, the idle path and notifications; the views' states in `tests/LockViewTest.qml`.)

**Stage 4 — failure and recovery.** Reload while locked keeps the lock (harness test);
the shell killed while locked can be restarted and re-locks (`allow_session_lock_restore`,
a restart of the shell by Hyprland); orphaned helpers are cleaned up at start. (Done, as
section 7, "Recovery", describes: the lock carried over a reload by a `PersistentProperties`
set into the new `WlSessionLock` before Quickshell realizes it and the rules' `restored`; a
lock marker in `$XDG_RUNTIME_DIR` that a restarted shell locks again from; the launcher as
the shell's supervisor, which also kills the dead shell's PAM helpers; under Hyprland
without `allow_session_lock_restore`, no lock asked for that would be refused. The restart
is the launcher's, not Hyprland's: an `exec` runs once. Harness tests `reload-explicit`,
`reload-hard`, `edit-while-locked`, `restart-kill-locked`, `restart-kill-unlocked`,
`restart-crash-locked`, `restart-launcher`, `restart-no-restore`,
`restart-no-restore-generic`, `marker-stale`; the rules' entry in `tests/LockRulesTest.qml`
(behaviour 14, sweep and liveness from carried locks). **The owner must add one line to
the Hyprland config** — section 7, "What the owner adds to hyprland.lua". Review fixes
(before Stage 6): no reload at unlock, the reload window narrowed, one supervisor per
session, a stopped shell left alone, the compositor's identity, slow retries while locked,
the marker's "unlocked" after the unlock request is out, the hyprctl question bounded —
tests `reload-window`, `supervisor`, `restart-locked-retry`, `restart-compositor-gone`,
`restart-hyprctl-hang`, `lock-log`, and `restart-crash-finger`'s launcher half.)

**Stage 5 — the system side.** PAM configs and the NixOS module (no `nullok`, no reliance
on `account`, the fingerprint config independent of the global switch), the method script
(D-Bus instead of parsing `fprintd-list`, a timeout), the logind monitor without
`XDG_SESSION_ID`. Report the Quickshell bug upstream.

**Stage 6 — the real machine, once.** Prepared, not performed: the checklist is
**`docs/plans/lockscreen-real-machine.md`** — the ways out first, then deployment
checks, then the tests cheapest first, each with what must happen, the log lines to match
and what it proves; any failure: `scripts/lock-log.sh` and stop. Before it, from the
review of Stage 4: the reload at unlock removed, the reload window narrowed, one
supervisor per session, the launcher's other findings fixed, and every step of a lock
logged with a wall-clock stamp (section 7, "Log every step"). The notes below are what the
checklist was built from.
What no harness covers: real password, real fingerprint, lid close and open, hibernation,
power key.
From Stage 4: (1) with `allow_session_lock_restore = true` added to `hyprland.lua` and the
shell started by Hyprland's autostart (so supervised: `pgrep -af scripts/launch.sh` shows
the launcher), kill the shell by its pid — the launcher's pid from
`$XDG_RUNTIME_DIR/h2s-shell-launcher.lock`, the shell its child: `launcher=$(cat
"$XDG_RUNTIME_DIR/h2s-shell-launcher.lock"); shell=$(pgrep -P "$launcher"); (sleep 30; kill
-KILL "$shell") &` (never a pattern kill: `pkill -f` also matches the PAM helpers, forks of
the shell with its command line, and test-bed shells; checklist step 2.14) — then
lock, wait: the prompt comes back within a few seconds, Hyprland's red "lockscreen app died"
screen shows at most for that long; (2) the same with a finger on the reader right after:
it unlocks at once (fprintd released the dead shell's claim when the launcher killed its
PAM helper — not shown in the harness); (3) "Restart to apply" in the settings while
unlocked, and `h2s-shell --restart` from a terminal: one shell afterwards (`qs list --all`);
(4) log out (Hyprland's exit) and back in: no launcher or shell left from the old session,
the new one not locked.
From the Stage 3/5 review fixes: (5) Caps Lock: at the desktop, `cat
/sys/class/leds/*::capslock/brightness` with Caps Lock off and on (a plain read; under
Hyprland the LED is expected to follow, unverified — the file exists here, 0644, read 0
with Caps Lock off); then lock with Caps Lock on: "Caps Lock is on" shows at the first
wake, goes when Caps Lock is turned off and a key typed; with an external keyboard too;
(6) the fingerprint after the rebuild with `timeout=-1`: lock, leave it untouched for six
minutes, touch the reader: it unlocks; `journalctl --user -b | grep Lockscreen` shows no
"fingerprint: PAM error" lines from that lock; (7) the shipped `pam/password`:
`tests/manual/pam-probe.sh` once (section 8: the journal before any retry, two attempts at
most); (8) select some text at the desktop, lock, middle-click on the prompt and on the
screen's top-left corner, type the password: it unlocks (nothing was pasted).
Logging of every auth event (never the secret) goes in before this, so a failure there is
read from the log rather than guessed.

## 5. Decisions (the owner's, 2026-11-14)

- Notifications on the lock screen default to "app only" (it stays a setting).
- Lock before sleep stays on by default.
- `loginctl unlock-session` (logind's Unlock signal) unlocks: the emergency way in from
  another console, and what the tests use.
- **Escape no longer unlocks — removed 2026-11-15.** It was kept as the owner's testing
  door (Escape at an awake prompt unlocked, against section 1) until the real-machine check
  was done; the owner then asked for it to go. The ways out are now: an accepted
  authentication (password, fingerprint, security key), logind's Unlock
  (`loginctl unlock-session` from another console — the emergency way in, and what the
  tests use), and the compositor ending the lock. What Escape does instead: on a sleeping
  prompt it wakes it, as any key; at an awake prompt it hides the prompt, exactly as the
  prompt's time-out does (the field empties, a question left unanswered is cancelled, a
  check under way goes on). A held Escape's repeats count for nothing (else it would toggle
  the prompt).
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
config that cannot start; since Stage 4 also started from locks carried over a reload).
Everything below is what the driver (`singletons/Lockscreen.qml`) relies on and must do for
the rules to hold, as Stages 1, 2 and 4 implement it, with the findings of the Stage 2
reviews and of the Stage 3 (views) and Stage 5 (system side) reviews fixed. It is complete
as it stands.

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
- An unlock decided while `locking` — an accepted authentication or logind's Unlock —
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
  `namedKeys`, and a `pamMessage` of the password's conversation has its `message`
  replaced by `"<not logged>"` (a passive method's message — "Place your finger…" — is
  kept: it is what explains a failure).
- `running(state) → { conversations: [{ method, conversation }], timers, lockTimers }`.
- Parsers: `parseMethods(lines)` (array or string → `{ method: { directory, config } }`,
  junk skipped, first line per method wins), `parseLogind(line, sessionPath)` (→ one of the
  events below or null; Lock/Unlock only on `sessionPath`, the shell's own session),
  `parseSessionPath(output)` (→ path, or "" for an error or nothing),
  `retryDelay(previousDelay, roundMilliseconds, result, timings?)` (→ ms after a `failed` or
  `maxTries` round, null otherwise — an `error` round's wait is the rules' own, see
  "Retries"; `timings` is the table to use — the rules pass the state's
  `settings.timings`, left out it is `LockRules.timings`).
- Tables: `timings`, `limits` (`errorLimit` 5, `revivals` 3; not overridable),
  `passiveMethods` (`fingerprint`, `u2f`: name, label, hint, eager), `unlockSources`
  (`["logind"]`), `namedKeys`, `sleepTimers`, `timerNames`, `pamResults`.

The driver's small pure helpers are `singletons/LockIoRules.qml` (tested in
`tests/LockIoRulesTest.qml`): `serialQueue(handle, onError)` (one event at a time),
`runStep(result, hooks)` (commit, then prepare / publish / each effect / finish, each guarded
on its own: a view that fails to publish cannot keep `lockCompositor` from running),
`passwordFallback(facts)` and `fallbackFacts(lines)` (below), `keyName`, `editField` (by code
point: never half a surrogate pair), `pointerMoved`, `capsLockFromLeds` (below),
`detectionEvent`, `restartDelay`, and the recovery's `markerFacts`, `markerDecision`,
`hyprlandLockFacts`, `lockSurelyRefused`.

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
| `retryMin` / `retryMax` / `quickRound` | 500 / 10000 / 20000 | passive retries after failures; a round of `quickRound` or more is "full-length" (nobody tried) |
| `errorRetry` | 30000 | a passive method's retry after a QUICK PAM Error (a full-length Error round is a time-out: `retryMin`, not counted) |

### State

Each region has a `status`.

| region | status | other fields |
|---|---|---|
| `phase` | unlocked / locking / locked / unlocking | `session` (+1 at every lock), `confirmLate` (the confirm timer expired; locking/unlocking), `pending` (`{ reason, method }` while unlocking, else null), `lastEnd` when unlocked: authenticated / logind / compositor / denied |
| `sleep` | awake / suspending / resuming | `inhibitor`: held / released, `minSuspendPassed` (suspending: the minSuspend timer has run) |
| `methods` | unknown / detecting / known | `generation`, `configs: { password, fingerprint, u2f }` (each `{ directory, config }` or null), `answered` (the script answered once in this lock), `lastResult` (answered / failed / ""), `askedAt` (wall clock of the last request), `waitForAnswer`, `passwordSource`: detected / fallback / none |
| `password` | idle / pending / verifying / asking / failed / unavailable | `conversation: { id, session }`, `config`, `avoid` (a config that could not be used in this lock, or null), `question`, `answerVisible`, `error`, `pamError`, `refusal`, `settling` |
| `passive[name]` | unavailable / idle / running / backoff / paused / broken | `config`, `conversation`, `startedAt`, `delay`, `lastResult` (the last round's result, or `timeout`: an Error after a full-length round), `errors` (quick Errors in a row), `revivals` (this lock and wake), `brokenBy` (error / asks / start / internal), `message`, `messageIsError`, `settling` |
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
| `restored` | `secure` | the shell was reloaded while locked and this process still holds the compositor's lock (carried over, Stage 4): from a FRESH state only (unlocked, session 0 — else ignored, "already locked" / "not a fresh state"), it enters the lock without asking the compositor — `adoptCompositorLock`, `announceLocked(true)`, then everything of a new lock (methods asked, waiting for the answer); `locked` when `secure` is exactly true (the compositor had confirmed it), else `locking` with the confirm timer. It can only enter a lock, never end or change one; no secret, conversation or pending unlock survives it |
| `lockRequested` | `source` (ipc, idle, logind, sleep, …) | locks from unlocked; cancels a pending unlock; ignored while locking or locked |
| `unlockRequested` | `source` | unlocks only for a source in `unlockSources`: `"logind"` (pending while locking) |
| `compositorLocked` | `session` | `WlSessionLock.secure` became true; `session` = the session of the last `lockCompositor` the driver executed |
| `compositorFinished` | `session` | the compositor ended the lock (locked) or refused it (locking, unlocking); `session` as above |
| `surfaceAdded` | `surface, screen` | a lock surface instance created; `surface` = the driver's id for that object; `screen` non-empty |
| `surfaceRemoved` | `surface` | that instance destroyed |
| `activity` | `surface` | pointer motion |
| `press` | `surface` | a pointer press (it moves the prompt to that surface) |
| `key` | `surface, key` (one of `namedKeys`, or ""), `text`, `autoRepeat` | every key pressed on the surface; `autoRepeat` true for a held key's repeats. Never ends a lock. Escape: on a sleeping prompt wakes it; at an awake prompt hides it (as the prompt time-out); never forwarded; repeated, ignored ("repeated Escape") |
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
| `adoptCompositorLock` | `session` | (`restored` only, first) remembers `session` as the one in force and sets `WlSessionLock.locked = true` — on a reload, before Quickshell realizes the new `WlSessionLock`, so that it takes the old one's lock over; nothing is sent to the compositor. Writes the lock marker ("locked"), and checks once the reload is done that the lock is held (else the process quits for a fresh one, see "Reload") |
| `lockCompositor` | `session` | writes the lock marker ("locked", before anything else: see "Restart"), sets `WlSessionLock.locked = true`, remembers `session` as the one in force, **then reads `locked` back**: false means Quickshell refused (no ext-session-lock, no surface component, `lock()` failing — all without a signal, and in each case before any lock object exists); it sets `locked = false` again (which sends nothing then, and clears Quickshell's target so the next lock is not a no-op) and queues `compositorFinished { session }` |
| `unlockCompositor` | `session, reason, method?` | only for a confirmed session (the compositor rule); sets `WlSessionLock.locked = false` — refused, with an error, if the lock is not `secure` |
| `announceLocked` | `locked` | tells the shell (`Profiles.screenLocked`); true: turns Quickshell's file watching off (`Quickshell.watchFiles = false`: no reload from file changes while locked, see "Reload") and asks for the password fallback again; false: restores file watching as it was (nothing else: edits made while locked take effect at the next file change) |
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
  region's timers included. `lockCompositor` is emitted nowhere else. A `restored` step
  begins with `adoptCompositorLock`, then `announceLocked(true)`, and has no
  `lockCompositor`; `adoptCompositorLock` is emitted nowhere else.
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
- **Compositor events carry the session** of the last `lockCompositor` (or
  `adoptCompositorLock`) executed. Quickshell
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
  extends the prompt's time. The key catcher is a hidden, input-method-enabled text input
  (hints: hidden, sensitive, no prediction; password echo; invisible, so no preedit shows):
  text that no single key event carries — a dead key and the letter after it, a Compose
  sequence, an input method's commit — arrives as its commit and is sent as a `key` with
  `key: ""` and that text (`autoRepeat` false), the catcher's own text emptied at once; a
  dead key or a key inside a Compose sequence sends nothing until then (Qt consumes it).
  Observed with Qt 6.12 under Hyprland 0.57: Hyprland offers text-input-v3 to a session-lock
  surface, Qt takes `QWaylandInputContext` and composes dead keys and Compose sequences itself
  from the locale's Compose table; a Backspace inside a sequence cancels it and still
  deletes. A pointer press anywhere on a surface sends `press`; motion sends `activity` only
  where the pointer really moved (`LockIoRules.pointerMoved`: not the first position a
  surface sees — the pointer entering, or the surface appearing under it — and not the same
  position again, which Qt Quick re-sends at every frame of a fade). This replaced "pointer
  events in a surface's first 300 ms are dropped", which let a fade longer than 300 ms, or a
  slow first frame, wake the prompt under a resting pointer, and dropped real presses.
  Keys are never filtered. The catcher lies outside the surface (no pointer reaches it)
  and the surface's `MouseArea` takes every button but the left one itself: a middle click
  on a Qt text input pastes the primary selection, which would put whatever was last
  selected on the desktop into the password (neither the catcher nor the field may ever
  see one); the left button goes on (the Unlock button, the field's cursor).
  Caps Lock (which Qt does not report) is read from the keyboards' LEDs
  (`singletons/lock/CapsLockLed.qml`: `/sys/class/leds/*::capslock/brightness`, one per
  keyboard, driven by the compositor from its xkb state; `LockIoRules.capsLockFromLeds`: any
  LED on is on; none, or one unreadable and none on, is unknown — no indicator), when the
  prompt wakes and at each key at an awake prompt, and once more 250 ms later (the LED may
  change just after the key arrives); never on a timer while nobody types. It is forgotten
  at `announceLocked(true)`. The driver exposes it as `capsLock` (true / false / null),
  outside the rules: the prompt says "Caps Lock is on". (It replaced inferring it from the
  keys, which carried a stale "on" into the next lock and took a composed capital — dead
  key + Shift+e, Compose, an input method's commit — for Caps Lock.)
- **Never expose the state**: only `describe()`, `describeEvent()`, `describeEffect()`.
- **Log every step** (Stage 6: what is read when the real machine fails), one line per
  event, prefixed `[Lockscreen]`, never typed text or its length: every event of
  `_loggedEvents` taken or ignored (with the reason) and every effect of `_loggedEffects`
  (through the describe functions: the lock request and its source, the compositor asked /
  confirmed / refused, methods detected — the configs per method — or failed with the
  reason, each PAM start with its config, each PAM message — the password's not logged —,
  each completion), the rules' `log` effects (retries, backoff, broken, refusals, the
  unlock with its reason and method), and the driver's own: "driver started" (supervised
  or not), "lock marker: locked <key>" / "unlocked", "<method> conversation <id> ended:
  <result> after <ms> ms (<config>)", and what the views showed, logged after the step's
  effects so that the log reads in order — "prompt awake on surface <id> (<screen>), woken
  by <event>", "prompt asleep (<cause>)", "submit refused: <reason>", "prompt shows:
  <error>", "the lock screen is up / gone". The adapters log the methods script's stderr,
  PAM errors, the inhibitor's start and release, the monitor's restarts and the
  `PreparingForSleep` answer; the recovery logs restores, reloads carried, quits for a
  restart. Wall-clock stamps: Quickshell's log file has them (`qs log --log-times`), and the
  launcher starts the shell with `--log-times` for its stderr. Where it all is, and the
  one command that prints it: `scripts/lock-log.sh` (the running instance's and recently
  ended instances' `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.qslog`, the supervisor's
  `$XDG_RUNTIME_DIR/h2s-shell-launcher.log`, the marker, and the journal's PAM / fprintd /
  polkit / logind lines; `lock-log` in the test bed).
- **Never keep old states or effects.** The secret lives in `state.secret` from submit to
  PAM's first hidden prompt, and travels in the `respondPam` effect (and a typed answer in
  `respondPam`, a key's character in `forwardKey`). Any old state kept around keeps the
  secret with it: the driver holds the current state only, drops each step's effects once
  run, and logs only through the describe functions.
- **Methods script**: the rules time out (`detect`, 5 s), and the script keeps a deadline of
  its own (4 s for fprintd), so that it ends — exit non-zero, a failure — before the rules
  give up on it and nothing it started lingers (Stage 5).
- **The password fallback** is chosen from the machine, as `scripts/lock-auth-methods.sh`
  chooses the password config — `LockIoRules.passwordFallback({ shellDirectory,
  systemDirectory, systemConfigReadable, nixos })`: `<system dir>/h2s-shell-password` when
  readable, else on NixOS `<system dir>/login`, else the shipped `pam/password`. The driver
  passes the shipped one to `initial()`, probes the two facts (`test -r`, `test -e
  /etc/NIXOS`) at start and at every lock, and sends a `settings` event when the answer
  differs. The system directory is `/etc/pam.d`, or `H2S_LOCK_SYSTEM_PAM_DIR` (the test bed's
  seam; the methods script honours it too).
- **Reload.** Quickshell reloads the shell when a file of it changes, or on
  `Quickshell.reload(hard)` (nothing in the shell calls it; the test bed's seam
  `H2S_LOCK_TEST_RELOAD=1` adds an IPC `locktest reload`). There is no IPC reload in 0.3.2.
  - File changes do not reload while locked: `Quickshell.watchFiles` is false from
    `announceLocked(true)` to `announceLocked(false)` (kept from the stop-gap: a reload now
    carries the lock, but it is the recovery path, not one to take at every file written
    while the owner is away). At `announceLocked(false)` file watching is simply switched
    back on; edits made while locked take effect at the next file change (Quickshell's new
    watcher does not see what changed before it). A reload right at the unlock (Stage 4,
    `find -newermt` and `Quickshell.reload(false)`) was removed after review: it opened the
    reload window below right after every unlock that followed an edit — the owner's
    Super+L dropped, a lid closed then slept unlocked (`reload-window`).
  - **The reload window** (any reload, above all a file saved while unlocked — the normal
    case while the shell is developed). From source and observed: `RootWrapper::reloadGraph`
    builds the whole new generation synchronously, with the event loop blocked (about two
    seconds for this shell), then `onReload` tears the old generation down (`deleteLater`,
    its engine deleted a pass later); a `Process` of the new generation starts only at its
    `postReload`, after the old one is destroyed (`Process::startProcessIfReady` waits for
    `isPostReload`). Meanwhile: an IPC call is answered "Not ready to accept queries yet."
    (two generations exist; `src/io/ipccomm.cpp`) and `qs ipc` still exits 0; the old
    logind monitor's lines are never read (event loop blocked, then the old engine
    interrupted) and the new monitor is not yet listening — a PrepareForSleep in between
    reaches nobody; the old generation's inhibitor dies with its `Process` (SIGKILL to the
    direct child), and logind refuses a new inhibitor once a sleep is under way. From
    systemd v260's source (read 2026-11-15, not observed on the real logind):
    `bus_manager_shutdown_or_sleep_now_or_later` (`src/login/logind-dbus.c:2153-2192`) sends
    PrepareForSleep(true), then — if any delay inhibitor is held — sets `delayed_action` and a
    timer of `inhibit_delay_max` (`:2117-2131`; 5 s by default, `logind-core.c:43`);
    `manager_dispatch_delayed` (`:2061-2099`, run after every event, `logind.c:1336`) sleeps as
    soon as `manager_is_inhibited` (`logind-inhibit.c:399-451`) finds no delay inhibitor left,
    or when the timer fires ("Delay lock is active … but inhibitor timeout is reached"). And
    `method_inhibit` (`logind-dbus.c:3856-3862`) answers `BUS_ERROR_OPERATION_IN_PROGRESS`
    ("The operation inhibition has been requested for is already running") while
    `delayed_action` covers sleep — from the signal until the job ends after the wake
    (`:4440-4448`). So the new generation cannot take an inhibitor of its own: only the ones
    held when the signal went out count, and the machine sleeps at min(the last of their
    releases, signal + 5 s). The test bed's `systemd-inhibit` stand-in refuses likewise
    between `logind_signal sleep` and `wake`. Narrowed
    from our side, three ways:
    - `scripts/launch.sh ipc` (what the Super+L bind runs) tries a call again for up to 3 s
      when Quickshell answers "Not ready to accept queries yet." or finds no running
      instance (a restart), and exits 1 if it was never taken.
    - The logind monitor, once listening (gdbus monitor's "The name org.freedesktop.login1
      is owned by …" line, which it prints after its match is in place), asks logind's
      `PreparingForSleep` property (`gdbus call … org.freedesktop.DBus.Properties.Get`;
      read-only, no polkit). True while the rules think the machine awake: the driver
      dispatches `prepareForSleep` (logged), and the monitor drops its own PrepareForSleep
      for that same sleep should it still arrive (within 10 s, no `resumed` between). Done
      at every start of the monitor: a reload, a start, a restart of the monitor.
    - The sleep inhibitor (`singletons/lock/SleepInhibitor.qml`) runs `systemd-inhibit`
      beside a small `sh` (the direct child Quickshell kills), reading the same input:
      released at once on the release line, and `graceSeconds` (3 s) after its input
      closes without one — this generation gone. logind waits for it (it was held when
      PrepareForSleep went out), so the new generation has those seconds to lock.
    What remains: a PrepareForSleep during a reload still locks only if the new generation
    has its lock confirmed before logind stops waiting. With s the signal, T the old
    generation's teardown (s ≤ T ≤ s + b, b the build of the new generation: the signal can
    come at any moment of it), d the time from T to `compositorLocked`, g the grace: logind
    sleeps at min(T + g, s + 5), the lock is confirmed at T + d, so it needs
    d < g (the grace) and b + d < 5 (logind's cap, worst alignment: the signal at the very
    start of the build). g above 5 − (T − s) buys nothing (the cap comes first), so g ≤ 5;
    beyond that, a longer grace only delays a sleep after a crash. Measured in the test bed
    (`reload-window`, 2026-11-15, 36 samples, alone and beside three other stacks): d
    0.052 / 0.062 / 0.073 s (min / median / max) — the new generation's monitor asks
    `PreparingForSleep` within ~20 ms of its start and the lock follows in ~50 ms — and s→T
    0.30 / 0.58 / 1.01 s (the signal sent as the reload's first log line appears, or 0.4 s
    later), so the lock came at most 1.07 s after the signal and at least 2.93 s before
    logind would sleep. g stays 3 s: ~2.9 s of margin over d, and
    with b ≈ 2 s on the real machine (an older estimate; Stage 6 measures it) b + d stays
    well under 5. (The earlier flake of this check, ±0.1 s, was not this race: the test
    asked every inhibitor held at the signal to outlast the lock, and one of them was the
    previous reload's, still in its grace and let go on its own schedule — harmless, logind
    waits for the last.) A crash or kill of the shell while awake delays a sleep that comes
    then by up to 3 s.
  - A soft reload while locked keeps the lock. `_carried`, a `PersistentProperties` placed
    before the `WlSessionLock` in `Lockscreen.qml` (keep it there: children are matched by
    position), holds `held` (this process has a compositor lock: from a `lockCompositor`
    read back true, or an `adoptCompositorLock`, to the end of the lock) and `secure` (the
    compositor confirmed it). The new instance's `reloaded` runs before Quickshell realizes
    the new `WlSessionLock`; if `held`, the driver dispatches `restored { secure }`, whose
    `adoptCompositorLock` sets the new `WlSessionLock.locked` true — so
    `realizeLockTarget(old)` keeps the inherited lock and makes new surfaces instead of
    unlocking. `QuickshellSettings::reset()` turned `watchFiles` back on at the reload;
    `announceLocked(true)` turns it off again. The rules' serial restarts in `initial()`:
    every adapter is the new generation's own (the old generation's PAM contexts, timers,
    detector and their signal connections die with it, connected to the old driver's
    closure only), so nothing tagged under the old serial can reach the new state. After
    the reload (`Qt.callLater`) the driver checks that the lock is held; if not (the old
    `WlSessionLock` was not handed over — a reload that changed `Lockscreen.qml`'s objects),
    the process can never lock again and quits for a fresh one (below).
  - A hard reload (`reload(true)`) hands nothing over: the old `WlSessionLock` is destroyed
    locked, and Quickshell's process-wide manager keeps it as active. The new generation
    finds the marker (below), its lock is refused at once, and the process quits with
    status 1 (`Qt.exit(1)`, the marker left "locked"); the launcher starts a fresh process,
    which locks. The session stays locked throughout (observed, `reload-hard`).
- **Restart** (a shell that stopped while locked: a crash, SIGKILL, the OOM killer, `qs
  kill`, SIGTERM, `h2s-shell --restart`).
  - The lock marker, `$XDG_RUNTIME_DIR/h2s-shell-lock`, written synchronously and
    atomically (`FileView`, `blockWrites`, `atomicWrites`): "locked <key>" in
    `lockCompositor` (before the request) and `adoptCompositorLock`; "unlocked" 250 ms
    after the step that returned to unlocked (`_markerUnlockDelay`), not in it — except a
    lock the marker asked to take back that the compositor refused (it still holds its
    lock). Why late: that step also set `WlSessionLock.locked = false`, and Quickshell's
    `unlock_and_destroy` only reaches the compositor when the event loop next flushes the
    Wayland connection; ext-session-lock-v1 has no reply to the unlock (and `secure` turns
    false inside the setter, before anything is sent), so "the compositor confirmed the
    unlock" cannot be had — a wait past the flush is what can. A shell killed within those
    250 ms comes back locked (fail closed: one authentication too many), never believing a
    session unlocked that the compositor still holds. A newer "locked" cancels a pending
    "unlocked"; a reload in between writes it in the new generation (`_carried
    .markerUnlockPending`, read by the start probe instead of taking the marker's "locked"
    for a lock to restore). The key is the compositor session: `<boot id>:<WAYLAND_DISPLAY>:
    <the socket's device, inode, ctime>`, from a probe at start ("?" until then).
  - At start the driver reads the marker (`LockIoRules.markerFacts`, `markerDecision`):
    "locked" with this session's key — or with "?" on either side (fail closed) — locks at
    once (`lockRequested { source: "restore" }`); "locked" with another key is stale (the
    compositor that was locked is gone: a new compositor session is a new login) and is
    overwritten with "unlocked"; anything else is nothing. The runtime dir must be the
    user's and writable by nobody else (XDG's 0700), the marker a plain file of the user's
    (not a link), else there is no marker (logged). The marker grants nothing: "locked"
    only causes a lock.
  - `scripts/launch.sh` supervises the shell (it no longer `exec`s Quickshell): the shell
    runs as its child (`qs --log-times -p …`, its input from /dev/null), in a process group
    of its own (`set -m`), with `H2S_SHELL_SUPERVISOR=<launcher pid>` in its environment.
    - **One supervisor per session**: it holds `$XDG_RUNTIME_DIR/h2s-shell-launcher.lock`
      (`flock`, util-linux: in `nix/package.nix`'s runtime programs; Arch's base) and writes
      its pid there; the shell and the pauses' `sleep` do not inherit the descriptor. A
      second launcher waits for the lock (15 s), then gives up with "launcher <pid> still
      supervises the shell of this session: not starting a second one" (exit 1). Without
      `flock` it says so and goes on unguarded. (Per user, as the marker is: two compositor
      sessions of one user are not supported.)
    - It waits for the shell to END (`wait -f`, bash ≥ 5.1; older bash polls a stopped
      child): a stopped shell (SIGSTOP, SIGTTIN/SIGTTOU) is left alone — `wait` used to
      return at the stop and the stopped shell was killed and replaced. When bash has
      already reaped the shell and kept no record (`wait` 127, seen with bash 5.3 in about one
      run in four of a test), the shell has ended and its status is lost: taken for a crash
      (restarted) — the loop used to spin there and never restart it.
    - When it ends the launcher first kills what is left in that group running Quickshell's
      binary (PAM helpers — not the crash reporter, the only process with
      `__QUICKSHELL_CRASH_DUMP_FD` in its environment: a shell relaunched in place carries
      the other `__QUICKSHELL_CRASH_*` variables, and so do the PAM helpers it forks; nothing
      else), then starts it again unless it was stopped on purpose: exit 0 or
      SIGTERM/SIGINT/SIGHUP (129/130/143) while the marker says unlocked; the launcher told
      to stop (SIGUSR1: let the shell go; SIGTERM/SIGINT: also stop it); the compositor gone.
      SIGHUP to the launcher (the terminal it was started from closed) is logged and
      ignored: the shell runs on, supervised — stopping it then left a locked session with
      no prompt.
    - "The compositor is gone": its socket is not the one seen at the launcher's start
      (device, inode, ctime — a new compositor under the same name is another session,
      whose own autostart starts its shell), or nobody holds `<socket>.lock`
      (libwayland-server keeps an exclusive flock on it while serving the socket; a crashed
      compositor leaves the socket file behind). Checked when the shell died and again
      after the pause.
    - Pauses 1, 2, 4, 8, 16 s while the shell keeps dying within 30 s; more than 5 restarts
      in 2 minutes: given up — unless the marker says locked (and the compositor is alive):
      then tried again every 60 s, each attempt logged, for as long as it stays so (giving
      up left the owner at the compositor's dead-lock screen with no shell). A shell that
      runs 30 s resets the count; the lock over (marker unlocked), deaths are counted
      afresh. `H2S_LAUNCHER_TEST_TIMINGS` ("first=0.1 slow=2 lockwait=3", seconds) shortens
      the pauses for the test bed (inert unless set).
    - `--restart` sends SIGUSR1 to the supervisor holding the lock (checked: the pid in the
      lock file, the user's, running `launch.sh`, the lock really held) whether or not a
      shell is alive — one sleeping before a restart used to be told nothing and started a
      second shell — and to each running shell's supervisor (the parent named in its
      environment, running `launch.sh`), before `qs kill`; then starts a new launcher with
      `setsid` (input and output /dev/null), which waits for the old one's lock.
    - Its messages, one line each, `<date time.ms> h2s-shell launcher[<pid>]: …`, go to
      stderr and to `$XDG_RUNTIME_DIR/h2s-shell-launcher.log` (moved to `.old` past 512 KB):
      Hyprland's autostart reads nobody's stderr.
    - `launch.sh ipc call|prop …`: see "The reload window" (tried again for up to 3 s).
  - Quickshell's crash handler restarts a crashed shell in the same process (same pid: the
    launcher sees nothing, there is never a second shell); a crash within 10 s of starting
    exits 255 instead, and the launcher restarts it. The PAM helpers the crashed image had
    forked are still children of that pid, and the launcher's clean-up does not run: once
    per process (`_helperSweepOnce`, a `PersistentProperties` whose `done` a soft reload
    carries; the LAST children of `Lockscreen.qml`, after `CapsLockLed`, so the ones before
    keep their positions) the driver kills its own children that run Quickshell's binary
    and started before the check — not the crash reporter (`__QUICKSHELL_CRASH_DUMP_FD` in
    its environment) — and only in a process that was relaunched in place (its exec-time
    environment, `/proc/<pid>/environ`, holds `__QUICKSHELL_CRASH_INFO_FD`; qunsetenv does
    not change that block): a process started fresh sweeps nothing. It cannot hit a helper
    of the new image's own conversations: those are forked after a methods detection that
    starts no earlier than the sweep's own `sh` (both Processes, started at the first
    `postReload` at the earliest), so they never have an earlier start time (`-lt`: the
    same clock tick is spared); what the image forks before the sweep runs `sh`, not
    Quickshell's binary. The launcher's clean-up is the other layer (a shell that died),
    with the same two tests at another moment. Needed since the fingerprint
    configs wait with no time limit (`timeout=-1`, section 8): such a helper would keep the
    reader claimed for good (`restart-crash-finger`).
  - Under Hyprland (`HYPRLAND_INSTANCE_SIGNATURE` set) a lock is taken back only after
    asking `hyprctl -j getoption misc:allow_session_lock_restore` and `hyprctl -j locked`
    (`LockIoRules.hyprlandLockFacts`), each bounded by `timeout 2` (a hung hyprctl stalled
    the restore for good while the status said "unlocked"): restoring not allowed and the
    session locked means the lock would be refused and the shell killed for asking (section
    1), so it is not asked for. Anything else — no answer included (logged: "Hyprland did
    not answer") — or no Hyprland, asks (`restart-hyprctl-hang`).
- **Recovery** (the compositor will not give the lock back). The shell sets
  `_restorePending`: `locked` stays true for the rest of the shell (no idle lock, the
  screensaver logic as locked), the IPC `status` says `compositor-locked`, `lock()` asks for
  the lock back rather than a new one, the marker stays "locked", and it looks again after
  5 s, doubling to a minute (`_restoreTable`). A refusal by the compositor itself (without
  the Hyprland question) is handled the same. Without Hyprland's answer each attempt may
  get the shell killed: the launcher slows down to one attempt a minute after 5 restarts in
  2 minutes (the marker says locked), so no hot loop, and a shell comes back by itself once
  the setting is on.
  The owner's ways back, from another console (Ctrl+Alt+F2, log in):
  - `hyprctl -i 0 eval 'hl.config({ misc = { allow_session_lock_restore = true } })'` (with
    `XDG_RUNTIME_DIR` set, as a login sets it; `-i 0` is the first Hyprland instance) — the
    shell's next look takes the lock (within a minute; at once with `h2s-shell --restart`),
    and the prompt is back. Then add the line below to the config for good.
  - If no shell runs any more (the launcher was killed, or the shell was never supervised):
    after the line above, start it from that console as Hyprland's autostart does
    (`H2S_SHELL_DIR=$HOME/src/h2s-shell h2s-shell --restart`), with `WAYLAND_DISPLAY` and
    `HYPRLAND_INSTANCE_SIGNATURE` set to the session's (`hyprctl instances` lists both); it
    finds the marker and locks.
  - `loginctl unlock-session` does nothing for a dead lock (it reaches the shell, and there
    is none holding the lock). Killing Hyprland ends the session (unsaved work is lost); a
    new login is not locked (the marker's key no longer matches).
- **What the owner adds to hyprland.lua** (not done here: the owner's config). In the
  `misc` table of the `hl.config({ … })` call in the MISC section of
  `~/.config/hypr/hyprland.lua`:

  ```lua
  hl.config({
      misc = {
          force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
          disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
          allow_session_lock_restore = true, -- a restarted lock screen (h2s-shell) may take the lock back
      },
  })
  ```

  Why: when the shell dies while locked, Hyprland keeps the session locked ("lockscreen
  app died") and, without this, refuses any new lock — the restarted shell cannot show a
  prompt, and the only ways back are the console commands above. With it, the restarted
  shell takes the lock over and the session never shows unlocked in between (observed:
  `restart-kill-locked`, the compositor polled every 50 ms). It does not weaken the lock: a
  new lock still needs the owner's authentication to end, and any program of the user could
  already lock the session. The autostart needs no change: `hl.exec_cmd(shell)` runs
  `h2s-shell`, which now supervises.

### What other QML in the shell can reach

Same-process QML is not a security boundary; the driver only keeps the obvious doors shut.
`Lockscreen` exposes `view`, `locked`, `screensaverVisible`, `capsLock`, `lock(source)`, the
surface functions and the IPC. The state, the event queue, the dispatch function and the surface
registry live in the closure `_build()` makes, not in properties; `_api` holds only the
operations above. The surface functions take the `LockSurface` object itself and act only for
one registered by `addSurface` (which accepts only a `LockSurface` instance, once, while a lock
is in force) — no guessable ids. Still reachable: a QML component that gets hold of a
`LockSurface` (or creates one) can send its input (a password it knows; no key unlocks);
`Lockscreen.children` lists the singleton's child objects (the logind monitor, the adapters,
the timers), whose signals other QML can emit — the driver accepts from each only the event
types it may raise (the logind monitor's include logind's Unlock); and, like any process of
the user, QML can run `loginctl unlock-session`, which is an accepted unlock by the owner's
decision. Defect 5 is therefore narrowed, not closed: the guarantee is against mistakes, not
against code running in the shell.

### Decisions, and why

- **No key unlocks; Escape hides the prompt** (section 5: Escape unlocked at an awake prompt
  until 2026-11-15, the owner's testing door, then removed). The events that end a lock are
  exactly: a `pamCompleted` success of the current conversation, `unlockRequested("logind")`
  (both pending while locking, carried out at `compositorLocked`), and — not unlocks by
  anyone — `compositorFinished` of the current session. The sweep's oracle fails on any
  `key` event that ends a lock or decides an unlock, and counts the Escapes it sends at an
  awake prompt (at least one per sixteen sequences); a behaviour test sends sixty Escapes,
  pressed and repeated, from every surface, from each situation (asleep, awake, two
  surfaces, a question pending, verifying, suspending, locking, locking while going to
  sleep, restored over a reload): the phase never changes, nothing is sent. What Escape
  does, in `_key` only: on a sleeping prompt it wakes it (any key does) and is not
  forwarded; at an awake prompt, from any surface, it hides the prompt through the same
  `_sleepPrompt` as the time-out — `fieldEpoch` +1 (what was typed goes), a question left
  unanswered is cancelled (its conversation aborted), a verification under way goes on and
  still unlocks if it succeeds. One press, one effect, rather than "first clear, then
  hide": the rules do not know whether the field holds text (it lives in the view), and
  hiding empties it anyway. Its auto-repeats are ignored ("repeated Escape") — otherwise a
  held Escape would toggle the prompt at the repeat rate.
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
  plugged in included) in a round shorter than `quickRound` waits `errorRetry` (30 s); the
  `errorLimit`-th (5th) such Error in a row breaks the method. An Error after a round of
  `quickRound` or more is a time-out with nobody trying — pam_fprintd's own `timeout` (30 s
  by default) ends an untouched round with PAM_AUTHINFO_UNAVAIL — and is NOT counted: it
  resets the count and waits `retryMin` (the reader is fine; the wait simply starts again,
  through the retry timer, never in the step that ended the round; a completion is no
  abort, so no settle). Counted, five of them broke the fingerprint after ~4.5 minutes of
  an untouched lock, until the next wake from sleep (the system-side review). Any other
  result resets the count. (A wall clock set back makes a round look quick: counted — the
  safe side.) Somebody coming back to the prompt
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
  outcome is just `lockRequested("idle")`. `enabled`/`timeout` go to an `IdleWatch`, which
  makes a new `IdleMonitor` whenever they change (changing them on a live one can leave
  `isIdle` false for good, section 1); `tests/lock/tests/idle.sh` and `idle-lock.sh` run the
  idle path end to end, before and after an unlock. `screensaverVisible`, the
  "lock after the screensaver" timer and the screensaver commands are the driver's too; the
  rules take only `lockOnSleep` and `passwordFallback`.

### Known limits

- **A compositor that never confirms and never refuses** leaves the lock `locking` for good:
  the owner can authenticate, and the unlock stays pending ("Unlocking…") for good; logind's
  Unlock waits the same way; a crash or kill of the shell leaves the session locked
  (section 1), and the restarted shell asks for a lock again (the marker). Nothing better is protocol-clean through Quickshell 0.3.2: ext-session-lock-v1
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
- `initial()` always starts unlocked; a lock carried over a reload enters by `restored`,
  only from a fresh state. What was typed or pending at the reload is gone (a new
  authentication is needed); a lock that was `unlocking` (an unlock pending the
  confirmation) is carried as a lock, not as the pending unlock — fail closed.
- The reload carries the lock only when `Lockscreen.qml`'s objects are in the same order in
  the old and the new file (Quickshell matches a singleton's children by position). A reload
  after an edit that changed them (possible only through `Quickshell.reload()`: file changes
  do not reload while locked) cannot carry it: the process quits and the launcher's fresh
  one locks — the session stays locked, the restart costs a second or two.
- The restart needs the launcher: a shell started without it (`qs -p …` by hand) that dies
  is not started again, and one that cannot lock again after a hard reload quits for
  nothing. Quickshell's crash handler still restarts a crash it catches in place.
- Under Hyprland without `misc:allow_session_lock_restore`, a shell that died while locked
  cannot get its prompt back until the setting is switched on (the owner's config; "What
  the owner adds"); meanwhile Hyprland's own "lockscreen app died" screen shows. Under a
  compositor that the shell cannot ask, a refused lock may get the shell killed at each
  attempt: 5 quick restarts, then one a minute for as long as the marker says locked (a
  shell that comes up once the compositor gives the lock back); the way back meanwhile is
  a console.
- Another locker holding the session (hyprlock, swaylock) when the shell restarts with a
  "locked" marker: under Hyprland with restoring allowed the shell asks, is refused and
  killed, 5 times quickly, then once a minute; with restoring off it waits. Not a supported
  setup.
- The PAM helpers left by a dead shell are killed by its launcher (a shell that died) or
  by the shell itself (restarted in place by Quickshell's crash handler: "Restart"). A
  helper of a shell that was not supervised (or of a launcher killed with it) lingers:
  with the shipped and generated fingerprint configs (`timeout=-1`) until a finger touches
  the reader (the orphan takes that touch and ends) or fprintd restarts; meanwhile the next
  shell's fingerprint cannot claim the reader, errs quickly (counted: broken after five,
  2 minutes) and the password serves. The test bed's fingerprint stand-in reproduces the
  lingering helper (it waits until its parent, the helper, dies), not the reader's claim:
  that fprintd releases a dead client's claim at once (it watches the client's bus name:
  `_fprint_device_client_vanished`, from source) is not shown here (Stage 6).
- The fingerprint reader is claimed for the whole lock (`timeout=-1`; it was so for most of
  it before, a new round starting right after each 30 s time-out). The conversation is
  ended at the unlock, when the lock ends (compositor), and before sleep — every one of
  those aborts it (rules: `_endLock`, `_reconcilePassive` while suspending); Quickshell's
  abort SIGKILLs the helper and fprintd releases the claim when its bus name vanishes.
  While locked, another fprintd client (`sudo` with pam_fprintd from another console, an
  SSH session) gets "already claimed" — which pam_fprintd turns into an error, and those
  programs into the password. Nobody else uses the reader while the session is locked.
- A profile switch that changes the screensaver's timeout while the screensaver shows
  takes it down: the new `IdleMonitor` (IdleWatch makes a fresh one on every change) starts
  non-idle, the end command runs, and the "lock after the screensaver" timer starts over
  when it idles again. Carrying "was idle" into the new watch would need a way to see the
  owner come back before the new monitor's first idle — a second monitor with a minimal
  timeout — more than it is worth; not done.
- The marker is written before the lock request: a shell killed between the two comes back
  locked although the compositor never was (fail closed: one authentication too many). A
  shell killed — or stopped on purpose, SIGTERM or `qs kill` — within 250 ms after an unlock
  likewise: the launcher starts it again and it locks ("unlocked" is written only then, past
  the flush of the unlock request: "Restart"); one killed after it, with the request still
  unread by a compositor that hangs, would come back believing the session unlocked —
  ext-session-lock-v1 gives no confirmation of an unlock to wait for.
- **The reload window** ("Reload"): for the ~2 s of a reload, an IPC call is dropped by
  Quickshell (the launcher's `ipc` tries again for 3 s: a raw `qs ipc` caller is not
  covered, and `qs ipc` still exits 0 — upstream draft, issue 4), and a PrepareForSleep is
  heard only through the `PreparingForSleep` question after the reload, locking in time only
  if the lock is confirmed within the old inhibitor's 3 s grace after the teardown and
  logind's 5 s maximum delay after the signal (logind refuses the new generation's own
  inhibitor while the sleep is under way). Measured in the test bed: the lock at most 0.07 s
  after the teardown and 1.07 s after the signal; the real machine's build time is Stage 6's
  to measure. Not closed: that would need the inhibitor and the monitor in a process that
  outlives reloads (the supervisor), duplicating the rules' sleep logic there and leaving an
  unsupervised shell without lock-before-sleep — more than the narrowed window is worth.
- Edits made while locked take effect at the next file change after the unlock, not at
  the unlock (no reload at unlock: "Reload").
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
  passwordFallbackKnown, capsLock (from the LED: true / false / null), marker, markerKeyKnown, restoring, restorePending,
  carriedHeld, carriedSecure }` (Stage 4: the marker as last written by this shell, a lock
  being taken back, the compositor refusing it, what a reload would carry). IPC `status`
  is `locked`, `unlocked` or `compositor-locked`.
- **The test bed's seams**, each inert unless set: `H2S_LOCK_AUTH_METHODS` (read by the
  methods script), `H2S_LOCK_TOOLS` (a directory with stand-ins for `gdbus` and
  `systemd-inhibit`: the test bed has no system bus, and the launcher puts the real gdbus
  first on PATH, so PATH could not serve), `H2S_LOCK_SYSTEM_PAM_DIR` (where the system-wide
  configs are looked for, so that a test shell's password fallback is never the machine's
  real PAM stack), `H2S_LOCK_TEST_RELOAD=1` (the `locktest reload` IPC),
  `H2S_LOCK_LEDS_DIR` (where `CapsLockLed` looks for `*::capslock/brightness` instead of
  `/sys/class/leds`: the nested compositor has no keyboard, and the real one's LED is not
  the test's) and `H2S_LOCK_TEST_TIMINGS` (a JSON object of `LockRules.timings` overrides
  handed to `initial()`: minutes of rounds in seconds; `initial()` drops unknown names and
  bad values; the timings decide when, never whether, a lock ends), and the launcher's
  `H2S_LAUNCHER_TEST_TIMINGS` (its pauses — first, slow — and how long a new launcher
  waits for the lock, in seconds: restart tests in seconds instead of minutes).

## 8. Stage 5: the system side (as implemented, 2026-11-14)

### The methods script

`scripts/lock-auth-methods.sh` asks fprintd over D-Bus with `gdbus call` (glib, already a
dependency; and `H2S_LOCK_TOOLS` replaces it in the test bed): `Manager.GetDevices`, then
`Device.ListEnrolledFingers("")` per reader until one has a finger — `""` means "the
caller": naming a user, even oneself, is not needed, and naming another makes fprintd ask
polkit for `setusername`, which puts an authentication dialog on the screen. Polkit is
asked even so: fprintd checks every `ListEnrolledFingers` against
`net.reactivated.fprint.device.verify` (fprintd 1.94.5, `src/device.c`: the call needs the
verify permission, checked with user interaction allowed). Its default is
`allow_active=yes` — no dialog for the active session's user — and `no` for an inactive
session (`PermissionDenied`: a failure, asked again later). A site policy that demands
authentication for it would put a dialog on the screen at every detection; the same rule
already governs pam_fprintd's `Claim` at every fingerprint conversation, so such a machine
has no usable fingerprint lock either way. Not checked against this machine's polkit (no
call to the real fprintd or polkit is made from here). The whole
question has a 4 s deadline, each call `timeout`-wrapped with what is left. fprintd not
installed (`ServiceUnknown`), no reader, no finger: an answer (exit 0, not offered); a
time-out, any other error (no bus, `PermissionDenied` from an inactive session) or a reply
that does not parse: a failure — the lines it could answer are printed first, then exit 1,
the reason on stderr. The consumer agrees as it was: exit 0 is `methodsDetected`, anything
else `methodsFailed` with its lines dropped (the password then takes the fallback, which is
chosen the same way as the script's password line); `MethodDetector` now logs the script's
stderr (one line per reason: gdbus's stderr is read apart from its reply, so a GLib warning
on a call that succeeded leaves the reply readable, and an error of several lines is one
line of reason; gdbus's own "Timeout was reached" counts as a time-out). Cost of dropping
the lines: a key offered by the same run is not used until the next detection — at the
first wake of the prompt at least 30 s after this one (or the wake grace after a sleep).

A passive method is offered only with a config that can load its module: a system-wide
`h2s-shell-<method>`, or the shipped one except on NixOS (there a module named without a
path is looked for only in the linked libpam's store directory — the journal shows
`PAM unable to dlopen(/nix/store/…-linux-pam-1.7.2/lib/security/pam_fprintd.so)`).

The security key: offered when the user has a key where that config's pam_u2f looks, as
pam_u2f 1.4 resolves it (`pam-u2f.c`, `resolve_authfile_path`): `authfile=` (with `expand`,
`%u`/`%h`; relative → under the home directory), else `$XDG_CONFIG_HOME/Yubico/u2f_keys`, else
`~/.config/Yubico/u2f_keys` (`sshformat`: `id_ecdsa_sk`). "Has a key" = a readable file with a
`<user>:` line, the name matched literally (the conversation runs as the user, so a
root-only mapping file cannot serve). The config's words are split without pathname
expansion (`[origin=…]`, `authfile=/x/*` are taken as written). Not followed:
`include`/`substack`, an `authfile` with spaces.

Tests: `tests/lock/tests/methods-script.sh` (the script alone, every fprintd behaviour of the
stand-in — a warning on gdbus's stderr, gdbus's own time-out, a reader vanishing between the
two calls, an error of two lines among them —, the u2f rules, a literal user name and
authfile, the 5 s bound, nothing left running) and `methods-fprintd.sh` (the
shell with the real script: offered and unlocking by finger; not offered and not re-asked;
fprintd hanging → failure logged with the script's reason, fallback, re-asked after 30 s and
offered). Against this machine's real fprintd (Stage 5): `password /etc/pam.d
h2s-shell-password`, `fingerprint /etc/pam.d h2s-shell-fingerprint`, exit 0 in 0.06 s —
`fprintd-list h2s` shows right-index-finger. Not "read-only" as far as the owner's screen
goes: an earlier agent's fprintd call put a polkit dialog there; no agent calls the real
fprintd, polkit or logind any more (the stand-ins serve).

### The shipped pam/password on NixOS: it does reach its helper

Defect 13's "pam_unix cannot reach its helper there" is contradicted by the journal and the
binaries. Quickshell 0.3.2 links `/nix/store/18ykcs87…-linux-pam-1.7.2/lib/libpam.so.0`; the
system's stacks name `/nix/store/v3n5aklh…-linux-pam-1.7.2` (another build of the same
version). A bare `pam_unix.so` resolves in the linked libpam's own `lib/security/`, and both
builds' `pam_unix.so` carry the helper path `/run/wrappers/bin/unix_chkpwd` (`strings`), which
exists, setuid root. The journal of 2026-11-13 shows the real shell's shipped config
(service `password`) running that helper: `unix_chkpwd[19986]: password check failed for user
(h2s)` at 22:35:17, and again at 22:39:41, 22:40:01, 22:40:19 — the helper ran and compared
hashes, i.e. those passwords were rejected, not unreachable. The 23:03:50 failure (and
22:42:23) has no helper line: unix_chkpwd does not log a blank-password check under `nullok`
(`unix_chkpwd.c`: `if (!nullok || !blankpass)` around the log call), and `pam_unix` with
`nullok` runs the helper with an empty password before prompting (`_unix_blankpasswd`), so
those lines fit an empty password (or a helper that could not be executed, which is not
logged either; how the old prompt could have sent an empty one was not traced). `PAM _pam_init_handlers: no default config other` is libpam not finding an
`other` file in the config directory Quickshell passes (`pam_start_confdir`): harmless.
How sure: high that the mechanism works (same module version and helper as `login`, helper
seen running); not confirmed with the real password, which was not typed. So the script and
`LockIoRules.passwordFallback` still say `login` on NixOS without the module's config;
dropping that (login waits for the fingerprint first) should follow one real check — Stage 6.
This machine has `/etc/pam.d/h2s-shell-password`, so the shipped file is never used here,
and pamtester cannot name a config directory: the check is `tests/manual/pam-probe.sh`
(with `pam-probe.qml` and a README beside it; no suite runs it, and nobody but the owner
may: it authenticates against the real account). One `PamContext` with
`configDirectory` = the shell's `pam/`, `config` = `password`, no window; the password read
without echo and passed through a private FIFO (never an argument, the environment or a
log); one attempt per run; it prints Success, Failed or Error. The owner runs it ONCE. On
anything but Success the journal is read before any retry (`journalctl --since -5min |
grep -E 'unix_chkpwd|pam_unix'`): a `unix_chkpwd … password check failed` line means the
password was wrong (the helper ran); no helper line means the helper was not reached. Two
attempts at most. On Success both places drop the `login` branch.

### The shipped configs

`auth` lines only (Quickshell runs `pam_authenticate` alone); `account` lines removed. No
`nullok` (the rules refuse an empty password anyway; without it an account with no password
cannot be unlocked by whatever is typed, and pam_unix no longer runs the helper twice).
Passive configs: one module, `required` (its own code is the result: MaxTries and a missing
reader stay distinguishable; `sufficient` + `pam_deny` would turn both into a plain failure);
pam_u2f with `cue`, never `interactive`. pam_fprintd with `timeout=-1`: its default, 30 s,
ends an untouched round with PAM_AUTHINFO_UNAVAIL (Quickshell: Error), which counted as a
fault broke the fingerprint after five rounds (~4.5 minutes; the rules no longer count a
full-length Error round, section 7, "Retries" — both fixes stand). From pam_fprintd's
source (1.94.5, `pam/pam_fprintd.c`): `timeout=<n>` is parsed with `atoi`, a negative value
becomes `UINT_MAX`, which the verify loop takes as no deadline; the timeout is per try.
`max-tries` stays at its default 3 (a negative value would be unlimited): three
non-matching fingers end in PAM_MAXTRIES, which the rules wait out (10 s) and restart — a
finger that keeps failing is then visible as such rather than an endless silent loop. The
cost: the reader stays claimed for the whole lock (see "Known limits").

**Arch (reasoning, not tested here).** `auth include system-auth` would bring what Arch puts
there: `pam_faillock` (preauth/authfail — wrong passwords at the lock count towards the
lockout, and a locked-out account cannot unlock by password at all until it expires),
`pam_systemd_home` (needed for homed users), and whatever the administrator added —
`pam_fprintd` in `system-auth` is a common recipe, and then the password conversation would
wait for a finger, which is what separate conversations exist to avoid. Bare `pam_unix`
works for `/etc/shadow` accounts (Arch's `unix_chkpwd` is setuid, as screen lockers need),
never waits, has pam_unix's 2 s failure delay as its brute-force brake, and does not feed
faillock. Recommendation: keep bare `pam_unix` as the shipped default; homed/LDAP/SSSD users
write `/etc/pam.d/h2s-shell-password` with the modules their accounts need, `auth` lines
only (`pam_systemd_home` `[success=done default=ignore]` + `pam_unix`, or `pam_sss`) — NOT a
plain `auth include system-auth`, which brings faillock (a lockout from wrong passwords at
the lock, and then no unlock by password) and often pam_fprintd/pam_u2f. The README and
install.sh say so. An account with an empty password cannot unlock by password at all (no
`nullok`, and the rules never send an empty one): README and FEATURES say so.

### The NixOS module

- `h2s-shell-password`: NixOS's generated stack (so pam_unix, and homed/SSSD/LDAP/Kerberos/
  kanidm when globally on — they are the password check) with every second factor off by
  `mkDefault`: `fprintAuth`, `u2f.enable`, `p11Auth`, `yubicoAuth`, `howdy.enable`,
  `oathAuth`, `otpwAuth`, `googleAuthenticator.enable`, `duoSecurity.enable`,
  `sshAgentAuth`, `rssh`, `usshAuth`. A machine opts one back in on the service itself; no
  module option of ours (nothing to add over NixOS's own).
- `h2s-shell-fingerprint` (when `services.fprintd.enable`) and `h2s-shell-u2f` (when
  `security.pam.u2f.enable`): `text` written out, `mkOverride 900` (above NixOS's generated
  default, below a machine's plain definition) — one `auth required` line, absolute path
  (the fingerprint's with `timeout=-1`).
  Built from options instead, a global switch (oath, howdy, homed's prompting module,
  mysql) would land in a passive stack. The u2f line takes `security.pam.u2f.settings`, with
  `cue = true; interactive = false` forced.
- Evaluated against this machine (the working copy's module in the system's
  `nixosSystem`, its configuration copied with and without the hand-written pair): password
  auth = `pam_unix sufficient likeauth try_first_pass` + `pam_deny required`; fingerprint =
  `auth required …fprintd-1.94.5/lib/security/pam_fprintd.so`; u2f not generated. With
  u2f (`interactive = true` set), oath, p11 and homed switched on in the evaluation: password
  = homed + unix + deny (no oath, no p11), u2f = `auth required …pam_u2f.so
  authfile=/etc/u2f_mappings cue [origin=pam://x y]` (no `interactive`), fingerprint
  unchanged. No warnings or assertions.
- No NixOS VM test: it would build a VM closure with Quickshell (long, large) and still need a
  PAM driver inside; the evaluation above checks the generated text line by line instead.

### For the owner's /etc/nixos

Now (the `h2s-shell` flake input, pinned at bd30fff, has no PAM in its module): replace the
hand-written `security.pam.services = { h2s-shell-password = …; h2s-shell-fingerprint = …; };`
block in `configuration.nix` with

```nix
  # The lock screen's PAM configs (h2s-shell). Delete once the h2s-shell flake input's
  # module writes them (nix/module.nix).
  security.pam.services = {
    h2s-shell-password = { fprintAuth = false; u2f.enable = false; };
    h2s-shell-fingerprint.text = ''
      auth required ${config.services.fprintd.package}/lib/security/pam_fprintd.so timeout=-1
    '';
  };
```

and rebuild (`sudo nixos-rebuild switch --flake /etc/nixos`). Generated password config:
unchanged; fingerprint config: one `auth required` line with `timeout=-1` (was `sufficient`
+ `pam_deny` + account/password/session lines) — a reader error or MaxTries now reaches the
shell as such, and an untouched reader waits for as long as the lock lasts.

Evaluated on this system (2026-11-14; the system's `nixosSystem` rebuilt from
`builtins.getFlake "path:/etc/nixos"`'s inputs with `configuration.nix` copied): (1) with the
block above in place of the hand-written one and the pinned `h2s-shell` input's module:
fingerprint = `auth required /nix/store/yl4rafcp…-fprintd-1.94.5/lib/security/pam_fprintd.so
timeout=-1`; password auth = `pam_unix sufficient likeauth try_first_pass` + `pam_deny
required`; no u2f; no warnings, no failed assertions; (2) with no block and the working
copy's module: fingerprint = the module's comment line + the same `auth required …
pam_fprintd.so timeout=-1`, password auth the same.
Later (the input carries this module): delete that block, `nix flake update h2s-shell`,
rebuild; the module then writes the same text. Keeping the block would also work (a plain
definition wins over the module's), but would stop following the module.

### Upstream

`docs/upstream/quickshell-session-lock-unlock-notify.md` (a draft, not filed): the unlock
notify (reproduced in the test compositor; fixed in Quickshell master by 18c95fae after
v0.3.2, unreleased), a failed `fork()` in `PamContext.start()` ending in `kill(-1, SIGKILL)`
(unfixed), `locked = false` before `secure` sending `unlock_and_destroy` (unfixed), and —
from the review of Stage 4 — `qs ipc call` exiting 0 when the call was dropped ("Not ready
to accept queries yet." during a reload), which the launcher's `ipc` now works around.

Not done in Stage 5: the logind monitor without `XDG_SESSION_ID` (Stage 5's list in
section 4; not part of this work).

## Backlog (after the real-machine check)

- `scripts/launch.sh`: during the restart pause check the compositor every second, or have a new launcher wait for the lock longer than the longest pause (a fast re-login after a shell death at logout can leave the new session without a shell).
- `scripts/launch.sh`: when `wait` returns 127, keep polling if the child is still alive and ours.
- Wrap the `qs ipc` calls in `timeout 5`.
- `recorded_supervisor` could prove the pid is the lock holder via `/proc/locks`.
- Write the marker's pending "unlocked" on destruction when the unlock was already flushed.
- CapsLockLed: a read arriving while a stale probe runs briefly shows the old answer.
- The screensaver drops when a profile changes its timeout while it shows.
- The three upstream Quickshell issues and the `qs ipc` exit-status one (`docs/upstream/`) are drafted, not filed.
- Whether to drop the `login` fallback on NixOS, once `tests/manual/pam-probe.sh` (checklist 2.17) settles it.
