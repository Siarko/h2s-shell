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
  "password first, Enter for the finger" stack on Arch meets this (section 3, Q4).
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

## 2. What "configuring PAM rules from the shell" can safely mean

The user-visible scope, the same words on both systems:
- **Fingerprint for sudo** — off / on.
- **Fingerprint for administrator prompts (polkit)** — off / on.
- **Which comes first** for those two, where both exist: the password (Enter on an empty
  field goes on to the reader) or the reader (the password after it gives up).
- **Security key (U2F)** for sudo / polkit — off / on, only with a key registered.
- **The lock screen** — shown, not configured through PAM: which methods it offers and
  which config each uses (already known: `lock-auth-methods.sh`). An optional preference to
  not offer a method (Q7) needs no root.
- Out of scope, on purpose: `login`, `system-auth`/`system-login`/`system-local-login`, the
  display managers (greetd, sddm, gdm…), `su`, `other`, account/session/password phases.
  A fingerprint at login would leave the keyring locked and is where a broken stack locks
  the user out of the machine; `system-auth` is shared by everything.

**NixOS** — `/etc/pam.d` is generated (links into `/etc/static`); the shell never writes it.
1. It reads the generated files (world-readable) to show what is in force.
2. It says what to set: module options of ours (preferred, extending
   `polkit.passwordFirst`) — e.g. `programs.h2s-shell.pam.sudo.fingerprint = true;`,
   `programs.h2s-shell.pam.polkit.passwordFirst = true;` — or, if the owner prefers (Q2),
   the plain NixOS lines (`security.pam.services.sudo.fprintAuth = true;`,
   `security.pam.services.sudo.rules.auth.fprintd.order = …unix.order + 10;`), with a Copy
   button, as the VPN page does. The rebuild is the user's; the page re-reads afterwards.
3. Nothing to back up, nothing to break from the shell: a broken generation is rolled back
   by NixOS itself.

**Arch** — the files are root's; the shell may change them only like this:
1. **Only files we own or a block we own.** `polkit-1`: a new `/etc/pam.d/polkit-1` that
   shadows `/usr/lib/pam.d/polkit-1`; removing ours restores the vendor stack exactly.
   `sudo`: a block between `# BEGIN h2s-shell` / `# END h2s-shell` lines at the top of the
   `auth` lines; removal deletes exactly that block. A file with a pam_fprintd/pam_u2f line
   outside our block, or that we cannot parse, is shown and refused ("changed by hand").
   (pacman keeps `/etc/pam.d/sudo` as a backup file: our edit survives updates, a new
   upstream version lands as `.pacnew` — the page notices one and says so.)
2. **The new text is built by a pure rule** (`PamEditRules`), never by the root step.
   Fingerprint and key lines are always `sufficient` (never `required`): if the reader is
   missing or fprintd hangs, the stack goes on to the password exactly as before.
3. **Tried before it is installed.** The candidate is written to a private staging
   directory under `$XDG_RUNTIME_DIR` with copies of every file it `include`s/`substack`s,
   and one PAM conversation runs against it **as the user** (a `PamContext` with that
   `configDirectory`, as the lock does with `pam/`), started by the user's click on "Try":
   the user types the password / touches the reader. Only a success enables "Apply". Running
   a user-writable config as the user grants nothing; nothing is loaded as root from there.
4. **The root step is one pkexec run through PrivilegedRuns**, on the user's click, with a
   fixed command text in the shell's code (as the VPN install): it checks the candidate's
   sha256 (passed as an argument) against the bytes it got, copies the current file to a
   root-owned backup (`/var/lib/h2s-shell/pam-backup/<service>.<time>`), writes the new file
   next to the target and renames it into place (atomic), then prints the result's sha256.
   No helper script, no polkit rule that skips the password: every change asks. (If a
   helper is ever wanted, it is installed root-owned, as `/usr/local/libexec/...` is for the
   VPN, and never run from the checkout.)
5. **Afterwards** the shell re-reads the file, compares the hash, and offers "Undo" (restore
   the newest backup, another click, another prompt). No automatic revert: it would need a
   prompt nobody clicked.
6. Never leave the user without root: polkit and sudo are changed one at a time, never in
   one run, so a mistake in one leaves the other to repair it with; `su` and the root TTY
   login are never touched. The page names the backup paths so a TTY repair is a `cp`.

## 3. Risks

- **Lockout.** Mitigated by scope (no login/system-auth/DM files), `sufficient` lines
  only, the user-run trial, one service per run, backups and Undo. Residual: a trial
  passes but the real caller differs (sudo runs account/session lines the trial skips;
  `pam_faillock` counts). The trial covers `auth`, which is all we change.
- **pam_faillock (Arch).** Password-first in sudo means our own `pam_unix` before
  `include system-auth`; an empty Enter to reach the reader is then either a counted failure
  (if it goes through system-auth) or an uncounted one (if ours is `sufficient` and fails
  quietly) — the first can lock the account for minutes, the second weakens faillock (Q4).
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

## 5. The settings page (needs a mockup; not built before it is agreed)

Settings → System → Authentication, a new card "Fingerprint and security key" below the
polkit agent's rows:
- A status line per service ("sudo: password only" / "polkit: fingerprint, then password" /
  "lock screen: password, fingerprint"), from `PamStacks`; "not known" when a file cannot be
  read or parsed (never "off").
