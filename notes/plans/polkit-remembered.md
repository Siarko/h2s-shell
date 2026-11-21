# A remembered administrator authorization — analysis and plan

Tracker "Later": a remembered polkit authorization. Decisions it starts from
(`notes/decisions.md`, "Privileged runs and the password prompt"): asked once, quiet for a few
minutes, as sudo's timestamp; exit-node switching prompts most; being Tailscale's operator
stays the user's choice. Rules that bind it (`CLAUDE.md`): nothing asks for a password
without the user's click; root helpers never from a place the user can write; NixOS and Arch
together; only Wayland assumed.

## 1. What prompts today

- Every root run of the shell goes through `PrivilegedRuns` as
  `<pkexec> <timeout> -k 3 <limit> <argv…>` (`PrivilegedRules.pkexecArgv`), so pkexec's
  program is always the shell's trusted `timeout` and the action always
  `org.freedesktop.policykit.exec`, whose default is `auth_admin` for everyone
  (`/usr/share/polkit-1/actions/org.freedesktop.policykit.policy`). Each run asks.
- The Tailscale module, when the user is not the operator, switches the exit node with
  `tailscale set --exit-node=<IPv4 | auto:any | empty>` through `module.privileged.start`
  (`h2s-shell-tailscale/module/TailscaleRules.qml`, command `exitNode`/`exitNodeAuto`/
  `exitNodeNone`). Its other changes (connect, settings, serve) take the same path.
- pkexec is a direct child of the Quickshell process (a `Process`); Quickshell's parent is
  `scripts/launch.sh`, which starts it detached with stdin from `/dev/null`.

## 2. How polkit's temporary authorizations work

Sources: `polkit(8)`, `pkexec(1)`, `pkcheck(1)`, `polkitd.conf(5)` of the installed polkit
128, the D-Bus reference in `/usr/share/gtk-doc/html/polkit-1/`, and polkit's source
(`src/programs/pkexec.c`, `src/programs/pkcheck.c`,
`src/polkitbackend/polkitbackendinteractiveauthority.c`, current upstream).

- **Keep results.** `auth_admin_keep` (and `auth_self_keep`): "Like auth_admin but the
  authorization is kept for a brief period (e.g. five minutes)" (`polkit(8)`). Either an
  action's default in its `.policy` file or a rule's return value
  (`polkit.Result.AUTH_ADMIN_KEEP`).
