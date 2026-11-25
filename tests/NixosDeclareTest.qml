import QtQuick
import qs.distributions.nixos
import qs.panels.settings
import qs.singletons
import qs.singletons.io

// The hibernation delay kept in the shell's file in the NixOS configuration (IntegrationRules'
// mode "declare"): NixosDeclareRules (what is in force by the published settings.json — the
// shell's value, the configuration's own systemd line that wins over it, systemd's default,
// unknown —, and the candidate: the shell's file with the one key changed, exactly), then the
// whole way on stand-ins, as the Hibernate section takes it: IntegrationChange → NixosIntegration
// (copy until connected, declare after) → NixosDeclare → the real NixosRebuildFlow and
// NixosRebuild, with a stand-in modal host, build and root step: Apply builds the candidate,
// Apply now switches, Undo builds the file as it was before; the modal closed is quiet, with
// nothing to undo; no flow, no start; the configuration's own value is shown and Apply is not
// offered over it.
//
// Stand-ins only: no nix, no pkexec, no notification. Asynchronous (the reading answers later).
TestCase {
    id: suite
    suiteName: "NixosDeclare"
    asynchronous: true

    readonly property string folder: "/srv/nixos-config"
    readonly property string kind: "sleep.hibernateDelay"
    readonly property string empty: "{\"version\":1}\n"
    readonly property string candidate: "{\n  \"version\": 1,\n  \"idle\": {\n    \"hibernateDelay\": 10800\n  }\n}\n"

    function reading(more, fileText, published) {
        const text = fileText ?? empty;
        return Object.assign({
            configuration: { found: true, folder, entry: "flake.nix", type: "flake" },
            real: folder, owner: "root", rootWrites: true, git: "absent", gitKnowsFile: "", host: "nixos",
            file: { path: folder + "/h2s-shell.json", state: "present", sha256: PamEditRules.sha256(text), text },
            fileStatus: "inForce", module: "present", published: "present",
            publishedSettings: published ?? { version: 1, settings: {}, inForce: {}, system: { idle: { hibernateDelay: null } }, own: { idle: { hibernateDelay: false } } },
            generations: { count: 3, current: 3 }, state: "connected", homeWarning: false, facts: []
        }, more ?? {});
    }

    // `own` defaults to what the module tells by priority: a merged value other than the file's
    function published(fileValue, merged, own) {
        const settings = fileValue === undefined ? {} : { idle: { hibernateDelay: fileValue } };
        const theirs = own ?? (merged !== null && NixosDeclareRules.seconds(merged) !== NixosDeclareRules.seconds(fileValue));
        return { version: 1, settings, inForce: { idle: { hibernateDelay: fileValue ?? null } }, system: { idle: { hibernateDelay: merged } },
                 own: { idle: { hibernateDelay: theirs } } };
    }

    // ── The stand-ins ──

    property QtObject _configuration: QtObject {
        property string state: ""
        property int revision: 0
        property bool busy: false
        property var value: null
        property int reads: 0
        function current() {
            return value === null ? null : JSON.parse(JSON.stringify(value));
        }
        function read() {
            reads++;
            Qt.callLater(() => {
                state = value?.state ?? "";
                revision++;
            });
        }
        function set(reading) {
            value = reading;
            state = reading?.state ?? "";
        }
    }
    property QtObject _builder: QtObject {
        property var requests: []
        property var handlers: null
        property var progress: null
        function build(request, handlers) {
            requests = requests.concat([request]);
            this.handlers = handlers;
            return { started: true, refusal: null };
        }
        function cancel() {}
        function release(path) {}
    }
    property QtObject _writer: QtObject {
        property var requests: []
        property var handlers: null
        function apply(request, handlers) {
            requests = requests.concat([request]);
            this.handlers = handlers;
            return { started: true, refusal: null };
        }
    }
    property QtObject _host: QtObject {
        property var questions: []
        property var answer: null
        function ask(question, callback) {
            questions = questions.concat([question]);
            answer = callback;
            return "";
        }
    }
    property NixosRebuild _rebuild: NixosRebuild {
        builder: suite._builder
        writer: suite._writer
        notifier: ({ send: () => null })
    }
    property NixosRebuildFlow _flow: NixosRebuildFlow {
        rebuild: suite._rebuild
        configuration: suite._configuration
        modalHost: suite._host
    }
    property NixosIntegration _integration: NixosIntegration {
        configuration: suite._configuration
        rebuild: suite._rebuild
        // Not connected: the system's own reading, a stand-in
        inForceCommands: ({ "sleep.hibernateDelay": ["sh", "-c", "printf '# /etc/systemd/sleep.conf\\n[Sleep]\\nHibernateDelaySec=1h\\n'"] })
    }
    property IntegrationChange _change: IntegrationChange {
        kind: suite.kind
        integration: suite._integration
    }
    property var _finished: []
    property var _answers: []

    property Connections _changes: Connections {
        target: suite._change
        function onFinished(mode, outcome) {
            suite._finished = suite._finished.concat([mode + ":" + (outcome?.ok === true ? "ok" : outcome?.quiet === true ? "quiet" : "failed")]);
        }
    }

    // ── Pure: NixosDeclareRules ──

    function _pure() {
        const rules = NixosDeclareRules;
        const inForce = (fileValue, merged, more, own) => rules.inForce(reading(more, null, published(fileValue, merged, own)), kind);
        const own = inForce(10800, 10800);
        assert(IntegrationRules.validInForce(own), "inForce: a valid answer " + JSON.stringify(own));
        assertEqual([own.state, own.value, own.from, own.elsewhere, own.afterOwn].join("|"), "set|10800|" + folder + "/h2s-shell.json||false",
                    "inForce: the file's value is what the system merged: the shell's own, in force");
        assertEqual(inForce("3h", "3h").elsewhere + "|" + inForce("3h", "3h").value, "|10800", "… the same as a time span");
        const theirs = inForce(10800, "10min");
        assert(IntegrationRules.validInForce(theirs), "inForce: valid, set elsewhere " + JSON.stringify(theirs));
        assertEqual([theirs.state, theirs.value, theirs.from, theirs.elsewhere, theirs.afterOwn].join("|"), "set|600|" + folder + "|" + folder + "|true",
                    "inForce: the configuration's own systemd line differs from the file's: set in the configuration, the shell cannot win over it");
        assertEqual(inForce(undefined, "10min").elsewhere, folder, "… the file gives none: the configuration's own");
        const equalOwn = inForce(10800, "3h", {}, true);
        assertEqual([equalOwn.state, equalOwn.value, equalOwn.elsewhere, equalOwn.afterOwn].join("|"), "set|10800|" + folder + "|true",
                    "inForce: the configuration's own definition at the file's value: still its own, nothing offered over it");
        const ownDefault = inForce(10800, null, {}, true);
        assert(IntegrationRules.validInForce(ownDefault), "… valid " + JSON.stringify(ownDefault));
        assertEqual(ownDefault.state + "|" + ownDefault.elsewhere, "default|" + folder, "… its own null: systemd's default, the configuration's");
        assertEqual(inForce(10800, 10800, {}, "yes").state, "unknown", "own not a boolean: unknown");
        assertEqual(inForce(undefined, null).state + "|" + inForce(undefined, null).value, "default|null", "nothing set anywhere: systemd's default");
        assertEqual(inForce(10800, "soon").state, "unknown", "a merged value not understood: unknown");
        assertEqual(rules.inForce(reading({}, null, { version: 1, settings: {}, inForce: {}, system: { idle: { hibernateDelay: 600 } } }), kind).state, "unknown",
                    "a module that does not tell whether the configuration defines it: unknown");
        assertEqual(rules.inForce(reading({}, null, { version: 1, settings: {}, inForce: {} }), kind).state, "unknown",
                    "a module that publishes no merged value: unknown, never the shell's");
        assertEqual(rules.inForce(reading({ state: "found" }, null, published(10800, 10800)), kind).state, "unknown", "not connected: unknown");
        assertEqual(rules.inForce(reading(), "pam.rules").state, "unknown", "a kind not kept in the file: unknown");

        const made = rules.request(reading(), kind, 10800);
        assertEqual(made.refusal, null, "request: no refusal");
        assertEqual(made.request.text, candidate, "request: the candidate exactly: the file with idle.hibernateDelay in seconds");
        assertEqual(JSON.stringify(made.request.previous), JSON.stringify({ value: null, text: empty }), "… the file before, for Undo");
        assertEqual(made.request.key + "|" + made.request.value, kind + "|10800", "… keyed to the setting and its value");
        const other = "{\"version\":1,\"polkit\":{\"rememberAdmin\":{\"minutes\":7}},\"idle\":{\"hibernateDelay\":\"1h\",\"x\":1}}";
        const changed = rules.request(reading({}, other), kind, 600).request;
        assertEqual(changed.text, JSON.stringify({ version: 1, polkit: { rememberAdmin: { minutes: 7 } }, idle: { hibernateDelay: 600, x: 1 } }, null, 2) + "\n",
                    "… the other keys and their order kept, the value replaced");
        assertEqual(changed.previous.value, "1h", "… the value before");
        assertEqual(rules.request(reading({ state: "found" }), kind, 600).refusal?.code, "notConnected", "not connected: refused");
        assertEqual(rules.request(reading({ file: { path: "x", state: "absent", sha256: "", text: "" } }), kind, 600).refusal?.code, "file", "no file: refused");
        assertEqual(rules.request(reading({}, "{"), kind, 600).refusal?.code, "file", "the file not JSON: refused");
        assertEqual(rules.request(reading({}, "{\"version\":1,\"idle\":\"3h\"}"), kind, 600).refusal?.code, "file", "idle not an object: refused");
        assertEqual(rules.request(reading(), kind, 59).refusal?.code, "value", "a value out of range: refused");
        assertEqual(rules.request(reading(), "pam.rules", 600).refusal?.code, "unavailable", "a kind not kept in the file: refused");

        // What the Hibernate section offers for it
        const capability = { mode: "declare", trial: false, undo: true, inForce: true, anyway: false, reason: "", known: true };
        const offer = (inForceAnswer, more) => HibernateRules.delayOffer(Object.assign({
            delay: { state: "set", seconds: 3600 }, picked: 10800, differs: true, capability, hint: "", inForce: inForceAnswer, busy: "", undoable: false
        }, more ?? {}));
        const overridden = offer(theirs);
        assertEqual(overridden.shown + "|" + overridden.apply.button + "|" + overridden.undo.shown, "true|none|false",
                    "offer: the configuration's own value: shown, no Apply, no Undo");
        assertEqual(overridden.line, "Set in your configuration: 600 s. Your own line wins. To change it here, remove it from your configuration.", "… its words");
        assertEqual(offer(theirs, { differs: false, undoable: true }).apply.button + "|" + offer(theirs, { differs: false }).shown, "none|true",
                    "… also when the picked time is the same");
        const plain = offer(own);
        assertEqual(plain.apply.button + "|" + JSON.stringify(plain.apply.request), "plain|" + JSON.stringify({ seconds: 10800, current: null, replace: false }),
                    "offer: the shell's own in force: Apply, for the picked time");
        assertEqual(plain.line, "Picked 10800 s; the system now hibernates after 3600 s. Apply rebuilds NixOS.", "… its words");
        assertEqual(offer(IntegrationRules.inForceUnknown()).apply.button, "none", "… not read: no Apply");
        const after = offer(own, { differs: false, undoable: true });
        assertEqual(after.undo.shown + "|" + after.line, "true|Undo puts back the shell's previous value and rebuilds NixOS.", "after an Apply: Undo");
    }

    // ── The way through, on stand-ins ──

    function _answerModal(button) {
        _host.answer({ button, subject: { nixosRebuild: _rebuild.state.run } });
    }

    function runAsync() {
        _pure();
        _configuration.set(reading({ state: "found", published: "absent", publishedSettings: null }));
        assertEqual(_integration.capability(kind).mode, "copy", "not connected: copied");
        assertEqual(_change.apply(10800, { flow: _flow }).refusal?.code, "mode", "… Apply refused before anything runs");
        _change.read();
        _then("not connected: the system's own reading", () => _change.inForce !== null, () => {
            assertEqual(_change.inForce.state + "|" + _change.inForce.value + "|" + _change.inForce.from, "set|3600|/etc/systemd/sleep.conf",
                        "not connected: what is in force read as for a setting to copy");
            _configuration.set(reading({}, null, published(undefined, "10min")));
            const capability = _integration.capability(kind);
            assertEqual([capability.mode, capability.undo, capability.inForce].join(" "), "declare true true", "connected: declared, with Undo and what is in force");
            assert(IntegrationRules.valid(capability), "… a valid capability");
            _change.read();
        });
        _then("the configuration's own value read", () => _change.inForce !== null, () => {
            assertEqual(_change.inForce.elsewhere + "|" + _change.inForce.value, folder + "|600", "readInForce: the configuration's own value, from the reading read anew");
            _configuration.set(reading({}, null, published(undefined, null)));
            const before = _host.questions.length;
            assertEqual(_change.apply(10800, {}).refusal?.code, "noFlow", "Apply without the window's way to the rebuild: refused");
            assertEqual(_host.questions.length, before, "… nothing asked");
            _change.read();
        });
        _then("systemd's default read", () => _change.inForce !== null, () => {
            assertEqual(_change.inForce.state, "default", "readInForce: nothing set: systemd's default");
            const started = _change.apply(10800, { flow: _flow });
            assertEqual(started.started, true, "Apply: started");
            assertEqual(_change.busy + "|" + _host.questions.length + "|" + _rebuild.phase, "apply|1|announced", "… busy, the announcing modal asked");
            assertEqual(_rebuild.state.subject.text, candidate, "… the candidate announced exactly");
            _answerModal("build");
            assertEqual(_builder.requests.length + "|" + _builder.requests[0]?.candidate, "1|" + candidate, "Build: the candidate built");
            _builder.handlers.done({ ok: true, drvPath: "/nix/store/a.drv", outPath: "/nix/store/a" });
            assertEqual(_rebuild.phase + "|" + _change.busy, "built|apply", "built: waiting for Apply now, still busy");
            assertEqual(_writer.requests.length, 0, "… nothing run as root before the click");
            assert(_flow.applyNow(), "Apply now taken");
            assertEqual(_writer.requests[0]?.candidate?.text, candidate, "Apply now: the root step gets the candidate");
            // The file holds what that Apply wrote
            _configuration.set(reading({}, candidate, published(10800, 10800)));
            _writer.handlers.done({ kind: "applied", ok: true });
        });
        _then("the Apply finished", () => _finished.length === 1 && _change.inForce !== null, () => {
            assertEqual(_finished.join(" ") + "|" + _change.busy + "|" + _change.undoable, "apply:ok||true", "applied: done ok, Undo offered");
            assertEqual(_change.inForce.state + "|" + _change.inForce.value + "|" + _change.inForce.elsewhere, "set|10800|", "… read again: the shell's own in force");
            _flow.panelRequested(null);
            assertEqual(_change.undo({ flow: _flow }).started, true, "Undo: started");
            assertEqual(_host.questions.length + "|" + _rebuild.state.subject.text, "2|" + empty, "… Undo's modal, the file as it was before as the candidate");
            _answerModal("build");
            assertEqual(_builder.requests[1]?.candidate, empty, "Undo: the file before built");
            _builder.handlers.done({ ok: true, drvPath: "/nix/store/b.drv", outPath: "/nix/store/b" });
            assert(_flow.applyNow(), "Undo's Apply now taken");
            _configuration.set(reading({}, empty, published(undefined, null)));
            _writer.handlers.done({ kind: "applied", ok: true });
        });
        _then("the Undo finished", () => _finished.length === 2 && _change.inForce !== null, () => {
            assertEqual(_finished[1] + "|" + _change.undoable, "undo:ok|false", "undone: nothing left to undo");
            assertEqual(_change.apply(600, { flow: _flow }).started, true, "another Apply: started");
            _answerModal("cancel");
        });
        _then("the modal closed", () => _finished.length === 3, () => {
            assertEqual(_finished[2] + "|" + _change.busy + "|" + _change.undoable + "|" + _builder.requests.length, "apply:quiet||false|2",
                        "the modal closed: quiet, nothing built, nothing to undo");
        });
        _clock.start();
    }

    // ---- Each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description, condition, action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite.finish();
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
}
