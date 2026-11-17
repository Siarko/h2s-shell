# Module API, the next versions: a module's API for other modules

One area of the plan. Read [the index](../api-next.md) first: the rules for every
slice (§2), the gate every slice passes (§7), the slice list with sizes and
dependencies, the lanes. `TC`, `TR`, "verified" and "assumed" are defined there.

`exports` and `uses`, the load order, and closing the reach into the host and into
other modules.

Slices in this file: P1, P2.

Section numbers are the plan's and stay as they were. Where each is:
§1 `migration.md` · §2, §8, §10 the index · §3.1–3.4 `commands.md` · §3.5–3.10 `facts.md` ·
§4.1–4.7 `places.md` · §4.8, §4.10 `cards.md` · §4.9 `elements.md` · §5 `module-api.md` ·
§6, §11 `versioning.md` · §7: the list, the lanes and "Later" in the index, a slice's row
in its file, Z in `migration.md` · §9: at the end of each file.

## 5. Step 5: a module's public API, basic version

### 5.1 Declaring and using

```
// the provider's module.json
"exports": { "version": "1.0" }
// its main
readonly property QtObject exports: QtObject { … }     // what other modules may use

// the dependent's module.json
"uses": { "tailscale": "1.0" }
// in its files
module.uses.tailscale        // the provider's `exports` object, and nothing else of it
```

- The version is "major.minor", checked like the shell's: same major, the provider's minor
  at least the one asked for. What a provider's minor may change is the provider's rule.
- A dependent gets the `exports` object only. It is a plain `QtObject`, which has no way up
  to the main (no `parent` in QML).
- A module with `exports` in the manifest and no such property on its main: an error in its
  status; dependents count it as missing.
- Basic version: required dependencies only. Optional ones later.

### 5.2 Load order

A pure rule, `ModuleRules.dependencyPlan(manifests, states)`, gives the order and the
reasons. A dependent's main is created after its providers' and destroyed before them.

### 5.3 Missing, incompatible, reload

- A new state `missing-module` (beside `missing-program`), with the reason in the status:
  "needs module tailscale 1.0: not installed" / "turned off" / "failed" / "has 0.9".
- A cycle: every module in it is `failed`, naming the cycle.
- **A provider turned off or reloaded**: its dependents go first (`missing-module`), then
  the provider; turned on again, the provider first, then they come back. So
  `module.uses.x` never changes under a live main, and is never null while the dependent
  runs.
- A shell reload rebuilds everything in the same order.

Test: `ModuleRulesTest` (order, cycle, each reason, version check); `ModulesTest` with two
fixture modules (provider off and on, the dependent follows; the object given is the
`exports` object).

### 5.4 Reach closed

- `Api.moduleStatus(id)` gives a frozen `{ id, name, version, state, active }`.
- `ModuleHandle.host` is renamed in the closing slice (to `_host`: QML cannot hide a
  property, and a read of one cannot be noticed, so there is no warning before that). The
  test kit (§3.3) gives suites what they used it for. `Api.module(id)` is listed in the
  caller's `deprecations` from P2 and goes in the closing slice too.
- The import check (`ModuleRules.allowedImports`) reports `qs.singletons*` and another
  module's directory as an error in the status, not a warning. The module still loads (the
  owner's earlier decision: the check never refuses).
- `qs.components` leaves the allowed imports with the closing slice (§4.9). The module
  uses 13 of its types (verified): `BarRow`, `BarText`, `Checkbox`, `DeleteButton`,
  `Dropdown`, `InputField`, `Pill`, `PointerArea`, `PopupWidget`, `PrivilegedMark`,
  `SmallButton`, `ToggleSwitch`, `VpnProvider`; in 17 of its files.

---

## 7. Slices

The rows of this file's slices; the order, sizes and dependencies are in the index.

### Step 5

| Slice | API | Files | Verified by |
|---|---|---|---|
| P1 `exports` and `uses` | 1.25 | `ModuleRules` (`dependencyPlan`, state), `ModuleHost.qml`, `api/ModuleHandle.qml`, two fixtures | `ModuleRulesTest`, `ModulesTest` |
| P2 Reach: `moduleStatus`, the old ways deprecated | 1.26 | `api/Api.qml`, `api/ModuleHandle.qml`, `ModuleRules` (import check) | `ModuleRulesTest`, `ModulesTest` |

---

## 9. Verified, assumed, hard

The part of the plan's §9 that is about this file.

**What the current code makes hard.**
- **QML cannot hide anything.** `host`, `module.main` and `exports` are reachable by a
  module that tries; the plan closes them by name, status errors and review. Review is
  for the project's own modules: for an outside module they are not closed (§2).
