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
