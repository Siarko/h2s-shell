# Next steps

The order the owner set on 2026-11-15, after the module host, the VPN provider
seam and the first Tailscale step were merged to `master`. Details live in the
plans named beside each item; this file only fixes the order.

## 1. Tailscale, to completion

Module repository: `h2s-shell-tailscale`. Plan: [tailscale.md](tailscale.md), §8
(delivery steps 2–6). Goal: as many Tailscale features as possible, ideally all.

1. Accounts (switch, add, log out), hostname, re-authentication, diagnostics.
2. Advertising (exit node, routes, tags) and Tailscale SSH.
3. Taildrop.
4. Serve, funnel, certificates, tailnet lock status, exit node per network.
5. The module's own bar widget.

Small items from the first real use, to take along:

- the muted status line has low contrast on the green tint of an active row
  in the network popup;
- the page's "Tailnet" field shows an e-mail address for a personal tailnet,
  although the entry name deliberately never does.

## 2. The rest of the module system

Plan: [modules.md](modules.md).

1. M4 — install from a repository: the user declares a repository link, the
   shell installs the module (`modules sync`), Settings → Modules page.
2. M5 — NixOS packaging, the safe-mode banner, the author guide.
3. M6 — signatures.

## 3. Texts and languages (large; added 2026-11-16)

The owner's words: the hints and other texts in the settings "sound very
strongly like AI"; all of them need a pass. Combine it with language support,
since today everything is English only.

1. Inventory: every user-visible string in the shell and in the modules
   (settings labels, hints, tooltips, warnings, notifications, the lock
   screen, the polkit prompt, popups).
2. A voice guide agreed with the owner before rewriting: short, plain,
   the way a person would say it; a handful of before/after examples the
   owner approves. No explaining the obvious, no stacked clauses.
3. Translation mechanism: decide between Qt's own (`qsTr`, `.ts`/`.qm`
   files — check what Quickshell supports and how it reloads) and a small
   string table of the shell's own; language chosen in the settings,
   following the system locale by default; the module API gets a way for a
   module to ship its own translations.
4. Rewrite the English texts by the guide, then add Polish as the first
   second language. The owner reviews the texts — this is not a task to
   finish unattended.

## Backlog (no order)

- The lock test `fallback` failed once (the PAM stand-in never answered):
  find out why.
- Module widgets pop in after the first frame.
- A start guard for slow crash loops.
- Quickshell 0.3.2: a second polkit request arriving while a prompt is open
  replaces the open one, which is then never finished (upstream).
- `SmallButton` / `DeleteButton` have no keyboard focus or activation.
- Opened connection cards have about 20 px of empty space under the detail
  line (the action stack is taller than the two text lines).
- The module's live suites depend on machine load (about 50 scenarios, each a
  shell client with stand-in processes): they pass ten runs in a row at load
  40, but any new scenario should wait on conditions, never on fixed sleeps.
- Tailscale, left for later (details in tailscale.md §8): re-authentication
  without the profile reset (`login-interactive`), re-applying settings after
  a same-account login, certificate renewal, a terminal launcher for SSH.
- Never clicked on a real machine: the file and folder dialogs of Taildrop.
