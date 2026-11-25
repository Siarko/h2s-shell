pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.api
import qs.components as Components

// What a module's suites get of the shell in module test mode (module API 1.10–1.17; tests only:
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
//                          (notify-send's words) }] — summary and body as they would be sent.
//                          (1.33) A progress notification (notify with `progress`) records
//                          each show, update and close instead: { kind "show" | "update" |
//                          "close", handle (its number, the same in all its records),
//                          appName, summary, body, progress, state, toast, expireTime (0: its toast
//                          stays, -1: the user's time), announce (how many so far), actions
//                          (the labels), format }; its handle acts as if the server answered
//                          at once
//   dismissNotification(handle)
//                          (1.33) the user closed the progress notification whose records
//                          carry `handle` (the number): its onDismissed runs, its handle is
//                          closed (no "close" record: the user closed it) → "" when done,
//                          else why not (no such open notification, outside test mode)
//   pressNotificationAction(handle, actionId)
//                          (1.33) the user pressed one of its actions: its onTriggered runs,
//                          the notification stays (a progress notification is resident) →
//                          "" when done, else why not (no such open notification, no such
//                          action)
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
//                          row is left out, and so are localNetworks rows with
//                          localNetworksReady false (the shell lists none then). Nothing of the real NetworkManager is read in test
//                          mode. Reset before each suite
//   setRemembered(untilMs) (1.39) what module.privileged.remembered tells: kept until
//                          untilMs (ms since the epoch, from now on); 0, a time past or not a
//                          number: nothing kept. It does not run out by itself: it stays until
//                          the next call. Reset before each suite
//   setDistribution(id)    (1.40) what Api.system.distribution tells, as H2S_DISTRIBUTION
//                          tells the shell: "nixos", "arch" or "generic" — that
//                          distribution's facts, from the tree's distributions/<id>/
//                          distribution.json (nothing of this machine's system); "": answered,
//                          unknown (a system that cannot be told); null: not answered (the
//                          default). Ready once the shell has read those files. → the
//                          problems, frozen ([] when taken; another value is left out and
//                          the distribution stays as it was). Reset before each suite
//   dataHome               (1.13) the data home the modules' data directories are in now:
//                          below the host's private temporary home ("" until it is made)
//   clearRecords()         empties `opened`, `notified` and `chooserCalls`, and sets the
//                          real clock, the default system and network facts, no
//                          distribution answered and nothing remembered again. The records are shared by every module's
//                          suites (they run side by side): it clears theirs too
//   (1.17, the file chooser: module.chooseFiles opens no dialog in test mode — each call
//   that would open one is recorded and waits for the suite's answer; the lock is the one
//   setSessionLocked or setChooserLocked sets. A chooser a suite left open and the chooser's
//   lock are reset before each suite)
//   chooserCalls           the calls that opened, oldest first: [{ moduleId, mode, title,
//                          startDirectory }] as the shell took them (the title cleaned, the
//                          directory absolute: the system's home, Api.system.home, when none
//                          was given)
//   chooserOpen            a chooser is open, waiting for an answer
//   answerChooser(moduleId, paths)
//                          the user chose these (absolute paths; one for "open" and
//                          "folder") in module `moduleId`'s open chooser → "" when answered,
//                          else why not (no chooser open, another module's open, a wrong
//                          answer: nothing answered); `done` gets { paths, cancelled:
//                          false, blocked: "", error: "" }
//   cancelChooser(moduleId)
//                          the user closed module `moduleId`'s dialog → "" or why not;
//                          `done` gets cancelled: true
//   setChooserLocked(on)   the session is locked, or not, for the file chooser alone: runs
//                          as administrator are left alone (setSessionLocked locks both)
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
//   setSessionLocked(on)   the session is locked, or not (for the runs as administrator,
//                          the file chooser and (1.34) side panels: a lock closes an open
//                          chooser, cancelled, and an open SidePanel, closed("lock"))
//   pageFrame              (1.34) the settings window's frame for a module's page, as a
//                          Component: a suite creates it in a window of its own and its page
//                          in the frame's `body` (laid out at the frame's inner width,
//                          scrolled by the frame), so the page's SidePanels open over it as
//                          in the settings window:
//                            const frame = ModuleTestKit.pageFrame.createObject(window.contentItem,
//                                { width: 600, height: 400 });
//                            const page = pageComponent.createObject(frame.body, { module: module });
//                          Destroying the frame is the page going (closed("page"))
//   privilegedIdle         no run as administrator waits or runs, of any module
// All of them do nothing outside test mode.
//
// Not here yet, because their feature is not in the API yet: anchors.
Singleton {
    readonly property bool testMode: Modules.host.testMode
    readonly property var widgetEntries: Modules.host.widgetEntries
    readonly property var opened: ApiInternals.opened
    readonly property var notified: Notifier.recorded
    readonly property var chooserCalls: FileChooser.testCalls
    readonly property bool chooserOpen: Modules.host.testMode && FileChooser.open

    function answerChooser(moduleId, paths) {
        return Modules.host.testMode ? FileChooser.testAnswer(moduleId, paths) : "module test mode is off";
    }

    function cancelChooser(moduleId) {
        return Modules.host.testMode ? FileChooser.testCancel(moduleId) : "module test mode is off";
    }

    function setChooserLocked(on) {
        if (Modules.host.testMode)
            FileChooser.testLocked = on === true;
    }

    function dismissNotification(handle) {
        if (!Modules.host.testMode)
            return "module test mode is off";
        const live = Notifier.testHandle(handle);
        if (live === null)
            return "no open progress notification " + JSON.stringify(handle ?? null);
        return live.testDismiss() ? "" : "it is closed";
    }

    function pressNotificationAction(handle, actionId) {
        if (!Modules.host.testMode)
            return "module test mode is off";
        const live = Notifier.testHandle(handle);
        if (live === null)
            return "no open progress notification " + JSON.stringify(handle ?? null);
        return live.testPress(actionId) ? "" : "it has no action " + JSON.stringify(String(actionId ?? ""));
    }

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
            ApiInternals.testNow = typeof ms === "number" && Number.isFinite(ms) && ms > 0 ? ms : 0;
    }

    function setRemembered(untilMs) {
        if (!Modules.host.testMode)
            return;
        const kept = typeof untilMs === "number" && Number.isFinite(untilMs) && untilMs > Date.now();
        ApiInternals.testRemembered = Object.freeze({ kept: kept, untilMs: kept ? untilMs : 0 });
    }

    function setSystem(facts) {
        if (!Modules.host.testMode)
            return Object.freeze(["module test mode is off"]);
        const checked = SystemFactsRules.testFacts(facts, {});
        if (facts === null || facts === undefined || typeof facts !== "object" || Array.isArray(facts)) {
            ApiInternals.testSystemGiven = null;
            return Object.freeze(checked.problems);
        }
        // Only the fields taken, so the defaults (the temporary home once made) show through
        const taken = {};
        for (const key of Object.keys(facts)) {
            if (!checked.problems.some(problem => problem.startsWith(key + ":")))
                taken[key] = checked.facts[key];
        }
        ApiInternals.testSystemGiven = taken;
        return Object.freeze(checked.problems);
    }

    function setDistribution(id) {
        if (!Modules.host.testMode)
            return Object.freeze(["module test mode is off"]);
        const checked = ModuleRules.testDistributionName(id);
        if (checked.problems.length === 0)
            ApiInternals.testDistributionName = checked.name;
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
        ApiInternals.testNetworkGiven = copy;
        return Object.freeze(ModuleRules.testNetworkFacts(copy).problems);
    }

    readonly property string dataHome: Modules.host.testMode && Modules.host.testHome !== "" ? Modules.host.testHome + "/.local/share" : ""

    function setSessionLocked(on) {
        if (Modules.host.testMode) {
            PrivilegedRuns.testLocked = on === true;
            FileChooser.testLocked = on === true;
            ApiElements.testLocked = on === true;
        }
    }

    readonly property Component pageFrame: Component {
        Components.ModulePageFrame {}
    }

    // The links, notifications and chooser calls recorded, and the clock setNow set
    function clearRecords() {
        if (Modules.host.testMode) {
            ApiInternals.testNow = 0;
            ApiInternals.testSystemGiven = null;
            ApiInternals.testNetworkGiven = null;
            setRemembered(0);
            ApiInternals.testDistributionName = null;
        }
        ApiInternals.opened = [];
        Notifier.clearRecorded();
        FileChooser.testClear();
    }
}
