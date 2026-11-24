import QtQuick
import qs.singletons

// IntegrationRules: an integration's table read as capabilities (a kind not defined, not
// named or named wrongly is unavailable with a reason; only an applied kind is tried or
// undone), what a valid answer is, the plan per mode, when apply and undo may start, and
// what is in force from a file read
TestCase {
    suiteName: "IntegrationRules"

    function run() {
        const rules = IntegrationRules;
        const kind = "sleep.hibernateDelay";
        const show = answer => JSON.stringify(answer);
        const unavailable = reason => show({ mode: "unavailable", trial: false, undo: false, inForce: false, reason, known: true });

        assertEqual(show(rules.kinds), show(["sleep.hibernateDelay"]), "the change kinds the shell defines");
        assertEqual(show(rules.modes), show(["apply", "declare", "copy", "unavailable"]), "the modes");

        // ── capability ──
        assertEqual(show(rules.capability({ [kind]: { mode: "apply", trial: true, undo: true, inForce: true } }, kind)),
                    show({ mode: "apply", trial: true, undo: true, inForce: true, reason: "", known: true }), "applied, tried, undone, read");
        assertEqual(show(rules.capability({ [kind]: { mode: "apply" } }, kind)), show({ mode: "apply", trial: false, undo: false, inForce: false, reason: "", known: true }),
                    "… each only when said");
        assertEqual(show(rules.capability({ [kind]: { mode: "apply", trial: 1, undo: "yes", inForce: {} } }, kind)),
                    show({ mode: "apply", trial: false, undo: false, inForce: false, reason: "", known: true }), "… said as true only");
        assertEqual(show(rules.capability({ [kind]: { mode: "copy", trial: true, undo: true, inForce: true } }, kind)),
                    show({ mode: "copy", trial: false, undo: false, inForce: true, reason: "", known: true }), "copied: never tried or undone by the shell");
        assertEqual(show(rules.capability({ [kind]: { mode: "declare", undo: true } }, kind)).indexOf('"undo":false') > 0, true, "… nor declared (not yet)");
        assertEqual(show(rules.capability({}, kind)), unavailable(rules.unsupported), "not named: unavailable, not supported");
        assertEqual(show(rules.capability({ [kind]: { mode: "unavailable", reason: "No swap." } }, kind)), unavailable("No swap."), "unavailable with its own reason");
        assertEqual(show(rules.capability({ [kind]: { mode: "unavailable" } }, kind)), unavailable(rules.unsupported), "… or the general one");
        assertEqual(show(rules.capability({ [kind]: { mode: "write" } }, kind)), unavailable(rules.unsupported), "a mode that is none: unavailable");
        assertEqual(show(rules.capability({ "no.kind": { mode: "apply" } }, "no.kind")), unavailable(rules.unsupported), "a kind the shell does not define: unavailable");
        assertEqual(show(rules.capability(null, kind)), unavailable(rules.unsupported), "no table: unavailable");
        assertEqual(show(rules.capability({}, "toString")), unavailable(rules.unsupported), "a name every object has: unavailable");
        assertEqual(show(rules.unknownCapability()), show({ mode: "unavailable", trial: false, undo: false, inForce: false, reason: rules.unknown, known: false }),
                    "while the distribution is not known: unavailable, not known");

        // ── valid ──
        for (const answer of [rules.unknownCapability(), rules.capability({}, kind), rules.capability({ [kind]: { mode: "apply", trial: true, undo: true } }, kind),
                              rules.capability({ [kind]: { mode: "copy" } }, kind)])
            assert(rules.valid(answer), "valid: " + show(answer));
        const good = { mode: "apply", trial: false, undo: true, inForce: true, reason: "", known: true };
        for (const [why, bad] of [["no mode", Object.assign({}, good, { mode: "x" })], ["no mode, nothing else wrong", Object.assign({}, good, { mode: "x", undo: false })], ["unavailable without a reason", { mode: "unavailable", trial: false, undo: false, inForce: false, reason: "", known: true }],
                                  ["unavailable but undone", { mode: "unavailable", trial: false, undo: true, inForce: false, reason: "r", known: true }],
                                  ["unavailable but read", { mode: "unavailable", trial: false, undo: false, inForce: true, reason: "r", known: true }],
                                  ["unavailable but tried", { mode: "unavailable", trial: true, undo: false, inForce: false, reason: "r", known: true }],
                                  ["copied but undone", Object.assign({}, good, { mode: "copy" })], ["copied but tried", Object.assign({}, good, { mode: "copy", undo: false, trial: true })],
                                  ["offered with a reason", Object.assign({}, good, { reason: "r" })], ["offered while not known", Object.assign({}, good, { known: false })],
                                  ["a flag not a boolean", Object.assign({}, good, { undo: 1 })], ["no reason", Object.assign({}, good, { reason: undefined })],
                                  ["nothing", null]])
            assert(!rules.valid(bad), "not valid: " + why);

        // ── values and plans ──
        assert(rules.validValue(kind, 60) && rules.validValue(kind, 86400), "the delay: a minute to a day");
        for (const wrong of [59, 86401, 600.5, "600", null])
            assert(!rules.validValue(kind, wrong), "… not " + show(wrong));
        assert(!rules.validValue("no.kind", 600), "a kind not defined takes nothing");
        assertEqual(rules.textOf(kind, 600), HibernateRules.dropInText(600), "the drop-in's text");
        assertEqual(rules.textOf("no.kind", 600), "", "… none for another kind");
        const applied = { [kind]: { mode: "apply" } };
        assertEqual(show(rules.plan(applied, kind, 600)), show({ preview: { files: [{ path: "/etc/systemd/sleep.conf.d/h2s-shell.conf", text: HibernateRules.dropInText(600) }] }, refusal: null }),
                    "applied: the file and its text");
        const copied = { [kind]: { mode: "copy", option: HibernateRules.nixosOption, hint: "Set it there." } };
        assertEqual(show(rules.plan(copied, kind, 600)), show({ preview: { option: HibernateRules.nixosOption, snippet: HibernateRules.nixosOption + " = 600;",
                                                                           hint: "Set it there." }, refusal: null }),
                    "copied: the option, its line, and the integration's hint");
        assertEqual(rules.plan({ [kind]: { mode: "copy", option: "x" } }, kind, 600).preview.hint, "", "… no hint given: none");
        assertEqual(rules.plan(applied, kind, 30).refusal?.code, "value", "a value it does not take: refused");
        assertEqual(show(rules.plan({}, kind, 600)), show({ preview: null, refusal: { code: "unavailable", text: rules.unsupported } }), "unavailable: refused with the reason");

        // ── when apply and undo may start ──
        assertEqual(rules.applyRefusal(rules.capability(applied, kind)), null, "apply: where applied");
        assertEqual(rules.applyRefusal(rules.capability(copied, kind)).code, "mode", "… not where copied");
        assertEqual(show(rules.applyRefusal(rules.capability({}, kind))), show({ code: "unavailable", text: rules.unsupported }), "… unavailable, with the reason");
        assertEqual(show(rules.applyRefusal(rules.unknownCapability())), show({ code: "unknown", text: rules.unknown }), "… not known");
        assertEqual(rules.undoRefusal(rules.capability({ [kind]: { mode: "apply", undo: true } }, kind)), null, "undo: where applied and undone");
        assertEqual(rules.undoRefusal(rules.capability(applied, kind)).code, "noUndo", "… not without Undo");
        assertEqual(rules.undoRefusal(rules.capability(copied, kind)).code, "mode", "… not where copied");
        assertEqual(rules.undoRefusal(rules.unknownCapability()).code, "unknown", "… not while not known");
        assertEqual(rules.refusal("value").text, "Not a value for this setting.", "plain reasons");
        assertEqual(rules.refusal("x").text, rules.texts.value, "… an unknown code: the value's");

        // ── what is in force ──
        const own = EtcFilesRules.inForce({ text: HibernateRules.dropInText(600) }, kind);
        const merged = (...files) => files.map(([path, body]) => "# " + path + "\n" + body).join("\n");
        const ownPath = "/etc/systemd/sleep.conf.d/h2s-shell.conf";
        assertEqual(show(rules.inForceCommand(kind)), show(["systemd-analyze", "--no-pager", "cat-config", "systemd/sleep.conf"]),
                    "the delay as systemd merges sleep.conf and its drop-ins");
        assertEqual(rules.inForceCommand("no.kind"), null, "… none for another kind");
        assertEqual(show(rules.inForceOf(kind, merged(["/usr/lib/systemd/sleep.conf", "[Sleep]\n#HibernateDelaySec=\n"], [ownPath, "[Sleep]\nHibernateDelaySec=600\n"]), own)),
                    show({ state: "set", value: 600, from: ownPath, elsewhere: "", file: own, afterOwn: false }), "set by the shell's own drop-in: not elsewhere");
        assertEqual(show(rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=2h\n"]), own)),
                    show({ state: "set", value: 7200, from: "/etc/systemd/sleep.conf", elsewhere: "/etc/systemd/sleep.conf", file: own, afterOwn: false }),
                    "set by another file read before the shell's: in force, set elsewhere (shown, overridden only asked)");
        assertEqual(show(rules.inForceOf(kind, merged([ownPath, "[Sleep]\nHibernateDelaySec=600\n"], ["/etc/systemd/sleep.conf.d/zz.conf", "[Sleep]\nHibernateDelaySec=\n"]), own)),
                    show({ state: "default", value: null, from: "/etc/systemd/sleep.conf.d/zz.conf", elsewhere: "/etc/systemd/sleep.conf.d/zz.conf", file: own, afterOwn: true }),
                    "systemd's default put back by a later file: that file's setting, read after the shell's");
        assertEqual(show(rules.inForceOf(kind, merged(["/usr/lib/systemd/sleep.conf", "[Sleep]\n#HibernateDelaySec=\n"]), null)),
                    show({ state: "default", value: null, from: "", elsewhere: "", file: null, afterOwn: false }), "no file sets it: systemd's default, nothing elsewhere; no file of the shell's");
        assertEqual(show(rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=soon\n"]), own)),
                    show({ state: "unknown", value: null, from: "", elsewhere: "", file: own, afterOwn: false }), "a value not understood: unknown");
        assertEqual(show(rules.inForceOf(kind, null, own)), show({ state: "unknown", value: null, from: "", elsewhere: "", file: own, afterOwn: false }), "not read: unknown, the shell's file still told");
        assertEqual(rules.inForceOf(kind, null, undefined).file, null, "no file of the shell's handed: null");
        assertEqual(rules.inForceOf(kind, null, "text").file, null, "… nor for one that is no answer");
        assertEqual(rules.inForceOf("no.kind", merged([ownPath, "[Sleep]\nHibernateDelaySec=600\n"]), null).state, "unknown", "another kind: unknown");
        assertEqual(show(rules.inForceUnknown()), show({ state: "unknown", value: null, from: "", elsewhere: "", file: null, afterOwn: false }), "nothing told");
        for (const answer of [rules.inForceUnknown(), rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=2h\n"]), own)])
            assert(rules.validInForce(answer), "a valid answer: " + show(answer));
        const set = { state: "set", value: 1, from: "/a", elsewhere: "/a", file: null, afterOwn: true };
        for (const [why, bad] of [["no state", Object.assign({}, set, { state: "absent" })], ["set without a value", Object.assign({}, set, { value: null })],
                                  ["a value by default", Object.assign({}, set, { state: "default" })], ["elsewhere not where it is from", Object.assign({}, set, { elsewhere: "/b" })],
                                  ["no from", Object.assign({}, set, { from: undefined })], ["a file that is none", Object.assign({}, set, { file: { state: "x" } })],
                                  ["no elsewhere", Object.assign({}, set, { elsewhere: null })], ["nothing", null],
                                  ["no afterOwn", Object.assign({}, set, { afterOwn: undefined })],
                                  ["read after the shell's with nothing elsewhere", Object.assign({}, set, { from: "", elsewhere: "" })],
                                  ["a state that is none, nothing else wrong", { state: "absent", value: null, from: "", elsewhere: "", file: null, afterOwn: false }],
                                  ["no from, nothing else wrong", { state: "default", value: null, from: undefined, elsewhere: "", file: null, afterOwn: false }]])
            assert(!rules.validInForce(bad), "not valid: " + why);
    }
}
