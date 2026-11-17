# Module API, the next versions: places (anchors)

One area of the plan. Read [the index](../api-next.md) first: the rules for every
slice (§2), the gate every slice passes (§7), the slice list with sizes and
dependencies, the lanes. `TC`, `TR`, "verified" and "assumed" are defined there.

The shared blocks, the names of the places, how content is put there, the pin test,
today's slots and the first consumer. The inside of a card (its regions and buttons,
§4.8), a module's icon and the mark on a closed card are in `cards.md`.

Slices in this file: U0, U1a, U1b, U2, U4a, U4b, U4c, U5.

Section numbers are the plan's and stay as they were. Where each is:
§1 `migration.md` · §2, §8, §10 the index · §3.1–3.4 `commands.md` · §3.5–3.10 `facts.md` ·
§4.1–4.7 `places.md` · §4.8, §4.10 `cards.md` · §4.9 `elements.md` · §5 `module-api.md` ·
§6, §11 `versioning.md` · §7: the list, the lanes and "Later" in the index, a slice's row
in its file, Z in `migration.md` · §9: at the end of each file.

## 4. Step 4: UI anchors

### 4.1 Blocks and placements

Views are built from five shared blocks. Each has an `anchor` name; that is all a view's
author writes. The files are new, in `components/`, on one base (`AnchorBlock.qml`: the
path, the hosts, reporting itself).

| Block | File | What it is | Its frame | Placements |
|---|---|---|---|---|
| Settings page | `SettingsPage.qml` | a page's root: scrolling, margins | the heading, and a banner under it (`KeepSettingsBar`) | prepend, append |
| Section | `SettingsSection.qml` | a titled group on a page | the title's line, with its buttons ("Find networks") | before, after, prepend, append |
| Card | `SettingsCard.qml` | a framed item that opens (a saved network, a VPN) | the header and the notice line | before, after; inside it through its regions (§4.8) |
| Row | `SettingsRow.qml`, in a popup `PopupRow.qml` | one line: a label with a control or a value | — | before, after |
| Popup section | `PopupSection.qml` | a group in a popup panel; the panel's root is one too | its header line and its closing divider | before, after, prepend, append |

