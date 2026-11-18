pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.api

// What a module's suites get of the shell in module test mode (module API 1.10, 1.11; tests only:
// `import qs.tests`, which a module may import in its tests alone). Under tests/run-modules.sh
// the shell's own module host runs in test mode; this is that host, seen from a suite.
//
//   testMode               the host is in test mode (true under tests/run-modules.sh)
//   setEnabled(id, on)     turns a module off or on as Settings → Modules does (the runner's
//                          config is never written) → true when `id` is a module id; false,
//                          and nothing done, outside test mode
//   status(id)             a module's status, as `modules list` has it, or null
//   widgetEntries          the loaded modules' bar widgets, merged, as the bar reads them
//   opened                 what Api.openUrl was asked, oldest first: [{ url, allowFile }]
//   notified               the notifications asked for (Api.notify, module.notify, the
//                          shell's own), oldest first: [{ summary, body, appName, urgency,
//                          actions (the labels), command (notify-send's words) }]
//   clearRecords()         empties `opened` and `notified`
//   (1.11, running as administrator: singletons/PrivilegedRuns.qml — the shell's polkit
//   agent and lock are never looked at in test mode, these are what the runs see)
//   setPolkitAgent(state)  the agent's state, PolkitRules.state's words: "active" (the
//                          shell's own prompt answers: the default), "conflict", "other",
//                          "blocked", "deciding", "none"
//   setPolkitRequest(open, request)
//                          the shell's prompt has a password request open, or not. Without
//                          `request`: the request of the run at the head of the queue, with
//                          the message pkexec sends for it (PolkitRules.pkexecMessage), so it
//                          holds and releases the head and is announced; with `request`
//                          ({ actionId, message }): that one, as another program's would be
//   polkitRequestOpen      a request is open (the agent closes it when the session locks)
//   polkitAnnouncement     what the prompt would show for the open request besides polkit's
//                          words (PrivilegedRuns.announcementFor): { module, authorization,
//                          command } or null
//   setSessionLocked(on)   the session is locked, or not
//   privilegedIdle         no run as administrator waits or runs, of any module
// All of them do nothing outside test mode.
//
// Not here yet, because their features are not in the API yet: anchors, the file chooser's
// answer, Api.system and module.dataDirectory, and the shell's clock.
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
        if (request !== undefined && request !== null) {
            PrivilegedRuns.testAgent.flow = { actionId: String(request.actionId ?? ""), message: String(request.message ?? "") };
            return;
        }
        const words = PrivilegedRuns._headPkexecArgv();
        PrivilegedRuns.testAgent.flow = {
            actionId: PolkitRules.pkexecAction,
            message: words.length > 0 ? PolkitRules.pkexecMessage(words) : "Authentication is required"
        };
    }

    readonly property bool polkitRequestOpen: PrivilegedRuns.testAgent.flow !== null
    readonly property var polkitAnnouncement: PrivilegedRuns.announcementFor(PrivilegedRuns.testAgent.flow)

    function setSessionLocked(on) {
        if (Modules.host.testMode)
            PrivilegedRuns.testLocked = on === true;
    }

    function clearRecords() {
        Api._opened = [];
        Notifier.clearRecorded();
    }
}
