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
  the password field (always there; typed before PAM asks, held), PAM's messages (a fingerprint
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

- 2026-11-15: "the prompt lets me in only with the finger" (the Framework, fprintd on).
  Found in the sources, not on a real prompt:
  - polkit's helper (`polkitagenthelper-pam.c`) calls `pam_start ("polkit-1", …)`: the
    service name is fixed, and the agent only starts a session (`polkit_agent_session_new`
    with an identity and the cookie) — no way to pick another stack or run a second
    helper. Its conversation relays PAM_TEXT_INFO / PAM_ERROR_MSG as messages and reads
    stdin only for PAM_PROMPT_ECHO_OFF/ON.
  - NixOS's polkit-1: `auth sufficient pam_fprintd.so` (11400), then `pam_unix.so
    likeauth try_first_pass` (11700), then pam_deny. pam_fprintd sends "Place your finger…"
    (info) and waits — 30 s per round (`DEFAULT_TIMEOUT`), three non-matching fingers
    (`DEFAULT_MAX_TRIES`) — ignoring the conversation's return value (`send_msg`) and
    anything the agent writes; only SIGINT inside the helper ends it early. Untouched it
    sends "Verification timed out" and returns PAM_AUTHINFO_UNAVAIL; `sufficient` goes on
    to pam_unix, which asks "Password:". A wrong password fails the attempt, and
    Quickshell's AuthFlow starts a new session — the reader first again.
  - The prompt showed the field only once `isResponseRequired` (the PAM question) came: for
    those 30 s it had PAM's message and Cancel, the focused field was hidden (so keys, Esc
    included, went nowhere). After a wrong password, another 30 s with "not accepted" and
    no field. So the password did work — after half a minute nobody waited for.
  - Changed: the field is always there; a password Entered before the question is held in
    it and sent the moment a hidden question comes (never into a shown one); a hint line
    from the conversation as it arrived (PolkitRules.conversation*, tested on both
    orders), the stack's order read from /etc/pam.d/polkit-1 (`Authentication.pamStack`);
    Esc on a focus scope; state reset when the next queued request takes the window.
  - System side, `programs.h2s-shell.polkit.passwordFirst` (NixOS module, default
    `services.fprintd.enable`): pam_fprintd's order = pam_unix's + 10. pam_unix fails an
    empty password without `nullok` (`verify_pwd_hash`), so Enter on an empty field goes
    on to the reader, and so does a wrong password (the prompt says it was not accepted;
    the password is asked again after the reader gives up). Its 2 s fail delay applies only
    when the whole stack fails. A system-wide change (every agent uses polkit-1), but the
    usual arrangement, and only the order moves.
  - Not adopted: shortening pam_fprintd (`timeout=`/`max-tries=` — still sequential);
    a parallel module like pam_fprintd_grosshack (not in nixpkgs).
  - Seen in Quickshell 0.3.2 while reading: `PolkitAgentImpl::initiateAuthentication`
    activates a request when the queue holds one — but the active request was popped from
    it, so a second request arriving while one is open replaces the open flow at once
    (the prompt now resets its state when `flow` changes).
