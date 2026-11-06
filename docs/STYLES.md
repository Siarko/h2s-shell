# Stylesheets: the shell's CSS variant

The reference for writing a stylesheet for the shell. **Draft: the language is being
designed** ([plans/selectors.md](plans/selectors.md), TODO 11.6) — nothing here is
implemented yet. Keep this file in step with the code: every syntax, selector, property or
at-rule the compiler accepts is listed here, and nothing that it does not.

## Glossary

The words used in the code, the plan and this reference, each for one thing.

| Term | Meaning | Example |
|---|---|---|
| **stylesheet** | a `.css` file: the built-in one, or a theme's | `Full.css` |
| **rule** | a selector and the declarations it applies | `button:hover { background: #333; }` |
| **declaration** | one property and its value | `border-radius: 6px` |
| **property** | what a declaration sets | `background`, `border-radius` |
| **selector** | which elements a rule applies to | `popup button.save:hover` |
| **compound** | one step of a selector, describing one element | `button.save:hover` |
| **element** | something on screen that takes a style; not every QML item is one | a button, a popup |
| **type** | what kind of element it is | `button`, `pill`, `popup` |
| **class** | a variant of a type | `.save`, `.delete` |
| **state** | something true of an element now, changing as it lives | `:hover`, `:checked` |
| **attribute** | a piece of data about an element | `[edge=left]` |
| **part** | a piece of a composite element, styled on its own | `button::label` |
| **context** | an element others can be addressed *inside*: only contexts may appear before the last step of a selector | `popup` in `popup button` |
| **context path** | the contexts an element sits in, outermost first | `bar > popup > row` |
| **key** | an element's context path and its own compound: what it looks itself up by | `bar > popup > row > button.save:hover` |
| **registry** | the list of types, their classes, states, parts, properties and each property's type and default | `button`: `background` (colour, default …) |
| **compiling** | turning stylesheets into the table | |
| **table** | the compiled result: key → the element's computed values | |
| **computed value** | the value an element ends up with for a property, after everything below | `border-radius` = 6 |
| **cascade** | how one value is chosen when several rules set the same property for an element | |
| **layer** | where a rule comes from, in a fixed order: built-in, the theme it extends, the theme, the palette, the draft | |
| **specificity** | how precisely a selector targets: states, classes, attributes and parts count more than types | `button.save:hover` is more specific than `button` |
| **inheritance** | an element taking a property it has no rule for from its context (text colour, font) | text in a popup takes the popup's colour |
| **variable** | a value with a name, set in one rule and used in others; inherited | `--accent`, used as `var(--accent)` |
| **tokenizer**, **syntax tree** | the parser's two steps: the file's characters into tokens, tokens into a tree that keeps positions and formatting | |

## Files

- Plain `.css` files. Everything that is ours is still valid CSS syntax — an at-rule, a
  custom property (`--name`) or a function — so editors and formatters work on them.
- Comments: `/* … */`.
- An unsupported or invalid declaration is dropped and reported; the rest of the file
  applies (as in browsers).

## Selectors

| Form | Meaning | Example |
|---|---|---|
| `type` | kind of element | `button` |
| `.class` | variant or role | `button.save`, `cell.clock` |
| `:state` | a state the element is in now | `button:hover` |
| `[attribute]`, `[attribute=value]` | data of the element | `bar[edge=left]` |
| `::part` | a part of a composite element | `button::label` |
| `context element` | inside a context | `popup button` |
| `context > element` | directly inside a context | `bar > popup` |

Descendant selectors may only name **contexts** on the left. Not supported: `#id`,
structural pseudo-classes (`:first-child`, `:nth-child`), sibling combinators (`+`, `~`),
the universal selector (to be confirmed).

## Cascade

1. The built-in stylesheet.
2. The themes of the `extends` chain, base first.
3. The palette.
4. The draft being edited.

A later layer always wins over an earlier one, whatever the specificity. Within a layer:
specificity, then order of appearance. Text colour and font are inherited along the
contexts.

## Element types, contexts, states, parts

*To be filled from the registry (stage 1 of the plan).*

## Properties and values

*To be filled from the registry.* Units: `px`; durations `ms`, `s`; colours `#rgb`,
`#rrggbb`, `#rrggbbaa`. Functions: `var()`; planned `alpha()`.

## At-rules

*None yet.* Planned: the theme being extended, a theme's own curves file, animations
(TODO 11.20).
