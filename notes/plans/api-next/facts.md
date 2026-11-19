# Module API, the next versions: facts, helpers and the file chooser

One area of the plan. Read [the index](../api-next.md) first: the rules for every
slice (§2), the gate every slice passes (§7), the slice list with sizes and
dependencies, the lanes. `TC`, `TR`, "verified" and "assumed" are defined there.

The module's main object and a popup's inputs, helpers, system and network facts, the
file chooser, and what this plan leaves out.

Slices in this file: B1, C1, C2, D1, E0, E1.

Section numbers are the plan's and stay as they were. Where each is:
§1 `migration.md` · §2, §8, §10 the index · §3.1–3.4 `commands.md` · §3.5–3.10 `facts.md` ·
§4.1–4.7 `places.md` · §4.8, §4.10 `cards.md` · §4.9 `elements.md` · §5 `module-api.md` ·
§6, §11 `versioning.md` · §7: the list, the lanes and "Later" in the index, a slice's row
in its file, Z in `migration.md` · §9: at the end of each file.

## 3. Step 3: the API extension (continued: 3.5–3.10)

### 3.5 Shared module object, and what a popup panel is given

```
module.main    // the object made from the manifest's `main` while the module is active;
               // null while off or with no main; notifies
```

The host sets it right after creating the main and clears it before destroying it. Views
read through it (`module.main?.client`) and must allow null.

A module's popup panel gets, each only when its root declares the property:

| Property | Value |
|---|---|
| `opener` | frozen `{ widgetType, preset, edge, byTouch }`: the bar widget that opened it |
| `availableHeight` | the most height before the panel must scroll; kept current |
| `fitsShownHeight` | declared true by the panel: it is sized to the height shown while the popup animates |
| `popupAnimating` | true while the popup moves or resizes |

`PopupWidget.togglePopup` passes `{ widgetType, preset }` as `contentData`
(`panels/Popup.qml` already carries it); the last three are set today and only get
documented and tested.

Test (`ModuleRegistriesTest`): `main` is set before the module's widgets complete, null
when off, a new object when on again; two bar entries on different presets each see their
own `opener.preset`.

### 3.6 Helpers

```
Api.format.bytes(n) / rate(n) / ago(ms, nowMs)
Api.address.isIpv4 / isIpv6 / isIp / parseCidr / contains / overlap / redact
Api.minuteNow                               // ms, updated on each minute boundary
module.notify(summary, { body, format: "plain" })   // also Api.notify
module.log(level, text, key)                // "[<id>]" prefix; with `key`: only when the
                                            // text for that key changed
```

One pure core singleton `singletons/AddressRules.qml` (from the module's tested code, with
its cases); `NetworkRules` delegates to it. `format: "plain"` escapes `&`, `<`, `>` and
drops control characters.

Test: `AddressRulesTest`, `FormatTest` (TB, `ago` in milliseconds), `NotifierTest` (plain),
`ModulesTest` (log dedupe).

### 3.7 System facts and the data directory

```
Api.system = { ready, userName, uid, hostName, home, configHome, dataHome, runtimeDirectory,
               downloadDirectory, readIpForwarding() → { ipv4, ipv6 }, refresh() }
module.dataDirectory     // "<dataHome>/h2s-shell/module-data/<id>", made 700 by the host
```

- `downloadDirectory` is `XDG_DOWNLOAD_DIR` from `user-dirs.dirs` (read, never sourced),
  else `~/Downloads`. `readIpForwarding` gives `null` for a value it could not read.
- The data directory is apart from `modules/<id>`, which installing and removing a module
  (step 8) owns. Moving the module's certificates there is module work.

Test: `SystemFactsTest` with fake files passed in as paths.

### 3.8 Network facts

```
Api.networksReady      // profiles and their Wi-Fi details are read
Api.networks           // a Wi-Fi row appears only once its details are read (no hotspot)
Api.localNetworks      // frozen [{ device, kind, family, address, network }], global scope,
                       // no VPN, tun, WireGuard or provider devices
Api.localNetworksReady
Api.vpnsUp             // rows gain fullTunnel, setsDns (true | false | null), routes
```

`VpnProvider` entries may set the same three fields; absent is `null` (unknown, never
"false"). The VPN anchors' context gains `otherVpns` (the rows) beside `otherVpnsUp`.

Test: `ModuleRulesTest` (`apiNetworks` with details missing, `apiVpnsUp`, `apiLocalNetworks`).

### 3.9 File chooser

```
module.chooseFiles({ mode: "open" | "openMany" | "folder", title, startDirectory }, done)
result = { paths: [absolute…], cancelled, blocked ("" | "locked" | "busy"), error }
```

