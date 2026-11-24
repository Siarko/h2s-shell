import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.singletons

// The trial before a PAM file is written: the candidate staged in a private directory with
// the files it includes, and one PAM conversation run against it as the user. Decisions
// (what to stage, what each answer means, when it is over) are PamTrialRules.step's; this
// only carries out its effects:
//
// - scripts/pam-files.sh in rounds for the files the candidate includes (as PamStackReader
//   reads stacks), its answers handed back as they come;
// - scripts/pam-trial-stage.sh to make the staging directory under `stagingParent` (the
//   runtime directory) and to remove it when the trial ends — also when this object is
//   destroyed mid-trial;
// - one PamContext with the staging directory as its configDirectory, its messages and
//   result handed back, the user's answer passed to it — never kept.
//
// Every command is a property, so a suite points it at stand-ins (tests/PamTrialTest.qml).
// Every event carries the trial it belongs to; an answer of an earlier trial changes nothing.
// What the view shows is `state` (PamTrialRules.initialState's fields).
Scope {
    id: root

    property var filesCommand: [Quickshell.shellDir + "/scripts/pam-files.sh"]
    property var stageCommand: [Quickshell.shellDir + "/scripts/pam-trial-stage.sh"]
    // Where the staging directory is made: private to the user
    property string stagingParent: Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    // Added to every command's environment (a suite's seams)
    property var environment: ({})
    property int timeoutMs: 6000

    // PamTrialRules' state of the current (or last) trial
    readonly property var state: _state
    // A line for the shell log about the I/O itself (never typed text)
    signal logLine(string level, string message)

    // A new trial of `text` as the service's file; ignored while one runs
    function start(service, text) {
        _dispatch({ type: "start", service: service, text: text, parent: stagingParent, token: _token() });
    }

    // The user's answer to the question PAM asks in trial `trial`; `text` is used, not kept
    function respond(trial, text) {
        _dispatch({ type: "respond", trial: trial, text: text });
    }

    function cancel(trial) {
        _dispatch({ type: "cancel", trial: trial });
    }

    property var _state: PamTrialRules.initialState()

    // The staging directory's eight letters or digits: a new name for each trial (one that
    // is already there makes the staging fail, never reused)
    function _token() {
        const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        let token = "";
        for (let i = 0; i < 8; i++)
            token += letters[Math.floor(Math.random() * letters.length)];
        return token;
    }
    // Set when a completion was reported from inside PamContext.start(): its fork failed
    property bool _completedInStart: false
    // The trial whose conversation runs, or 0
    property int _conversation: 0

    function _dispatch(event) {
        const out = PamTrialRules.step(_state, event);
        const before = _state.phase;
        _state = out.state;
        if (out.state.phase !== before && (out.state.phase === "failed" || out.state.phase === "passed"))
            logLine(out.state.phase === "passed" ? "info" : "warning", "PAM trial of " + out.state.service + ": " + out.state.phase
                    + (out.state.reason !== "" ? " (" + out.state.reason + ")" : ""));
        for (const effect of out.effects)
            _carry(effect);
    }

    function _carry(effect) {
        switch (effect.type) {
        case "readFiles": {
            const paths = effect.paths;
            _run(Array.from(filesCommand).concat(paths), (lines, result) =>
                _dispatch({ type: "filesRead", trial: effect.trial, lines: lines, result: result, paths: paths }));
            break;
        }
        case "stage": {
            const argv = Array.from(stageCommand).concat(["stage", effect.parent, effect.directory]);
            for (const file of effect.files)
                argv.push(file.name, file.text);
            _run(argv, (lines, result) => _dispatch({ type: "staged", trial: effect.trial, lines: lines, result: result }));
            break;
        }
        case "startPam":
            _startPam(effect.trial, effect.configDirectory, effect.config);
            break;
        case "respondPam":
            if (_conversation === effect.trial)
                _context.respond(effect.text);
            break;
        case "abortPam":
            if (_conversation === effect.trial) {
                _conversation = 0;
                _context.abort();
            }
            break;
        case "removeStaging":
            _run(Array.from(stageCommand).concat(["remove", effect.parent, effect.directory]), (lines, result) => {
                if (!result.ok)
                    root.logLine("warning", "PAM trial: the staging directory " + effect.directory + " was not removed");
            });
            break;
        }
    }

    function _run(argv, done) {
        const lines = [];
        _runner.start(Array.from(argv), {
            timeoutMs: timeoutMs,
            killAfterMs: 1000,
            environment: environment,
            maxOutputBytes: 1048576,
            keepOutput: false,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => done(lines, result)
        });
    }

    function _startPam(trial, configDirectory, config) {
        if (_context.active) {
            // A conversation of an earlier trial still runs (an abort not settled): this one
            // is refused rather than started over it
            logLine("error", "PAM trial: asked to start while a conversation still runs: refused");
            _dispatch({ type: "pamStartFailed", trial: trial });
            return;
        }
        // Only while inactive: PamContext drops a config set during a conversation
        _context.configDirectory = configDirectory;
        _context.config = config;
        _conversation = trial;
        _completedInStart = false;
        const started = _context.start();
        if (started || _completedInStart)
            return;
        _conversation = 0;
        logLine("warning", "PAM trial: PamContext.start() refused " + configDirectory + "/" + config);
        _dispatch({ type: "pamStartFailed", trial: trial });
    }

    function _resultName(result) {
        switch (result) {
        case PamResult.Success: return "success";
        case PamResult.Failed: return "failed";
        case PamResult.MaxTries: return "maxTries";
        default: return "error";
        }
    }

    property CommandRunner _runner: CommandRunner {}

    PamContext {
        id: _context

        onPamMessage: {
            if (root._conversation === 0)
                return;
            root._dispatch({
                type: "pamMessage", trial: root._conversation, message: message,
                messageIsError: messageIsError, responseRequired: responseRequired, responseVisible: responseVisible
            });
        }

        onError: error => {
            if (root._conversation !== 0)
                root.logLine("warning", "PAM trial: PAM error: " + PamError.toString(error));
        }

        onCompleted: result => {
            const trial = root._conversation;
            if (trial === 0)
                return;
            root._conversation = 0;
            root._completedInStart = true;
            root._dispatch({ type: "pamCompleted", trial: trial, result: root._resultName(result) });
        }
    }

    // Destroyed mid-trial (the page closed): the runner's runs end with it (a staging run
    // among them, killed), so the staging directory — made or being made — is removed by a
    // command of its own. Not where Qt dropped the trial's properties before this runs (an
    // object waiting for a deferred delete whose JavaScript wrapper the collector took first):
    // `_state` then reads undefined, and nothing here knows the directory any more.
    Component.onDestruction: {
        const state = _state;
        if (state && state.staging !== "")
            Quickshell.execDetached(Array.from(stageCommand).concat(["remove", state.parent, state.staging]));
    }
}
