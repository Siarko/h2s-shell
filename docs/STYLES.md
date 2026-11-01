# Stylesheets: the shell's CSS variant

The reference for writing a stylesheet for the shell. **Draft: the language is being
designed** ([plans/selectors.md](plans/selectors.md), TODO 11.6) — nothing here is
implemented yet. Keep this file in step with the code: every syntax, selector, property or
at-rule the compiler accepts is listed here, and nothing that it does not.

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
