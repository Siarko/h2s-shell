# Module API: the next versions

Status: a plan, for the owner's final approval. Every question asked is answered (§8).
Nothing here is built.

This file is the index: what the round gives, the rules for every slice, the direction,
the slice list, the lanes, the owner's answers. The design and each slice's files and
tests are in one file per area under [api-next/](api-next/). An agent given a slice reads
this file and the slice's area file.

| File | Holds | Sections |
|---|---|---|
| [commands.md](api-next/commands.md) | the command runner, program lookup with trust, test mode, privileged runs, the prompt | §3.1–3.4 |
| [facts.md](api-next/facts.md) | the module's main object, helpers, system and network facts, the file chooser, what is not in this plan | §3.5–3.10 |
| [places.md](api-next/places.md) | anchors: blocks, placements, names, building, the pin test, today's slots and the first consumer | §4.1–4.7 |
| [cards.md](api-next/cards.md) | a card's regions and buttons, a module's icon, the mark on a closed card | §4.8, §4.10 |
| [elements.md](api-next/elements.md) | public elements, kinds, sizes, pills, a module's own elements, the theme's tokens | §4.9 |
| [module-api.md](api-next/module-api.md) | a module's API for other modules; reach closed | §5 |
| [migration.md](api-next/migration.md) | what the module works around today; the module's slices; the closing slice | §1, §7 (step 6, Z) |
| [versioning.md](api-next/versioning.md) | the version rule and the floor, other authors, the doors to keep open | §6, §11 |

Section numbers (§) are kept from the plan as one file, so a reference reads the same
everywhere: §2, §7, §8 and §10 are here; §9 (verified, assumed, hard) is divided, at the
end of each area file.

## At a glance

**A module will be able to**
- run commands, also as administrator, through the shell (time limits, live output);
- put its own rows, buttons and opening parts at named places in the shell's settings
  pages, popups and network cards: before, after, at the start or at the end of a part;
- build its screens from the shell's public elements, choosing a kind (primary,
  secondary, danger, warning, success) and a size, and from elements of its own, made of
  QtQuick with the theme's colours and type sizes; never from the shell's internal
  components, so the shell can change its insides without breaking modules;
- show its icon on a closed network card; open a file chooser; offer an API to other
  modules.

**A user will see**
- buttons that stop or delete something with a coloured border, filling with the colour
  under the pointer (network and Bluetooth popups, network cards);
- the small choice buttons (pills) in three sizes; 2 pixels lower in the profile
  condition editor and the widget settings pane;
- a password prompt that says "Module" and "Authorization", the exact command one click
  away; with another password agent, a notification saying the same;
- the exit node of a network on that network's opened card, the Tailscale icon on the
  closed one; the table on the Tailscale page goes.

**Order of work**: 48 small changes, each with its test. (1) Running things and facts,
16. (2) Places, public elements, the new looks, the icon, 18. (3) A module's API for other
modules, 2. (4) The Tailscale module moves onto all of it, 11, then one change removes
the old ways.

**Risks**: rebuilding the network card (held by a test written on the old card); the file
chooser may not open from the shell (a one-day trial first; if it fails, that part
waits); telling the shell's own password request apart rests on the system message's
wording (read once by hand on NixOS and Arch); with another password agent one
administrator run waits for the other.

