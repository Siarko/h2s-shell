pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io as Io

// The module API (docs/plans/modules.md, "Module API 1.0", 1.1, 1.2 and 1.3): with qs.components, everything a
// module may use of the shell. A module imports `qs.api` and reaches:
//
//   Api.version            "1.3" — this shell's module API, "major.minor". A module's manifest
//                          asks for one ("api"); it loads when the major is the same and this
//                          minor is at least the one asked for. Adding anything bumps the minor;
//                          changing or removing anything bumps the major.
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
//
// And these types (files beside this one):
//   SettingEditor, SectionTitle, Heading, Hint, DetailRow, SwitchRow — the settings window's
//                          building blocks, so a module's page looks like the core's
//   CommandAction, CommandQuery, PrivilegedAction — running commands the shell's way
//   ThemeTokens, ModuleHandle, ModuleStore — what Api.theme, a handle and its store are
//
// From qs.components (API 1.1): VpnProvider, the base type of a VPN provider — a module's uses
// its module id as `providerId`, and its three VPN slots (network.vpn.row, .card, .page) are
// manifest `slots` contributions like any other (Api.slots; docs/plans/tailscale.md §3).
Singleton {
    id: root

    readonly property string version: ModuleRules.apiVersion

    readonly property ThemeTokens theme: ThemeTokens {}

    // The slots the core offers in this API version (ModuleRules.slotTable, the reference)
    readonly property var slots: Object.freeze(ModuleRules.slotTable.map(entry => Object.freeze(Object.assign({}, entry))))

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
