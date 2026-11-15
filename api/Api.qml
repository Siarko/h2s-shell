pragma Singleton

import Quickshell
import QtQuick

// What modules may use of the shell (docs/plans/modules.md). For now only the module API's
// version; the next stage grows this into the facade modules import (`import qs.api`).
//
// The version is the module API's own, separate from the shell's (singletons/Version.qml):
// "major.minor". A module's manifest asks for one ("api": "1.0"); it loads when the major is
// the same and this minor is at least the one asked for (ModuleRules.apiCompatibility).
// Adding to the API — a slot, a function — bumps the minor; changing or removing anything
// bumps the major.
Singleton {
    readonly property string version: "1.0"
}