- Per service (sudo, polkit): a switch "Fingerprint", a switch "Security key" (disabled with
  a reason when no reader/no finger enrolled/no key registered), a two-choice "First:
  password / fingerprint".
- Arch: a change shows the lines that will be written (read-only text), then "Try" (the
  conversation's prompt inline: password field, PAM's messages), then "Apply" (the password
  prompt), then "Undo". A file changed by hand: its text and "Changed outside the shell —
  not edited".
- NixOS: the same switches build the lines to add, a Copy button, and "after
  `nixos-rebuild switch` this page shows the new state".
- Lock screen row: what it offers and from which config; the optional per-method switches.

## 6. Slices, in order

Core pieces first (pure, no UI, no root); each with its tests.
1. **PamStackRules** (pure): parse a service with `include`/`substack`/`@include` followed
   across an ordered directory list (`/etc/pam.d`, then `/usr/lib/pam.d`; NixOS the first
   only) → the `auth` lines in order, which of password/fingerprint/key come and in what
   order, faillock present, `required` vs `sufficient`. `PolkitRules.pamStackOrder` becomes
   a call of it. Unit cases with Arch, NixOS, Debian-style `@include` fixtures.
2. **PamStacks** (singleton, read-only): reads polkit-1, sudo and the lock's configs from
   both directories (seamed), plus facts (NixOS, pam_fprintd.so / pam_u2f.so present,
   enrolled — from the methods script's existing answers). Fixes the Arch polkit hint.
   Suite on stand-in directories.
3. **PamEditRules** (pure): current text + wanted state → new text with our marked block /
   our own polkit-1, or a refusal with a reason; removal exact; and the NixOS text (module
   options or plain lines). Unit cases, round trips (add then remove = original bytes).
4. **NixOS options** `programs.h2s-shell.pam.{sudo,polkit}.{fingerprint,securityKey,
   passwordFirst}`, `polkit.passwordFirst` kept as the old name of one of them. A test
   checks the module text as NetworkTest does for the VPN module.
5. **Trial** (Arch): staging dir builder + a `PamContext` adapter as in `PamMethod.qml`;
   suite against lock-bed-style `pam_exec` stacks.
6. **Apply / Undo** (Arch): the fixed root command through PrivilegedRuns, its result read
   by a pure rule (`PamEditRules.applyReply`); suite with the stand-in pkexec on a temp dir.
7. **Mockup** of section 5 (mockup gallery, tracker "Later"), agreed by the owner.
8. **The page**, behind the mockup; then docs (FEATURES, ARCHITECTURE "Authentication"),
   README "Lock screen", CHANGELOG (Unreleased; a new module option is a minor).
9. (Optional, Q7) lock per-method preference in `SettingsSchema` + a `LockRules` filter.

## 7. Open questions for the owner

Q1. On Arch, should the shell write PAM files at all, or only show the lines to add, as on
NixOS? Writing means: the user clicks "Apply", types the administrator password, and
`/etc/pam.d/sudo` gets a three-line block with a backup kept; showing means the user copies
the lines into the file with an editor themselves. Writing is more convenient and adds
slices 5–6; showing is safe by construction.

Q2. On NixOS, should the page show options of the shell's module
(`programs.h2s-shell.pam.sudo.fingerprint = true;`), which need the module imported, or
plain NixOS lines (`security.pam.services.sudo.fprintAuth = true;` plus an `order` line for
password-first), which work without it but are longer and depend on NixOS's rule names?

Q3. Which services belong on the page: only sudo and polkit, as planned, or also the login
at the display manager? A fingerprint at login, for example in greetd, would not unlock the
keyring (Wi-Fi passwords, browser secrets ask again) and is where a broken stack keeps the
user out of the machine — so the plan leaves it out.

Q4. On Arch, password-first for sudo collides with pam_faillock: Enter on an empty field to
reach the reader is either counted as a failed password (five of them in ten minutes lock
the account for ten minutes with a common setting) or must bypass faillock for that one
line. Which do you want — fingerprint-first only on Arch, password-first with the empty
Enter counted, or password-first with our own uncounted pam_unix line?

Q5. Is a mandatory "Try" before "Apply" acceptable? It means typing the password (or
touching the reader) once in the shell's own field, as the user, before the administrator
password is asked for the change itself — two steps for one switch, but a stack that would
not let the user in is never installed.

Q6. Where should Arch backups live and how many are kept? The plan says
`/var/lib/h2s-shell/pam-backup/<service>.<time>`, root-owned, all kept; an alternative is
one backup per service next to the file (`/etc/pam.d/sudo.h2s-shell-backup`), easier to find
from a TTY but visible to every tool listing `/etc/pam.d`.

Q7. Should the lock screen get a preference to not offer a method that the machine has —
for example, a laptop with an enrolled finger where the user wants only the password on the
lock while keeping the fingerprint for sudo? It needs no root and is slice 9.

Q8. Should the page also offer security keys (pam_u2f) for sudo and polkit in the first
version, or fingerprint only first? Keys add `authfile`/`cue` handling to the edit rules and
a "no key registered" state; the lock already supports them.
