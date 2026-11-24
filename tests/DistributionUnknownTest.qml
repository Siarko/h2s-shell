import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io
import qs.singletons.network

// What uses the distribution's answer, while the answer changes and when it cannot be told —
// in a process of its own, since it makes the shell's one Distribution answer otherwise
// (its reader's override):
// - the reader that waits for it (RememberedAdminReader) never sees a moment's
//   "cannot be told" while a new answer comes in (Distribution's ready and id are two
//   bindings on one answer: read apart, one may still hold the old value);
// - with the distribution not known, nothing is looked up on a guessed PATH: the command
//   runner's tools, pkexec, RememberedAdmin's gdbus and readlink, a module's programs;
// - the VPN plugins are looked for in every shipped distribution's directories;
// - the integration is the answer's; with none, no change kind is offered and nothing runs.
TestCase {
    id: suite
    suiteName: "DistributionUnknown"
    asynchronous: true
    ownProcess: true

    property Component _adminReaderComponent: Component {
        RememberedAdminReader {}
    }

    property var _adminReader: null
    property var _seen: ({ admin: [] })
    property var _readyAnswers: []
    property int _question: 0
    property var _inForce: null

    function _note(key, value) {
        const seen = Object.assign({}, _seen);
        seen[key] = seen[key].concat([value === undefined ? "undefined" : JSON.stringify(value)]);
        _seen = seen;
    }

    function _answered(id) {
        return Distribution.detection.ready && Distribution.detection.id === id;
    }

    function runAsync() {
        // (And the command runner's own look-up done, so that nothing of it runs later)
        _then("Distribution answered the first time", () => Distribution.detection.ready && CommandTools.known
              && !CommandTools._lookup.running && !CommandTools._probe.running, () => {
            _adminReader = _adminReaderComponent.createObject(suite, {});
            _adminReader.nixosChanged.connect(() => suite._note("admin", suite._adminReader.nixos));
            // What a consumer acting on readiness reads at that moment
            Distribution.readyChanged.connect(() => {
                if (Distribution.ready)
                    suite._readyAnswers = suite._readyAnswers.concat([Distribution.detection.id]);
            });
            assertEqual(VpnManager.pluginDirectories.join(" "),
                        "/run/current-system/sw/lib/NetworkManager/VPN /usr/lib/NetworkManager/VPN /etc/NetworkManager/VPN",
                        "VPN plugins: every shipped distribution's directories, each one's order kept (/usr/lib before /etc)");
            Distribution._reader.override = Distribution.detection.id === "arch" ? "nixos" : "arch";
        });
        _then("a new answer", () => _answered(Distribution._reader.override), () => {
            const expected = Distribution.detection.id === "nixos" ? "true" : "false";
            assertEqual(_seen.admin.join(","), "undefined," + expected,
                        "RememberedAdminReader: not answered, then the new answer — never a moment's \"cannot be told\" (null) between");
            assertEqual(_readyAnswers.join(","), Distribution.detection.id, "the answer read from detection when ready changes: the new one");
            assertEqual(Distribution.integration?.distribution, Distribution.detection.id, "the integration: the new answer's");
            _seen = { admin: [] };
            Distribution._reader.override = "no-such-distribution";
        });
        _then("the distribution not known", () => Distribution.detection.ready && Distribution.detection.id === "", () => {
            assertEqual(_seen.admin.join(","), "undefined,null", "RememberedAdminReader: not answered, then cannot be told");
            assertEqual(Distribution.integration, null, "no integration");
            const capability = Distribution.capability("sleep.hibernateDelay");
            assertEqual(capability.mode + "|" + capability.known + "|" + capability.reason, "unavailable|false|" + IntegrationRules.unknown,
                        "a change kind: unavailable, not known, with the reason");
            assertEqual(Distribution.plan("sleep.hibernateDelay", 3600).refusal?.code, "unknown", "… no plan");
            assertEqual(Distribution.apply("sleep.hibernateDelay", 3600, { done: () => suite.fail("an apply answered while unknown") }).refusal?.code, "unknown",
                        "… apply refused, nothing run");
            assertEqual(Distribution.undo("sleep.hibernateDelay", { done: () => suite.fail("an undo answered while unknown") }).refusal?.code, "unknown", "… undo too");
            Distribution.readInForce("sleep.hibernateDelay", answer => suite._inForce = answer);
            _question = CommandTools._question;
            CommandTools._lookUp();
            assert(CommandTools._question === _question && !CommandTools._lookup.running,
                   "the command runner's tools: not looked up on a guessed PATH");
            PrivilegedRuns._lookUpPkexec();
            assertEqual(PrivilegedRuns.pkexec, "", "pkexec: none");
            assert(PrivilegedRuns.pkexecReason.includes("distribution is not known") && PrivilegedRuns.known,
                   "… known, with the reason: " + PrivilegedRuns.pkexecReason);
            RememberedAdmin._lookUp();
            assertEqual(RememberedAdmin._gdbus + "|" + RememberedAdmin._readlink, "|", "RememberedAdmin: no gdbus, no readlink");
            Modules.host._checkPrograms(["sh"]);
            assertEqual(VpnManager.pluginDirectories.length, 3, "VPN plugins: still every shipped distribution's directories, whichever this one is");
        });
        _then("the module host answered", () => Modules.host.programVerdicts.sh !== undefined && !Modules.host._checkingPrograms && _inForce !== null, () => {
            assertEqual(_inForce.state, "unknown", "what is in force while unknown: unknown");
            const verdict = Modules.host.programVerdicts.sh;
            assertEqual(verdict.path + "|" + verdict.trusted + "|" + verdict.reason, "|false|the distribution is not known",
                        "a module's program: not looked up, the reason said");
            Distribution._reader.override = "";
        });
        _then("back to the machine's answer", () => Distribution.detection.ready && Distribution.detection.id !== "", () => {
            PrivilegedRuns._lookUpPkexec();
        });
        _then("pkexec looked for again", () => !PrivilegedRuns.pkexecReason.includes("distribution is not known"), () => {
            assert(true, "pkexec looked for again with the machine's answer: " + (PrivilegedRuns.pkexec || PrivilegedRuns.pkexecReason));
        });
        _clock.start();
    }

    function _end() {
        _adminReader?.destroy();
        suite.finish();
    }

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 15000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }
}
