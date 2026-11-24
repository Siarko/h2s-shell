import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// Create of the shell's file in the NixOS configuration, the one-time setup's first step,
// the way NixosViewRules.createWay says for the reading the user saw: a root-owned
// configuration through the root step's create (`writer`, NixosApply: the password asked at
// this click), any other written as the user by scripts/nixos-create.sh, no password. Only
// ever called from the Create click. One at a time.
QtObject {
    id: root

    // The root step's writer (NixosApply; a suite's stand-in)
    property var writer: null
    property var userCommand: [Quickshell.shellDir + "/scripts/nixos-create.sh"]

    readonly property bool busy: _busy || writer?.busy === true

    property bool _busy: false

    // `reading`: NixosConfigRules.reading's, as the page showed it; `done(outcome)`, once, with
    // { ok, quiet (nothing ran: a prompt dismissed), error (the page's text, "" none) } →
    // { started, refusal (null or { code, text }) }
    function create(reading, done) {
        const answer = outcome => {
            if (typeof done === "function")
                done(outcome);
        };
        if (busy)
            return { started: false, refusal: NixosApplyRules.refusal("running") };
        const way = NixosViewRules.createWay(reading);
        if (way === "root") {
            if (!writer)
                return { started: false, refusal: NixosApplyRules.refusal("start") };
            return writer.apply({ op: "create", reading: reading }, {
                done: outcome => answer(NixosViewRules.rootCreateOutcome(outcome))
            });
        }
        const argv = NixosViewRules.userCreateArgv(userCommand, reading);
        if (argv.length === 0)
            return { started: false, refusal: NixosApplyRules.refusal(reading?.file?.state === "present" ? "exists" : "arguments") };
        _busy = true;
        _runner.start(argv, {
            timeoutMs: 10000,
            killAfterMs: 1000,
            maxOutputBytes: 4096,
            done: result => {
                root._busy = false;
                answer(NixosViewRules.userCreateOutcome(result));
            }
        });
        return { started: true, refusal: null };
    }

    property CommandRunner _runner: CommandRunner {}
}