**The four placements.** `before` and `after` put an element next to the block, outside it
(a card's frame included). `prepend` and `append` put it inside, as the first or the last
of the block's content. The frame is never content: a prepended element comes under a
page's heading, a section's title, a popup section's header; an appended one above a popup
section's divider.

**One order, top to bottom,** for a block B holding c1 … cn:

```
B.before · B's frame · B.prepend · c1.before · c1 · c1.after · … · cn.after · B.append · B.after
```

It follows from where the hosts stand (§4.4), so `prepend` on a section and `before` on its
first row never compete: the section's element is above the row's.

**How consistent the views are today** (verified by reading `panels/`):
- 26 settings pages with four kinds of root: `Flickable` (14), `ShapeSettings` (5),
  `ColumnLayout` (4, scrolled by the window), `Item` (3: network pages with an editor
  laid over them). There is no page block.
- Sections are a `SectionTitle` (or a hand-made title line with a button) followed by loose
  siblings, and only on the network pages; other pages mark sections with a comment or a
  `Label`. There is no section block.
- Cards exist as `NetworkProfileCard` and `NetworkDeviceCard`. Rows exist as `SwitchRow`,
  `DetailRow`, `SettingEditor`, `SettingInputRow`, and many hand-made `RowLayout`s.
- 9 popup panels, each a bare `Item` with a `Column`; only the network popup has parts in
  files of their own (`panels/network/VpnSection.qml` and others). There is no popup
  section block.

**What is refactored first.** Not everything. A view gets blocks when it gets its first
anchor. This round converts only what today's slots and the first consumer need: the
General page, the network and notifications popups, the VPN, Wi-Fi and Ethernet pages.
`NetworkProfileCard` is rebuilt on `SettingsCard`. Other views follow when a module needs
them or when step 7 touches them; until then they have no anchors, and the table says so.

### 4.2 Naming

```
<surface>.<view>[.<block>]…[.<region>]
```

- `surface`: `settings` or `popup`. The bar has no anchors.
- `view`: the settings page's id (`SettingsWindow.pages`: `general`, `network_vpn`, …) or
  the popup's key (`WidgetRegistry`: `network`, `notifications`, …). These ids are public
  already (`Api.openSettings`).
- `block`: the block's `anchor` name, `[a-z][a-zA-Z0-9]*`, written in the code. It says
  what the block holds (`saved`, `vpns`, `connections`), never where it is (`top`,
  `bottom`) and never the title's words, so a new title or a translation changes nothing.
- A block repeated per item is named by its kind: `card`, `row`. All instances share one
  path; the item is in the element's `context` (`context.networkId`).
- `region`: `actions` or `settings`, under a card only (§4.8).
- Unique among siblings. A block with no `anchor` is not addressable and adds no level.

The anchors of this round. Every `context` also has `anchor` and `placement`.

| Path | What | Offers | Scope | `context` |
|---|---|---|---|---|
| `settings.general` | the General page | append | — | `editIndex` (the profile being edited) |
| `popup.network.connections` | the VPN, Ethernet and Wi-Fi parts of the network popup | append | — | `wifiEnabled`, `wifiConnected`, `ethernetConnected` |
| `popup.network.connections.vpn.row` | each VPN's row in the popup | after | own-provider | `vpnId`, `entryId`, `vpn`, `provider`, `otherVpnsUp`, `otherVpns` |
| `popup.notifications` | the notifications popup, under its header | prepend | — | `count` (the notifications in the list) |
| `settings.network_vpn.vpns.card.settings` | each VPN's card, its opened part | prepend | own-provider | as the VPN's row |
| `settings.network_wifi.saved.card` | each saved Wi-Fi network's card | marks (§4.10) | — | — |
| `settings.network_wifi.saved.card.settings` | the same card's opened part | append | — | `networkId`, `name`, `kind`, `active` |
| `settings.network_ethernet.profiles.card` | each wired profile's card | marks | — | — |
| `settings.network_ethernet.profiles.card.settings` | the same card's opened part | append | — | as the saved Wi-Fi network's |
| `settings.network_wifi.saved.card.actions` | the same card's buttons | append | — | as its `settings` |
| `settings.network_ethernet.profiles.card.actions` | the wired profile card's buttons | append | — | as its `settings` |
| `settings.network_vpn.vpns.card.actions` | the VPN card's buttons | append | own-provider | as the VPN's row |

The first four contexts are today's slots' (verified: `ModuleRules.slotTable`), with
`otherVpns` added (§3.8). A block kind can take more than the table offers (a section's
`before`, a card's `after`, a region's other end); a placement is published when a module
needs it. Hotspot cards stand in another section (`hotspots`) and are not published.

### 4.3 How a path is derived and stays stable

- The window gives a page's root its base (`settings.<page id>`), the popup gives a panel's
  root `popup.<key>`. A block's path is its nearest enclosing block's path plus its own
  `anchor`; it finds that block by walking up `parent`. The path is a binding, not a value
  computed once: a block moved under another parent has the new path.
- So a path changes only when a block is renamed or moved under another block. Reordering
  blocks, changing titles or wrapping them in layouts changes nothing.
- The list of anchors is a table, `ModuleRules.anchorTable`:
  `{ path, kind, placements, takes, marks, context, scope, since, where }`. `Api.anchors` is its
  frozen copy; a test holds the documentation's list to it (§7, Z). Only paths in the table take
  content: naming a block does not publish it.
- Views built by a module are not anchors in this round, and neither are a module's
  elements (§4.5 says why).

### 4.4 Registration and building, within the Repeater rules

- **A block's root is a plain column:** its `before` host, its body (the frame and the
  content: a card's border is the body's), its `after` host. The parent layout sees one
  item, so a block works in a `Column`, a layout, or as a `Repeater`'s delegate; the view
  puts layout properties on the block and the block hands its width to the body. A hidden
  block hides its `before` and `after` content with it.
