# Module API, the next versions: inside a card, a module's icon, the mark on a closed card

One area of the plan. Read [the index](../api-next.md) first: the rules for every
slice (§2), the gate every slice passes (§7), the slice list with sizes and
dependencies, the lanes. `TC`, `TR`, "verified" and "assumed" are defined there.

A card's two regions (its opened part, its buttons), the manifest's icon, and the mark
a module sets on a closed card. The card block, the paths and the hosts are in
`places.md` (§4.1, §4.2, §4.4).

Slices in this file: U6, U7a, U7b.

Section numbers are the plan's and stay as they were. Where each is:
§1 `migration.md` · §2, §8, §10 the index · §3.1–3.4 `commands.md` · §3.5–3.10 `facts.md` ·
§4.1–4.7 `places.md` · §4.8, §4.10 `cards.md` · §4.9 `elements.md` · §5 `module-api.md` ·
§6, §11 `versioning.md` · §7: the list, the lanes and "Later" in the index, a slice's row
in its file, Z in `migration.md` · §9: at the end of each file.

## 4. Step 4: UI anchors (continued: 4.8, 4.10)

### 4.8 Inside a card

A card is not one list. `NetworkProfileCard.qml` (verified) has a header (the name and a
line; on the right the primary button and, opened, the secondary buttons stacked under it,
each as wide as its label, on one right edge), a notice line, and, opened, a column: the
card's own rows (connect automatically, priority), then the rows the page adds (the Wi-Fi
password; a VPN's details). The same card serves Wi-Fi, Ethernet, hotspots and VPN
providers' entries; some have no "Edit connection…", no "Forget", or a "Settings…".

So a card takes no `prepend` or `append` itself. It has two regions, each an anchor under
the card's path:

| Region | Holds | `prepend` | `append` | An element must be |
|---|---|---|---|---|
| `<card>.settings` | the opened column | above "Connect automatically" | under the page's own rows | anything; `SettingsRow` or `ExpandingRow` is what fits |
| `<card>.actions` | the secondary buttons | under the primary button, above "Settings…" | under "Edit connection…", above "Forget" / "Delete" | the public `SmallButton` (§4.9), of any kind |

The table (§4.2) publishes `append` on the saved networks' `settings`, `prepend` on the
VPN cards' (where today's slot stands), and `append` on every published card's `actions`.

- **Built while the card is open,** both. A page keeps one card open (`_open`: verified),
  so a module's element exists once per page, not once per network. Closing the card
  destroys it; what it showed (an `ExpandingRow` left open) starts closed next time.
- **Context** is the card's item, per path (§4.2). No `open`: a region's element exists
  only while the card is open.
- **Variants.** A region exists on every card of a published path, whatever buttons that
  card has.
- **Not regions:** the header's name and line, the primary button, the notice line. A
  module does not change them.

**The `actions` region** (the owner's decisions: the shell's button, always above
"Forget" / "Delete", any kind).

- "Forget" stays last whatever a module adds. The region right-aligns each button at its
  own width, as the card's are; it gives a button at most a third of the card's width, and
  a longer label is cut (the internal button gains eliding). The size is `m`.
- Every kind is allowed, with or without asking first (the owner's decision). So a
  module's `danger` button that acts on the first click may stand directly above the
  shell's "Forget", which asks first. A module that wants the caution sets
  `confirm: true` itself.
- **Why a button is required there and nothing else is.** The stack sits in the card's
  header beside the name; anything but a button breaks the header of every card.
  `settings` is a full-width column where today's VPN card content (detail rows,
  warnings, a hint) is legitimate, so there the elements are offered, not demanded.
