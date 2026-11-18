pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io as Io
import qs.singletons.network

// The module API (notes/plans/modules.md, "Module API 1.0", 1.1, 1.2 and 1.3; notes/plans/api-next.md from 1.4): everything a
// module may use of the shell. A module imports `qs.api` and reaches:
//
//   Api.version            "1.7" — this shell's module API, "major.minor". A module's manifest
//                          asks for one ("api"); it loads when the major is the same, this
//                          minor is at least the one asked for, and the one asked for is not
//                          below the shell's floor (ModuleRules.apiFloor: the oldest version
//                          whose modules still run unchanged). Every change bumps the minor
//                          and has its "- 1.x:" line under "Module API" in CHANGELOG.md.
//                          Until the first release announced as open to module authors a
//                          minor may also remove things: the old way keeps working while it
//                          is listed in the module's status (`deprecations`, in `modules
//                          list`), then goes in a change that raises the floor — a module
//                          below it does not load, and says why. From that release on a
//                          removal needs a major version, after at least one release that
//                          listed the thing as deprecated.
//   Api.theme              the theme's tokens, read-only (api/ThemeTokens.qml)
//   Api.slots              the slots the core offers: [{ name, where, context, since }]
//   Api.module(id)         a module's handle (api/ModuleHandle.qml), or null
//   Api.moduleAt(url)      the handle of the module whose directory holds `url` — in any file
//                          of a module: Api.moduleAt(Qt.resolvedUrl("."))
//   Api.notify(summary, options)   a notification (options: Notifier's — body, urgency, icon,
//                          actions…); a module's own handle's notify() names the module
//   Api.openUrl(url, options)  opens a link in the user's programs (xdg-open, no shell): only
//                          http:, https:, mailto: — file: with { allowFile: true }; anything
//                          else (no scheme, a bare path, another scheme) refused, logged, false
//   Api.copy(text)         puts text on the clipboard
//   Api.openSettings(page) the settings window on a page, by id (a core page's or a module's)
//   Api.networks           (1.3) the saved networks this computer joins, frozen:
//                          [{ id (the NetworkManager profile UUID, system.vpnWithNetworks' key),
//                          name, kind ("wifi" | "ethernet"), active (bool, fully up) }] — no
//                          hotspots, VPNs, bridges or their ports; active ones first, then
//                          NetworkProfiles' order; empty until the profiles are read. A new
//                          array only when something in it changed
//   Api.vpnsUp             (1.3) the VPNs up now, frozen: [{ name, type ("wireguard", "vpn"…
//                          or "provider"), provider (a provider's providerId, else "") }];
//                          a new array only when something in it changed.
//                          Both show every installed module the saved network names and the
//                          VPN names: modules are trusted and run in the shell's process
//
// And these types (files beside this one):
//   SettingEditor, SectionTitle, Heading, Hint, DetailRow, SwitchRow — the settings window's
//                          building blocks, so a module's page looks like the core's
//   CommandAction, CommandQuery, PrivilegedAction — running commands the shell's way
//   SmallButton (1.4), Dropdown, InputField, Pill, Checkbox, ToggleSwitch, PrivilegedMark
//                          (1.5), SettingsRow, ExpandingRow, Notice (1.6) — the public
//                          elements (below)
//   PopupWidget, BarText, BarRow, PointerArea, VpnProvider (1.7) — the base types (below)
//   ThemeTokens, ModuleHandle, ModuleStore — what Api.theme, a handle and its store are
//
// Public elements (1.4): types made for the API, which hold the shell's internal component
// inside and show only their own properties; the shell changes its insides freely. On one
// a module picks a meaning, never a colour, a radius or a number of pixels: `kind` (what
// the element is about) and `size` ("xs", "s", "m" — the default —, "l"; an element takes
// the ones it has). Both lists are open: a word an element does not know shows as its
// default and is logged once per element type and word. Every text is shown as written
// (plain text). An element's properties and signals are pinned by tests/ApiElementsTest.qml;
// a change to them is a version change.
//   SmallButton            label, available, checked, tooltip;
//                          kind: "primary" (performs the action) | "secondary" (the default:
//                          a step in between, opens something, "Cancel") | "danger" (stops
//                          or removes) | "warning" (goes on, but think) | "success" (a good
//                          outcome to take); size: "xs" | "s" | "m";
//                          confirm (false; true: the first click only turns the button into
//                          the question, with a "×" that takes it back, the second acts),
//                          confirmLabel (the question; the label and "?" unless given),
//                          cancelTip (the "×"'s tooltip), asking (the first click was made;
//                          set it false when what the button acts on changes);
//                          clicked() — do it: the click, or with confirm the second one;
//                          asked() — the first click of a button that asks. A danger button
//                          without confirm acts on the first click. A button that asks
//                          shows no `checked` and keeps its own width in a layout.
//   Dropdown               (1.5) options ([{ value, label }]), value (the owner sets it),
//                          placeholder (shown while the value is none of the options);
//                          size: "xs" | "s" | "m"; picked(value) — the choice made
//   InputField             (1.5) text, placeholder, problem (the value is wrong now),
//                          password (hidden, with an eye), revealed (the eye flips it);
//                          size: "xs" | "s" | "m"; accepted(), textEdited(),
//                          editingFinished(), revealToggled()
//   Pill                   (1.5) label, picked (the owner sets it), tooltip;
//                          size: "s" | "m" | "l" — the theme's three pill heights;
//                          clicked()
//   Checkbox               (1.5) label, checked (the owner flips it); toggled()
//   ToggleSwitch           (1.5) checked (the owner changes it), and every item's
//                          `enabled`; toggled()
//   PrivilegedMark         (1.5) need — polkit's answer for what the control beside it
//                          does: "auth" (the default: the lock), "no" (not allowed), "yes"
//                          or "" (nothing to mark: hidden, no room taken). An answer it
//                          does not know shows the lock. Where a module sets `visible`
//                          itself, an element with nothing to mark is empty and without
//                          size, but a layout keeps its spacing around it.
//   SettingsRow            (1.6) label, hint (a short line under the label), value (a
//                          text on the right); its children, written inside it, are the
//                          controls on the right, in a row (`controls` is where they go,
//                          nothing to set). Fills the width a layout gives it.
//   ExpandingRow           (1.6) label, hint, open (a click on its line flips it; the
//                          owner may set it); its one child, written inside it, is what it
//                          opens (`content`, a Component): built when the row opens,
//                          destroyed when it closes, as wide as the row. Fills the width.
//   Notice                 (1.6) text — a small line that wraps, as the line on a
//                          network's card; kind: "warning" (the default) | "danger" |
//                          "success". Fills the width.
//                          The settings blocks above (SectionTitle, Heading, Hint,
//                          SwitchRow, a SettingEditor's label, hint and unit) and a
//                          module's page name in the settings window show their texts as
//                          written from 1.6: markup in them is no longer read.
//                          qs.components has types of these names too (other properties:
//                          a fontSize, other kinds): in a file that imports both, the
//                          import written last gives the name.
//
// Base types (1.7): what a module's own object extends where the shell needs the object
// itself — the bar its widget, VpnManager a provider. Each is the shell's internal type,
// not a wrapper: the names below are pinned (tests/ApiElementsTest.qml), what else the
// type has is not promised.
//   PopupWidget            a bar widget that opens the popup its manifest names:
//                          widgetType, popup (set by the bar), popupOpen, interactive;
//                          clicked, hover(status), scrolled(delta), scrollNotch(direction),
//                          middleClicked; its children are the cell's content
//   BarText                text on the bar, turned or stacked on a bar at a side: text,
//                          font, color, alignment, elide, length, leadingGap
//   BarRow                 items along the bar, a row or a column: vertical (read-only),
//                          spacing
//   PointerArea            the MouseArea of a module's own control: lit (its hover look,
//                          a tap included), centred, reach, and a MouseArea's own
//   VpnProvider            a VPN provider (the contract is API 1.1's, written in
//                          components/VpnProvider.qml): providerId (the module's id),
//                          kind, typeName, glyph, entries, ready, busy, canChange,
//                          lockdownNote, settingsPage; connect(entryId, request),
//                          disconnect(entryId, request), attend(entryId);
//                          failed(entryId, what, reason). Its three VPN slots
//                          (network.vpn.row, .card, .page) are manifest `slots`
//                          contributions like any other (Api.slots).
//
// `import qs.components` is deprecated (1.7): with the base types here, qs.api has
// everything a module took from the shell's internal components, which may change in any
// release. A module that still imports it loads as before, and the import is listed in
// its status (`deprecations`, in `modules list`); it becomes an error with the change
// that raises the floor.
Singleton {
    id: root

    readonly property string version: ModuleRules.apiVersion

    readonly property ThemeTokens theme: ThemeTokens {}

    // The slots the core offers in this API version (ModuleRules.slotTable, the reference)
    readonly property var slots: Object.freeze(ModuleRules.slotTable.map(entry => Object.freeze(Object.assign({}, entry))))

    // (1.3) Through a JSON text: a string property notifies only when its value changes, so
    // a module reacting to these is not woken by every re-read of the profiles
    readonly property string _networksText: NetworkProfiles.listRead
        ? JSON.stringify(ModuleRules.apiNetworks(NetworkProfiles.profiles, NetworkProfiles.wifi)) : "[]"
    readonly property var networks: ModuleRules.frozenRows(_networksText)

    readonly property string _vpnsUpText: JSON.stringify(ModuleRules.apiVpnsUp(VpnManager.activeVpns))
    readonly property var vpnsUp: ModuleRules.frozenRows(_vpnsUpText)

    function module(id) {
        return Modules.handle(id);
    }

    function moduleAt(url) {
        return Modules.handleAt(url);
    }

    function notify(summary, options) {
        Notifier.send(String(summary), options ?? {});
    }

    // A link, given to xdg-open as one argument (no shell). Only with a scheme, and only
    // http:, https: and mailto: — file: too with { allowFile: true }; anything else (a bare
    // path, a .desktop file, another scheme a program is registered for, text starting with
    // "-", control characters, more than 4096 characters) is refused, logged, → false
    // (ModuleRules.openUrlProblem).
    function openUrl(url, options) {
        const text = String(url ?? "");
        const problem = ModuleRules.openUrlProblem(text, options);
        if (problem !== "") {
            console.warn("[Modules] Api.openUrl refused " + JSON.stringify(text.slice(0, 200)) + ": " + problem);
            return false;
        }
        _opener.run(["xdg-open", text], result => {
            if (!result.ok)
                console.warn("[Modules] xdg-open " + text + " failed:", result.error || result.code);
        });
        return true;
    }

    function copy(text) {
        Quickshell.clipboardText = String(text ?? "");
    }

    function openSettings(page) {
        Shell.openSettings(String(page ?? ""));
    }

    property Io.CommandAction _opener: Io.CommandAction {}
}