- `prepend` and `append` hosts are the first and the last child of the block's content.
- **A host is today's `ModuleSlot` machinery,** kept as it is (`components/AnchorContent.qml`):
  a `Repeater` on a `ScriptModel` keyed by `ModuleRules.contributionKey`, each element in a
  `ModuleContribution` guard. It is created only when the module host lists content for
  that path and placement, so a block nobody targets costs one string.
- Both Repeater rules hold as they do for `ModuleSlot` today (verified: it sits in
  `NetworkPanel.qml`, built by `panels/Popup.qml` outside the window's incubation, and in
  `GeneralSettings.qml`): popup content is still created through `Qt.callLater`, and no
  host binds a live array.
- **Repeated blocks.** The pages build their cards from a `ScriptModel` keyed by the item
  (`objectProp: "uuid"`: verified on the three network pages), so one delegate stands for
  one network as long as it lives, and the elements inside it never change item. A change
  to the item (renamed, connected) reaches an element as a new `context`, passed only when
  it differs by value (`ModuleContribution`, as today). An item that goes takes its
  delegate, the hosts and the elements with it.
- Blocks also report themselves to a plain core singleton, `singletons/Anchors.qml`
  (`live`: path → count). Nothing in the running shell reads it; the pin test does.

**An element** is what a slot contribution is today: built in its own guard; its root may
declare `module`, `context` and `shown`. `context` is `{ anchor, placement, … }` plus what
the table documents for that path.

