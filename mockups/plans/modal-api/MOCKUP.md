# The modal in the module API (planning)

## Purpose

Shows where the shell's modal (`components/SettingsModal.qml`) can stand once a module asks
through the API, before any code: over the Settings window as today, over a bar popup (two
options), over a module's side panel, and the Tailscale questions the owner listed (Log out,
Serve Stop all, Taildrop Save over a taken name). One stage per scene (a stand-in desktop with
the bar and the Tailscale popup, or a stand-in Settings window on the Tailscale page) and a
note under it.

Open on a screen: `tests/mockup.sh open plans/modal-api` (`--scene <name>` for one scene).
The last scene, `modal-api-live`, is interactive. Headless:
`tests/run-mockups.sh --shoot plans/modal-api`.

Real pieces: the theme, `SmallButton`, `SettingsModal` (its look, sizes, dim, keys).
Stand-ins: the bar, the Tailscale popup's rows, the Settings window's frame, sidebar and page,
the side panel.

## Scenes

1. `settings-today`: the shell's own question over the Settings window (deleting a theme):
   today's host, unchanged.
2. `popup-inside`: option A — the dim and the panel inside the popup body only. The panel is
   314 px wide (popup 350 less twice the padding) instead of 380; a short popup cuts it.
3. `popup-screen`: option B, proposed — the popup's surface (already as large as the screen
   below the bar) widens its input mask while a question is open, dims that whole area and
   centres the modal at its usual width. The bar stays usable.
4. `side-panel`: Taildrop "Save all" from the Files… side panel: the window, the dimmed page
   and the side panel all under the modal.
5. `module-logout`: Tailscale Log out from its page, a danger question.
6. `module-stop-all`: Serve Stop all, naming what stops as a list (`items`).
7. `keyboard`: nothing lit on opening; Tab goes left to right (Replace, Keep both, Cancel),
   Shift+Tab back, Escape answers cancelled.
8. `modal-api-live`: Save or Save all in the popup; a taken name asks; the answer is printed
   as the module would get it; "Lock the session" and "Close the popup" withdraw an open
   question (`blocked: "locked"` / `"closed"`).

## The proposed API

```
module.ask(from, question, done)  → handle { open (bool), cancel() }
  from      an Item of the module's where it asks (the clicked button): the shell walks up
            from it to the place's host — the Settings window, a side panel's page, a bar
            popup (its own or an anchor's)
  question  { kind: "danger" | "warning" | "success" | "info",
              title, body: [lines: string | { text, strong }], items: [strings],
              checks: [{ key, label }],
              buttons: [{ id, label, kind, privileged }], cancelLabel,
              size: "s" | "m", subject }
  done(answer)  once, frozen: { button (the id, "cancel" when cancelled), cancelled,
            blocked: "" | "locked" | "busy" | "place" | "closed" | "module", values (the
            checks), subject }
```

- `cancelled`: the user's own no (Cancel, ×, Escape). `blocked`: not asked or withdrawn by
  the shell, told apart from cancelled as the file chooser does — "locked" (the session is
  locked or locked while open), "busy" (another question is open: one at a time in the whole
  shell), "place" (refused where it stands: the bar itself, the tray menu, an anchor in no
  popup or window, the lock screen), "closed" (the window, the page or the popup it stood in
  closed), "module" (the module was disabled or reloaded: answered while its items are being
  torn down, so the handler only sets the module's own state).
- A callback with a handle, like `module.chooseFiles`, rather than a Promise: the API's one
  asynchronous style.
- Button labels: the button text rule (one line, at most 3–4 words). Until the overflow
  mockup (HS-238) decides, the API documents the rule and logs a longer label once.

## Proposed wording (stand-ins)

- Log out: "Log out of Tailscale?" — "This computer leaves the tailnet … until you log in
  again." / "Its exit node, the routes it shares and its Serve shares stop; the account stays
  in the list." Buttons: Log out, Cancel.
- Stop all: "Stop all Serve shares?" — "These stop at once, also the ones this page does not
  list:" and the list. Buttons: Stop all, Cancel.
- Save: "The name report-2026.pdf is taken" / "2 names are taken" — "Files of these names are
  already in ~/Downloads:" / "Keep both saves the new one as “name (1)”." and the list.
  Buttons: Replace, Keep both, Cancel.

## Open questions

- Popup: option A or B (proposed B: the modal looks the same everywhere).
- In option B, should a click on the bar while a question is open still act (proposed: yes; a
  popup switched or closed by it withdraws the question, `blocked: "closed"`)?
- Replace's warning outline and the keyboard ring are close on a warning button (scene
  `keyboard`): left for the themes' rework, or a clearer ring now?