It covers tracker steps 3 (API extension), 4 (UI anchors) and 5 (a module's public API), and
says what step 6 (the Tailscale migration) then removes. The owner's decisions in
`notes/tracker.md` ("Decisions") are binding; this plan follows them.

References: the shell at `50129d9`, the Tailscale module (`h2s-shell-tailscale`, files under
its `module/`) at `13468e9`. `TC` is the module's `TailscaleClient.qml`, `TR` its
`TailscaleRules.qml`. "Verified" means read in the code at those commits; "assumed" is
marked. The lists are at the end of each area file (§9).

---

## 2. Rules for everything below

- **Callbacks, not promises;** results are plain frozen objects; errors are fields, never
  exceptions. Bad input gives a result with `error` set.
- **Decisions are pure functions** in `*Rules.qml` with unit cases; the new singletons only
  do I/O.
- **Module off.** Every object a module makes from `qs.api` lives under its main or its
  views. The host destroys them; no callback runs after that.
- **Session locked** (new read-only `Api.sessionLocked`, the shell's `Lockscreen.locked`). Plain runs continue (a VPN must
  follow the networks). Nothing that asks the user starts: no password prompt, no dialog.
  Those return `blocked: "locked"`.
- **Trust.** A module runs in the shell's process, which also holds the lock screen's
  password prompt and the polkit agent; QML has no sandbox, and no isolation is planned
  (the owner's decision, §10). Every guard below stops mistakes, not a hostile module.
  Wherever this plan names review as the guard, that is for the project's own modules.
  An outside module has no review: there the password prompt's text (Module,
  Authorization, the command) is the only protection, and the user is told that the
  module does not come from the project (§10). Step 8 writes this down for users.

---

## 6. Versioning, in brief

The whole rule is in [versioning.md](api-next/versioning.md).

- A slice that changes the API bumps the minor once and adds one `- 1.x:` line under
  `### Module API` in `CHANGELOG.md`.
- Slices in steps 3–5 only add; the old ways keep working and are listed in a module's
  `deprecations`. One closing slice (Z) removes them and raises the floor
  (`ModuleRules.apiFloor`: below it a module is `incompatible`, with the reason).
- A minor may remove things only until the first release announced as open to module
  authors; from then a removal needs a major version and a release listed as deprecated.

---

## 10. Direction

The owner's answers of 2026-11-17. Not slices: where the round's work is to fit.

- **The shell becomes a fairly small framework** that defines the structure and the way
  of working. Built-in features are split out into modules; some ship with the shell.
- **One class of modules.** A shipped module uses only the public API, like anyone's.
  Every feature split out proves the API.
- **The shell provides the services, or abstractions for reaching them;** a module builds
  on them and adds the whole feature: popups, elements, widgets, settings pages. Every
  built-in feature will be gone through and divided this way. The lock screen, password
  prompts and privileged runs stay in the framework.
- **Other authors.** Today every module is the owner's; later other users write modules.
  Until then the shell and its module system are built up so that they can do so without
  problems (tracker, "Ready for outside authors").
- **Trust: no isolation.** "Isolation makes no sense: the shell must work and modules
  need access to its functions." Running modules in a process of their own is not a later
  question. Instead the user must know what they install: a module that does not come
  from the project is announced as such, with a plain statement and a confirmation when a
  module that is not shipped is first enabled, and shown when a user's copy replaces a
  shipped one. It is then not the project's responsibility.
- **The order after this round** (the owner's decision): the author guide, a module
  template and a module's tests runnable without a checkout of the shell; then the
  built-in features are divided, one first, as the proof that the API is enough; only
  then is the shell announced as open to module authors, and from that release a removal
  needs a major version (§6). All tracker steps.

What this round must not close off is listed in §11.

---

## 7. Slices

Every slice: one change with its test; `tests/run-unit.sh` green, and `tests/run-modules.sh`
on the released module green; the `Api.qml` header, `ModuleRules.apiVersion` and one
CHANGELOG line updated together, as the last edit before the merge (those three lines are
where parallel slices meet, whatever the files look like). A slice that changes what
`docs/ARCHITECTURE.md` says under "Modules" changes that text too. The numbers assume this
order; a slice merged out of order, or after one that was dropped, takes the next free
minor.

### Size, and what can run in parallel

48 slices. S is a day or less of work with its test, M a few days, L about a week or a
slice whose review needs care.
"Needs" is the order that must hold; "File" is the area file under `api-next/` with the
slice's files and tests. The module's slices (M) raise the module's manifest `api`.

| Slice | Size | API | Needs | File |
|---|---|---|---|---|
| S0 `ModuleRules.qml` in five files | M | — | — (first) | versioning |
| A0 Version gate, floor, `deprecations` | S | — | S0 | versioning |
| A1 Command runner | L | 1.4 | A0 | commands |
| A1b Host on the runner | M | — | A1 | commands |
| A2 Program lookup with trust | M | 1.5 | A1 | commands |
| A2b One reader for the test seams | S | — | A2 | commands |
| A3 Test mode | M | 1.6 | A2b | commands |
| A4 Privileged start | L | 1.7 | A3 | commands |
| A5 The prompt says who and what for | M | — | A4 | commands |
| B1 Shared module object, popup inputs | S | 1.8 | S0 | facts |
| C1 Helpers | M | 1.9 | S0 | facts |
| A6 The notification when the shell's prompt does not answer | S | — | A3, A4, C1 | commands |
| C2 System facts, data directory | M | 1.10 | A3 | facts |
| D1 Network facts | S | 1.11 | C1 | facts |
| E0 File chooser: the spike | S | — | — | facts |
| E1 File chooser | M | 1.12 | E0, A3 | facts |
| U0 Anchor rules | M | — | S0 | places |
| U1a The host and the page block, on a fixture view | L | 1.13 | U0 | places |
| U1b The General page | S | 1.14 | U1a | places |
| U2 Popups | M | 1.15 | U1b | places |
| T0 The theme's token names pinned | S | — | — (before M10) | elements |
| T1 Pills in three sizes | S | — | — | elements |
| F1a The button inside: the bordered kinds, asking in every kind's colour | M | — | — | elements |
| F1b Public elements: the pattern, and the button | M | 1.16 | F1a | elements |
| F2 Public elements: the controls | M | 1.17 | F1b, T1 | elements |
| F3 Public elements: rows and texts | M | 1.18 | F1b | elements |
| F4 Public elements: the base types; `qs.components` deprecated | S | 1.19 | F1b | elements |
| U4a The section and the card with `settings`, on a fixture view | M | — | U1a | places (the regions: cards) |
| U4b `NetworkProfileCard` on `SettingsCard` | L | — | U4a | places |
| U4c The VPN page | M | 1.20 | U4b | places |
| U5 The Wi-Fi and Ethernet pages | M | 1.21 | U4c | places |
| U6 The card's button place | S | 1.22 | U5, F1b | cards |
| U7a A module's icon | M | 1.23 | S0 | cards |
| U7b The mark on a closed card | S | 1.24 | U6, U7a | cards |
| P1 `exports` and `uses` | L | 1.25 | A3 | module-api |
| P2 Reach: `moduleStatus`, the old ways deprecated | S | 1.26 | P1 | module-api |
| M1 Runner | L | module | A1 | migration |
| M2 Programs and test mode | M | module | A2, A3, C2 | migration |
| M3 Privileged, with a `what` for every run | M | module | A4, M2 | migration |
| M4 Main and popup | S | module | B1 | migration |
| M5 Helpers and facts | M | module | C1, C2, D1 | migration |
| M6 Its row and card move from `slots` to `anchors` | S | module | U2, U4c | migration |
| M7 The exit node per network on the network cards, with the mark | M | module | F3, U5, U7b, M6 | migration |
| M8 "Send file…" from the popup; both Taildrop dialogs through the chooser | S | module | E1 | migration |
| M9 The manual "for now" override | S | module | M7 | migration |
| M10 Off the shell's internals | L | module | T0, T1, F1a–F4 | migration (the renames: elements) |
| M11 The last | S | module | M1–M10 | migration |
| Z The closing slice | M | 1.27 | M11 released | migration |

**Lanes for independent agents.** Each lane is one agent at a time; lanes do not edit the
same files, except as named below.

| Lane | Slices | Lives in |
|---|---|---|
| Commands and administrator runs | A0, A1, A1b, A2, A2b, A3, A4, A5, A6 | `singletons/io/`, `ModuleHost.qml`, `polkit/` |
| Facts and helpers | B1, C1, D1, C2, E0, E1 | new singletons, `api/Api.qml`, `network/` |
| Places | U0, U1a, U1b, U2, U4a, U4b, U4c, U5, U6, U7b | `components/` (the blocks), `panels/` |
| Elements and looks | T0, T1, F1a, F1b, F2, F3, F4, U7a | `api/`, `components/SmallButton.qml`, `DeleteButton.qml`, `Pill.qml`, the theme |
| Dependencies | P1, P2 | `ModuleRules`, `ModuleHost.qml` |
| The module | M1–M11 | the module's repository; each after the core slices it needs |

Where lanes meet, one slice at a time:
- `ModuleHost.qml`: A1b, A2, A3, B1, C2, E1, U1a, U7a, U7b, P1.
- `components/SettingsCard.qml`: U4a, U6, U7b (all in the places lane, plus U7b's mark).
- The version line, the `Api.qml` header and the CHANGELOG: every slice with a version,
  as its last edit before the merge.

### Later, not in this round

Recorded, not designed (the owner, 2026-11-17; also in the tracker's "Later"):

- **The order of modules:** the order in which modules are loaded, and the order of
  different modules' elements in one place. Two separate things. Until then both are by
  module id (loading also follows `uses`, §5.2).
- **Modules' own elements, published:** a module defines an element of its own, with its
  own public styles that a theme can set, and publishes it through a public API, so that
  libraries of extra elements can exist. (Building its own elements for itself is allowed
  now, §4.9.)
- **Ready for outside authors**, **the built-in features divided** between the shell
  and modules, and **the announcement to module authors**, in that order: tracker steps,
  not slices of this plan (§10, §11).

---

## 8. The owner's answers

All of 2026-11-17. Nothing is open.

| What | The owner's answer | Where |
|---|---|---|
| Where the per-network exit node sits | The saved network's card, opened. The connection editor can follow as a second anchor once a module's row can join a form | §4.7 |
| Placements | `before`, `after` (outside the block), `prepend`, `append` (inside, first and last) | §4.1 |
| The shell's controls in modules | Not a promise on the internals: a layer of public elements made for the API, which use the internal ones inside. A module uses them where they exist and fit | §4.9 |
| A module's own elements | Allowed: built from QtQuick, every colour and type size from the theme's tokens. Importing the shell's internal components is the thing to avoid, and the only thing detected. (Replaces "only from public elements") | §4.9 |
| Variants | A module picks a meaning, not a look, on every public element. A button's kind is `primary`, `secondary`, `danger`, `warning` or `success`; more may come. Asking first is separate and goes with any kind | §4.9 |
| Buttons with a tone | A class of bordered buttons, `danger`, `warning`, `success`: a border in the tone's colour at rest, the whole background in it under the pointer. Every such button in the shell takes it, the per-row ones in the popups included | §4.9 |
| "Cancel" | No kind of its own: a module's "Cancel" is `secondary` | §4.9 |
| Pills | Three sizes, `s`, `m`, `l`, standard, set by the theme, offered through the API. The shell's 24 px pills become `s` (22 px) | §4.9 |
| A module's button on a card | Built in this round. The shell's button, of any kind, always above "Forget" / "Delete"; a `danger` one may act on the first click | §4.8 |
| An element that opens | The shell's `ExpandingRow` | §4.9 |
| A closed card | Shows the module's icon when the module has something set for that network; the detail is on the opened card | §4.10 |
| A module's icon | A glyph of the icon font, an SVG file or an image file; the module chooses | §4.10 |
| The prompt's "what for" | A few words given with each run: "Module: Tailscale, Authorization: Send a file" must already say what it is about. The labels "Module" and "Authorization" stay | §3.4 |
| The command in the prompt | Hidden; shown on a click; the real command; a long one whole, scrolling | §3.4 |
| A module's privileged run when another polkit agent answers | Run, with a shell notification just before, naming the module and what for | §3.4 |
| A prompt open or waiting when the screen locks | Cancelled as if dismissed; the user clicks again after unlocking | §3.4 |
| A long privileged action | Only the password question is one at a time; with another agent strictly one action at a time | §3.4 |
| A privileged run for which no password is asked | Nothing on screen; one log line naming the module | §3.4 |
| The file chooser | In this round, a minimal version | §3.9 |
| The order of modules (loading, and elements in one place) | Both wanted, both later; for now by module id | §7, "Later" |
| A module's elements published to other modules, element libraries | Later | §7, "Later" |
| Who writes modules | Today the owner; later other users. Until then the shell and its module system are built up so that they can do so without problems | §10, §11 |
| Review as a guard | Holds for the project's own modules. An outside module has none; there the prompt's text is the only protection | §2 |
| Removing things from the API | In a minor until the first release announced as open to module authors; from then only with a major version, after at least one release listed as deprecated, announced in the CHANGELOG's "Module API" section and the author guide | §6 |
| Where the shell is going | A fairly small framework that defines the structure and the way of working; built-in features are split out into modules, some shipped with the shell | §10 |
| Shipped modules | Use only the public API, like anyone's module: one class of modules | §10 |
| What stays in the shell | The services, or abstractions for reaching them; the lock screen, password prompts and privileged runs. A module builds on them and adds the whole feature | §10 |
| Trust | No isolation: "the shell must work and modules need access to its functions". The user must know what they install: a module that is not the project's is announced as such, and is then not the project's responsibility | §10 |
| Which comes first: announcing to authors, or the first split-out | The first built-in feature is split out into a module on the public API first, as the proof that the API is enough; only then is the shell announced as open to module authors | §10 |
