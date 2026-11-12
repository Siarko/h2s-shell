# Plan: the shell as the polkit agent (TODO 11.35), and the System tab (11.36)

Agreed with the user 2026-11-12.

## Why

A program needing admin rights (NetworkManager for system connections, systemd,
`pkexec`, installers) asks polkit; when a password is needed, polkit asks the session's
authentication agent to show a prompt. Neither machine runs one, so such requests are
refused silently. Quickshell's `Quickshell.Services.Polkit` lets the shell be the agent
with its own themed prompt (`PolkitAgent` registers on creation and unregisters when
destroyed; `AuthFlow` carries the message, action, identities, prompt, `submit`/cancel).

## Decisions

- **Built in, switchable**, self-contained (its own singleton and window), so it can
  become an optional module later with the mechanism dictation needs (11.24).
- **Not simply on.** `system.polkitAgent` starts undecided. At the shell's first start,
  after a wait (agents started by the compositor get going): a known agent's process
  running → off; none → the shell tries to register: it does → on; it does not (an agent
  it does not know holds the session) → off. Written once (a global setting); the user
  changes it later.
- **Told plainly, as far as can be seen.** polkit logs neither agents nor refusals, and a
  refusal reaches only the program that asked (watching the system bus needs root). So:
  - the shell's own privileged requests (the System tab) know their result: refused with
    no agent → a notification offering to turn the shell's agent on
    (`Authentication.reportDenied`);
  - at start: the shell's agent off and no known agent running → one notification, "Turn
    on";
  - the shell's agent on but another agent's process appears (it cannot register then),
    or the shell could not register → a notification offering to turn the shell's off.
- **The prompt**: an overlay on the focused screen, exclusive keyboard focus, the
  background dimmed; what asks (message, action id), the account when several can answer,
  the password field (hidden unless PAM says otherwise), PAM's messages (a fingerprint
  reader's "place your finger" needs no password), a wrong password shown and asked
  again, Cancel and Esc. The lock screen card's look. The password is never logged.
- **System tab**: a third tab, "Settings of this computer, kept by the system — they apply
  at once, in every profile". No profile picker there. First page: Authentication.
  The agent's setting lives there although the shell holds it: it is not per profile and
  it is about the system's prompts.

## Code

- `singletons/PolkitRules.qml` — pure: the known agents, the first-start decision, the
  state shown (tested).
- `singletons/Authentication.qml` — the setting, the agent (a LazyLoader of PolkitAgent),
  the first-start decision, the process scan, the notifications, `reportDenied`.
- `polkit/AuthPrompt.qml` — the prompt window; `shell.qml` creates it while a request is
  open.
- `panels/settings/AuthenticationSettings.qml`, the System tab in `SettingsWindow.qml`.

## Progress

- 2026-11-12: built — rules (tested), the singleton with the first-start decision, the
  probe and the notifications, the prompt, the System tab with Authentication. On the
  host the first start found no agent and turned the shell's on; `pkexec true` opened the
  prompt (message, action, account, field) and cancelling it closed the prompt. Left to
  the user: a real password, a wrong one, the Framework by touch.
- 2026-11-12: on the Framework the first start turned the agent on but it ended
  "blocked": the agent of the successful try was destroyed and made again at once, and
  polkit refused the new registration before letting the old go. The agent of the try now
  stays (`_keepAgent`), and a refused registration is retried three times, 2 s apart,
  before it counts as another agent's (also covers a restart, the old shell not yet gone).
  The warnings are critical notifications, whose toasts now stay until dismissed.

