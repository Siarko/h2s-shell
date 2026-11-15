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
