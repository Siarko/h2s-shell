pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.api

// What a module's suites get of the shell in module test mode (module API 1.10–1.16; tests only:
// `import qs.tests`, which a module may import in its tests alone). Under tests/run-modules.sh
// the shell's own module host runs in test mode; this is that host, seen from a suite.
//
//   testMode               the host is in test mode (true under tests/run-modules.sh)
//   setEnabled(id, on)     turns a module off or on as `modules setEnabled` over IPC does (the runner's
//                          config is never written) → true when `id` is a module id; false,
//                          and nothing done, outside test mode
//   status(id)             a module's status, as `modules list` has it, or null
//   widgetEntries          the loaded modules' bar widgets, merged, as the bar reads them
//   opened                 what Api.openUrl was asked, oldest first: [{ url, allowFile }]
//   notified               the notifications asked for (Api.notify, module.notify, the
//                          shell's own), oldest first: [{ summary, body, appName, urgency,
//                          actions (the labels), format ("plain" or ""; 1.12), command
//                          (notify-send's words) }] — summary and body as they would be sent
//   setNow(ms)             (1.12) the shell's clock for Api.minuteNow (the start of that
//                          minute); 0: the real clock again. Reset before each suite
//   setSystem(facts)       (1.13) what Api.system tells: the fields given ({ ready, userName,
//                          uid, hostName, home, configHome, dataHome, runtimeDirectory,
//                          downloadDirectory, ipForwarding: { ipv4, ipv6 } } — what
//                          readIpForwarding() returns) over made-up defaults (ready, "tester",
//                          1000, "test-host", the directories below the host's private
//                          temporary home, forwarding off) — each call from the defaults, not
//                          from the call before; null: the defaults. → the
//                          problems, frozen ([] when every field was taken): a field of the
//                          wrong kind or one Api.system does not have is left out. Never
//                          moves module.dataDirectory, which stays in the host's temporary
//                          home. Reset before each suite
//   setNetworks(facts)     (1.16) what Api's network facts tell: { networksReady,
//                          networks: [{ id, name, kind, active }], localNetworksReady,
//                          localNetworks: [{ device, kind, address: "<address>/<prefix>" }]
//                          (family and network derived, as the shell does), vpnsUp: [{ name,
//                          type, provider, fullTunnel, setsDns, routes }] } over the defaults
//                          (both read, no network, no VPN) — each call from the defaults; null:
//                          the defaults. Rows go through the shell's own checks. → the
//                          problems, frozen ([] when everything was taken): a wrong field or
//                          row is left out. Nothing of the real NetworkManager is read in test
//                          mode. Reset before each suite
//   dataHome               (1.13) the data home the modules' data directories are in now:
//                          below the host's private temporary home ("" until it is made)
//   clearRecords()         empties `opened` and `notified`, and sets the real clock and the
//                          default system and network facts again
//   (1.11, running as administrator: singletons/PrivilegedRuns.qml — the shell's polkit
//   agent and lock are never looked at in test mode, these are what the runs see)
//   setPolkitAgent(state)  the agent's state, PolkitRules.state's words: "active" (the
//                          shell's own prompt answers: the default), "conflict", "other",
//                          "blocked", "deciding", "none"
//   setPolkitRequest(open, request)
//                          the shell's prompt has a password request open, or not; each call
//                          opens a new one. `request`: { command: [words handed to pkexec] }
//                          — pkexec's request for that command, its English message built
//                          here as pkexec builds it (pkexecMessage) — or { actionId,
//                          message } as given; without it a pkexec request that names no
//                          command (as another program's would be)
//   pkexecMessage(words)   pkexec's message for these words (polkit 0.120 and later)
//   polkitRequestOpen      a request is open (the agent closes it when the session locks)
//   polkitAnnouncement     what the prompt would show for the open request besides polkit's
//                          words (PrivilegedRuns.announcementFor: PolkitRules.announcement's
//                          { module, moduleName, moduleId, authorization, command,
//                          commandShown, … }) or null
//   setSessionLocked(on)   the session is locked, or not
//   privilegedIdle         no run as administrator waits or runs, of any module
// All of them do nothing outside test mode.
//
// Not here yet, because their features are not in the API yet: anchors and the file
// chooser's answer.
Singleton {
    readonly property bool testMode: Modules.host.testMode
    readonly property var widgetEntries: Modules.host.widgetEntries
    readonly property var opened: Api._opened
    readonly property var notified: Notifier.recorded

    function setEnabled(id, on) {
        return Modules.host.testMode ? Modules.host.setEnabled(String(id ?? ""), on === true) : false;
    }

    function status(id) {
        return Modules.host.status(String(id ?? ""));
    }

    readonly property bool privilegedIdle: PrivilegedRuns.idle

    function setPolkitAgent(state) {
        if (Modules.host.testMode)
            PrivilegedRuns.testAgent.state = String(state ?? "");
    }

    function setPolkitRequest(open, request) {
        if (!Modules.host.testMode)
            return;
        if (open !== true) {
            PrivilegedRuns.testAgent.flow = null;
            return;
        }
        const pkexecAction = "org.freedesktop.policykit.exec";
        if (Array.isArray(request?.command))
            PrivilegedRuns.testAgent.flow = { actionId: pkexecAction, message: pkexecMessage(request.command) };
        else if (request !== undefined && request !== null)
            PrivilegedRuns.testAgent.flow = { actionId: String(request.actionId ?? ""), message: String(request.message ?? "") };
        else
            PrivilegedRuns.testAgent.flow = { actionId: pkexecAction, message: "Authentication is required to run a program as the super user" };
    }

    // pkexec's message, written here from polkit's src/programs/pkexec.c and not from the
    // shell's PolkitRules, so a suite checks the shell's matching against pkexec rather than
    // against itself: command_line = g_strjoinv (" ", argv); past 80 bytes cmdline_short =
    // g_strdup_printf ("%.38s ... %s", command_line, command_line + len - 37). Bytes are
    // UTF-8 (encodeURIComponent's); a character the cut splits is dropped.
    function pkexecMessage(words) {
        const commandLine = Array.from(words ?? []).map(word => String(word)).join(" ");
        const bytes = unescape(encodeURIComponent(commandLine));
        let short = commandLine;
        if (bytes.length > 80)
            short = _decodeCut(bytes.substring(0, 38)) + " ... " + _decodeCut(bytes.substring(bytes.length - 37));
        return "Authentication is needed to run `" + short + "' as the super user";
    }

    // A byte string as text, a character split at either end dropped
    function _decodeCut(bytes) {
        let text = bytes;
        while (text.length > 0 && (text.charCodeAt(0) & 0xc0) === 0x80)
            text = text.substring(1);
        for (let drop = 0; drop <= 3; drop++) {
            try {
                return decodeURIComponent(escape(text.substring(0, text.length - drop)));
            } catch (error) {}
        }
        return "";
    }

    readonly property bool polkitRequestOpen: PrivilegedRuns.testAgent.flow !== null
    readonly property var polkitAnnouncement: PrivilegedRuns.announcementFor(PrivilegedRuns.testAgent.flow)

    function setNow(ms) {
        if (Modules.host.testMode)
            Api._testNow = typeof ms === "number" && Number.isFinite(ms) && ms > 0 ? ms : 0;
    }

    function setSystem(facts) {
        if (!Modules.host.testMode)
            return Object.freeze(["module test mode is off"]);
        const checked = SystemFactsRules.testFacts(facts, {});
        if (facts === null || facts === undefined || typeof facts !== "object" || Array.isArray(facts)) {
            Api._testSystemGiven = null;
            return Object.freeze(checked.problems);
        }
        // Only the fields taken, so the defaults (the temporary home once made) show through
        const taken = {};
        for (const key of Object.keys(facts)) {
            if (!checked.problems.some(problem => problem.startsWith(key + ":")))
                taken[key] = checked.facts[key];
        }
        Api._testSystemGiven = taken;
        return Object.freeze(checked.problems);
    }

    function setNetworks(facts) {
        if (!Modules.host.testMode)
            return Object.freeze(["module test mode is off"]);
        // A copy, so a suite changing its object afterwards changes nothing
        let copy = null;
        try {
            copy = facts === null || facts === undefined ? null : JSON.parse(JSON.stringify(facts));
        } catch (error) {
            return Object.freeze(["the network facts are not plain data: " + error]);
        }
        Api._testNetworkGiven = copy;
        return Object.freeze(ModuleRules.testNetworkFacts(copy).problems);
    }

    readonly property string dataHome: Modules.host.testMode && Modules.host.testHome !== "" ? Modules.host.testHome + "/.local/share" : ""

    function setSessionLocked(on) {
        if (Modules.host.testMode)
            PrivilegedRuns.testLocked = on === true;
    }

    // The links and notifications recorded, and the clock setNow set
    function clearRecords() {
        if (Modules.host.testMode) {
            Api._testNow = 0;
            Api._testSystemGiven = null;
            Api._testNetworkGiven = null;
        }
        Api._opened = [];
        Notifier.clearRecorded();
    }
}