- **How long.** 300 s, polkitd's `ExpirationSeconds` (`polkitd.conf(5)`; Arch ships it
  commented out in `/usr/share/polkit-1/polkitd.conf`). One value for the whole system, every
  program's kept authorizations: there is no per-action length. Older polkit has the 5 minutes
  compiled in (NixOS's version to be checked).
- **What is kept: (action id, subject) — nothing else.** `polkit(8)`: "authorization checks
  for the same action identifier and subject will succeed … even if the variables passed along
  with the check are different. Therefore, if the result of an authorization rule depend on
  such variables, it should not use the *_KEEP constants." In the source the kept
  authorization is looked up before a rule's `no` is honoured
  (`check_authorization_sync`: implicit `yes` → kept authorization → implied actions → only
  then `no`). **A rule cannot narrow a kept authorization by program or arguments.**
- **The subject for pkexec is its parent process.** `pkexec.c`: `pid_of_caller = getppid ()`,
  `subject = polkit_unix_process_new_for_owner (pid_of_caller, 0, getuid ())`; a parent that
  is init is refused ("Refusing to render service to dead parents"). Not the session, not
  pkexec itself. For the shell: **the Quickshell process**.
- **Matching a subject.** The same process (pid with start time, or its pidfd), same uid
  ("denying slowfork" otherwise). Recent polkit also accepts a *different* process with the
  same non-init parent, the same cgroup and the same controlling terminal, started after that
  terminal (sudo-like, per terminal). The shell runs without a controlling terminal, so this
  should not widen anything for it — to be confirmed in the device trial (§7).
- **Its life.** Ends at its expiry, when the subject process goes (watched by pidfd, else a
  2 s poll), or when revoked. It is stored with the *agent's* session as its scope.
- **Revoking and listing.** `pkcheck --list-temp` / `pkcheck --revoke-temp`: all temporary
  authorizations of the caller's own session (`polkit_unix_session_new_for_process_sync
  (getpid ())`); the authority refuses a caller from another session. No password. D-Bus also
  has `RevokeTemporaryAuthorizationById` (same session check). `--list-temp` prints per entry
  `authorization id:`, `action:`, `subject: <subject> (<cmdline>)`,
  `obtained: <rel> (<%c>)`, `expires: <rel> (<%c>)` with `<rel>` as "N min N sec from now" /
  "N sec from now".
- **Other agents.** All of this is polkitd's: it works the same whichever agent asked.

**So, what a kept authorization means here:** for its few minutes, *the shell's process* may
do *that action* without a password. Who can make the shell's process start pkexec:
- any module (modules run in the shell's process — `docs/ARCHITECTURE.md`, "Modules");
- **any process of the user**, by writing a QML file the shell loads: the shell's tree and
  the module directories are the user's, and the shell reloads a changed file at once. (A
  debugger attach is limited where Yama's `ptrace_scope` is 1, as on this Arch machine, but
  the file route needs none.)

The plan therefore assumes: **whatever is kept is open to every process of the user for the
window.** The question is only how much is kept.

## 3. Options

### (a) A rule: `org.freedesktop.policykit.exec` → `AUTH_ADMIN_KEEP` for some programs

```js
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" && subject.user == "<user>" &&
        action.lookup("program") == "/usr/bin/timeout")  // or tailscale, if run without timeout
        return polkit.Result.AUTH_ADMIN_KEEP;
});
```

- Narrowing by `program`, `command_line` (pkexec: "do not use this for any security checks"),
  user or `subject.pid` only decides *when the password is asked and kept*. Once kept, the
  key is (exec, the shell's process), and polkit answers yes to **any** pkexec the shell's
  process starts — `pkexec /bin/sh` included — for 5 minutes, the rule's `no` included.
- Can the subject be "the shell's own process"? A rule sees `subject.pid` and
  `system_unit`, but the shell is a user process with no root-owned identity; a rule cannot
  tell it from any other process of the user.
- **Exposes: full root to every process of the user for 5 minutes after any exit-node
  switch.** This is sudo's timestamp, but sudo's is per terminal; this is per shell, which
  every process of the user can steer (§2). Not recommended.

### (b) The shell's own actions, each on a root-owned helper (recommended)

- A helper per remembered operation, root-owned in a root-only directory, e.g.
  `h2s-shell-tailscale-exit-node`: takes one argument and refuses anything but `""`,
  `auto:any`, or an IPv4/IPv6 address (no flag, no other `tailscale set` option — think
  `--operator=`); runs the tailscale path fixed at install, with its own time limit
  (`timeout` by absolute path), an empty environment, stdin closed; exit codes mapped to the
  module's outcomes. pkexec's own advice: a program whose authorization can be retained
  "should never implicitly trust user input".
- A policy file `org.h2s-shell.remembered.policy`, one action per helper:

  ```xml
  <action id="org.h2s-shell.tailscale.exit-node">
    <description>Change Tailscale's exit node</description>
    <message>Authentication is required to change Tailscale's exit node</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/…/h2s-shell-tailscale-exit-node</annotate>
  </action>
  ```

  pkexec picks the action whose `exec.path` is the program it runs (`find_action_for_path`),
  so `pkexec <helper> <arg>` is checked as `org.h2s-shell.tailscale.exit-node`, kept as
  (that action, the shell's process).
- The helper must be pkexec's program: such a run goes as `pkexec <helper> <arg>` — without
  the queue's outer `timeout`, whose path would otherwise be the program (and keeping
  `timeout` keeps everything). The helper keeps its own limit instead.
- **Exposes for 5 minutes: exactly what the helpers accept** — here, switching the exit node
  among the tailnet's nodes, to automatic, or off. Every other pkexec still asks.
- Several helpers later: each its own action and its own password, or (later) one meta action
  with `org.freedesktop.policykit.imply` naming them, obtained by `pkcheck -u` for the shell's
  process — one password for all of them. Not in the first version.

### (c) Others, rejected

- **Tailscale's operator for a while** (set `--operator`, reset after N minutes): wider (all of
  Tailscale's preferences), outlives a crash of the shell, and the reset itself needs root.
- **A rule with its own clock** (`Date` in a rule, as `polkit(8)` suggests): rules have no
  state; one would need `polkit.spawn` reading a stamp a root helper writes. More moving
  parts than (b) for the same narrowness.
- **A root daemon with D-Bus actions:** (b)'s exposure with a resident root service to keep
  secure. Only if helpers ever need state.
- **Raising `ExpirationSeconds`, sudo's timestamp, NOPASSWD:** system-wide, per terminal, or
  no window at all.

## 4. Revoking: lock, "Forget now", restart

- **At lock**: the shell runs `pkcheck --revoke-temp` (trusted path, as pkexec's). It clears
  every kept authorization of the session — other programs' too, which is what a lock should
  do. The queue starts nothing while locked anyway; the revoke matters because code written
  into the shell's files could start pkexec itself while the user is away.
- **"Forget now"**: the same command (session-wide, said in the row's hint), no question —
  forgetting is harmless.
- **The shell restarting** ends it (the subject process is gone); a reload does not (same
  process).
- A revoke that fails (non-zero, pkcheck missing) is "unknown": the row says "Could not
  forget", and the next list decides what shows; logged once per change of outcome.
- To check in the trial on both machines: the agent's session and pkcheck's session are the
  same when the shell runs in a systemd user unit (uwsm and similar), so the revoke reaches
  the shell's kept authorizations.

## 5. Installing

The helper and the policy file are root files. The shell discovers what is installed with
`pkaction --verbose` (unprivileged): actions `org.h2s-shell.*`, their `exec.path`, whose
file must pass the trusted-program verdict (`ModuleRules.programVerdict`); otherwise the
remembered path is off and runs go the usual way, asking every time.

**NixOS** — an option of the shell's module:

```nix
programs.h2s-shell.polkit.remember = [ "tailscale-exit-node" ];   # default [ ]
```

adds a derivation to `environment.systemPackages` with `libexec/h2s-shell/<helper>` (the
tailscale path from `config.services.tailscale.package`) and
`share/polkit-1/actions/org.h2s-shell.remembered.policy` whose `exec.path` is the helper's
store path (NixOS links `share/polkit-1` into the system profile, where polkit reads
actions). An assertion asks for `services.tailscale.enable`. No `security.polkit.extraConfig`:
(b) needs no rule. Settings shows this line with Copy, as the PAM page does.

**Arch** — the shell writes, the PAM plan's way (`notes/plans/pam-config.md` §2.6):
- Files: `/usr/local/libexec/h2s-shell/<helper>` (root, 0755; directory root 0755) and
  `/usr/share/polkit-1/actions/org.h2s-shell.remembered.policy` (no package owns either name;
  that polkitd picks a new action file up without a restart is checked in the trial). Each
  starts with `Written by h2s-shell <sha256>`; a file changed by hand is shown and replaced
  only through "Replace…".
- Texts built by pure rules (`RememberRules.helperText(tailscalePath)`,
  `RememberRules.policyText(helpers)`), the tailscale path from the trusted-program verdict.
- One click "Install" → one pkexec run of a fixed command text in the shell's code through
  PrivilegedRuns: it checks the sha256 of what it got, backs the old files up to
  `/var/lib/h2s-shell/polkit-backup/<name>.<UTC time>` (root, 0700, all kept, on the list of
  places the shell writes), writes next to the target and renames, prints the hashes.
  "Remove" and Undo the same way. This install itself asks every time (an
  `org.freedesktop.policykit.exec` run); it is never remembered.
- No trial: a broken policy file only makes the action unknown, and runs fall back to the
  usual path.
- What root executes later is only the installed copy in the root-only directory; the
  helper's text lives in the user-writable tree only until a password-confirmed install —
  the same accepted risk as the PAM writes.

## 6. How it shows

Mockup first (`~/src/h2s-mockups/polkit-remembered/`), before any view code.
- **The prompt** (`polkit/AuthPrompt.qml`): for an action whose `implicit active` is
  `auth_admin_keep` (`pkaction`), one line under the password field: "Remembered for 5 min"
  (the minutes from `polkitd.conf` where readable, else 5). A rule may change it, and
  `/etc/polkit-1/rules.d` is not readable by the user on Arch, so the line is a promise of
  the action's default; the list below is the truth afterwards.
- **The run's dressing**: the queue ties a request to a helper run by its action id
  (`org.h2s-shell.*` and the head's helper) instead of pkexec's quoted command; Module,
  Authorization and the command stay as they are.
- **Settings → System → Authentication**, a section "Remember for a few minutes": per
  operation its state (installed / not / changed by hand) with Install/Remove (Arch) or the
  Nix line (NixOS); while something is kept: "Tailscale exit node · remembered, 4 min left"
  and "Forget now".
- **The module's mark**: an API reading lets the Tailscale module show its `PrivilegedMark`
  as needing nothing while the exit-node action is kept.
- **The truth** is `pkcheck --list-temp`, parsed by `RememberRules.parseList(text, nowMs)`
  (entries of actions `org.h2s-shell.*` whose subject is the shell's pid → `{ action,
  untilMs }`). Read after a helper run ends, after a revoke, and once a second only while a
  view shows a countdown (timers gated on visibility); nothing polls otherwise.

## 7. Tests (stand-ins only)

Never the real polkitd, pkexec, `/etc` or `/usr`.
- **Rules** (`tests/RememberRulesTest.qml`): the helper's argument grammar (the same cases
  the helper script runs), `policyText`/`helperText` (exact texts, hashes, round trip of the
  header), `parseList` on fixtures built from `pkcheck.c`'s format and on a capture taken by
  hand on each machine, the prompt's line, the queue's argv for a helper run.
- **The helper script**: run as the user on its template with a stand-in tailscale (an
  absolute path in a temp dir) — accepted and refused arguments, the time limit, exit codes.
- **The queue**: the module test kit's stand-in pkexec, a helper run without the outer
  timeout, its request tied by action id; the lock calling the stand-in pkcheck's
  `--revoke-temp` (a stand-in that records its calls); a failed revoke shown as unknown.
- **Arch install**: the fixed command run by the stand-in pkexec onto a temp tree, backups,
  rename, hashes, changed-by-hand detection; the guard that refuses a target under `/etc` or
  `/usr` in test mode.
- **NixOS**: `tests/system/nixos` evaluates the option — the policy's `exec.path` is the
  helper's store path, the assertion without Tailscale.
- **By hand, by the owner** (`tests/device/`, both machines): the second exit-node switch
  within 5 minutes asks nothing; a plain run of the shell (any other `pkexec`) still asks
  within the window; `pkexec <helper>` from a terminal asks (another subject); lock and
  "Forget now" end it; a shell restart ends it; under a systemd user unit too.

## 8. Slices

1. `RememberRules` (pure): grammar, texts, parser, prompt line; cases.
2. The helper template and its suite on a stand-in tailscale.
3. Discovery (`pkaction --verbose` → installed helpers, verdict) and the queue's helper runs
   (`PrivilegedRules`), the request tied by action id; the stand-in pkexec suite.
4. Revoke at lock and on demand, the list reader; stand-in pkcheck suite.
5. Module API (minor): the manifest names the remembered operation it uses
   (`"privileged": { "remembered": ["tailscale-exit-node"] }`), `module.privileged.remembered
   (name)` → frozen `{ available, untilMs }`, `start` with the helper; `CHANGELOG`
   `### Module API`, `api/Api.qml`. Then the Tailscale module uses it, falling back to today's
   run when not installed.
