# Plan: styling with CSS-like selectors (TODO 11.6)

Status: **stage 0 done 2026-11-01; paused 2026-11-06** — the open questions, explained, are in
[selectors-questions.md](selectors-questions.md), for the user to think over before stage 1. The language itself is
documented, as it is decided and built, in [../STYLES.md](../STYLES.md) — keep the two
apart: this file is the plan and the progress, STYLES.md is the reference for whoever
writes a stylesheet.

## Why

Themes today are flat values per kind of element (`button.radius`, `osdToast.padding`,
themes stage 7). Which value an element takes in which state is decided in QML — e.g.
`components/SmallButton.qml` picks its colour from `kind` and hover in a chain of
conditionals. The user wants styling by element kind, variant, place and state, as with
CSS selectors (`popup button:hover`, `button.delete`), with a cascade, in a stylesheet a
theme is written in — and the settings' Appearance pages still editing it.

So the real work is not the parser: it is moving the "state → value" logic out of about
120 QML files into a built-in stylesheet, element by element. Scale (2026-11-01): 218 QML
files, 2086 reads of `Theme.*` in 121 of them (125 distinct tokens), 99 hover reads, 147
`Behavior`s, 6 kinds of window (bar, popup, HUD, settings, lock screen, screensaver).

## Decisions (with the user, 2026-11-01)

- **Our own CSS variant, in `.css` files.** Every extension is syntactically valid CSS — an
  at-rule, a custom property (`--name`) or a function — so editors highlight and format the
  files without errors.
- **Resolved statically.** A stylesheet is read, parsed and validated once, and compiled
  into a table an element addresses directly by its key; nothing is matched at runtime
  (see "Model").
- **A cascade**, and **inheritance** (text colour, font) — resolved in the table at
  compile time, not by walking the tree at runtime.
- **Identifiers (`#id`)**: probably not — nothing in the shell is unique (a bar per
  monitor, several widgets of a kind). To confirm in the audit.
- **Popups are children of the bar, siblings of the widgets**, not inside the widget that
  opened them. Similar cases are analysed in the audit (stage 1).
- **The inspector starts read-only**: exploring the structure, so whoever styles knows
  what there is and how to address it. Editing in it is not planned.
- **Animations come later, as instructions in the stylesheet** (TODO 11.20); the language
  and the compiler leave room for them. 11.5 (dynamic-island bar) waits for animations,
  since then it can be done by configuration.
- **Curves stay a library of their own** (`curves.json`), so a user's curves work with a
  theme downloaded from elsewhere. A theme may bring its own curves file.
- Both systems live side by side for a long time: `Theme.*` keeps working while
  components move to styles one by one.

## Model

### Elements, contexts, keys

- An element has a **type** (semantic, not the component's name: `button`, `pill`,
  `field`, `row`, `list-item`, `card`, `popup`, `bar`, `cell`, `toast`, `tooltip`, …),
  **classes** (variant or role: `button.save`, `cell.clock`), **states** (pseudo-classes
  that change while it lives: `:hover`, `:pressed`, `:focus`, `:checked`, `:disabled`,
  `:selected`, `:current`, `:open`), **attributes** (data: `[edge=left]`, `[vertical]`,
  `[urgency=critical]`) and **parts** (pseudo-elements of a composite element:
  `button::label`, `toast::badge`, `slider::thumb`). Names to be settled by the audit.
- Some types are **contexts** (likely `bar`, `popup`, `hud`, `settings`, `lock`, maybe
  `card`, `row`). A descendant selector may only name contexts: `popup button` works,
  `button text` does not. An element's context path is short and known when it is
  created (`bar > popup`).
- An element's **key** is its context path (with the contexts' classes and states), its
  type, classes, attributes and states:
  `bar popup.calendar | button.save | :hover`.

### The compiled table

- **At load:** parse → validate → order the layers → apply specificity → substitute
  `var()` → fill in defaults from the registry → inheritance along the context path.
- **The table** maps a key to a plain object of computed values. An entry is computed the
  first time its key is asked for and kept; after warm-up the shell only addresses it, and
  it never holds more entries than keys that actually occur.
- **At runtime** an element only builds its key (a binding: a state or a context's state
  changing makes a new key) and reads its entry. Only that element's bindings re-evaluate.
- A theme change (or a draft edit) recompiles and drops the table; every element reads
  again — as on a theme reload today.
- Given up on purpose: arbitrary ancestor chains and structural selectors (`:first-child`,
  siblings). Fewer surprises, and what makes the static table possible.

### Cascade

Layers, later always beating earlier regardless of specificity (CSS `@layer` semantics),
so a theme extending another overrides it the way a partial theme does today:

1. the built-in stylesheet (in the repo: today's values and state logic)
2. the themes of the `extends` chain, base first
3. the palette (`colorsFrom` today; matugen)
4. the draft being edited

Within a layer: specificity, then order.

### Editing both ways

- The parser keeps a full syntax tree with comments and formatting, not only values.
- An edit from the settings is an operation on it — "set `border-radius` in the rule
  `button`" — changing the value in place, or adding the rule at the end; removing deletes
  the declaration. Hand-written parts of the file survive.
- Drafts become a list of such operations over the theme's tree.
- The Appearance pages edit canonical rules (`button`, `popup`, `:root` variables). When a
  more specific rule overrides what a control edits, the page says so ("overridden by
  `popup button` at line 42"), so a slider never silently does nothing.

### Not element styles

Some of today's tokens do not belong to one element: `reservedSpace` (the bar window's
exclusive zone), the bar's corners as a percentage of half its thickness, animation roles
and their durations, popup widths in percent. Each becomes either a property of its
element (`bar { thickness: 40px }`) or a global variable (`:root { --duration-hover: 100ms }`)
— decided per token in stage 1.

### Curves

A curve name is looked up in the theme's own curves, then the user's library, then Qt's
built-in easings. The editor shows where a curve comes from.

## Stages

Each verified on the host before the next.

0. **Prototype.** Contexts, keys and the table on a few components (a button in the bar,
   in a popup, in the settings), with `:hover` and a context's state; measure compile
   time for a stylesheet of a few hundred rules and the cost per element. Confirms or
   changes the model before the rest is planned in detail.
1. **Vocabulary and registry.** An audit of every element of the shell: which get a type,
   which classes, states, parts, which are contexts, the cross-window cases (popup in the
   bar, tray submenus, tooltips, `FloatingList` in a popup's `overlayHost`, toasts in the
   HUD, the notification card on the lock screen, the power menu). The result: a registry
   (data) of types with their properties, value types, states and parts — what the
   inspector, the validator and the settings read — and its description in STYLES.md.
2. **Assigning.** Shared components first (properties on our own components), then
   windows and panels (a small marker object where there is no component of ours).
3. **Inspector, read-only.** A window: pick mode (a transparent layer on every shell
   window catches the click, the deepest item found with `childAt`, outlined as in
   browser dev tools), "freeze" (popups stay open, toasts stay, timers stop), the tree of
   styled elements, an element's identity (type, classes, states, attributes, context
   path, key) and geometry, its QML type and properties. The lock screen cannot be
   inspected from outside (a session lock lets nothing else in).
4. **Parser, compiler, validator.** Pure functions with tests: tokenizer, syntax tree with
   formatting, selectors, cascade, the table. A real tokenizer and a recursive parser
   following CSS Syntax Level 3 (its tokens, blocks and error recovery), not regular
   expressions — the prototype's were throwaway. Every token keeps its position (line,
   column, offset) for the validator and for edits in place; strings, `url()`, nested
   blocks and at-rules parse by the same rules, so nesting, `@layer`-like rules or
   animations later need no new parser. Parsing (on a file change) is kept apart from
   compiling (the cascade, from the tree), so edits from the settings patch the tree
   without parsing again; compile time is measured again against the prototype's 2.1 ms. The validator reports unknown properties,
   wrong value types, unsupported at-rules and selectors that cannot match (types or
   classes outside the registry), with line and column — in the settings (`Theme.errors`),
   over IPC, from the command line. The inspector shows an element's table entry and the
   rules behind each value (file, line, overridden ones crossed out).
5. **The built-in stylesheet.** Today's values and state logic as CSS; components move
   from `Theme.*` to their table entries a few at a time, compared pixel by pixel with
   the version before.
6. **User themes in CSS.** A one-time migration of the theme files and drafts (backup
   first), edits that keep formatting, drafts as operations, the Appearance pages on top.
   No lasting support for two formats.
7. **Tidying.** The old `Theme.*` path removed where nothing reads it.

## Progress

*Stage 0, prototype, 2026-11-01* (a scratch config outside the repo: a compiler in JS —
selectors, layers, specificity, `var()`, inheritance along contexts, a memoised table —
contexts and a button reading every value from its entry, against a control button
written today's way). All 14 correctness checks passed: keys through a window link
(`styleParent`) and through Repeater delegates, a later layer beating a more specific
rule, inheritance and custom properties through contexts, a context's state restyling its
descendants. Measured on the host, 314 rules, 500 buttons:

| | styled | today's way |
|---|---|---|
| compile a stylesheet | 2.1 ms | — |
| create 500 buttons | 9.6 ms | 5.6 ms |
| one element's state change (hover) | 7.5 µs | 1.3 µs |
| a row's state change restyling its 10 buttons | 75 µs | — |
| theme change: compile + restyle everything | 8.6 ms | — |

Slower per element, but in absolute terms far below a frame: a hover touches one to ten
elements. The cost is in building the key and every bound value re-reading the new entry,
not in matching (entries are memoised; a run needs about ten).

Found:
- **Popups under the bar: `bar button` matches every popup's buttons**, as CSS does — a
  rule meant for the bar's cells reaches into popups. Either the bar's widgets are their
  own context (`cell button`) and `bar` means the bar with its popups, or popups hang
  elsewhere. To decide with the user.
- **Layers beat specificity everywhere**: a theme writing `button:hover` also overrides
  the built-in `button.save:hover` and `button.delete:hover`. Predictable, but a short
  rule in a theme can flatten variants. To decide with the user; the validator could warn
  about it.
- **Every property needs a default** (from the registry): an element created before its
  stylesheet loads, or a key no rule sets a property for, otherwise gets `undefined`.

## Open

- **A theme as a folder** (stylesheet, curves, imports) rather than one file — a theme
  bringing its own files, or downloaded, suggests it. Changes the theme library's layout.
- **A curve name in both the theme and the user's library**: proposed — the theme sees its
  own, the user overrides it deliberately in a theme extending it.
- **Order with matugen (11.7)**: matugen can write CSS variables directly; done before the
  stylesheet themes, its template would be rewritten.
- Which functions values get: `alpha()` is needed (the transparent variants are derived in
  code today); `calc()` probably not at first.
- Nesting (`button { &.save { … } }`) — would mirror today's token groups.
- The full list of contexts, and whether `card`/`row` are among them.