A minimal version in this round (the owner's answer). It covers what the module's
dialogs do today (verified in its `TaildropSection.qml`): several files to send, starting
in the home directory; the folder for received files, starting in the current one. Saving
under a new name and name filters come when a module needs them.

- On the handle, not on `Api`: the shell closes the dialog and drops `done` when the module
  is turned off.
- Hosted by the shell, not by the caller's window, so a popup can call it and close.
- One at a time for the whole shell (`busy`); refused while locked; a lock while it is open
  closes it (`cancelled`). Absolute paths, never URLs. `title` is plain text, capped at 60.

**Starts with a spike**, a day at most, on NixOS and on Arch. Done when a `FileDialog`
owned by the shell, with no settings window open:
1. opens as a window of its own from a click in a popup, and stays when the popup closes;
2. takes the keyboard, in Hyprland and in the test bed's compositor;
3. returns several files, one folder, and a cancel, and starts in `startDirectory`;
4. can be destroyed while open without a crash.

If 1 or 2 fails, the same four with a small shell window as the dialog's parent. If that
fails too, the slice stops and reports: the API is not built on a guess, and row 20 of §1
stays until it is solved.

**The spike's finding** (E0; Arch, Quickshell 0.3.2, Qt 6.12, Hyprland and the runners'
headless labwc 0.20.3; not run on NixOS). A scratch shell of its own, the dialog made by the
shell's root, opened by a click in a layer-shell window that then closes.

Which dialog appears is decided by Qt's platform theme (`QT_QPA_PLATFORMTHEME`), not by the
shell, and the three behave differently:

| Platform theme | Dialog | Without a parent window | Several files | `reject()`, `close()` | Destroyed while open |
|---|---|---|---|---|---|
| none; `qt6ct` with its "standard dialogs" left at the default (this machine); the runners' compositor | Qt Quick's own, a window of the shell (`org.quickshell`), drawn in the Controls style, not the shell's theme | does not open: `open()` does nothing, `visible` stays false, no warning | no: its list has one current item; Shift+Down and Ctrl+A gave one file | the window goes at once | no crash; **the window stays** until the shell ends. Closed first, then destroyed: gone at once |
| `xdgdesktopportal` | the portal's (here `xdg-desktop-portal-gtk`, a window of that process); `multiple`, `directory`, `current_folder` are sent | opens | offered by the portal (the option is sent; not picked by hand) | the dialog reports closed, **the window stays** until the shell ends | no crash; the window stays until the shell ends |
| `gtk3` | GTK's, in the shell's process | opens | not tried | the window goes | not tried |

`options: FileDialog.DontUseNativeDialog` (`FolderDialog` has it too) gives Qt Quick's own
dialog under every theme (seen under `xdgdesktopportal`: no portal call).

The four points, for Qt Quick's own dialog, which is the one this machine and the test bed
have:

1. **Fails without a parent, passes with one.** The parent is any visible window of the
   shell: the dialog is made as a child of an item in it. A hidden window does not count. A
   layer-shell window does, also one transparent pixel shown only while the dialog is open,
   so no window of the settings is needed and nothing else shows. The dialog stays when the
   popup closes. Under a layer-shell parent Hyprland tiles it; under a normal window it
   floats.