6. NixOS option and its evaluation test; Arch install/remove/Undo with the stand-in suite.
7. Views behind the agreed mockup; docs (ARCHITECTURE "Running as administrator", FEATURES,
   README), CHANGELOG.

**Note for the PAM plan** (§2.6.6 expects the second write to be quiet): with (b) it is not —
PAM writes run as `org.freedesktop.policykit.exec` and must never be remembered (a quiet PAM
write is root). Either two prompts stay, or one root run writes both services.

## 9. Open questions for the owner

1. **Narrow or sudo-like?** polkit keeps "this action for this process", whatever the
   command, and every process of yours can make the shell's process run things (by editing a
   file the shell loads). Sudo-like (a): after one exit-node switch, any root command through
   the shell passes for 5 minutes — `pkexec /bin/sh` too. Narrow (b): only the installed
   operations pass (switching the exit node), everything else still asks. Recommendation:
   (b).
2. **Which operations in the first version, and who ships them?** Each needs a small root
   helper that checks its arguments, installed by the system. Example: exit node only (a
   node, automatic, off); later perhaps connect/disconnect. Recommendation: exit node only,
   the helper shipped with the shell (only the system install can place root files), used by
   the Tailscale module through the API when present.
3. **Forget at lock?** While you are away, a remembered switch is usable by anything running
   as you. Example: lock with the window open → after unlock the next switch asks again.
   Recommendation: yes; "Forget now" and the lock clear all remembered authorizations of the
   session (other programs' too).
4. **How long?** polkit's length is one system-wide value (5 minutes), the same for every
   program; the shell can only end it earlier. Example: a setting "1 min" would mean the
   shell forgets after 1 minute. Recommendation: 5 minutes, no setting.
5. **Arch: install from Settings?** As with PAM: a click "Install" writes the helper and the
   policy file as root, with backups and Undo; NixOS gets the module line to copy.
   Recommendation: yes, the same way as the PAM page.
