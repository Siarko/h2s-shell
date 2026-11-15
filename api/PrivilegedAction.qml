import QtQuick
import qs.singletons
import qs.singletons.io as Io

// A command run as root through pkexec, the shell's way (module API 1.0) — polkit asks for
// the password through the shell's own prompt or whichever agent runs:
//
//   PrivilegedAction { id: admin }
//   admin.run(["tailscale", "up"], "Connecting Tailscale", result => { … })
//
// run(command, what, done, environment) queues `pkexec <command…>` (one at a time) and calls
// done({ ok, code, dismissed, refused, lines, error }):
//   ok         it ran and exited 0
//   dismissed  pkexec exited 126: the prompt was dismissed or the password not accepted —
//              nothing is shown (the user chose it); put the state back
//   refused    pkexec exited 127: not authorised, or no authentication agent answered — the
//              shell says so once, with the way out (Authentication.reportDenied(what))
//   otherwise  the command itself failed: notified as "<what> failed" with its error, unless
//              notifyFailures is false (a VPN provider emits failed() instead)
// `environment` ({ NAME: value }) goes to pkexec's environment — but pkexec clears the
// environment of what it runs: pass what the command needs as arguments, never a secret.
QtObject {
    id: root

    // What runs the command as root: pkexec (a module's suites put a stand-in here)
    property var elevate: ["pkexec"]
    // "<what> failed" notifications for a command that ran and failed
    property bool notifyFailures: true
    readonly property bool busy: _action.busy

    function run(command, what, done, environment) {
        if (!Array.isArray(command) || command.length === 0 || command.some(part => typeof part !== "string")) {
            done?.({ ok: false, code: -1, dismissed: false, refused: false, lines: [], error: "not a command" });
            return;
        }
        const label = String(what ?? command[0]);
        _action.run(elevate.concat(command), result => {
            const answer = Object.assign({}, result, { dismissed: result.code === 126, refused: result.code === 127 });
            if (answer.refused)
                Authentication.reportDenied(label);
            else if (!answer.ok && !answer.dismissed && root.notifyFailures)
                Notifier.send(label + " failed", { body: result.error || ("Exit code " + result.code) });
            done?.(answer);
        }, environment ?? {});
    }

    property Io.CommandAction _action: Io.CommandAction {}
}
