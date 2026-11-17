# Module API, the next versions: commands, privileged runs and the prompt

One area of the plan. Read [the index](../api-next.md) first: the rules for every
slice (§2), the gate every slice passes (§7), the slice list with sizes and
dependencies, the lanes. `TC`, `TR`, "verified" and "assumed" are defined there.

Running a command, finding a program and judging it, test mode, running as
administrator, and what the password prompt says.

Slices in this file: A1, A1b, A2, A2b, A3, A4, A5, A6.

Section numbers are the plan's and stay as they were. Where each is:
§1 `migration.md` · §2, §8, §10 the index · §3.1–3.4 `commands.md` · §3.5–3.10 `facts.md` ·
§4.1–4.7 `places.md` · §4.8, §4.10 `cards.md` · §4.9 `elements.md` · §5 `module-api.md` ·
§6, §11 `versioning.md` · §7: the list, the lanes and "Later" in the index, a slice's row
in its file, Z in `migration.md` · §9: at the end of each file.

## 3. Step 3: the API extension

### 3.1 Command runner

A new core type `singletons/io/CommandRunner.qml`, with `api/CommandRunner.qml` as its
`qs.api` name. `CommandAction` and `CommandQuery` keep their contracts and are rebuilt on
it. `ModuleHost` and the lock screen use the core type, never `qs.api`.

```
CommandRunner {
    property var environment: ({})   // added to every run
    readonly property int running
    function start(argv, options) → handle { running, cancel() }
    function cancelAll()
}
options = { timeoutMs: 30000 (0: no limit), killAfterMs: 3000, environment,
            onStdout, onStderr, onLine (line, stream), keepOutput: true,
            maxOutputBytes: 1048576, done }
result  = { ok, code, stdout, stderr, timedOut, cancelled, failedToStart, truncated, durationMs }
```

- `argv` is a non-empty array of strings; the runner never uses a shell itself.
- The time limit is enforced twice: coreutils `timeout -k` around the command (found and
  trusted by the shell, so the run ends even if the shell dies), and a watchdog in the
  runner for when `timeout` is missing.
- `done` runs exactly once, except after the runner is destroyed. `cancel()`: TERM, then
  KILL after `killAfterMs`; `done` gets `cancelled: true`; chunk and line callbacks stop at
  once.
