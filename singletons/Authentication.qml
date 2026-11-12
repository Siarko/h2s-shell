pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import QtQuick

// The shell as the session's polkit authentication agent: the prompt for an
// administrator's password when a program needs one (polkit/AuthPrompt.qml shows `flow`).
// Only one agent can answer per session, so it is a setting (`system.polkitAgent`), decided
// at the first start: another agent running → off; none → the shell tries, and keeps it
// on if it registered (PolkitRules). Notifications say when no agent answers or two
// collide. docs/plans/polkit.md has the reasoning.
//
// Whether an agent answers can be seen only by trying: polkit tells no one which agent
// holds the session, and logs nothing. So with the setting off and no known agent's
// process running, the shell registers for a moment ("probing") — refused, an agent it
// does not know answers; accepted, there is none, and it lets go again at once.
Singleton {
    id: root

    // "", "on", "off" (a global setting: the shell holds it, never per profile)
    readonly property string mode: Profiles.value("system.polkitAgent") ?? ""
    // The known agents running besides the shell (PolkitRules.agentsIn)
    property var otherAgents: []
    // A registration tried for a moment: "decide" at the first start, "probe" to tell an
    // unknown agent from none; "" while not trying
    property string _trying: ""
    // What the last probe found: "", "none", "unknown"
    property string _probed: ""

    readonly property PolkitAgent agent: _agentLoader.item
    readonly property bool registered: agent?.isRegistered ?? false
    // The request being answered, or null (not while only trying)
    readonly property var flow: _trying === "" && agent?.isActive ? agent.flow : null
    readonly property string state: _trying === "decide" ? "deciding"
        : PolkitRules.state(mode, mode === "on" && registered, otherAgents, _probed === "unknown")

    // Kept from a successful first-start try until the setting says "on": destroyed and
    // made again at once, the new agent's registration came before polkit had let the old
    // one go, and was refused
    property bool _keepAgent: false
    // Off for a moment to make the agent again (a refused registration, retried)
    property bool _remaking: false
    property int _retries: 0

    LazyLoader {
        id: _agentLoader
        active: !root._remaking && (root.mode === "on" || root._trying !== "" || root._keepAgent)
        PolkitAgent {}
    }

    // A registration refused while the setting is on: tried again a few times before it
    // counts as another agent's — after a restart, the old shell may not have let go yet
    onAgentChanged: if (agent !== null) _checkRegistered.restart()
    Timer {
        id: _checkRegistered
        interval: 2000
        onTriggered: {
            if (root.mode !== "on" || root.registered || root._trying !== "" || root._retries >= 3)
                return;
            root._retries++;
            root._remaking = true;
            Qt.callLater(() => root._remaking = false);
        }
    }

    function setOn(on: bool): void {
        Profiles.setGlobal("system.polkitAgent", on ? "on" : "off");
    }

    // For the shell's own privileged requests (the System tab): refused, and maybe because
    // no agent answered — say so, with the way out
    function reportDenied(what: string): void {
        if (state === "none") {
            _tellNoAgent(what + " — no authentication prompt answered");
            return;
        }
        Notifier.send(what + " — not allowed", { body: "The password was not given or not accepted." });
    }

    function _tellNoAgent(summary) {
        Notifier.send(summary, {
            // Stays until answered: a toast that slid away would leave the problem unseen
            urgency: "critical",
            body: "No polkit agent is running, so programs asking for an administrator's password are refused. The shell can be the agent.",
            actions: [{ id: "on", label: "Turn the shell's prompt on", onTriggered: () => root.setOn(true) }]
        });
    }

    // ── Trying to register for a moment ──
    function _try(why) {
        _trying = why;
        _tried.restart();
    }

    Timer {
        id: _tried
        interval: 3000
        onTriggered: {
            const accepted = root.registered;
            const why = root._trying;
            // Before `_trying` lets go of the agent: the one that registered stays the one
            // (see `_keepAgent`)
            if (why === "decide")
                root._keepAgent = accepted;
            root._trying = "";
            if (why === "decide") {
                root.setOn(PolkitRules.firstStart([], accepted) === "on");
            }
            else {
                root._probed = accepted ? "none" : "unknown";
                if (root._probed === "none")
                    root._tellAboutAgents([]);
            }
        }
    }

    // ── The agents running, looked at now and then ──
    Process {
        id: _scanProcess
        command: ["ps", "-eo", "args="]
        property var _lines: []
        stdout: SplitParser { onRead: line => _scanProcess._lines.push(line) }
        onExited: {
            const found = PolkitRules.agentsIn(_lines);
            _lines = [];
            const appeared = found.filter(name => !root.otherAgents.includes(name));
            const left = root.otherAgents.some(name => !found.includes(name));
            root.otherAgents = found;
            if (left)
                root._probed = "";
            root._afterScan(appeared);
        }
    }

    function _requestScan() {
        if (!_scanProcess.running && _trying === "")
            _scanProcess.running = true;
    }

    function _afterScan(appeared) {
        // The first start: decided once, after agents the compositor starts had their time
        if (mode === "") {
            if (_firstStartDue) {
                if (PolkitRules.firstStart(otherAgents, null) === "off")
                    setOn(false);
                else
                    _try("decide");
            }
            return;
        }
        // Off with no known agent: an unknown one, or none? Found out once
        if (mode === "off" && otherAgents.length === 0 && _probed === "") {
            _try("probe");
            return;
        }
        _tellAboutAgents(appeared);
    }

    property bool _firstStartDue: false
    Timer {
        // Agents started with the session come up in the first seconds
        interval: 20000
        running: true
        onTriggered: {
            root._firstStartDue = true;
            root._requestScan();
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root._firstStartDue
        onTriggered: root._requestScan()
    }

    // Turned on or off by the user: looked at again
    onModeChanged: {
        _keepAgent = false;
        _retries = 0;
        _probed = "";
        _toldNone = false;
        _toldBlocked = false;
        if (_firstStartDue)
            Qt.callLater(_requestScan);
    }

    // ── Trying the prompt (Settings → System → Authentication) ──
    // pkexec, run by the shell itself: started detached its parent was gone at once, and
    // pkexec refuses to work for a dead parent. Its exit says how it went: 0 allowed,
    // 126 cancelled or refused, 127 no agent (or not allowed at all).
    function tryPrompt(): void {
        if (!_tryProcess.running)
            _tryProcess.running = true;
    }

    readonly property bool tryingPrompt: _tryProcess.running

    Process {
        id: _tryProcess
        command: ["pkexec", "true"]
        onExited: exitCode => {
            if (exitCode === 0)
                Notifier.send("Authenticated", { body: "The prompt works: the password was accepted.", urgency: "low", category: "x-qs-shell" });
            else if (exitCode === 127)
                root.reportDenied("Trying the prompt");
            else
                Notifier.send("Not authenticated", { body: "Cancelled, or the password was not accepted.", urgency: "low" });
        }
    }

    //   h2s-shell ipc call authentication status
    //   h2s-shell ipc call authentication tryPrompt
    IpcHandler {
        target: "authentication"
        function tryPrompt(): void {
            root.tryPrompt();
        }
        function status(): string {
            return JSON.stringify({
                mode: root.mode, state: root.state, registered: root.registered,
                otherAgents: root.otherAgents, probed: root._probed, trying: root._trying,
                requestOpen: root.flow !== null
            }, null, 2);
        }
    }

    // ── Telling ──
    property bool _toldNone: false
    property bool _toldBlocked: false

    function _tellAboutAgents(appeared) {
        const now = state;
        if (now === "none" && !_toldNone) {
            _toldNone = true;
            _tellNoAgent("No authentication prompt");
        } else if (now === "conflict" && appeared.length > 0) {
            Notifier.send(appeared.join(", ") + " cannot answer password requests", {
                urgency: "critical",
                body: "The shell's authentication prompt holds the session, so this agent could not register. Keep one of them.",
                actions: [{ id: "off", label: "Turn the shell's prompt off", onTriggered: () => root.setOn(false) }]
            });
        } else if (now === "blocked" && !_toldBlocked && _retries >= 3) {
            _toldBlocked = true;
            Notifier.send("The shell's authentication prompt could not start", {
                urgency: "critical",
                body: "Another polkit agent holds the session" + (otherAgents.length > 0 ? " (" + otherAgents.join(", ") + ")" : "")
                    + ", so it answers password requests instead.",
                actions: [{ id: "off", label: "Turn the shell's prompt off", onTriggered: () => root.setOn(false) }]
            });
        }
    }
}