**Scope.** `own-provider` (the VPN paths) builds a module's element only on the items of
its own VPN provider. The block tells its hosts the item's provider id; the host lists only
that module's content (a pure rule, `ModuleRules.anchorContent(anchors, path, placement,
scopeId)`). A card's regions are part of the card, so they follow its scope.

Manifest:

```
"anchors": [{ "at": "settings.network_wifi.saved.card.settings", "place": "append", "component": "ExitNodeRow.qml" }]
```

`at` is a path in the table, `place` one of that path's placements, `component` a file of
the module. The same three twice is an error (the second is dropped): the key that keeps
an element alive across changes is the module and the file. An older shell keeps the
unknown `anchors` field with a warning (verified: `ModuleRules`, "unknown field … kept").

### 4.5 Missing anchors, and order

- **A path this shell does not offer**, or a placement that path does not take: an error in
  the module's status, shown in Settings → Modules and `modules list`. The rest of the
  module loads. Today an unknown slot is only a warning.
- **An anchor removed by a later shell**: the same error, and the shell's API floor (§6)
  says which version the module must be written for.
- **A path in the table that no view builds any more** is a shell defect; the pin test
  (§4.6) catches it before release. At run time such content shows nowhere.
- **The status texts** for the manifest fields this plan adds, each naming the field first
  as today's do:
  - "anchors: `x` is not a place this shell offers (module API 1.n)"
  - "anchors: `x` does not take `prepend` (it takes: append)"
  - "anchors: `File.qml` is named twice for `x`, `append` (the second is ignored)"
  - "anchors: `x` takes a SmallButton" (at build)
  - "icon: one character, an SVG file or a picture is expected", "icon: `a.svg` is
    larger than 64 KiB", "icon: `a.svg` cannot be drawn"
  - "exports: the main has no `exports` object", "exports: the version `x` is not
    \"major.minor\""
  - "uses: needs module `x` 1.0: not installed" (or "turned off", "failed", "has 0.9"),
    "uses: `a` and `b` need each other"
  - "optionalPrograms: not a list (ignored)", "testPrograms: `dir` is not a directory of
    this module"
- **Several modules on one path and placement**: by module id, alphabetically; within a
  module, manifest order; top to bottom, the same for all four placements. A module's
  elements there stay together. Stable across machines (verified: `ModuleRules.merge` sorts
  by id today, not by the search path).

The order of modules, both the order they are loaded in and the order of their elements
in one place, is the owner's to design in a later stage (§7, "Later"). Until then there is
one rule everywhere: by module id. `ModuleRules.anchorContent` is the only place that
orders elements, so a later rule changes one function.

### 4.6 The test that pins the list

`tests/AnchorsTest.qml`:
1. builds every converted settings page and popup panel with the fixture module off,
   collects `Anchors.live`, and compares it with the table: every table path is live, and
   every live path that is not in the table is listed in the test as "named, not published";
2. checks every path against the naming rule, and that no table path is under
   `lockscreen`, the screensaver or `singletons/lock` (`tests/lock-closure.sh` takes
   `AnchorContent` and the five block files in place of `ModuleSlot`: none may be reached
   from the lock screen's path);
3. with the fixture module on: one element per published placement of each path appears,
   in the order of §4.1, with the documented context; an unknown path gives a status error;
   a mark set and cleared shows and goes on a closed card (§4.10); a button of each kind
   on an `actions` region, and an element that is not the button refused (§4.8). The
   fixture module is that region's consumer: the Tailscale module puts no button on a
   card in this round.

The suites run with no D-Bus (verified: `tests/headless.sh`), so building a network page
reads nothing real. Repeated blocks need an item to be live: the VPN page gets
`tests/FakeVpnProvider.qml`; for Wi-Fi and Ethernet the suite sets
`NetworkProfiles.profiles` (a plain property: verified).

The pure parts have their own cases in `ModuleRulesTest`: the manifest check, the slot
aliases, `anchorContent` (scope and order), `cardMarks` (§4.10).

### 4.7 Today's slots, and the first consumer

| Slot (`ModuleRules.slotTable`) | Becomes | Where it shows |
|---|---|---|
| `network.popup.sections` | `popup.network.connections`, append | unchanged |
| `notifications.popup.top` | `popup.notifications`, prepend | unchanged: under the header, above the list |
| `settings.general.bottom` | `settings.general`, append | unchanged |
| `network.vpn.row` | `popup.network.connections.vpn.row`, after, own-provider | unchanged |
| `network.vpn.card` | `settings.network_vpn.vpns.card.settings`, prepend, own-provider | unchanged: today it is the first of the page's rows (verified: `NetworkVpnSettings.qml`), and a provider's card has no rows of its own above them |
| `network.vpn.page` | removed: a provider's page is its `settingsPage` (API 1.2); the module does not use the slot | — |

A slot keeps its `ModuleSlot` until the slice that converts its view. From then on a
manifest's `slots` entry for it is read as the anchor, and listed in the module's
`deprecations` (§6); their `context` also carries `slot`, and on the card `open: true`, as the old
names promise. One thing differs for the VPN card: its content was built with the card and
is now built when the card opens. The module's card content only shows details (verified:
`TailscaleCard.qml` reads no `context.open`), so nothing is lost.

`components/ModuleSlot.qml`, `Api.slots`, the `slots` field, and `components/VpnExtras.qml`
with `VpnProvider.rowExtras` / `cardExtras` (used only by the test stand-in: verified) go in
the closing slice (§7).

**First consumer: the exit node per network.** The saved network's card, opened, already
holds that network's own choices, each applied at once (connect automatically, priority:
`NetworkProfileCard.qml`). The module appends one row there, on
`settings.network_wifi.saved.card.settings` and
`settings.network_ethernet.profiles.card.settings`, with context
`{ networkId (the profile's UUID, as in Api.networks), name, kind, active }`.
The choice stays in `module.store`, keyed by `networkId`, and applies at once like its
neighbours. Hotspots and VPNs have other paths, so the row never shows there.
`NetworkExitTable.qml` on the module's page goes; with it goes the one place that showed
every network's choice at a glance; the icon on the closed cards takes its place (§4.10).

---

## 7. Slices

The rows of this file's slices; the order, sizes and dependencies are in the index.

### Step 4

| Slice | API | Files | Verified by |
|---|---|---|---|
| U0 Anchor rules | — | `ModuleRules` (`anchorTable`, empty; the path rule; the manifest's `anchors` check; slot aliases; `anchorContent`), `tests/ModuleRulesTest.qml` | rule cases |
| U1a The host and the page block, on a fixture view | 1.13 (the manifest's `anchors`) | `components/AnchorBlock.qml`, `AnchorContent.qml` (from `ModuleSlot`), `SettingsPage.qml`, `singletons/Anchors.qml`, `ModuleHost.qml`, `api/Api.qml` (`anchors`), `tests/lock-closure.sh` | `AnchorsTest` (new) on a fixture page; the walk up `parent` in `QuickshellPinTest` |
| U1b The General page | 1.14 | `SettingsWindow.qml`, `GeneralSettings.qml`, the first table row | `AnchorsTest`; the page's rows at the same places before and after; the slot case through its alias |
| U2 Popups | 1.15 | `components/PopupSection.qml`, `PopupRow.qml`, `panels/Popup.qml`, `NetworkPanel.qml`, `panels/network/VpnSection.qml`, `NotificationPanel.qml` | `AnchorsTest`; the popups' parts at the same places before and after; by hand once |
| U4a The section and the card with `settings`, on a fixture view | — | `components/SettingsSection.qml`, `SettingsCard.qml`, `AnchorContent.qml` (scope) | `AnchorsTest` on a fixture: the region while open, scope, a card that goes |
| U4b `NetworkProfileCard` on `SettingsCard` | — | `NetworkProfileCard.qml` | a geometry test written first, on the old card: where its named parts stand, closed and open, as a Wi-Fi, a wired, a hotspot and a provider's card; the same numbers after |
| U4c The VPN page | 1.20 | `NetworkVpnSettings.qml`, `network/VpnManager.qml`, table rows | `AnchorsTest`, `VpnProvidersTest`; by hand once |
| U5 The Wi-Fi and Ethernet pages | 1.21 | `NetworkWifiSettings.qml`, `NetworkEthernetSettings.qml`, table rows | `AnchorsTest`; by hand once |

---

## 9. Verified, assumed, hard

The part of the plan's §9 that is about this file.

**Verified in the code.**
- The slot table has six names; the module uses `network.vpn.row` and `network.vpn.card`.
  `ModuleSlot` is used in `NetworkPanel.qml`, `NotificationPanel.qml` and
  `GeneralSettings.qml`; the two VPN slots are built by `components/VpnExtras.qml`.
  `ModuleRules.merge` orders modules by id.
- The survey in §4.1; `NetworkProfileCard`'s controls apply at once; the connection editor
  saves on a button.
- `NetworkProfileCard.qml`: the secondary buttons are right-aligned at their own width,
  "Forget" last; the opened column is the card's two rows, then the page's (`_extra`); all
  of it is built with the card today and only hidden while closed. On the VPN page the
  provider's content is the first of the page's rows. The three network pages build their
  cards from `ScriptModel`s keyed by `uuid` and keep one card open (`_open`).
- The unit suites run with D-Bus addresses that lead nowhere (`tests/headless.sh`), and
  today only compile the network pages (`tests/SettingsPagesTest.qml`);
  `NetworkProfiles.profiles` is a plain property a suite can set.
- A manifest's unknown top-level field is kept with a warning.

**Assumed.**
- A block can find its enclosing block by walking `parent` at completion, also inside a
  `Loader` and a `Repeater` delegate. U1a starts by checking it in `QuickshellPinTest`.
- A `ScriptModel` keeps a delegate when its item's values change. If it rebuilds it
  instead, a module's element on that card is rebuilt too: harmless, an opened
  `ExpandingRow` closes.
- The pin test can build the network pages with no D-Bus without errors that fail a suite.

**What the current code makes hard.**
- **No shared blocks exist.** Anchors need them first; converting all 26 pages and 9 popups
  at once would be a large visual-risk change, so the plan converts view by view and the
  anchor list starts short.
- **"Connection's options" has two homes** with different save models; the owner chose the card (§8).
- **The VPN slots are filtered per provider** and built through `VpnManager.extrasFor` and
  `VpnExtras`, not `ModuleSlot`. U2 and U4c move a module's content to the anchor hosts with
  `scope`; `VpnExtras` stays for a provider that is no module's (the test stand-in) until
  the closing slice.
- **One card for four uses.** `NetworkProfileCard` serves Wi-Fi, Ethernet, hotspots and
  VPN providers; rebuilding it on `SettingsCard` (U4b) is the largest visual risk of step 4.
  That slice changes nothing else and is held by a geometry test written on the old card.
- **A block's root gains a level** (§4.4), so a converted view's layout properties move
  from today's item to the block. Views that anchor into their children by `id` need care.