- `timedOut`: code 124 and the run took at least `timeoutMs`.
- `failedToStart`: Quickshell emits no `exited` then; `running` just turns false (assumed
  from the module's working code).

Test: `tests/CommandRunnerTest.qml` with `sh -c` scripts: time-out, cancel waiting and
running, KILL after a TERM trap, separate stderr, lines split across chunks, the output
cap, a program that cannot start, no callback after destroy. The
`CommandAction` and `CommandQuery` suites stay as they are.

### 3.2 Program lookup with trust

Manifest: `requires.programs` as today, plus `optionalPrograms` (a missing one does not
stop the module). On the handle:

```
module.programs        // frozen { name: { path: "/abs/…" | "", trusted: bool, reason } }
module.programsReady
module.recheckPrograms()   // look again; at most every 2 s; also run on resumed()
```

- The host's program check (`ModuleHost._checkPrograms`) also prints the path, the real
  path and their owners and modes. The verdict is a pure rule in `ModuleRules`, moved from
  the module (`TR` `toolsProbe`, `_statTrusted`) with its cases.
- **Trusted** means: the resolved path is in the Nix store, or the file, its real file and
  every directory above each of them are owned by root and writable by no one else. That holds on NixOS
  (`/run/current-system/sw/bin` leads into the store) and on Arch (`/usr/bin`).
- A read that fails gives `trusted: false`, never true.

Test: verdict cases in `ModuleRulesTest`; a fixture module with a missing optional program
and a user-owned one.

### 3.3 Test mode

One switch, set only by the shell's test entry points: `tests-modules.qml` sets it in
process; the lock bed sets it through the single test-seam reader that
`notes/plans/architecture-cleanup.md` §3 plans (its `Api.testBed` is this plan's
`Api.testMode`: one name, `testMode`). A stray environment variable alone never turns it
on.

In test mode:
- `module.programs` come from the manifest's `testPrograms` directory (inside the module),
  with `trusted: true, reason: "test stand-in"`.
- Privileged runs use `<testPrograms>/pkexec`, which must exist. **Stand-ins never meet the
  real pkexec.**
- `Api.openUrl`, `module.chooseFiles` and `Notifier.send` record the call and open or send
  nothing (today `Notifier` runs `notify-send`, which reaches a real daemon).
- `module.dataDirectory` and `Api.system` come from the test kit.
- `Api.testMode` is true (read-only).

`qs.tests` gains `ModuleTestKit` (tests only; the running shell has no `qs.tests`):
`setEnabled(id, on)`, `status(id)`, `widgetEntries`, `anchorEntries(path)`,
`setSystem(facts)`, `setNow(ms)`, `opened`, `notified`, `chooserAnswer`.

Test (`ModulesTest`): a fixture's stand-in is used only in test mode; with test mode off
`testPrograms` is ignored; a privileged run in test mode never calls a pkexec found on
`PATH` (one is put there that fails the suite if run).

### 3.4 Privileged start, and the prompt's "who and what for"

**The surface is on the handle**, so the shell knows which module asks without being told:

```
module.privileged.available          // trusted pkexec and timeout found
module.privileged.unavailableReason
module.privileged.start(argv, options) → handle { running, cancel() }

options = { what (required), timeoutMs (required, 1 s … 1 h), onStdout, onStderr, onLine,
            notifyFailures: true, done }
result  = { ok, code, stdout, stderr, dismissed, refused, notFound, timedOut, cancelled,
            blocked ("" | "locked" | "untrusted" | "no-purpose" | "unprintable"), error }
```

- **Where pkexec is.** NixOS: the setuid wrapper, `/run/wrappers/bin/pkexec` (the store's
  copy is not setuid and cannot work). Arch: `/usr/bin/pkexec`. Both pass the trust rule
  (§3.2); the lookup takes the wrapper directory first.
- **One queue for the whole shell** (`singletons/PrivilegedRuns.qml`): one password
  question at a time.
  - *When the next run may start.* Only the password question is one at a time. A run
    holds the head of the queue while its question can still come: until its polkit
    request ended, or 2 s passed with none. Then the next run may start and ask, though
    the first still runs: a long streamed run does not block the others. With another
    agent the shell cannot see the question, so there it is strictly one run at a time: a
    run holds the head until it ends, at most 2 minutes.
  - *No password was asked* (a polkit rule allowed the run): nothing on screen; the log
    line below is all.
  - *After a cancel* the next run waits until the cancelled pkexec has exited, or
    `killAfterMs` has passed. Otherwise the cancelled run's request, still on its way,
    would be shown with the next run's lines, and two live requests meet a known
    Quickshell defect (tracker: a second request replaces an open prompt).
  - *A module turned off:* its waiting runs leave the queue and its running ones are
    cancelled; no callback runs.
  - One log line per start, with the module's id and `what`.
- **Time limit.** The shell puts its own trusted `timeout` inside pkexec. `cancel()` after
  the program started as root stops waiting; the root process ends at its limit.
- **No time window** after a click (the owner's decision). That nothing prompts without the
  user's click stays a development rule, checked in review and by the module's tests for
  the project's own modules. An outside module has no review; for it, and for every
  module, what the user gets is a prompt that says who asks and what for.
- **Refused before pkexec runs:**
  - `untrusted`: `argv[0]` has no trusted verdict (§3.2), or is a shell or `env` (then the
    real program would be an argument nobody checked). What is left open, said honestly:
    only `argv[0]` is judged, so a trusted interpreter given a script from the module's
    own directory passes. Review catches it in the project's own modules; the rule does
    not, and for an outside module nothing does but the command shown in the prompt.
  - `unprintable`: a word of `argv` holds a control or format character (Unicode Cc, Cf:
    a newline, a right-to-left override). Such a command could not be shown as it is.
  - `locked`; `no-purpose` (`what` empty after cleaning); `notFound` as today.
- **The session locks:** the open prompt is closed and every waiting run ends as
  `dismissed`, quietly, with `blocked: "locked"`; the user clicks again after unlocking.
  The prompt is a window above everything (`polkit/AuthPrompt.qml`), and a password asked
  behind or over the lock screen is the thing the rule forbids.
- **Root helpers.** By the rule above, nothing under a module's own directory in the user's
  data home ever runs as root. No module has a root helper today; where a packaged helper
  is looked up is designed when the first one needs it.

**The prompt** (`polkit/AuthPrompt.qml`, when the shell's agent answers). Under the shell's
title: two labelled lines in the body size, a line "Command" that opens on a click, then
polkit's own message and action as today.

```
Authentication required
Module          Tailscale
Authorization   Send a file
▸ Command
```

opened:

```
▾ Command
/usr/bin/timeout -k 3 30 /usr/bin/tailscale file cp -- report.pdf laptop:
```

- **One pure function makes every text:** `PolkitRules.announcement({ moduleName, moduleId,
  what, pkexecArgv })` → `{ module, authorization, command, summary, body }`. The prompt
  and the notification below only show them.
- **`Module`**: the manifest's `name`, taken by the shell from the handle the run was
  started on. The id follows in brackets only when the name does not read as the id (name
  lower-cased, letters and digits only, differs from the id): "Tailscale", but
  "System update (xmod)". The id cannot be a word for the shell (`ModuleRules.reservedIds`
  holds `shell`, `system`, `polkit`, `h2s-shell`: verified); the name is free text, so the
  id is what keeps it honest.
- **`Authorization`**: the run's `what`, a few words naming the action ("Send a file",
  "Connect"), never a sentence.
- **`Command`** (the owner's decision: hidden, shown on a click). Closed for every new
  request. Opened, it shows the real command: the very list of words the shell hands to
  pkexec, the shell's `timeout` in front included, joined with shell quoting. Nothing is
  dropped, folded or cut: a command that could not be shown as it is was refused before
  (`unprintable`). A long one is shown whole, in a box that scrolls. The line is a `PointerArea` like a card's
  header; it never takes the keyboard from the password field.
- **The two values are cleaned and capped:** control and format characters (Cc, Cf)
  dropped, white space folded to one line, cut with "…" at 40 each. All texts are
  `Text.PlainText`; polkit's message and action become plain text too.
- **Not spoofable as the shell.** A module's words only fill the two values and the opened
  command. The title, the labels and the frame are the shell's; one line per value, so a
  text cannot fake a second line.
- **Which request is announced.** The agent's flow carries only `message`, `actionId` and
  `cookie` (verified in Quickshell's polkit types): no command line, no caller. So
  `PolkitRules.announces(flow, run)` matches the run at the head of the queue when the
  action is pkexec's (`org.freedesktop.policykit.exec`) and the message names the program
  pkexec is given, which is the shell's `timeout`, by the path given or its real path
  (assumed: pkexec's message holds one of them in every locale). A run is announced at
  most once: a request that arrives after the head's request ended is shown as today,
  with no module lines, and so is anything else. A request the shell did not start is
  never dressed up.
- **The notification.** Whenever the agent's state is not `active` or `conflict` (the two
  in which the shell's own prompt answers: `PolkitRules.state`) the shell cannot dress the
  prompt, or does not know: `other`, `blocked`, `deciding`, `none`. Then the run goes
  ahead, and when it reaches the head of the queue, just before pkexec starts, the shell
  sends one notification from the same rule: summary `Module: Tailscale`, body
  `Authorization: Send a file`, plain text. It states who runs what, not that a password
  is wanted: the shell cannot know whether that agent will ask.

The old `PrivilegedAction` type keeps working until the closing slice (§7), listed in the
module's `deprecations` (§6); its runs go through the same queue and are announced with
`Module  Not named` and no `Authorization` line.

Test: `PolkitRulesTest` (announcement cleaning and caps, the bracketed id, matching by
both paths, a run announced once, a hostile name and `what`, an `argv` with a newline and
with U+202E refused, the notification's texts); a shell suite with a stand-in pkexec that
prints and sleeps: streaming, cancel while queued and after start, the next run waiting
for a cancelled one's exit, the head released when the request ended and after 2 s
with none, the time limit in the argv,
every `blocked` reason, 127 reported once, a module turned off with runs waiting and
running, a lock with runs waiting; for each agent state a notification recorded before
the stand-in starts, or none; the command shown equal to the stand-in's own arguments; a
`LockViewTest`-style view test for the prompt's lines and the click.

---

## 7. Slices

The rows of this file's slices; the order, sizes and dependencies are in the index.

### Step 3

| Slice | API | Files | Verified by |
|---|---|---|---|
| A1 Command runner | 1.4 | `singletons/io/CommandRunner.qml`, `api/CommandRunner.qml`, `io/CommandAction.qml`, `io/CommandQuery.qml`, `api/Api.qml` (`_opener`) | `CommandRunnerTest`; old suites unchanged |
| A1b Host on the runner | — | `ModuleHost.qml` (four blocks) | `ModulesTest`; lock bed `modules`, `modules-hung` |
| A2 Program lookup with trust | 1.5 | `ModuleRules.qml`, `ModuleHost.qml`, `api/ModuleHandle.qml`, a fixture | verdict cases (every directory above, the resolved path, the setuid wrapper); fixture |
| A2b One reader for the test seams | — | the reader of `architecture-cleanup.md` §3, and the places that read a seam today | the lock bed, unchanged and green |
| A3 Test mode | 1.6 | `ModuleHost.qml`, `Modules.qml`, `api/Api.qml`, `Notifier.qml` (records in test mode), `tests-modules.qml`, `tests/ModuleTestKit.qml` | `ModulesTest` (the cases in §3.3) |
| A4 Privileged start | 1.7 | `singletons/PrivilegedRuns.qml`, `PolkitRules.qml`, `api/ModuleHandle.qml`, `api/PrivilegedAction.qml` (onto the queue), `tests/lock-closure.sh` | stand-in pkexec suite |
| A5 The prompt says who and what for | — (user-visible: CHANGELOG "Unreleased") | `PolkitRules.qml` (`announcement`, `announces`), `polkit/AuthPrompt.qml`, `Authentication.qml` | `PolkitRulesTest`; view test; pkexec's real message read once by hand on both systems |
| A6 The notification when the shell's prompt does not answer | — (user-visible) | `singletons/PrivilegedRuns.qml` | stand-in pkexec suite, per agent state (needs A3's record and C1's plain format) |

---

## 9. Verified, assumed, hard

The part of the plan's §9 that is about this file.

**Verified in the code.**
- `ModuleHost.qml` has four `Process` blocks with their own deadlines; `Lockscreen.qml`
  three probes; `api/PrivilegedAction.qml` checks only "absolute and executable" and
  queues per instance; nothing in the core uses that type.
- Quickshell's polkit flow exposes `message`, `actionId`, `cookie`, identities and the
  conversation; no command line. `AuthPrompt.qml` sets no `textFormat` on those texts.
- `Process` has `signal(int)`, `stdinEnabled` and `write()`, `environment`,
  `workingDirectory` (Quickshell 0.3.2's types).

**Assumed.**
- A program that cannot start gives no `exited` (seen in the module's working code).
- pkexec's message names the path of the program it is given (the shell's `timeout`), as
  given or resolved, in every locale. A5 reads the real pkexec's message once, by hand, on
  both systems; the rule's cases then hold both texts.
- Signalling pkexec while its prompt shows ends it; a destroyed `Process` may not kill its
  child (the runner signals explicitly).

**What the current code makes hard.**
- **The prompt cannot identify its caller.** The flow has no command line or process id;
  matching rests on the queue's head and pkexec's message (the assumption above). With
  another agent the shell cannot show anything in the prompt, and that prompt names only
  `timeout`: the notification is all the user is told.
- **The queue's rules rest on what the shell can see.** With its own agent it sees a
  request begin and end; with another it sees nothing, so there the rules are time limits
  (§3.4).
- **The core breaks its own rule:** `network/VpnLockdown.qml` runs `pkexec sh <script>`
  from the shell's tree (tracker, "Found while writing the development rules"). It is not
  a module run and stays outside this plan, but the prompt will show it without module
  lines, as a plain pkexec request.