2. **Passes.** Hyprland: the dialog is the active window as soon as it is mapped (the
   compositor's answer; no key was sent on the real session). labwc: a real Escape cancelled
   it and a real Return accepted the chosen file (`wtype`, in the runners' compositor).
3. **One file, one folder, a cancel: pass. Several files: fail.** `FileDialog.OpenFiles`
   opens, and returns one file. `startDirectory` (`currentFolder`) is where it opens (seen
   in the real window). A `FolderDialog` accepted with nothing chosen returns the first
   folder in the list, not the folder it shows (`accept()` from code; the "Open" button was
   not clicked by hand).
4. **Passes, with a rule.** No crash in Hyprland or labwc. The dialog is closed before it
   is destroyed, else its window stays.

What follows for E1:

- The shape that works everywhere tried: Qt Quick's own dialog (`DontUseNativeDialog`), a
  one-pixel layer-shell window of the shell as its parent, `close()` before `destroy()`.
  It is the only one the shell can close (a lock, a module turned off) and the only one a
  test can drive.
- That shape cannot return several files, which `openMany` promises and the module's
  "send files" uses. The portal can, but its window cannot be closed by the shell, and it
  is there only where the user's platform theme says so. **E1 waits for the owner's
  choice:** one file per call (and `openMany` leaves the API, or returns one), the
  platform's dialog where there is one (several files; a lock does not close it), or a
  chooser of the shell's own.
- Not tried by hand, for the owner: Ctrl+click and Shift+click on two files in Qt Quick's
  own dialog (expected: one stays chosen); "Open" in the folder dialog with nothing chosen.

**As built (E1, module API 1.17).** The owner's answer was "the system's standard dialog"
(tracker, "Decisions"); E1 takes the lead's reading of it — whichever dialog the user's Qt
platform theme gives, as the module's dialogs do today — and leaves `DontUseNativeDialog`
off (one place in `singletons/FileChooser.qml` if the owner wants Qt Quick's own everywhere).
So `openMany` returns several files only where the platform's dialog can (the portal's), one
with Qt Quick's own; a lock and the module turned off close Qt Quick's own and GTK's, while a
portal's window stays on screen and its answer is dropped. The one-pixel layer-shell window
(no input, shown only while a dialog is open) is the parent; the dialog is closed before it
is destroyed, and the window hidden before it is destroyed (else Qt Quick's dialog warns that
it found no window to open in). `startDirectory` empty is the home directory. Tested:
`tests/FileChooserTest.qml` runs Qt Quick's own dialog in the unit runner's headless
compositor, driven by QtTest key events (Down to a file, Return; Escape); a module's suites
get recorded calls (`ModuleTestKit`). By hand, open: the portal's and GTK's dialogs through
the shell, Ctrl/Shift+click in Qt Quick's own.

### 3.10 Not in this plan

- A terminal call and a terminal setting: the owner decided a global "default programs"
  setting later. "Copy ssh command" stays.
- A time window after a click for privileged runs.
- API 2.0: until the first release announced as open to module authors, removals ship
  in a minor (§6).

---

## 7. Slices

The rows of this file's slices; the order, sizes and dependencies are in the index.

### Step 3

| Slice | API | Files | Verified by |
|---|---|---|---|
| B1 Shared module object, popup inputs | 1.8 | `ModuleHost.qml`, `api/ModuleHandle.qml`, `components/PopupWidget.qml`, `panels/Popup.qml` | `ModuleRegistriesTest` |
| C1 Helpers | 1.9 | `singletons/AddressRules.qml`, `network/NetworkRules.qml`, `Format.qml`, `Notifier.qml`, `api/Api.qml`, `api/ModuleHandle.qml` | `AddressRulesTest`, `FormatTest`, `NotifierTest`, `ModulesTest` |
| C2 System facts, data directory | 1.10 | `singletons/SystemFacts.qml`, `ModuleHost.qml`, `api/Api.qml`, `api/ModuleHandle.qml`, test kit | `SystemFactsTest` |
| D1 Network facts | 1.11 | `ModuleRules.qml` (`apiNetworks`, `apiVpnsUp`, `apiLocalNetworks`), `api/Api.qml`, `network/VpnManager.qml`, `components/VpnProvider.qml` | `ModuleRulesTest` |
| E0 File chooser: the spike | — | none kept; the finding is in §3.9 | the four points of §3.9, on Arch; not run on NixOS |
| E1 File chooser | 1.17 | `singletons/FileChooser.qml`, `ModuleHost.qml`, `api/ModuleHandle.qml`, test kit, `tests/lock-closure.sh` | recorded calls in test mode; closed with the module; by hand |

---

## 9. Verified, assumed, hard

The part of the plan's §9 that is about this file.

**Verified in the code.**
- The module's two dialogs (`TaildropSection.qml`): several files, from the home directory;
  a folder, from the current one. The core has a `FileDialog` on the VPN page.

**Verified by running it** (the spike, §3.9; Arch only).
- A `FileDialog` of the shell with no window as its parent does not open, silently, unless
  the platform theme gives a native dialog. With a visible window of the shell as its
  parent (a one-pixel layer-shell window is enough) it is a window of its own, stays when
  the popup closes, and has the keyboard in Hyprland and in labwc.
- Qt Quick's own dialog returns one file, never several; a folder; a cancel; it opens in
  `currentFolder`.
- Destroyed while open: no crash, the window stays; closed first, it goes. The portal's
  window cannot be closed from the shell at all.

**What the current code makes hard.**
- **Several files and a dialog the shell can close do not come together** (§3.9): Qt Quick's
  own dialog has the second, the portal's the first.
- The module's "send files" dialog and the core's two (`NetworkVpnSettings.qml`,
  `WallpaperSettings.qml`) are plain `FileDialog`s: which dialog a user gets, and whether
  several files can be picked, depends on the platform theme today.

**Assumed.**
- NetworkManager may or may not report `tailscale0`'s addresses; the filter covers both.
- The module's dialogs have never been clicked on a real machine (tracker backlog).
- NixOS has the same three dialogs by platform theme as Arch (§3.9): the spike was not run
  there.
