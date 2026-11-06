# Selectors (11.6): open questions and established facts

Part of [selectors.md](selectors.md). **Paused 2026-11-06 at the user's request**: they want to
think these over before stage 1. The words used here are defined in the glossary of
[../STYLES.md](../STYLES.md#glossary).

## Established facts

From the analysis and the stage 0 prototype (2026-11-01, a scratch config outside the
repo; results in [selectors.md](selectors.md#progress)):

- **The model works.** The prototype passed all 14 checks:
  - keys built across a window (popup → bar) and through Repeater delegates;
  - inheritance and variables passed down through contexts;
  - a context's state (a hovered row) restyling the elements inside it.
- **The cost is far below a frame.** With 314 rules and 500 buttons:
  - compiling: 2.1 ms;
  - one element's state change: 7.5 µs (today's way: 1.3 µs);
  - a theme change, everything restyled: 8.6 ms.

  A hover touches one to ten elements.
- **The real work is moving logic out of QML.** Which value an element takes in which
  state is decided in QML today (e.g. `SmallButton.qml`'s colour chain). With selectors,
  that logic moves into the built-in stylesheet, element by element. Scale: 218 QML
  files, 2086 reads of `Theme.*` in 121 files.
- **No attached properties without C++.** Elements get their type and classes as
  properties of our own components, or through a small marker object.
- **The parser will be a real one** (decided 2026-11-01, the user's point): a tokenizer
  and a syntax tree following CSS Syntax Level 3, keeping positions and formatting, with
  no regular expressions. The prototype's regex parser was throwaway.
- **Every property needs a default in the registry.** An element created before its
  stylesheet loads, or a key no rule covers, otherwise gets `undefined`.
- **The lock screen cannot be inspected from another window**: a session lock lets
  nothing else in.

## Questions for the user

### 1. Does a rule "for the bar" reach into popups?

Popups are children of the bar (decided). As in CSS, `bar button { border-radius: 4px }`
then changes the buttons on the bar **and every button in every popup**. The prototype
showed this happening.

Proposed: each widget on the bar is a context of its own, type `cell`. Then:

| Selector | Means |
|---|---|
| `cell button` | buttons on the bar itself |
| `popup button` | buttons in popups |
| `bar button` | both |

### 2. When a theme and the built-in stylesheet disagree, which wins?

The built-in stylesheet has:

```css
button:hover        { background: grey; }
button.save:hover   { background: green; }
button.delete:hover { background: red; }
```

A theme adds only:

```css
button:hover { background: blue; }
```

- **(a) The layer always wins.** This is the prototype's behaviour. The theme comes later,
  so every hovered button is blue, "Save" and "Delete" included.
  - Predictable: what a theme writes always applies.
  - But one short rule takes the variants' colours away.
- **(b) Specificity first, the layer only on a tie.** This is classic CSS.
  `button.save:hover` is more specific than `button:hover`, so "Save" stays green, "Delete"
  stays red, and only plain buttons turn blue.
  - The variants survive.
  - But a theme's rule sometimes seems not to work, and overriding takes a more specific
    selector.

Proposed: (a), with two safeguards:

- the validator warns "this rule also overrides `button.save:hover`, `button.delete:hover`";
- the inspector shows where every value comes from.

### 3. A theme as a folder?

A theme may bring its own files, such as a curves file or imports, and themes may be
downloaded. That suggests a folder per theme rather than one file, which changes the
theme library's layout.

### 4. A curve name in both the theme and the user's library

Example: the theme defines `snappy`, and so does the user. Proposed: the theme sees its
own; the user overrides it deliberately in a theme extending it.

Lookup order: the theme's curves → the user's library → Qt's built-in easings.

### 5. Order with matugen (11.7)

matugen can write CSS variables directly. If matugen is done before themes move to CSS,
its template will be rewritten later.

### 6. Smaller points, for stage 1 or 4

- **Functions in values:** `alpha()` is needed, since the transparent variants are
  derived in code today. `calc()`: probably not at first.
- **Nesting:** `button { &.save { … } }` would mirror today's token groups.
- **Which types are contexts:** likely `bar`, `popup`, `hud`, `settings`, `lock`; are
  `card` and `row` among them?
- **Identifiers (`#id`):** probably dropped, since nothing in the shell is unique. To be
  confirmed by the audit.
- **Parts vs prefixed properties:** composite elements need either `button::label` or
  properties such as `background` vs `color`, as in CSS.
- **`:active`:** in CSS it means "pressed"; for us it would mean "the current workspace".
  Proposed: `:pressed` and `:current`.
- **Cases to analyse in the audit:**
  - tray submenus;
  - tooltips (`HoverTip`);
  - `FloatingList` drawn in a popup's `overlayHost`;
  - toasts in the HUD;
  - the notification card on the lock screen;
  - the power menu.
