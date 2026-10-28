pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.components
import qs.singletons

// Client for the pttd dictation daemon — see quickshell-integration.md.
// The shell only observes state and sends commands; audio capture and keyboard
// emulation stay entirely on the daemon side.
Singleton {
    id: root

    readonly property bool connected: _socket.connected

    // Daemon state. Every `state` event overwrites all of these at once.
    property string server: "off"      // "off" | "loading" | "ready" | "error"
    property string dictation: "idle"  // "idle" | "listening" | "speaking"
    property int pending: 0

    // Wake mode and dictation are two independent switches, not one tri-state mode:
    // while wake is on, stopping dictation only returns the daemon to phrase
    // listening — the microphone stays open until wake_off or server_stop.
    property bool wake: false

    // Wake configuration lives in the daemon's own config file and is edited by the
    // CLI and other clients too, so the latest `wake_config` event is the only
    // source of truth — never a local copy, and never mirrored into Config.
    property var startPhrases: []
    property var stopPhrases: []
    property bool wakeOnStart: false

    property string partialText: ""
    property string lastFinalText: ""
    property string lastCommand: ""

    // One line for the bar: the live partial while speaking, then the text that was
    // actually typed, for a short while after the fragment ends.
    readonly property string previewText: {
        if (partialText !== "")
            return partialText;
        return _finalVisible ? lastFinalText : "";
    }

    readonly property string socketPath: {
        if (Config.stt.socketPath !== "")
            return Config.stt.socketPath;
        const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") ?? "";
        return runtimeDir !== "" ? runtimeDir + "/ptt/ctl.sock" : "";
    }

    property bool _finalVisible: false

    Logger {
        id: logger
        prefix: "[STT]"
        enabled: Config.stt.debug
    }

    // ── Commands ──────────────────────────────────────────────────────────────
    // Only toggle() has a UI caller today; the rest are the transport layer for
    // the wake/server menu.

    function toggle()        { _send("toggle"); }
    function start()         { _send("start"); }
    function stop()          { _send("stop"); }
    function wakeOn()        { _send("wake_on"); }
    function wakeOff()       { _send("wake_off"); }
    function wakeToggle()    { _send("wake_toggle"); }
    function serverStart()   { _send("server_start"); }
    function serverStop()    { _send("server_stop"); }
    function serverRestart() { _send("server_restart"); }
    function requestStatus() { _send("status"); }

    function _send(command) {
        if (!_socket.connected) {
            logger.warn("not connected, dropping command:", command);
            return;
        }
        _socket.write(JSON.stringify({ cmd: command }) + "\n");
        _socket.flush();
        logger.log("→", command);
    }

    // ── Incoming messages ─────────────────────────────────────────────────────

    function _handleLine(line) {
        if (line.trim() === "")
            return;

        let message;
        try {
            message = JSON.parse(line);
        } catch (parseError) {
            logger.warn("unparseable line:", line);
            return;
        }

        // Command replies carry no `event` field; events always have one. That is
        // the only way to tell them apart on the shared connection.
        if (message.event === undefined) {
            if (message.ok === false)
                logger.warn("← rejected:", message.error);
            else
                logger.log("← ok");
            return;
        }

        _handleEvent(message);
    }

    function _handleEvent(message) {
        switch (message.event) {
        case "state":
            server = message.server ?? "off";
            dictation = message.dictation ?? "idle";
            pending = message.pending ?? 0;
            // Absent on daemons predating wake mode — treat as off.
            wake = message.wake ?? false;
            logger.log("← state:", server, dictation, "pending", pending, "wake", wake);
            break;

        case "wake_config":
            startPhrases = message.start_phrases ?? [];
            stopPhrases = message.stop_phrases ?? [];
            wakeOnStart = message.wake_on_start ?? false;
            logger.log("← wake_config: start", JSON.stringify(startPhrases),
                       "stop", JSON.stringify(stopPhrases), "onStart", wakeOnStart);
            break;

        case "partial":
            partialText = message.text ?? "";
            // An empty partial means the fragment ended — hand the line over to the
            // text that was actually typed.
            if (partialText === "" && lastFinalText !== "")
                _showFinalBriefly();
            break;

        case "final":
            if ((message.text ?? "") !== "") {
                lastFinalText = message.text;
                _showFinalBriefly();
            }
            break;

        case "command":
            lastCommand = message.name ?? "";
            logger.log("← command:", lastCommand);
            break;

        case "error":
            logger.error("daemon error:", message.message);
            Notifier.send(message.message ?? "Dictation error", {
                appName: "Dictation",
                urgency: "critical",
                category: "x-qs-shell"
            });
            break;

        default:
            // Unknown event types are ignored on purpose — the protocol is additive.
            logger.log("← unknown event, ignored:", message.event);
        }
    }

    function _showFinalBriefly() {
        _finalVisible = true;
        _lingerTimer.restart();
    }

    function _clearState() {
        server = "off";
        dictation = "idle";
        pending = 0;
        wake = false;
        startPhrases = [];
        stopPhrases = [];
        wakeOnStart = false;
        partialText = "";
        lastFinalText = "";
        lastCommand = "";
        _finalVisible = false;
        _lingerTimer.stop();
    }

    Timer {
        id: _lingerTimer
        interval: Config.stt.finalLingerMs
        onTriggered: root._finalVisible = false
    }

    // ── Connection ────────────────────────────────────────────────────────────

    Socket {
        id: _socket

        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => root._handleLine(line)
        }
    }

    // Driven by this singleton's own `connected` property rather than the socket's
    // state-change signal, so the handler does not depend on how that signal is
    // named in the installed Quickshell version.
    onConnectedChanged: {
        if (connected) {
            logger.log("connected to", socketPath);
            // Replies with the current `state` and `wake_config`, so no separate
            // status request is needed.
            _send("subscribe");
        } else {
            logger.log("disconnected");
            _clearState();
        }
    }

    // The daemon may be down or restarting, so keep retrying quietly. The attempt is
    // made unconditionally rather than behind an "already connecting" latch: a failed
    // connect does not necessarily emit a state change, and a latch that never got
    // cleared would wedge the retry loop for good.
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: !_socket.connected && root.socketPath !== ""
        onTriggered: {
            // Assigned here rather than bound, so the path never changes underneath a
            // live connection — this timer only runs while disconnected.
            if (_socket.path !== root.socketPath)
                _socket.path = root.socketPath;
            _socket.connected = true;
        }
    }

    // Drop the current connection so the retry timer picks the new path up.
    onSocketPathChanged: {
        if (_socket.connected) {
            logger.log("socket path changed, reconnecting to", socketPath);
            _socket.connected = false;
        }
    }
}
