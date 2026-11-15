pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.components

// Who may unlock the screen. Lockscreen starts this when the session locks and unlocks
// on `authenticated()`; the lock prompt shows its state and hands it what is typed.
//
// Every way of proving who is there is a PAM conversation of its own, all running side
// by side (scripts/lock-auth-methods.sh says which, and with which PAM config):
//
//   password     started when something is typed and sent. A full conversation: when
//                PAM asks again (a one-time code after the password), the prompt shows
//                the question and the next thing typed answers it.
//   fingerprint  runs for as long as the screen is locked, so a finger on the reader
//                unlocks with nothing typed, and a typed password never waits for it.
//   u2f          a security key, likewise: touch it to unlock.
//
// One conversation for everything (the "login" config, as it was) cannot do this: PAM
// goes through its modules in order, so with a fingerprint reader the password was only
// looked at once the reader had given up, half a minute later.
Singleton {
    id: root

    signal authenticated
    // The typed answer was wrong: the prompt empties its field
    signal rejected

    // Between begin() and end(): nothing unlocks outside it, whatever a conversation
    // that was still running reports
    property bool _active: false

    // ---- Password ----
    readonly property bool verifying: (_password.active || _hasPending) && !awaitingInput
    // PAM asked for something more after what was sent: `question` says what, and
    // `answerVisible` whether it may be shown as typed
    property bool awaitingInput: false
    property string question: ""
    property bool answerVisible: false
    property string error: ""

    property string _passwordDirectory: ""
    property string _passwordConfig: ""
    property string _pending: ""
    property bool _hasPending: false
    // The last thing PAM said was wrong, shown instead of a plain "failed": it knows why
    // (an account locked after too many attempts, an expired password)
    property string _pamError: ""

    readonly property var fingerprint: _fingerprint
    readonly property var securityKey: _securityKey

    Logger {
        id: _log
        prefix: "[LockAuth]"
    }

    function begin() {
        _active = true;
        error = "";
        _fingerprint.reset();
        _securityKey.reset();
        _detect();
    }

    // Asks which methods there are; _applyMethods starts them. Again after a sleep and
    // when somebody comes back to a prompt without a reader: what the reader's service
    // said while the machine was going to sleep, or just waking, is not to be trusted.
    property bool _detectAgain: false

    function _detect() {
        if (_methods.running) {
            // Its answer may predate what made this call necessary
            _detectAgain = true;
            return;
        }
        _methodLines = [];
        _methods.running = true;
    }

    function end() {
        _active = false;
        cancelPassword();
        error = "";
        _fingerprint.reset();
        _securityKey.reset();
    }

    // What was typed: the password, or the answer to `question`
    function submit(text) {
        if (!_active)
            return;
        if (_password.active) {
            if (awaitingInput) {
                awaitingInput = false;
                _password.respond(text);
            }
            return;
        }
        error = "";
        _pamError = "";
        _pending = text;
        _hasPending = true;
        // Sent before the methods are known (the first moments of a lock): started by
        // _applyMethods then
        if (_passwordConfig !== "")
            _password.start();
    }

    // The prompt went away with a conversation half done
    function cancelPassword() {
        if (_password.active)
            _password.abort();
        awaitingInput = false;
        question = "";
        _pending = "";
        _hasPending = false;
    }

    // Somebody is at the machine: methods that fail at once when their device is absent
    // (a security key not plugged in yet) try again now rather than after their delay
    function nudge() {
        if (!_active || _paused)
            return;
        _securityKey.retryNow();
        if (!_fingerprint.available)
            _detect();
        else
            _fingerprint.revive();
    }

    // The fingerprint reader goes away over a suspend, taking the conversation with it:
    // one left running, or started while the machine is on its way down (the screen
    // locks at that very moment), is dead when it wakes. So nothing runs from pause() to
    // resume(), which starts afresh.
    property bool _paused: false

    function pause() {
        _paused = true;
        _fingerprint.stop();
        _securityKey.stop();
    }

    function resume() {
        _paused = false;
        if (!_active)
            return;
        _fingerprint.stop();
        _securityKey.stop();
        _detect();
        _afterWake.restart();
    }

    // The reader's service may not answer in the first moments after waking: asked once
    // more a little later, if that left the lock without a reader
    Timer {
        id: _afterWake
        interval: 4000
        onTriggered: {
            if (root._active && !root._paused && !_fingerprint.available)
                root._detect();
        }
    }

    function _succeed() {
        if (!_active)
            return;
        _active = false;
        root.authenticated();
    }

    // ---- Which methods, with which PAM configs ----
    property var _methodLines: []

    function _applyMethods(lines) {
        const found = {};
        for (const line of lines) {
            const [name, directory, config] = line.split("\t");
            if (name && directory && config)
                found[name] = { directory: directory, config: config };
        }
        // Without the script's answer the password still works, from the shipped config
        const password = found.password ?? { directory: Quickshell.shellDir + "/pam", config: "password" };
        // A conversation under way keeps the config it started with
        if (!_password.active) {
            _passwordDirectory = password.directory;
            _passwordConfig = password.config;
        }
        if (!_fingerprint.waiting)
            _fingerprint.configure(found.fingerprint);
        if (!_securityKey.waiting)
            _securityKey.configure(found.u2f);
        if (!_active)
            return;
        if (!_paused) {
            _fingerprint.start();
            _securityKey.start();
        }
        // Typed and sent before the methods were known
        if (_hasPending && !_password.active)
            _password.start();
    }

    Process {
        id: _methods
        command: [Quickshell.shellDir + "/scripts/lock-auth-methods.sh"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim() !== "")
                    root._methodLines.push(line);
            }
        }
        onRunningChanged: {
            if (running)
                return;
            root._applyMethods(root._methodLines);
            if (root._detectAgain) {
                root._detectAgain = false;
                root._detect();
            }
        }
    }

    PamContext {
        id: _password
        configDirectory: root._passwordDirectory
        config: root._passwordConfig

        onPamMessage: {
            if (responseRequired) {
                if (root._hasPending) {
                    const answer = root._pending;
                    root._pending = "";
                    root._hasPending = false;
                    respond(answer);
                } else {
                    root.question = message.trim().replace(/:$/, "");
                    root.answerVisible = responseVisible;
                    root.awaitingInput = true;
                }
            } else if (messageIsError && message.trim() !== "") {
                root._pamError = message.trim();
            }
        }

        onCompleted: result => {
            root.awaitingInput = false;
            root.question = "";
            root._pending = "";
            root._hasPending = false;
            if (result === PamResult.Success) {
                root._succeed();
                return;
            }
            if (result === PamResult.Error) {
                _log.error("the password check could not run, PAM config",
                    root._passwordDirectory + "/" + root._passwordConfig);
                root.error = "Password check is not available";
            } else if (root._pamError !== "") {
                root.error = root._pamError;
            } else {
                root.error = result === PamResult.MaxTries ? "Too many attempts" : "Authentication failed";
            }
            // Which config said no is what tells a wrong password from a broken setup
            _log.error("password not accepted (" + PamResult.toString(result) + "), PAM config",
                root._passwordDirectory + "/" + root._passwordConfig);
            root.rejected();
        }
    }

    // A method that needs nothing typed: it runs until it succeeds, and starts again
    // when a round ends without success (a finger not recognised, the reader's time-out).
    component PassiveMethod: Scope {
        id: method

        // For the log
        property string name: ""
        // What to show while it waits, when PAM itself has said nothing
        property string hint: ""
        // Tries again on nudge(): for a device that may only just have been plugged in
        property bool eager: false
        // Whether the screen is locked: outside that nothing runs, and nothing unlocks
        property bool enabled: false
        signal succeeded

        // An inline component cannot see the ids of the file around it: it has its own
        // log, and reports through `succeeded`
        property Logger _methodLog: Logger { prefix: "[LockAuth]" }

        property string configDirectory: ""
        property string config: ""
        readonly property bool available: config !== "" && !_broken
        readonly property bool waiting: _context.active
        // PAM's last word: what to do ("Place your finger…") or what went wrong
        property string message: ""
        property bool messageIsError: false

        // PAM could not run the config at all (a module that is not installed): asking
        // again would fail the same way, so it is left alone until the next lock
        property bool _broken: false
        // The pause before another round. Rounds that end quickly are failed attempts
        // (or an absent device), and each makes the next wait longer; a round that ran
        // its time out was nobody trying, and resets it.
        readonly property int _minRetryDelay: 500
        readonly property int _maxRetryDelay: 10000
        readonly property int _quickRound: 20000
        property int _retryDelay: _minRetryDelay
        property double _roundStartedAt: 0

        function configure(found) {
            configDirectory = found?.directory ?? "";
            config = found?.config ?? "";
        }

        function start() {
            if (!enabled || !available || _context.active)
                return;
            _retry.stop();
            _roundStartedAt = Date.now();
            _context.start();
        }

        function stop() {
            _retry.stop();
            if (_context.active)
                _context.abort();
        }

        function retryNow() {
            if (eager && _retry.running)
                start();
        }

        // Neither waiting nor about to: it should be, so it is started. For whatever
        // left it stopped without the lock ending.
        function revive() {
            if (!_retry.running)
                start();
        }

        function reset() {
            stop();
            config = "";
            configDirectory = "";
            message = "";
            messageIsError = false;
            _broken = false;
            _retryDelay = _minRetryDelay;
        }

        PamContext {
            id: _context
            configDirectory: method.configDirectory
            config: method.config

            onPamMessage: {
                if (message.trim() !== "") {
                    method.message = message.trim();
                    method.messageIsError = messageIsError;
                }
                // Nothing is typed for these: "press Enter when ready" gets its Enter
                if (responseRequired)
                    respond("");
            }

            onCompleted: result => {
                if (!method.enabled)
                    return;
                if (result === PamResult.Success) {
                    method.succeeded();
                    return;
                }
                if (result === PamResult.Error) {
                    _methodLog.error(method.name, "cannot be used, PAM config",
                        method.configDirectory + "/" + method.config);
                    method._broken = true;
                    return;
                }
                const quick = Date.now() - method._roundStartedAt < method._quickRound;
                method._retryDelay = quick
                    ? Math.min(method._retryDelay * 2, method._maxRetryDelay)
                    : method._minRetryDelay;
                _retry.interval = method._retryDelay;
                _retry.start();
            }
        }

        Timer {
            id: _retry
            onTriggered: method.start()
        }
    }

    PassiveMethod {
        id: _fingerprint
        name: "fingerprint"
        hint: "Touch the fingerprint reader"
        enabled: root._active
        onSucceeded: root._succeed()
    }

    PassiveMethod {
        id: _securityKey
        name: "security key"
        hint: "Touch your security key"
        enabled: root._active
        onSucceeded: root._succeed()
        eager: true
    }
}