- **How the host knows it is the button.** The public `SmallButton` carries a read-only
  mark, `apiElement: "SmallButton"`; the host reads it from the built element and refuses
  another with an error in the module's status ("anchors: `…card.actions` takes a
  SmallButton"). Not `instanceof`: the host is in `components/`, the public type in
  `qs.api`, and `qs.api` imports `qs.components`; the core keeps those two from importing
  each other (verified: `ModuleRules.qml`'s note on `apiVersion`). A module that fakes the
  mark has made a mistake no guard here is for (§2, trust).
- **Built in this round** (the owner's decision), as slice U6: the card's button column
  published as an anchor, with the two rules above. No slice of the Tailscale migration
  uses it; the pin test's fixture module does (§4.6).

**A closed card** builds no module element. It can show the module's icon (§4.10).

### 4.10 A module's icon, and the mark on a closed card

**The icon** is declared once in the manifest, in one of three ways; the module chooses
(the owner's decision):

| `"icon"` | What it is | How the shell shows it |
|---|---|---|
| `{ "glyph": "…" }` | one character of the shell's icon font, as `VpnProvider.glyph` is today | as text, in the text colour of its place: it follows the theme |
| `{ "svg": "icon.svg" }` | an SVG file | by default as a shape: the shell paints it in the same colour as a glyph (`QtQuick.Effects`' colorization, which the shell uses already), so a one-colour drawing follows the theme. With `"colors": "own"` it is shown in its own colours |
| `{ "image": "icon.png" }` | a PNG or WebP picture | in its own colours, always |

- **One shell component draws it everywhere,** `components/ModuleIcon.qml`, given a module
  id: a square as tall as a line of body text, the picture fitted inside, never cropped or
  stretched. No QML of the module is involved in any of the three. This round it is used
  on closed cards; Settings → Modules (step 8) is the next place.
- **Files.** Inside the module's directory only, named by a path relative to it; taken
  through the host's file check like every file the manifest names (a regular file,
  inside the directory after links are resolved: `ModuleHost`, verified in
  `docs/ARCHITECTURE.md`, "Modules"). At most 64 KiB for an SVG, 256 KiB for a picture.
  Pixel dimensions are not limited: the shell asks for the picture at the size it shows
  (`sourceSize`), so a large one costs no more than its file.
- **A glyph** is one character, counted as a code point (the font's icons above U+FFFF are
  two UTF-16 units), neither white space nor a control or format character, and not one of
  the shell's own status marks (the lock and the no-entry sign of `PrivilegedMark`).
- **Never nothing, silently.** A manifest whose `icon` is wrong (two characters, a file
  outside the directory, too large, another type) gets an error in the module's status and
  no icon. A file that passes the check but cannot be drawn gets the same error when the
  shell first tries. In both cases, and for a module with no `icon` at all, the shell
  shows the first letter of the module's name in the muted colour in the icon's place. A
  glyph the font lacks cannot be detected; it shows as the font's empty box.

**The mark on a closed card.** A closed card shows no module element, but it shows the
module's icon when the module says something of its is set for that item. The detail is on
the opened card, in the module's row (the exit node's name).

```
module.setMark(path, itemId, label) → bool    // label: what it stands for, "Exit node: home"
module.clearMark(path, itemId)
```

- **Where.** At the end of the card's name line, after the name, before the buttons; the
  name is cut first, the icons keep their place. Shown open and closed.
- `path` is a card's path that the table lists as taking marks (§4.2: the saved Wi-Fi
  networks' and the wired profiles' cards); `itemId` is the item's id as in the card's
  context (`networkId`). `label` is the icon's accessible name and its tooltip, shown as
  "Tailscale: Exit node: home": plain text, one line, 40 characters.
- A path that takes no marks, or the 201st mark of one module on one path: `false`, the
  mark is not kept, and one warning in the module's status.
- **Several modules on one card:** in module id order, the first three. A pure rule,
  `ModuleRules.cardMarks(marks, path, itemId)` → `[{ module, label }]`.
- **The module goes off:** the host holds the marks and drops that module's, so its icons
  go at once. They are not stored; a module sets them again when it starts.
- A mark does nothing on a click; the card's header keeps the click.

---

## 7. Slices

The rows of this file's slices; the order, sizes and dependencies are in the index.

### Step 4

| Slice | API | Files | Verified by |
|---|---|---|---|
| U6 The card's button place | 1.22 | `components/SettingsCard.qml` (`actions`), `AnchorContent.qml` (`takes`, the mark), table rows, the fixture module | `AnchorsTest`: a button of each kind, a non-button refused, "Forget" still last; the geometry test of U4b with a button added |
| U7a A module's icon | 1.23 | `ModuleRules` (manifest `icon`), `ModuleHost.qml` (the file check), `components/ModuleIcon.qml` | `ModuleRulesTest` (each kind, each refusal); a fixture per kind and one whose file cannot be drawn: the letter and the status error |
| U7b The mark on a closed card | 1.24 | `ModuleRules` (`cardMarks`, the table's card rows), `ModuleHost.qml`, `api/ModuleHandle.qml` (`setMark`, `clearMark`), `components/SettingsCard.qml` | `ModuleRulesTest` (order, three, the cap, a module off); `AnchorsTest` |

---

## 9. Verified, assumed, hard

The part of the plan's §9 that is about this file.

**Assumed.**
- An SVG painted in one colour through `QtQuick.Effects` looks right at the size of a line
  of text (U7a). A glyph the font lacks shows as an empty box and cannot be detected.
