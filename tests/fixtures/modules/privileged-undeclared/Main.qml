import QtQuick
import qs.api

// Asks to run its stand-in as administrator without a privileged block in its manifest,
// both ways a module can: module.privileged.start and the old PrivilegedAction. The shell
// refuses both before any prompt (tests/ModulesTest.qml; its own suite,
// tests/UndeclaredTest.qml, in module test mode)
QtObject {
    id: root

    property var module: null

    property PrivilegedAction legacy: PrivilegedAction {
        notifyFailures: false
    }

    // The old type, its stand-in pkexec as the elevating program; `mark`: a file the stand-in
    // pkexec would create if it ran
    function tryLegacy(mark, done) {
        legacy.elevate = [module.programs.pkexec.path];
        legacy.run([module.programs["h2s-fixture-root"].path, "x"], "Try the old way", done, { UNDECLARED_MARK: mark });
    }
}
