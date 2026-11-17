# Module API, the next versions: public elements and looks

One area of the plan. Read [the index](../api-next.md) first: the rules for every
slice (§2), the gate every slice passes (§7), the slice list with sizes and
dependencies, the lanes. `TC`, `TR`, "verified" and "assumed" are defined there.

The public elements, the button's kinds, sizes and pills, a module's own elements and
the theme's tokens, and keeping modules off the shell's internals.

Slices in this file: T0, T1, F1a, F1b, F2, F3, F4.

Section numbers are the plan's and stay as they were. Where each is:
§1 `migration.md` · §2, §8, §10 the index · §3.1–3.4 `commands.md` · §3.5–3.10 `facts.md` ·
§4.1–4.7 `places.md` · §4.8, §4.10 `cards.md` · §4.9 `elements.md` · §5 `module-api.md` ·
§6, §11 `versioning.md` · §7: the list, the lanes and "Later" in the index, a slice's row
in its file, Z in `migration.md` · §9: at the end of each file.

## 4. Step 4: UI anchors (continued: 4.9)

### 4.9 Public elements

**Public elements** are types in `qs.api`, made for the API, that use the shell's
internal components inside (the owner's decision). The shell changes its internals
freely; a public element keeps its own properties. Where a public element exists and
fits, a module uses it; what the set does not offer, a module builds itself ("A module's
own elements", below). At the end of the migration a module imports nothing from
`qs.components`.

**On a public element a module picks a meaning, not a look** (the owner's decision). Two
small enumerated properties, the same words on every element that has them:

| Property | Says | Values |
|---|---|---|
| `kind` | what the element is about | `primary`, `secondary`, `warning`, `danger`, `success`; an element takes the ones it has |
| `size` | how large | `xs`, `s`, `m` (the default), `l`; an element takes the ones it has |

Never a colour, a radius or a number of pixels: that holds for the public elements'
properties, not for a module's own elements (below). A theme decides how a kind and a size
look. Both lists are open: the shell may add a value in a later minor. A value an element
does not know shows as that element's default (below), so a module written for a newer
shell still shows a working control on an older one.

**The button.** One public element, `SmallButton`.

```
SmallButton {
    label; available; checked; tooltip
    kind: "secondary"          // "primary" | "secondary" | "danger" | "warning" | "success"
    size: "m"                  // "xs" | "s" | "m"
    confirm: false             // true: asks first
    confirmLabel               // the question; default: the label and "?"
    cancelTip                  // the tooltip of the "×" that takes the question back
    asking                     // the first click was made
    signal clicked()           // do it
    signal asked()             // the first click of a button that asks
}
```

- **The kind and asking first are two things** (the owner's decision). `kind` says what
  the button is about; `confirm` says that the first click only turns it into the
  question, with a "×" that cancels, and the second click acts. Any kind can ask. A
  boolean, not more kinds: a kind added later can ask without a second value being
  invented for it, and a module switches asking on or off without changing what the
  button is.
- `clicked()` means "do it" either way: the click, or with `confirm` the second click. A
  module adds or drops `confirm` without touching its handler.
- **A `danger` button without `confirm` acts on the first click.** That is the module's
  "Disconnect". What loses something takes `confirm`.

**One word, five kinds** (the owner's decisions: "primary, secondary, warning, danger,
maybe more", then a class of bordered buttons with a tone, `success` among them). Seen as
a design system the button has four things that vary: how strongly it stands out (filled,
plain, bordered), its tone (none, danger, warning, success), whether it asks first, its
size. Only five combinations of the first two exist, so they get one word each, and
"bordered" is how the three toned kinds look, not a word a module writes:

| Kind | Is for | At rest | Under the pointer, or a pressing finger |
|---|---|---|---|
| `primary` | performs the action | filled with `Theme.confirm`; label `Theme.textPrimary`; no border | `Theme.confirmHover` |
| `secondary` (the default) | an in-between step, opens something; also "Cancel" | `Theme.surface`; label `Theme.textSecondary`; no border | `Theme.surfaceHover` |
| `danger` | stops or removes something | as `secondary`, with a border in `Theme.error` | filled with `Theme.error`; label `Theme.textPrimary` |
| `warning` | goes on, but the user should think | as `secondary`, with a border in `Theme.warning` | filled with `Theme.warning`; label `Theme.textPrimary` |
| `success` | a good outcome to take ("Approve", "Trust") | as `secondary`, with a border in `Theme.success` | filled with `Theme.success`; label `Theme.textPrimary` |

- The first two are today's looks (verified: `components/SmallButton.qml`, `save` and
  `normal`). `danger` is today's `delete` with the border added: the fill under the
  pointer is what it does now; the border makes the kind visible before the pointer
  arrives, and on a touch screen, where it never does.
- **Tokens.** The colours above are all the theme's; none is new. The border is as wide as
  `Theme.border.width`. The radius comes from the kind's theme group: `button`,
  `saveButton`, `deleteButton` (verified), and two new ones, `warningButton` and
  `successButton`, each a radius, editable in the theme editor as the others are.
- **Not available** (`available: false`): the whole button at 0.35 opacity, border
  included, as every button today; no fill under the pointer.
- **With `confirm`**, at rest the button looks as its kind does. Asking, it is plain with
  the question in the kind's colour and a border in it, the "×" attached: `danger` in
  `Theme.error` (as `DeleteButton` asks today), `warning` in `Theme.warning`, `success` in
  `Theme.success`, `primary` in `Theme.confirm`, `secondary` in `Theme.textPrimary` with
  `Theme.outline`. This is the owner's "confirmation.danger", "confirmation.primary".
- **The list is open.** A later kind is a new word; a later way to stand out (a filled
  toned button) would be a second property with today's look as its default. Neither
  breaks a module.

Other shapes considered:

| Shape | Why not |
|---|---|
| `variant: "bordered"; tone: "danger"` | two properties of which most pairs do not exist (filled danger, plain warning); the author types a look, and a theme that draws toned buttons another way makes the word untrue |
| one dotted word, `"bordered.danger"` | the same look word, plus a string to take apart and to mistype |
| `kind` with a switch `bordered` | a `primary` with a border and a `danger` without one become writable, and neither exists |

**In the shell itself** the internal `delete` kind and `DeleteButton` take the bordered
look in the same change (F1a), so the shell's and a module's buttons stay alike:

- the one-click red buttons (5 places, verified): "Turn off hotspot" and the Wi-Fi
  "Disconnect" in the network popup; "Disconnect" on each active VPN's row there; the
  primary "Disconnect" of an active network card; "Disconnect" on a connected device's row
  in the Bluetooth popup;
- the buttons that ask first: 17 in 15 files (verified), among them "Forget" on the
  cards and in the Wi-Fi popup, the deletes in the settings pages, and the "✕" on every
  device's row in the Bluetooth popup. Two of the 17 ask before turning something on
  ("Connect" on a card, "Turn on" for a hotspot): those become `primary` with `confirm`,
  not `danger`.
- All of them take the border (the owner's decision), the small "✕" on every row of the
  Bluetooth popup and the per-row "Disconnect" buttons included. The shell keeps no
  borderless danger look.

Today's internal looks, mapped:

| Internal | Public | Note |
|---|---|---|
| `kind: "normal"` | `secondary` | |
| `kind: "save"` | `primary` | |
| `kind: "delete"` | `danger` | gains the border |
| `DeleteButton` | `danger` with `confirm` | gains the border |
| — | `warning`, `success` | new inside the shell |
| `kind: "cancel"` | `secondary` | the same colours as `normal` (verified); only its shape is its own theme group ("Buttons that cancel", `Theme.cancelButton`). A theme that shapes that group differently does not reach a module's "Cancel". Whether the shell keeps the group is theme work, outside this plan |
| `kind: "saveChange"` | not offered | the calendar's "save an existing event"; no module uses it; stays internal |

**Sizes.** One vocabulary, `xs`, `s`, `m`, `l`, standing for the theme's own steps:

| Element | Offers | Stands for |
|---|---|---|
| `SmallButton`, `Dropdown`, `InputField` | `xs`, `s`, `m` | the theme's type sizes `fontSizeXSmall`, `fontSizeSmall`, `fontSizeBody` (what the module passes as `fontSize` today) |
| `Pill` | `s`, `m`, `l` | three heights in the theme's `pill` group (slice T1) |

The shell's own pills are 22 px by default and 24, 26 or 30 px where a view says so
(verified: 7 with the default, 10 with 24, 10 with 26, one with 30). T1 gives the `pill`
group three heights, `minHeight` (kept: `s`, 22), `mediumHeight` (`m`, 26) and
`largeHeight` (`l`, 30), editable in the theme editor, and moves every pill of the shell
onto one of them. Four heights into three: the ten 24 px pills become `s` (the owner's
decision), 2 px lower, in the profile condition editor and the widget settings pane.

**How an element is made.**

- **A control is a wrapper, not a subtype.** `api/SmallButton.qml` is an `Item` holding the
  internal component; a subtype would hand a module `color`, `radius`, `font` and every
  internal property. Values are forwarded with `property alias` where the name and the
  values are the same, with a binding through a pure mapping where they are not (the public
  `kind` → the internal one; `size` → the theme's step); signals are passed on signal to
  signal.
- **It stands in a layout as the internal one did.** The wrapper's implicit size is the
  inner item's, the inner item fills the wrapper (so `Layout.fillWidth` on a field
  stretches the field, as the module does; the internal button's fixed
  `width: implicitWidth` is overridden inside). Layout hints the internal root sets on
  itself are declared again on the wrapper (`SwitchRow`, `DetailRow`, `Hint`: fill the
  width; `SectionTitle`, `SwitchRow`: their margins), and a module may still override
  them.
- **Hidden takes no room.** `DetailRow` (no value) and `PrivilegedMark` (nothing to mark)
  hide themselves inside; the wrapper is visible only when the module's `visible` and the
  inner item's both are.
- **A base type is a subtype:** `PopupWidget`, `BarText`, `BarRow`, `PointerArea`,
  `VpnProvider`. The bar, the pointer and `VpnManager` need the object itself. Their
  public properties are pinned by name; what else they inherit is not promised.
- **An unknown value** (`kind: "primry"`) shows as the default (`secondary`, `m`), and the element prints one
  console warning per element type and value. An element cannot know which module built
  it, so the warning is not in a module's status. `PrivilegedMark` is the exception to
  "the default": an unknown `need` shows the lock, never nothing.
- **Themed.** Elements read `Theme` only.
- **Pointer and keyboard.** Everything that lights up does so through `PointerArea`'s
  `lit`. None of the shell's buttons takes the keyboard today (tracker backlog); when they
  do, every module gets it with the elements.
- **Plain text.** Every text a module can set is shown as `Text.PlainText`, on one line
  where it is a label. Today that is missing in (verified) `SwitchRow`, `Heading`, `Hint`,
  `SectionTitle`, `DeleteButton`, `Checkbox`, `Dropdown` (its option labels are tailnet
  device names), `InputField` (the placeholder), `SchemaSettingEditor` (a manifest's
  labels and hints) and `SettingsPageList` (a module's page label). F1–F3 fix each with
  its element.
- **Pinned** by `tests/ApiElementsTest.qml`, for every element: its public property and
  signal names; each kind and size reaching the internal value it stands for (read
  from the inner item, so a wrong mapping fails); the element in a `RowLayout` and a
  `ColumnLayout` with the internal one's geometry, stretched and hidden; a label
  "<b>x</b>" shown as written. A change to that list is an API version change.

**The starting set**: what the Tailscale module uses from `qs.components` (13 types:
verified), what `qs.api` offers already (6), and what the anchors need (3 new).

| Public element | Inside | Public properties and signals | Kind, size |
|---|---|---|---|
| `SmallButton` | `components/SmallButton.qml`, `DeleteButton.qml` | above | `kind`, `size`, `confirm` |
| `Dropdown` | `components/Dropdown.qml` | `options`, `value`, `placeholder`, `picked(value)` | `size` |
| `InputField` | `components/InputField.qml` | `text`, `placeholder`, `problem`, `password`, `revealed`, `accepted()`, `textEdited()`, `editingFinished()`, `revealToggled()` | `size`. `problem` stays a state (the value is wrong now). The internal `outlined` and `fieldColor` are looks for where a field stands; no module uses them; not offered |
| `Pill` | `components/Pill.qml` | `label`, `picked`, `tooltip`, `clicked()` | `size`: `s`, `m`, `l` |
| `Checkbox` | `components/Checkbox.qml` | `label`, `checked`, `toggled()` | — |
| `ToggleSwitch` | `components/ToggleSwitch.qml` | `checked`, `enabled`, `toggled()` | —. The larger switch the shell's popups use is not offered until a module needs one |
| `PrivilegedMark` | `components/PrivilegedMark.qml` | `need` | `need` is polkit's answer, a meaning already: "", `yes` (nothing shown), `auth` (the lock), `no` (not allowed) |
| `SwitchRow` | `panels/settings/SwitchRow.qml` | `label`, `hint`, `checked`, `need`, `toggled()` | as `PrivilegedMark` |
| `DetailRow` | `panels/settings/DetailRow.qml` | `label`, `value` | — |
| `SettingsRow` (new) | the row block (§4.1) | `label`, `hint`, `value`; its children are the controls on the right | — |
| `ExpandingRow` (new) | `components/ExpandingRow.qml` | `label`, `hint`, `open`; its child is the content | — |
| `Heading`, `SectionTitle` | `panels/settings/` | `text` | the two are the two levels |
| `Hint` | `panels/settings/Hint.qml` | `text` | — (the muted line) |
| `Notice` (new) | a line as the card's notice line | `text` | `kind`: `warning` (the default), `danger`, `success`. The module writes 32 warning lines and 3 success lines by hand today (verified) |
| `SettingEditor` | `panels/settings/SchemaSettingEditor.qml` | `key`, `editIndex` | — |
| `PopupWidget`, `BarText`, `BarRow` | `components/` (base types) | what a bar widget sets today, pinned by name | — |
| `PointerArea` | `components/PointerArea.qml` (base type) | `lit`, `centred`, `reach`, and a `MouseArea`'s own | — |
| `VpnProvider` | `components/VpnProvider.qml` (base type) | its documented contract (API 1.1), without `rowExtras`, `cardExtras`, `pageUrl` | — |

- The names are the internal ones wherever the meaning is the same, so most of the
  migration is a change of import. What a module must rewrite (M10): the values of `kind`
  (`save` → `primary`, `delete` → `danger`, `cancel` and `normal` → `secondary`);
  `fontSize` → `size`; a pill's `minimumHeight` → `size`; `DeleteButton { … onConfirmed }` →
  `SmallButton { kind: "danger"; confirm: true; … onClicked }` and `askingStarted` →
  `asked`; a
  hand-made warning `Text` → `Notice`. None is `Row` or `Button`: with `import QtQuick`
  beside `import qs.api` those would silently replace QtQuick's `Row` (and Controls'
  `Button`) in a module's file.
- `ExpandingRow` is how a module adds an element that opens, on a card's `settings`, a
  section or a page. Its line looks and answers as a card's header does: the same "▸" /
  "▾" mark, the whole line a `PointerArea` (`centred: false`). Its child is held as a
  `Component` through the wrapper's default property (QML wraps a child given to a
  `Component` property, as a `Repeater`'s delegate; that this also holds through the
  public wrapper's alias is assumed, checked in `QuickshellPinTest`), so nothing of it
  exists while closed. It is not an anchor.
- The six that `qs.api` offers already stay subtypes until the closing slice, which makes
  them wrappers (a tightening: a module could set an internal property on them today).

**A module's own elements** (the owner's decision; it replaces "only from public
elements").

- A module may build any element of its own from QtQuick (`Item`, `Rectangle`, `Text`,
  the layouts, `Shape`), in its own files.
- Such an element takes every colour and every type size from the theme's public tokens
  (`Api.theme`), never a literal, so it follows the theme in use as the shell's own
  elements do. A token `Api.theme` lacks is asked for (a token added is a minor version).
- Where a public element exists and fits, the module uses it. A "should": nothing checks
  it, and nothing checks the tokens either.
- "A meaning, never a raw colour or size" is a rule for the public elements' properties.
  A module's own element has whatever properties its author gives it.
- The one thing detected is importing the shell's internal components ("Keeping modules
  off the internals", below).
- The rules for any view hold in a module's own element too, and are the module's to
  keep: text from outside is plain text on one line; hover comes from the public
  `PointerArea`'s `lit`; no live array on a `Repeater`.
- **The token names are pinned** by `tests/ApiThemeTokensTest.qml` (slice T0): the names
  `Api.theme` offers (`api/ThemeTokens.qml`: colours, type sizes, the groups) equal a list
  written in the test, and each colour and type size is the core theme's value of the
  same name. Today no test pins the list (verified: only `SettingsPagesTest` names the
  file, to compile it), though a module's own elements rest on nothing else. A change to
  the list is an API version change, as for the elements.
- Not this: a module publishing its elements to other modules, with styles a theme can
  set (§7, "Later"), and a module's own theme tokens (§11).

**How the set grows.** A module that needs an element, a property, a kind or a size the
set lacks asks for it when it is of general use (another module, or the shell itself,
would use the same), and builds its own otherwise. What is added: one per slice, a minor
version, its line in `ApiElementsTest`. Nothing is added ahead of a module that needs it.

**Keeping modules off the internals.** The shell's internal components (`qs.components`,
`qs.singletons`, the files under `panels/`) may change in any release; that is the reason
a module must not import them, and the import is the one thing about a module's views
that is detected. QML cannot stop an import. The import check
(`ModuleRules.allowedImports`) lists `import qs.components` among the module's
`deprecations` (§6) from the slice that completes the set (F4), and as an error from the
closing slice, when `qs.components` leaves the allowed list; `qs.singletons` and a
directory outside the module's own are errors from P2 (§5.4). The module still loads (the
owner's earlier decision: the check never refuses); the error shows in Settings → Modules
and `modules list`, and `tests/run-modules.sh` fails a module that has it. The check
reads import lines only: a file that builds a core component through
`Qt.createComponent` is not seen by it, only in review, which the project's own modules
get and an outside module does not.

---

## 7. Slices

The rows of this file's slices; the order, sizes and dependencies are in the index.

### Step 4

| Slice | API | Files | Verified by |
|---|---|---|---|
| T0 The theme's token names pinned | — (no change to the API: a test) | `tests/ApiThemeTokensTest.qml`, `tests.qml` | the names of `Api.theme` equal the test's list; each colour and type size equals the core theme's of the same name; a token removed or renamed fails |
| T1 Pills in three sizes | — (user-visible: the theme editor gains two heights; the pills of the profile condition editor and the widget settings pane are 2 px lower) | `singletons/ThemeBuiltin.qml`, `ThemeRules.qml` (the `pill` group), `components/Pill.qml` (`size`), the 21 places that set `minimumHeight` | `ThemeTest`: the three heights; a pill of each size has its height; a source check that no file sets a pill's height as a number; the pills that were 22, 26 and 30 px keep their height, the ones that were 24 are 22 |
| F1a The button inside: the bordered kinds, asking in every kind's colour | — (user-visible: the shell's disconnect and delete buttons gain a border; the theme gains "Buttons that warn" and "Buttons for a good outcome") | `components/SmallButton.qml` (`delete` bordered, `warning`, `success`, eliding), `DeleteButton.qml` (bordered; the question's colour by kind; plain text), `ThemeBuiltin.qml`, `ThemeRules.qml` (`warningButton`, `successButton`), the two places that ask before turning something on | `ThemeTest`; a view test: each kind's colours and border at rest, under the pointer, asking, and not available |
| F1b Public elements: the pattern, and the button | 1.16 | `api/SmallButton.qml` (wrapper: `kind`, `size`, `confirm`, the mark), `tests/ApiElementsTest.qml` | `ApiElementsTest` (new) |
| F2 Public elements: the controls | 1.17 | `api/Dropdown.qml`, `InputField.qml`, `Pill.qml`, `Checkbox.qml`, `ToggleSwitch.qml`, `PrivilegedMark.qml`; plain text in the four internal ones that lack it | `ApiElementsTest` |
| F3 Public elements: rows and texts | 1.18 | `components/SettingsRow.qml`, `ExpandingRow.qml`, `api/SettingsRow.qml`, `ExpandingRow.qml`, `Notice.qml`; plain text in `SwitchRow`, `Heading`, `Hint`, `SectionTitle`, `SchemaSettingEditor`, `SettingsPageList` | `ApiElementsTest`; the `Component` child through the wrapper, in `QuickshellPinTest` |
| F4 Public elements: the base types; `qs.components` deprecated | 1.19 | `api/PopupWidget.qml`, `BarText.qml`, `BarRow.qml`, `PointerArea.qml`, `VpnProvider.qml`, `ModuleRules` (import check) | `ApiElementsTest`; `ModuleRulesTest`; `VpnProvidersTest` with a provider made from `qs.api` |

---

## 9. Verified, assumed, hard

The part of the plan's §9 that is about this file.

**Verified in the code.**
- What `qs.api` offers today: `SettingEditor`, `SectionTitle`, `Heading`, `Hint`,
  `DetailRow`, `SwitchRow`; four of them set no `textFormat`.

**Assumed.**
- A child given to a `Component` property is wrapped, not built, also through a wrapper's
  default alias (F3); a wrapper `Item` that takes its size from the item inside stands in
  a `RowLayout` and a `ColumnLayout` as that item did (F1, in `ApiElementsTest`).
- `tests/run-modules.sh` can be made to fail on an import error in a module's status.

**What the current code makes hard.**
- **A public control is one more `Item`** around the internal one (§4.9). The module has
  65 buttons; the cost is small but real, and layout properties a module sets must reach
  the wrapper, not the inside.
- **The public kinds are not the internal looks.** `warning` and `success` do not exist
  inside yet, and the border is new on 20 of the shell's own buttons (F1a); the internal `cancel` and `saveChange` have no public form, and asking first is a
  second component inside (`DeleteButton`) behind one public button.
- **Four pill heights become three** (T1): ten pills become 2 px lower.
