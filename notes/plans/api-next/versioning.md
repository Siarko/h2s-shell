# Module API, the next versions: versioning, other authors, the doors to keep open

One area of the plan. Read [the index](../api-next.md) first: the rules for every
slice (§2), the gate every slice passes (§7), the slice list with sizes and
dependencies, the lanes. `TC`, `TR`, "verified" and "assumed" are defined there.

The version rule and the floor, what changes when other people write modules, and
what this round must leave possible for the direction (§10, in the index).

Slices in this file: S0, A0.

Section numbers are the plan's and stay as they were. Where each is:
§1 `migration.md` · §2, §8, §10 the index · §3.1–3.4 `commands.md` · §3.5–3.10 `facts.md` ·
§4.1–4.7 `places.md` · §4.8, §4.10 `cards.md` · §4.9 `elements.md` · §5 `module-api.md` ·
§6, §11 `versioning.md` · §7: the list, the lanes and "Later" in the index, a slice's row
in its file, Z in `migration.md` · §9: at the end of each file.

## 6. Versioning

**A minor may remove things until the first release announced as open to module
authors** (the owner's decisions). Until then, what it means here:

- Every slice that changes the API bumps the minor once and adds one `- 1.x:` line under
  `### Module API` in `CHANGELOG.md`. What a slice refuses or removes is named in that
  line after "Tightened:". The headers of `api/Api.qml` and `ModuleRules.qml` say today
  that changing or removing anything bumps the major; A0 rewrites them to this rule.
- There is no 2.0 in this plan.
- **The manifest check gains a floor.** `ModuleRules.apiFloor` is the oldest API version
  whose modules still run unchanged on this shell. `apiCompatibility` then answers: same
  major, `apiFloor` ≤ the module's `api` ≤ the shell's. Below the floor the module is
  `incompatible`, with the reason "written for module API 1.3; this shell needs 1.26 or
  newer (the module needs updating)". So a tightening is never silent.
- **The floor is never the version that removes.** A module cannot ask for a version the
  shell does not have yet, so a slice that removes sets the floor to the last version that
  only added, and merges after a module written for that version is released (§7, Z).
- **During this plan the floor moves once.** Slices in steps 3–5 only add: the old ways
  (`PrivilegedAction`, `elevate`, `slots`, `Api.module`, `import qs.components`) keep
  working. New calls are strict from their first version. One closing slice after step 6
  removes the old ways and raises the floor. `master` therefore always runs the released
  module.
- **Old ways are listed, not warned about.** A module's status gains a list,
  `deprecations` (`ModuleRules.statusOf`), shown by `modules list` and Settings → Modules:
  "slots: use `anchors` (goes with the shell's next tightening)". `warnings` stays what it
  is: the released module's suite asserts it is empty (verified:
  `tests/TailscaleModuleTest.qml`), and a slice that added a warning would turn the gate
  "the released module's suites are green" red.
- A test compares the newest `- 1.x:` line in `CHANGELOG.md` with `ModuleRules.apiVersion`
  (`ModuleRulesTest.qml` stops hard-coding "1.3").
- **From the first release announced as open to module authors** (the owner's answer),
  "a minor may remove" ends:
  - a removal comes only with a major version;
  - and only after the thing was listed as deprecated (`deprecations`) for at least one
    release;
  - removals are announced in `CHANGELOG.md`'s "Module API" section and in the author
    guide.

  A minor then only adds. The floor stays as the mechanism and no longer moves within a
  major.
- **The closing slice's sequencing is a one-off.** "Merges after the module is released"
  (§7, Z) works because there is one module today and the shell and it are released by
  the same hand. With other authors nobody can wait for every module: the release in
  which a thing is listed as deprecated is what gives them the time.

---

## 11. Doors to keep open

Nothing here is built in this round. A slice that touches one of these keeps it possible.

- **A place for shipped modules outside the tree Quickshell scans.** Modules are found by
  `scripts/launch.sh` (`module_roots`: the user's data home, then each
  `<data dir>/h2s-shell/modules`). On NixOS `nix/package.nix` copies the whole tree to
  `$out/share/h2s-shell`, so a `modules/` directory inside the repository would land on a
  system search root and inside the scanned tree at once. To verify before a place is
  chosen: whether Quickshell then registers the modules' files as shell types, and where
  Arch's `install.sh` puts the tree (not read for this).
- **Where a module comes from, and visible shadowing.** A module's status gets a "where
  from" field (shipped, the system's, the user's). Today the first on the search path
  wins and the user's root is first (verified: `ModuleRules.precedence`,
  `module_roots`): the losing copy is listed as `duplicate`, but nothing on the winning
  one says that it replaces a shipped module. That is to be shown, with the statement of
  §10.
- **The import check as a function of the module,** not one global list
  (`ModuleRules.allowedImports` today), so that what a module may import can depend on
  the module without a second mechanism.
- **Core code keeps using core types, never `qs.api`** (as §3.1 says for the runner), so
  the public layer stays a layer and a feature can move out from under it.
- **A reserved prefix for anchors owned by modules.** A feature split out would own the
  places others attach to; the names `settings` and `popup` stay the shell's, and no
  published path takes a first part a module could later need (§4.2).
- **The gaps a split-out feature would meet,** each an API extension of its own when the
  first feature needs it:
  - system state beyond the network: Bluetooth, audio, the battery, the notification
    list, the compositor;
  - popups, windows and on-screen displays that stand alone, not opened by a bar widget;
  - the settings keys of a moved feature (today's keys are the core's; a module's are
    `mod.<id>.*`), with their migration;
  - IPC names: a module's targets are `<id>` or `<id>.<name>` (`api/ModuleHandle.qml`'s
    comment; whether anything enforces it is to verify), so a moved feature's target
    would change name or need an alias;
  - a module offering places to other modules (§4.3: a module's views are not anchors in
    this round);
  - a module's own theme tokens.

---

## 7. Slices

The rows of this file's slices; the order, sizes and dependencies are in the index.

### Step 3

| Slice | API | Files | Verified by |
|---|---|---|---|
| S0 `ModuleRules.qml` in five files | — | the pure split of `architecture-cleanup.md` §2.1, nothing else | `ModuleRulesTest` unchanged and green |
| A0 Version gate, floor, `deprecations` | — | `ModuleRules.qml` (`apiFloor`, `apiCompatibility`, `statusOf`), the version rule in the headers of `api/Api.qml` and `ModuleRules.qml`, `tests/ModuleRulesTest.qml` | rule cases; CHANGELOG ↔ `apiVersion` test |

---

## 9. Verified, assumed, hard

The part of the plan's §9 that is about this file.

**Verified in the code.**
- `apiCompatibility` checks major and minor only; `tests/ModuleRulesTest.qml` hard-codes
  "1.3".

**What the current code makes hard.**
- **`ModuleRules.qml` is one 1667-line file** that nearly every slice edits; its split is
  slice S0. That does not end the meeting of parallel slices in the version line, the
  `Api.qml` header and the CHANGELOG, which stay a merge-time edit.
