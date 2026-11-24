import QtQuick
import Quickshell
import Quickshell.Io
import qs.distributions
import qs.distributions.arch
import qs.distributions.generic
import qs.distributions.nixos
import qs.singletons

// The contract every distribution integration keeps (distributions/Integration.qml,
// IntegrationRules), run over each shipped one — a new distribution passes it first. For every
// change kind the shell defines, and kinds it does not: capability answers a valid mode (an
// applied kind is one EtcFiles writes; unavailable carries a reason); plan answers a preview
// by the mode or a refusal; apply, undo and readInForce answer — apply and undo at once, and
// `done` exactly once when started, never when not; readInForce once, later. The generic
// integration is safe while the system is unknown to the shell: nothing offered, nothing run,
// nothing read. Each shipped distribution has its integration in Distribution, and
// Distribution's answers are its integration's.
//
// Arch's runs go to a stand-in under a scratch base (never pkexec, never /etc): it records
// each run and answers as a dismissed prompt; its reads go through the real
// scripts/pam-files.sh, as the user, in the scratch folder. Asynchronous.
TestCase {
    id: suite
    suiteName: "DistributionContract"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-distribution-contract-test-" + Date.now()
    // Every kind the shell defines, and two it does not
    readonly property var _kinds: IntegrationRules.kinds.concat(["no.such.kind", "toString"])
    // A value each defined kind takes
    readonly property var _values: ({ "sleep.hibernateDelay": 10800, "network.connectivityUri": "http://nmcheck.gnome.org/check_network_status.txt" })
    // Stand-ins for the merged readings: the system's own file sets each kind
    readonly property var _merged: ({
        "sleep.hibernateDelay": ["sh", "-c", "printf '# /etc/systemd/sleep.conf\\n[Sleep]\\nHibernateDelaySec=2h\\n'"],
        "network.connectivityUri": ["sh", "-c", "printf 'file\\t%s\\ttext\\n|[connectivity]\\n|uri=http://mine/\\nend\\t%s\\ndone\\n' \"$0\" \"$0\"",
                                    "/etc/NetworkManager/NetworkManager.conf"]
    })
    // What each shipped integration answers per defined kind (mode, undo, inForce)
    readonly property var _expectedModes: ({
        arch: { "sleep.hibernateDelay": "apply undo inForce", "network.connectivityUri": "apply undo inForce" },
        nixos: { "sleep.hibernateDelay": "copy - inForce", "network.connectivityUri": "copy - inForce" },
        generic: { "sleep.hibernateDelay": "unavailable - -", "network.connectivityUri": "unavailable - -" }
    })

    property var _integrations: []
    // Per integration id: the runs its stand-in was handed
    property var _runs: ({})
    // Per "<id> <function> <kind>": how often done was called
    property var _answers: ({})
    // Per "<id> <function> <kind>": what started (a done must come for each)
    property var _expected: []
    property bool _ready: false

    property Component _arch: Component {
        ArchIntegration {}
    }
    property Component _nixos: Component {
        NixosIntegration {}
    }
    property Component _generic: Component {
        GenericIntegration {}
    }

    function _standIn(id) {
        return (request, done) => {
            const runs = Object.assign({}, suite._runs);
            runs[id] = (runs[id] ?? []).concat([request.what]);
            suite._runs = runs;
            Qt.callLater(() => done({ ok: false, code: 126, stdout: "", stderr: "", dismissed: true, refused: false, cancelled: false, blocked: "", error: "" }));
        };
    }

    function _counter(key) {
        return answer => {
            const answers = Object.assign({}, suite._answers);
            answers[key] = (answers[key] ?? []).concat([answer]);
            suite._answers = answers;
        };
    }

    function _check(integration) {
        const id = integration.distribution;
        for (const kind of _kinds) {
            const label = id + " " + kind + ": ";
            const capability = integration.capability(kind);
            assert(IntegrationRules.valid(capability), label + "a valid capability: " + JSON.stringify(capability));
            assert(capability.known, label + "… known (an integration's answer)");
            const defined = IntegrationRules.kinds.includes(kind);
            if (defined)
                assertEqual([capability.mode, capability.undo ? "undo" : "-", capability.inForce ? "inForce" : "-"].join(" "), _expectedModes[id]?.[kind],
                            label + "the expected mode");
            if (!defined)
                assertEqual(capability.mode, "unavailable", label + "a kind the shell does not define: unavailable");
            if (capability.mode === "unavailable")
                assert(capability.reason !== "", label + "unavailable, with its reason: " + capability.reason);
            if (capability.mode === "apply")
                assert(EtcFilesRules.knows(kind) && integration.files !== null, label + "applied: a file EtcFiles writes");
            if (id === "generic")
                assertEqual(capability.mode + "|" + capability.reason, "unavailable|" + IntegrationRules.unsupported, label + "generic: not supported");

            const value = _values[kind] ?? 1;
            const planned = integration.plan(kind, value);
            assert(planned !== null && typeof planned === "object" && "preview" in planned && "refusal" in planned, label + "plan answers");
            if (capability.mode === "unavailable") {
                assertEqual(planned.preview, null, label + "… no preview");
                assertEqual(planned.refusal?.text, capability.reason, label + "… refused with the reason");
            } else {
                assertEqual(planned.refusal, null, label + "a value it takes: planned");
                if (capability.mode === "apply") {
                    assertEqual(planned.preview.files[0].path, EtcFilesRules.files[kind], label + "… the file it writes");
                    assert(EtcFilesRules.validText(planned.preview.files[0].text), label + "… a text EtcFiles writes");
                } else if (capability.mode === "copy") {
                    assert(planned.preview.option !== "" && planned.preview.snippet.startsWith(planned.preview.option + " "), label + "… the option and the line to copy: "
                           + planned.preview.snippet);
                    assert(planned.preview.hint.includes(planned.preview.option), label + "… a hint naming the option: " + planned.preview.hint);
                }
                assertEqual(integration.plan(kind, "x").refusal?.code, "value", label + "a value it does not take: refused");
            }

            // One run at a time per EtcFiles: a kind's turn waits for the last one's answer
            if (integration.files?.busy === true)
                _deferred.push(() => _changes(integration, kind, capability, value, label));
            else
                _changes(integration, kind, capability, value, label);

            integration.readInForce(kind, _counter(id + " readInForce " + kind));
            _expected.push(id + " readInForce " + kind);
        }
    }

    // Undo before any change, then apply: each answers at once, `done` once when started
    function _changes(integration, kind, capability, value, label) {
        const id = integration.distribution;
        // Before any change: nothing to put back
        const undone = integration.undo(kind, { done: _counter(id + " undo " + kind) });
        assert(typeof undone?.started === "boolean" && (undone.started ? undone.refusal === null : typeof undone.refusal?.text === "string"),
               label + "undo answers: " + JSON.stringify(undone));
        assert(!undone.started, label + "… nothing undone before a change");
        assertEqual(undone.refusal.code, capability.undo ? "noUndo" : capability.mode === "unavailable" ? "unavailable" : capability.mode === "apply" ? "noUndo" : "mode",
                    label + "… refused for its reason");

        const applied = integration.apply(kind, value, { done: _counter(id + " apply " + kind) });
        assert(typeof applied?.started === "boolean" && (applied.started ? applied.refusal === null : typeof applied.refusal?.text === "string"),
               label + "apply answers: " + JSON.stringify(applied));
        assertEqual(applied.started, capability.mode === "apply", label + "… started only where the shell applies");
        if (applied.started)
            _expected.push(id + " apply " + kind);
        if (capability.mode === "unavailable")
            assertEqual(applied.refusal.text, capability.reason, label + "… refused with the reason");
    }

    // The changes waiting for their integration's EtcFiles
    property var _deferred: []
    // Runs the waiting changes one at a time, each once nothing runs
    function _runDeferred() {
        _steps.unshift({ description: "a waiting change's turn", condition: () => _integrations.every(integration => integration.files?.busy !== true), action: () => {
            const next = suite._deferred.shift();
            if (next !== undefined) {
                next();
                suite._runDeferred();
            }
        } });
    }

    function runAsync() {
        _then("the scratch folder made, the shell's timeout looked up", () => _ready && CommandTools.known, () => {
            _integrations = [
                _arch.createObject(suite, { start: _standIn("arch"), base: _scratch, inForceCommands: _merged }),
                _nixos.createObject(suite, { start: _standIn("nixos"), base: _scratch, inForceCommands: _merged }),
                _generic.createObject(suite)
            ];
            assertEqual(_integrations.map(integration => integration.distribution).sort().join(" "), DistributionRules.ids.slice().sort().join(" "),
                        "an integration for every shipped distribution");
            for (const integration of _integrations)
                _check(integration);
            assertEqual(_integrations[2].files, null, "generic: nothing it could write with");
            const unknown = IntegrationRules.unknownCapability();
            assert(IntegrationRules.valid(unknown) && unknown.mode === "unavailable" && !unknown.known, "while the distribution is not known: unavailable, not known");
            assert(_deferred.length > 0, "Arch's second applied kind waits for the first one's run");
            _runDeferred();
        });
        _then("every started apply and every readInForce answered", () => _expected.every(key => (_answers[key] ?? []).length > 0)
              && !_integrations[0].files.busy, () => {
            for (const key of Object.keys(_answers))
                assertEqual(_answers[key].length, 1, key + ": answered once");
            for (const key of Object.keys(_answers).filter(key => !_expected.includes(key)))
                fail(key + ": answered, though not started");
            for (const integration of _integrations) {
                for (const kind of _kinds) {
                    const answer = (_answers[integration.distribution + " readInForce " + kind] ?? [])[0];
                    assert(IntegrationRules.validInForce(answer), integration.distribution + " " + kind + ": what is in force, " + JSON.stringify(answer));
                    if (!integration.capability(kind).inForce)
                        assertEqual(JSON.stringify(answer), JSON.stringify(IntegrationRules.inForceUnknown()), integration.distribution + " " + kind + ": … unknown where it is not read");
                }
            }
            assertEqual((_answers["arch apply sleep.hibernateDelay"] ?? [])[0]?.quiet, true, "arch: the hibernation delay's apply ran (its prompt dismissed)");
            const archDelay = (_answers["arch readInForce sleep.hibernateDelay"] ?? [])[0];
            assertEqual(JSON.stringify(archDelay), JSON.stringify({ state: "set", value: 7200, from: "/etc/systemd/sleep.conf", elsewhere: "/etc/systemd/sleep.conf",
                                                                   file: { state: "absent", text: null, sha256: "absent", ours: false }, afterOwn: false, shadowed: null }),
                        "arch: the delay in force, set elsewhere (read before the shell's file), and the shell's own file (none in the scratch tree)");
            const nixosDelay = (_answers["nixos readInForce sleep.hibernateDelay"] ?? [])[0];
            assertEqual(nixosDelay?.elsewhere + " " + nixosDelay?.value + " " + nixosDelay?.file, "/etc/systemd/sleep.conf 7200 null", "nixos: the delay in force, no file of the shell's");
            assertEqual(JSON.stringify(_runs), JSON.stringify({ arch: ["Change the time before hibernating", "Change the connectivity check's address"] }),
                        "runs as administrator: only arch's applied kinds, once each; none from nixos or generic");
            assertEqual(JSON.stringify((_answers["arch readInForce network.connectivityUri"] ?? [])[0]),
                        JSON.stringify({ state: "set", value: "http://mine/", from: "/etc/NetworkManager/NetworkManager.conf", elsewhere: "/etc/NetworkManager/NetworkManager.conf",
                                         file: { state: "absent", text: null, sha256: "absent", ours: false }, afterOwn: false, shadowed: null }),
                        "arch: the address in force, set in NetworkManager.conf (read before the shell's file), and the shell's own file");
            assertEqual((_answers["nixos readInForce network.connectivityUri"] ?? [])[0]?.file?.state, "absent",
                        "nixos: the shell's own file read too, for Write anyway");
            assertEqual(_integrations[1].capability("network.connectivityUri").anyway, true, "nixos: the address written anyway when asked");
            // Distribution forwards to the integration of the system it answered
            Distribution.whenReady(() => suite._facade = true);
        });
        _then("Distribution answered", () => _facade, () => {
            const id = Distribution.detection.id;
            assertEqual(Distribution.integration?.distribution ?? "(none)", id === "" ? "(none)" : id, "Distribution's integration: the answered distribution's");
            for (const shipped of DistributionRules.ids)
                assertEqual(Distribution._integrations[shipped]?.distribution, shipped, "Distribution has " + shipped + "'s integration");
            for (const kind of IntegrationRules.kinds) {
                const capability = Distribution.capability(kind);
                assertEqual([capability.mode, capability.undo ? "undo" : "-", capability.inForce ? "inForce" : "-"].join(" "),
                            id === "" ? "unavailable - -" : _expectedModes[id][kind], "Distribution's " + kind + ": the answered distribution's mode");
                assertEqual(capability.known, id !== "", "… known once answered");
            }
            const delay = Distribution.plan("sleep.hibernateDelay", 600);
            const plans = { arch: "/etc/systemd/sleep.conf.d/h2s-shell.conf", nixos: HibernateRules.nixosOption + " = 600;", generic: "unavailable", "": "unknown" };
            assertEqual(delay.preview?.files?.[0]?.path ?? delay.preview?.snippet ?? delay.refusal?.code, plans[id], "… its plan: the distribution's");
        });
        _clock.start();
        _exec(["sh", "-c", "mkdir -p \"$1/etc/systemd\" \"$1/etc/NetworkManager\" && chmod 755 \"$1/etc/systemd\" \"$1/etc/NetworkManager\"", "sh", _scratch], code => {
            suite.assertEqual(code, 0, "the scratch folder made");
            suite._ready = true;
        });
    }

    property bool _facade: false

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
            if (!ready && waited < 10000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready) {
                suite.fail("timed out waiting: " + step.description);
                suite._steps = [];
                return;
            }
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        for (const integration of _integrations)
            integration.destroy();
        _exec(["rm", "-rf", "--", _scratch], () => suite.finish());
    }

    function _exec(command, done) {
        const process = _process.createObject(suite, { command: command });
        process.exited.connect(code => {
            done?.(code);
            process.destroy();
        });
        process.running = true;
    }

    property Component _process: Component {
        Process {}
    }
}
