# PAM configuration from the shell — analysis and plan

Tracker: order of work, step 1 (this plan) and step 11 (the work). Decisions it starts from
(`notes/decisions.md`, "Lock and PAM"): the order of password and fingerprint is the
system's PAM stack, not the prompt's; configuring PAM rules from the shell is wanted.

## 1. What exists

**Lock screen** — every way of unlocking is a PAM conversation of its own, side by side
(`singletons/lock/PamMethod.qml:44-67`, one `PamContext` each; Quickshell runs only
`pam_authenticate`, so only `auth` lines count). Which config each uses is decided by
`scripts/lock-auth-methods.sh:89-107`: `/etc/pam.d/h2s-shell-<method>` when readable, else
the shipped `pam/<method>`; on NixOS the passive methods only from `/etc/pam.d` (modules
named without a path are looked for only in libpam's store directory), and the password
falls back to `login` there. The fallback is the same choice as a pure rule
(`singletons/LockIoRules.qml:75-90`), fed by `--fallback-facts` (`lock-auth-methods.sh:54-59`).
- `pam/password`: `auth required pam_unix.so`, no `nullok`, no faillock (`pam/password:15`).
- `pam/fingerprint`: `auth required pam_fprintd.so timeout=-1` (`pam/fingerprint:19`);
  offered when fprintd over D-Bus has a finger enrolled (`lock-auth-methods.sh:176-296`).
- `pam/u2f`: `auth required pam_u2f.so cue` (`pam/u2f:14`); offered when the user has a key
  where that config's pam_u2f looks (`lock-auth-methods.sh:109-174`).
- For the lock there is no "order": the methods run at once. Nothing here needs root.

**polkit prompt** — `singletons/Authentication.qml` is the agent; polkit's helper runs one
stack, `polkit-1`, whatever agent shows it. The shell only reads it: `FileView` on
`/etc/pam.d/polkit-1` (`Authentication.qml:54-65`) → `PolkitRules.pamStackOrder`
(`singletons/PolkitRules.qml:336-367`: "fingerprint-first" / "password-first" / "password" /
"" for unknown or an `include`) → a hint in Settings
(`panels/settings/AuthenticationSettings.qml:92-101`) and the prompt's wording.

**NixOS module** (`nix/module.nix`)
- `programs.h2s-shell.polkit.passwordFirst` (`:32-46`, default = `services.fprintd.enable`):
  moves pam_fprintd to pam_unix's order + 10 in `polkit-1` (`:73-75`). The one existing
  "PAM rule from the shell", as a module option.
- `h2s-shell-password` (`:86-99`): NixOS's usual stack with every second-factor/passive
  switch `mkDefault false`; `h2s-shell-fingerprint` (`:112-117`) and `h2s-shell-u2f`
  (`:121-126`, with the machine's `security.pam.u2f.settings`, `cue` forced) as whole texts at
  `mkOverride 900`, only when fprintd / pam_u2f are enabled.

**Arch** — `install.sh:85-96` only prints what to install (fprintd, pam-u2f) and warns that a
system-wide `h2s-shell-password` must not be `include system-auth` (pam_faillock). It writes
nothing under `/etc/pam.d`. README "Lock screen" (`README.md:116-140`) says the same.

**Findings while reading**
- On Arch, `polkit-1` is not in `/etc/pam.d`: polkit ships `/usr/lib/pam.d/polkit-1`
  (libpam's vendor directory, read when `/etc/pam.d` has no file of that name), and it is
  `auth include system-auth`. So `Authentication.pamStack` is "" on Arch twice over (wrong
  directory, and `include` is not followed) and Settings shows no hint.
- Arch's `system-auth` puts `pam_faillock` around `pam_unix` (`[default=die] pam_faillock.so
  authfail`): a failed or empty password ends the stack and counts toward the lockout. Any
  "password first, Enter for the finger" stack on Arch meets this (§2.4).
- **Root precedent**: the VPN blocking installs its script with one pkexec run of a fixed
  `sh -c` text from the shell's code (`singletons/network/VpnLockdown.qml:490-506`) and on
  NixOS shows a module to save instead (`NetworkRules.lockdownNixosModule`,
  `NetworkRules.qml:1376`). PrivilegedRuns (`singletons/PrivilegedRuns.qml:7-36`) is the
  queue every shell-side root run goes through: one prompt at a time, never while locked.
- **Test precedent**: the lock bed never meets the real stack — `pam/` in its copy only
  denies (`tests/lock/run.sh:314`), the "system" PAM directory is the test's own
  (`H2S_LOCK_SYSTEM_PAM_DIR`, `tests/lock/lib.sh:417-422`, `Lockscreen.qml:131-132`), stacks
  are `pam_exec`/`pam_deny`/`pam_permit` with absolute module paths
  (`tests/lock/pam/password`). `scripts/seams.sh` holds the shell's seams as constants.

## 2. What "configuring PAM rules from the shell" means: the rule editor

The owner's answers (§7) turn the few switches of the first draft into a visual rule editor:
per service an ordered list of rows, tried from the top as PAM runs a stack, each row a
method with PAM's own control word and the method's details. The list generates the service's
`auth` lines; Arch gets them written (after a trial), NixOS gets the same rows as options of
the shell's module to paste.

### 2.1 Scope

- **Services**: sudo and polkit (`polkit-1`) only. One rule list serves both by default; the
  switch "Separate rules for administrator prompts" splits it into two lists (sudo; polkit).
  Turning the switch off while the lists differ asks in a warning modal (§5) "Use sudo's rules
  for both?" — polkit's list is replaced by sudo's. Writes still go one service per run (§2.6).
- **Only `auth` lines.** `account`, `password` and `session` lines are never written; the
  trial covers `auth`, which is all that changes.
- **Out of scope, on purpose**: `login`, `system-auth`/`system-login`/`system-local-login`,
  every display manager (greetd, sddm, gdm…), `su`, `other`. A fingerprint at login would leave
  the keyring locked and is where a broken stack keeps the user out of the machine;
  `system-auth` is shared by everything. A login manager of the project's own is a later
  analysis (tracker "Later"), not part of this plan.
- **The lock screen** is not configured through PAM: Settings → Lockscreen gets switches to
  not offer the fingerprint or the security key (§2.8). No root, no system file.

### 2.2 Rows

A service's rules are an ordered list of rows `{ method, control, details }`. PAM tries them
from the top; the generated lines are in the same order.

| Method | Module | Details (the row's chips) | Offered when |
|---|---|---|---|
| Fingerprint | `pam_fprintd.so` | Timeout, 5–120 s (`timeout=`, default 10); Tries, 1–10 (`max-tries=`, default 3). "Not counted" (fprintd has its own tries) | fprintd answers over D-Bus and a finger is enrolled |
| Security key | `pam_u2f.so` | Ask for the key's PIN (`pinverification=1`, off by default); `cue` always on; the keys file is pam_u2f's default (`~/.config/Yubico/u2f_keys`), shown with the number of keys in it | `pam_u2f.so` is installed and the user's keys file has a key |
| Password | `pam_unix.so` | Failures count (pam_faillock), Arch only, where the system's rules have pam_faillock (§2.4) | always |
| Password (as the system) | the service's own auth lines | none: read-only, fixed last (§2.3) | always |

Never offered or written: `nullok`, `nouserok`, `debug`, a keys file outside the user's home,
any other module. The facts ("offered when") come from the methods script's existing answers
(`lock-auth-methods.sh`) and `PamStacks`; a fact that cannot be read is "unknown" and treated
as absent.

**Control words** (the owner's answer A): the row shows the word PAM uses, and a plain
explanation under the picked word and as its tooltip:

| Word | Explanation in the editor |
|---|---|
| `sufficient` (the default for a new row) | "Enough on its own: if it passes, you are in; if not, the next row is tried." |
| `required` | "Must pass. The next rows still run; a failure is told at the end." |
| `requisite` | "Must pass. A failure ends it at once." |
| `optional` | "Counts only when no other row decides." |

Rows carry only these four words; the generated lines may use PAM's bracket syntax where a
pattern needs it (the counted password, the closing line), never shown as a row's word.

**How a row is written** (Arch; NixOS through the module, §2.7):
- A `sufficient` or `optional` fingerprint or key row is written `-auth <word> pam_…so …`:
  the `-` makes libpam skip the line when the module is not installed (a package removed
  later), so the row falls away instead of breaking the stack.
- A `required` or `requisite` fingerprint or key row is written as plain `auth`: a missing
  module then fails the stack — a second factor never silently disappears. Such a row is
  refused while the method is not ready (R2).
- An uncounted Password row: `auth <word> pam_unix.so try_first_pass`.

### 2.3 The fixed last row, and `include system-auth`

"Password (as the system)" is the service's own `auth` lines, kept as they are: on Arch,
sudo's `auth include system-auth` and the vendor polkit file's `auth include system-auth`
(system-auth: `pam_faillock preauth`, `pam_systemd_home`, `pam_unix … nullok`,
`pam_faillock authfail`, `pam_env`, `pam_faillock authsucc`); on NixOS, the auth rules NixOS
generates for the service. The shell's rows go above it. In the editor it is the last row,
with a lock instead of the handle; it cannot be moved, edited or have rows put below it. The
preview shows it folded as "kept as it is", and unfolded the lines the include brings in
(PamStackRules follows the include, read-only).

A row above it that lets the user in (a `sufficient` fingerprint) ends the stack, so the
system's lines below are not run — exactly as every distribution's "fingerprint for sudo"
works; their pam_faillock reset and pam_env are skipped on that path.

**Removing it** (the owner's answer B) goes only through a danger modal (§5) that says what is
lost: the system's way of asking the password, pam_faillock's counting, systemd-homed
accounts. Without it the shell's block ends with a closing line, so the system's lines are
never reached — the original `include` line stays in the file, unreached, and putting the row
back removes only the closing line:
- a list with a `required` or `requisite` row ends with `auth [default=done] pam_permit.so`
  (it keeps the result those rows set: their failure stays a failure);
- a list of `sufficient`/`optional` rows only ends with `auth requisite pam_deny.so` (reached
  only when no row let the user in). An `optional` row alone then does not let the user in —
  stricter than PAM's own rule, and W5 says so.
Both are unit cases and lock-bed-style scenarios (§4) in the trial suite.

### 2.4 pam_faillock: what counts and how it shows

Arch's system-auth counts wrong passwords (`/etc/security/faillock.conf`: `deny`,
`fail_interval`, `unlock_time`; libpam's defaults 3, 900 s, 600 s when unset). The editor
shows it on the rows:
- the fixed row carries a chip "Counts: 3 wrong in 15 min lock 10 min" (read from
  faillock.conf; "Counts: not known" when it cannot be read);
- an own Password row has the detail "Failures count", on by default (§7b Q2), and a chip
  "Counted" / "Not counted";
- fingerprint and key rows say "Not counted".

A counted Password row is written as a fixed pattern, e.g. for `sufficient`:

```
auth  required                      pam_faillock.so preauth
auth  [success=done default=ignore] pam_unix.so     try_first_pass
auth  optional                      pam_faillock.so authfail
```

and for `required`/`requisite` the system's own shape (`[success=1 default=bad]` on
pam_unix, then `[default=die] pam_faillock.so authfail`). `preauth` being `required` means a
lockout closes the whole service, reader included, as the system's own rules do. A success
through the row does not reset the count (only the system's `authsucc` does; the count
expires after `fail_interval`) — said in the row's hint. The exact lines are fixed in
`PamEditRules` with unit cases, and run in the trial suite against a stand-in counter.

The preview marks counted lines, and two warnings name the trade-off (W3, W4): a counted
Password row above a reader turns the empty Enter used to reach the reader into a wrong
password; an uncounted one is outside the lockout.

### 2.5 Refused and warned lists

One pure function, `PamRuleRules.check(rows, facts)` → `{ refusals, warnings }`, each item
`{ code, row, text }` (`row` −1 for the list). `facts`: `{ system, service, fingerprint,
securityKey, faillock, otherService }` — `fingerprint`/`securityKey` "ready" / "absent" /
"unknown", `faillock` the parsed numbers or null, `otherService` the other service's rows (in
force or pending). Every code is a unit case; the editor shows refusals in red under the list
with the row marked, warnings in the warning colour; Apply (and on NixOS Copy) is off while
there is a refusal.

Refused:
- **R1 No way in**: no row can let the user in with what the machine has now — no password
  row of either kind and every reader/key row's method not "ready" ("unknown" counts as not
  ready).
- **R2 A required second factor that cannot pass**: a `required`/`requisite` fingerprint or
  key row whose method is not "ready" (written as plain `auth`, it would fail every time).
- **R3 Empty list**: no rows at all.
- **R4 Out of range**: a detail outside its range (timeout 5–120 s, tries 1–10), an unknown
  method or word (only reachable from a hand-made NixOS option or a damaged block; the
  editor itself cannot make one).
- **R5 Both closed**: neither sudo nor polkit would keep a password row (this list and
  `otherService`) — the user must keep one of the two as the way to repair the other.
- **R6 Changed by hand**: the service's file is refused as a whole (§2.6.1); the editor is
  read-only.

Warned (Apply stays; the trial proves the rows work now):
- **W1 Only a reader**: no password row — "Only the reader lets you in. If it breaks, use the
  other service, su or a root console."
- **W2 Two factors**: a `required`/`requisite` reader or key row — "Both needed: without the
  reader nobody gets in."
- **W3 Empty Enter counts**: a counted Password row above a reader row — "An empty Enter to
  reach the reader counts as a wrong password (3 lock you out for 10 min)."
- **W4 Not counted**: an uncounted Password row where the system counts — "Wrong passwords in
  this row are not counted."
- **W5 Does nothing**: an `optional` row in a list where another row decides.
- **W6 Asked twice**: the same method in two rows.
- **W7 Password again**: an own `sufficient` Password row above the fixed row — "A wrong
  password is asked again by the last row."
- **W8 Not saved**: split lists that differ only because a shared Apply stopped between the
  two services (§2.6.6).

### 2.6 Arch: writing

1. **Only files we own or a block we own.** `sudo`: our lines between `# BEGIN h2s-shell
   <sha256>` and `# END h2s-shell` at the top of the `auth` lines; the hash is of the lines
   between, so an edit inside the block is noticed. `polkit-1`: a new `/etc/pam.d/polkit-1`
   that shadows `/usr/lib/pam.d/polkit-1`, its first line `# Written by h2s-shell <sha256>`,
   our rows above the vendor file's auth lines, its other lines copied from the vendor file;
   removing ours restores the vendor stack exactly. **Changed by hand** (refused, R6): the
   block's hash does not match; a `pam_fprintd`/`pam_u2f` line outside our block; a
   `/etc/pam.d/polkit-1` not written by us; a file `PamStackRules` cannot parse. The page then
   shows the file's text with the offending lines marked and "Changed outside the shell — not
   edited" (§7b Q1). pacman keeps `/etc/pam.d/sudo` as a backup file, so our block survives
   updates and a new upstream version lands as `.pacnew`, which the page reports; for polkit,
   the copied lines are compared with the vendor file and a difference reported ("polkit's own
   file changed: Apply again to take it over").
2. **Built by a pure rule.** `PamEditRules.build(currentText, rows, facts)` → the new text or a
   refusal; `PamEditRules.rows(text)` reads our block back into rows. Round trips: rows →
   text → rows; adding then removing the block gives back the original bytes.
3. **Always tried before it is installed** (answer C). Apply opens the trial modal: the
   candidate is written to a private staging directory under `$XDG_RUNTIME_DIR` with copies of
   every file it includes, and one PAM conversation runs against it as the user (a
   `PamContext` with that `configDirectory`, as the lock does); the user authenticates as the
   new rules ask (touches the reader, types the password). Running a user-writable config as
   the user grants nothing; nothing is loaded as root from there. A failure writes nothing. A
   shared list whose auth lines come out the same for both services is tried once.
4. **The root step** follows the trial's success without another click (the click on Apply
   started it): one pkexec run through PrivilegedRuns with a fixed command text in the shell's
   code; it checks the candidate's sha256 (an argument) against the bytes it got, copies the
   current file to `/var/lib/h2s-shell/pam-backup/<service>.<UTC time>` (directory root-owned,
   0700; every backup kept, answer Q6), writes the new file next to the target and renames it
   into place, then prints the result's sha256. No helper script, no polkit rule that skips the
   password. The backup directory goes on the list of every place the shell writes files, and
   its disk use under the later disk-space work (both tracker "Later").
5. **Afterwards** the shell re-reads the file, compares the hash and offers Undo (restore the
   newest backup: a click, a prompt, no trial — it is the state that was in force). No
   automatic revert: it would need a prompt nobody clicked.
6. **One service per run**: a shared list is written as two runs, sudo first, then polkit —
   two administrator prompts, two backups (§7b Q3). Each prompt is answered by polkit-1 still
   as it was. A cancel between leaves the lists different: the page shows them split, with W8
   and Apply for the one not saved. `su` and the root console login are never touched; the
   page names the backup paths so a repair from a console is one `cp`.

### 2.7 NixOS: the module's options

`/etc/pam.d` is generated; the shell never writes it. The page reads the generated files (what
is in force), runs the same editor and checks, and instead of Apply shows the snippet of the
shell's module options with Copy (answer Q2); "after `nixos-rebuild switch` this page shows the
new rules". A broken generation is rolled back by NixOS itself; there is no trial on NixOS.

```nix
programs.h2s-shell.pam = {
  # One list for sudo and polkit…
  rules = [
    { method = "fingerprint"; control = "sufficient"; timeout = 10; tries = 3; }
    { method = "system"; }
  ];
  # …or, with "Separate rules for administrator prompts", one per service:
  # sudo.rules = [ … ];
  # polkit.rules = [ … ];
};
```

- **Types**: `rules`, `sudo.rules`, `polkit.rules` are `nullOr (listOf (submodule { method =
  enum [ "fingerprint" "securityKey" "password" "system" ]; control = enum [ "sufficient"
  "required" "requisite" "optional" ] (default "sufficient"); timeout, tries = nullOr int; pin,
  counted = bool; }))`, default null = the service untouched. A service's own list wins over
  `rules`.
- **Translation**: each row becomes `security.pam.services.<svc>.rules.auth."h2s-<n>"` (`order`
  below the first of NixOS's own auth rules, in the rows' order; `control`; `modulePath` from
  the package — `pkgs.fprintd`, `pkgs.pam_u2f`, libpam's pam_unix; `settings` from the
  details). `{ method = "system"; }` stands for NixOS's own rules; without it the module adds
  the same closing line as §2.3 and turns NixOS's own auth rules for that service off.
- **Conflicts**: for a service with rules the module sets NixOS's own `fprintAuth` and
  `u2fAuth` to `mkDefault false`; a value set to true explicitly is an assertion ("sudo's rules
  come from programs.h2s-shell.pam: remove fprintAuth"). `polkit.passwordFirst` stays,
  deprecated: without polkit rules it does what it does now, with them an assertion asks to
  drop it.
- **Assertions** mirror R1–R5 where the module can know them (`services.fprintd.enable`,
  `security.pam.u2f.enable`); warnings W1–W2 become `warnings`.
- **Counting** on NixOS: pam_faillock is not in NixOS's default stack; the "Failures count"
  detail is offered only when the generated file has it.
- The snippet is built by `PamEditRules.nixosSnippet(rows, split)`, pure, with cases.

### 2.8 The lock screen

Settings → Lockscreen, a block "Ways to unlock" (answer F): Password — always offered, shown
as a switch that is on and cannot be changed ("Always offered"); "Fingerprint" and "Security
key" switches, `lockscreen.offerFingerprint` and `lockscreen.offerSecurityKey` in
`SettingsSchema` (default on), each off with a reason when the computer does not have the
method ("No finger enrolled", "No key registered"). A pure `LockRules` filter drops a switched-
off method from the list the methods script found. No root, no system file; sudo and polkit
are set on the Authentication page.

## 3. Risks

- **Lockout.** Mitigated by scope (no login/system-auth/DM files), the refused
  lists (§2.5: no way in, a second factor that cannot pass, both services without a
  password), `-auth` for optional readers, the user-run trial, one service per run, backups and Undo. Residual: a trial
  passes but the real caller differs (sudo runs account/session lines the trial skips;
  `pam_faillock` counts). The trial covers `auth`, which is all we change.
- **pam_faillock (Arch).** Password-first in sudo means our own `pam_unix` before
  `include system-auth`; an empty Enter to reach the reader is then either a counted failure
  (if it goes through system-auth) or an uncounted one (if ours is `sufficient` and fails
  quietly) — the first can lock the account for minutes, the second weakens faillock (§2.4, §7b Q2).
- **A stack broken by hand or by a package update.** Refused when not recognised; a
  `.pacnew` is reported, not merged.
- **Other agents and display managers.** polkit-1 serves every polkit agent; changes apply
  to them too (said on the page). DMs are never touched. A remote session (ssh) running
  sudo: pam_fprintd skips remote sessions itself in current versions; the page says the
  fingerprint is for this seat.
- **NixOS drift.** Lines shown for an option that the machine's config already sets
  otherwise; the page shows what is in force after reading, not what it assumed.
- **Root from a writable place.** The command text is in the shell's QML, which the user can
  write — acceptable only because every run asks the password (same as any pkexec use);
  no passwordless rule is ever installed for PAM changes.

## 4. How tests stay off the real PAM

- Every reader takes its PAM directories from a seam (`seam_system_pam_dir` exists; add the
  vendor directory as a second, `seam_vendor_pam_dir`, in `scripts/seams.sh` and the test
  tree's copy, checked by `TestSeamsShapeTest`), and a suite runs the reader on stand-in
  directories with Arch-shaped and NixOS-shaped fixtures (both systems on every machine).
- `PamEditRules`/`PamStackRules`: unit cases on fixture texts only.
- The trial: a suite runs it against a private staging dir whose "included" files are the
  lock bed's `pam_exec` stacks (accepts one test password), never `system-auth`.
- The apply command: run by the stand-in pkexec (the module test kit's pattern) with its
  target directory a temp dir; a guard refuses any target under `/etc` or `/usr` in test
  mode. Real pkexec and real `/etc/pam.d` only by hand, by the owner (`tests/device/`).

## 5. The settings page

Mockup: `~/src/h2s-mockups/pam-rules-planned/` (scenes switched at the top; `shoot.sh` takes
them headless). Not built before the owner has agreed it.

Settings → System → Authentication, below the polkit agent's rows, a section "Sign-in rules":
- **Status line** per service, from `PamStacks`: "In force: fingerprint, then the system's
  password · /etc/pam.d/sudo"; "not known" when a file cannot be read or parsed (never "off").
  Under it what this computer has: "Fingerprint reader: 1 finger · Security key: none
  registered".
- **The switch** "Separate rules for administrator prompts" (off: one list titled "sudo and
  administrator prompts"; on: two lists, "sudo" and "Administrator prompts (polkit)").
- **A list per service**: rows of pills — the drag handle, the method's pill (icon and name),
  the control word's pill, the details as small chips ("10 s", "3 tries", "Counted"), an arrow
  that opens the row, and the "×". An opened row shows the four control words as pills with
  the picked one's explanation under them, and the method's details (number fields, a
  switch). The last row is "Password (as the system)" with a lock for a handle and its
  pam_faillock chip; its "×" opens the danger modal. "＋ Add a row" opens the method list;
  a method the computer does not have is shown off with its reason ("No key registered"). A
  new row opens with `sufficient` picked.
- **Checks** under the list: refusals in red, warnings in the warning colour (§2.5).
- **Preview** (a "Show file" toggle): the generated file, read-only, our lines in the accent
  colour, counted lines marked, the system's lines muted "kept as it is" (unfolded: what the
  include brings).
- **Buttons**: Arch — "Apply" (save look; off with a refusal or with nothing changed),
  "Reset" (back to what is in force), "Undo" (after a write; names the backup), the backup
  folder named. NixOS — the snippet (§2.7) under the list with "Copy" and the rebuild line.
- **Apply**: the trial modal (info) — "Try the new rules": what to do ("Touch the reader or
  type your password"), PAM's messages and the password field inline, Cancel. On success it
  turns into the success modal while the administrator prompt opens; after the write, success
  "Saved" with the backup path (one button = informing). On failure a warning modal "Not
  saved": PAM's reason, "Try again", Cancel.
- **Changed by hand**: the list read-only and dimmed, the file's text with the offending
  lines marked, "Changed outside the shell — not edited", the reason ("A fingerprint line
  outside the shell's block"), "Read again".
- **Modals** are the Settings modal of the modules plan (`notes/plans/modules-management.md`
  §4.1: kinds danger/warning/success/info, the window dimmed, "×" = cancel, always a cancel) —
  no element of this page's own. Used for: removing the fixed row (danger), turning the split
  off with differing lists (warning), the trial and its outcome (info → success / warning).
- **Lock screen**: the switches of §2.8 on the Lockscreen page.

## 6. Slices, in order

Pure pieces first (no UI, no root), each with its tests; then the I/O; then the views behind
the agreed mockup.
1. **Reading stacks** (`PamStackRules`, pure): parse a service with `include`/`substack`/
   `@include` followed across an ordered directory list (`/etc/pam.d`, then `/usr/lib/pam.d`;
   NixOS the first only) → the `auth` lines in order, our block and its hash, faillock present;
   `faillock.conf` parsed. `PolkitRules.pamStackOrder` becomes a call of it. Unit cases with
   Arch, NixOS and Debian-style fixtures.
2. **`PamStacks`** (singleton, read-only): reads polkit-1, sudo, the lock's configs and
   faillock.conf from both directories (seamed: `seam_vendor_pam_dir` next to
   `seam_system_pam_dir`), plus the facts (NixOS; fingerprint/key ready from the methods
   script's answers). Fixes the empty polkit hint on Arch. Suite on stand-in directories.
3. **Rules and checks** (`PamRuleRules`, pure): the row model, the control words and their
   explanations, the methods' details and ranges, `check(rows, facts)` with every R and W
   code (§2.5) as a case.
4. **Text** (`PamEditRules`, pure): rows → the Arch block / our polkit-1 (the `-auth` rule,
   the counted pattern, the closing lines), text → rows, changed-by-hand detection, round
   trips; `nixosSnippet(rows, split)`. Unit cases.
5. **NixOS options** `programs.h2s-shell.pam.{rules,sudo.rules,polkit.rules}` with the
   translation, conflicts and assertions of §2.7; `polkit.passwordFirst` deprecated. A test
   checks the module's text, and `tests/system/nixos` evaluates it for a case set and compares
   the generated auth lines with `PamEditRules`' for the same rows.
6. **Trial** (Arch): staging builder + a `PamContext` adapter as in `PamMethod.qml`; suite
   against lock-bed-style `pam_exec` stacks, the closing lines and the counted pattern
   included (a stand-in counter for pam_faillock).
7. **Apply / Undo** (Arch): the fixed root command through PrivilegedRuns, one service per run,
   its reply read by `PamEditRules.applyReply`; suite with the stand-in pkexec on a temp dir.
8. **The Settings modal**: the modules plan's slice (V1); whichever plan reaches it first
   builds it, the other uses it.
9. **The rule list element**: rows of pills with the handle, the opened row, the fixed last
   row, the add list (the drag and add patterns of `ReorderList`, keyed by row id); a suite
   with clicks.
10. **The page**, behind the mockup; then docs (FEATURES, ARCHITECTURE "Authentication"),
    README "Lock screen", CHANGELOG (Unreleased; new module options are a minor).
11. **Lock-screen switches** (§2.8): `SettingsSchema` keys, the `LockRules` filter with
    cases, the Lockscreen page's block.

## 7. Decided

The owner, 2026-11-21 (`notes/decisions.md`, "Lock and PAM", to add with the first slice):
- Q1 Arch: the shell writes the PAM files — Apply with a backup, an owned block, Undo (§2.6).
- Q2 NixOS: the page shows options of the shell's module, `programs.h2s-shell.pam.*` (§2.7).
- Q3 Only sudo and polkit; login untouched. A login manager of the project's own is a later
  analysis (tracker "Later").
- Q4/Q5 Everything is clicked together in Settings as visual rules: rows (pills) with details,
  evaluated in order, generating the PAM config (§2.2).
- Q6 Backups in `/var/lib/h2s-shell/pam-backup`, all kept; the folder goes on a list of every
  place the shell writes files; disk-space management for the shell's files later (tracker
  "Later").
- A Rows use PAM's own control words, each with a plain explanation.
- B A fixed last row "Password (as the system)", removable only through a danger modal.
- C The trial is a fixed step: Apply → the trial modal → on success the administrator password
  and the write.
- D One rule list for sudo and polkit; "Separate rules for administrator prompts" splits it;
  writes go one service at a time.
- E Security keys (pam_u2f) in the first version, as one more row kind.
- F Settings → Lockscreen: switches to not offer fingerprint / security key on the lock (no
  root, no system files); the password cannot be switched off there.

## 7b. Open questions for the owner

Q1. **A file changed by hand: only refuse, or offer to replace it?** Example: someone added
`auth sufficient pam_fprintd.so` to `/etc/pam.d/sudo` with an editor, outside the shell's
block. The plan shows the file, marks that line and edits nothing; the user removes the line
by hand (or keeps it and leaves the shell out). The alternative is a "Replace" button: the
hand-made file goes to the backups and the shell writes its own. Replacing is convenient but
throws away rules the shell does not understand (a pam_ldap line, a second factor of another
kind). Recommendation: refuse only in the first version.

Q2. **Does an own "Password" row count wrong passwords by default?** Example: rows
"Password · sufficient" then "Fingerprint" — to reach the reader the user presses Enter on an
empty field. Counted (on): each empty Enter is a wrong password for pam_faillock; with libpam's
default (deny = 3) three of them lock sudo and polkit for a while. Not counted
(off): no lockout from the empty Enter, but a password guessed in that row is never stopped by
the lockout. Recommendation: on by default, with the warning W3 telling what the empty Enter
costs; the user switches it off per row.

Q3. **One list for both services: two administrator prompts on Apply?** Example: the shared
list gets a fingerprint row; Apply runs the trial once, then asks the administrator password
to write sudo, then again to write polkit. One prompt for both would mean one root run
changing both files — against the rule that a mistake in one service leaves the other to repair
it with. Recommendation: two prompts, the modal saying "1 of 2" / "2 of 2"; a cancel after the
first leaves the lists split with "Administrator prompts: not saved".
