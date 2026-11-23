import QtQuick
import Quickshell.Io
import qs.singletons

// The NixOS module's PAM options (nix/pam.nix) against the editor's rules, from their text:
// the methods, control words, detail ranges and libpam's own modules agree with
// PamRuleRules'. And the case set tests/system/nixos/pam.sh evaluates on NixOS
// (tests/fixtures/pam-nixos/cases.json): each case's options are PamEditRules.nixosSnippet's
// for its rows, and its lines are PamEditRules' lines for the same rows — written as NixOS
// writes them (no `-auth`: the module comes from its package; a module by its file name) —
// so the module's lines there are compared with the editor's.
TestCase {
    suiteName: "PamNixosModule"

    property var _module: FileView {
        path: Qt.resolvedUrl("../nix/pam.nix")
        blockLoading: true
    }
    property var _cases: FileView {
        path: Qt.resolvedUrl("fixtures/pam-nixos/cases.json")
        blockLoading: true
    }

    // A Nix list of strings in the module's text: the first after what `prefix` (a regular
    // expression) matches, up to its `]`
    function _nixList(text, prefix) {
        const match = new RegExp(prefix + "[^\\[]*\\[([^\\]]*)\\]").exec(text);
        return match ? (match[1].match(/"[^"]*"/g) ?? []).map(word => word.slice(1, -1)) : null;
    }

    // A line as NixOS's file has it, for comparing: `-auth` is `auth`, a module its file
    // name, words one space apart
    function normalized(line) {
        const words = PamStackRules.words(String(line).replace(/#.*$/, "")) ?? [];
        if (words[0] === "-auth")
            words[0] = "auth";
        if (words.length > 2)
            words[2] = words[2].replace(/^.*\//, "");
        return words.join(" ");
    }

    function _facts(machine, service) {
        return {
            system: "nixos", service,
            fingerprint: machine?.fprintd === true ? "ready" : "absent",
            securityKey: machine?.u2f === true ? "ready" : "absent",
            faillockPresent: machine?.logFailures === true
        };
    }

    function run() {
        const text = _module.text();
        assert(text.length > 0, "nix/pam.nix is read");

        // --- the module's names and ranges are the editor's ---
        assertEqual(JSON.stringify(_nixList(text, "\\bmethods = ")),
                    JSON.stringify(PamRuleRules.addOrder.filter(method => method !== "raw").concat(["system", "raw"])),
                    "the methods are the editor's rows");
        assertEqual(JSON.stringify(_nixList(text, "\\bcontrols = ")), JSON.stringify(PamRuleRules.controls.map(control => control.word)),
                    "the control words are the editor's four");
        const spec = PamRuleRules.methods.fingerprint.details;
        assert(text.includes("timeout = mkOption {\n        type = types.nullOr (types.ints.between " + spec.timeout.min + " " + spec.timeout.max + ");"),
               "timeout's range is the editor's (" + spec.timeout.min + "–" + spec.timeout.max + ")");
        assert(text.includes("tries = mkOption {\n        type = types.nullOr (types.ints.between " + spec.tries.min + " " + spec.tries.max + ");"),
               "tries' range is the editor's (" + spec.tries.min + "–" + spec.tries.max + ")");
        const libpam = _nixList(text, "\\blibpamModules = ");
        assertEqual(JSON.stringify((libpam ?? []).map(name => name + ".so")), JSON.stringify(PamRuleRules.libpamModules),
                    "libpam's own modules are the editor's");
        assert(text.includes("systemModules = \"" + PamRuleRules.nixosModuleDirectories[0] + "\";"),
               "the system profile's module folder is the editor's");
        for (const control of PamRuleRules.controls.map(item => item.word)) {
            const lines = PamEditRules.countedLines(control);
            assert(text.includes(control + " = [ \"" + PamStackRules.words(lines[1])[1] + "\" \"" + PamStackRules.words(lines[2])[1] + "\" ];"),
                   "a counted " + control + " row's controls are the editor's");
        }
        for (const word of ["required", "requisite"])
            assert(text.includes(word + " = \"" + PamEditRules.writtenControls[word] + "\";"), "an own " + word + " row is written as the editor writes it");
        for (const kind of ["permit", "deny"]) {
            const words = normalized(PamEditRules.closingLines[kind]).split(" ");
            assert(text.includes(kind + " = line \"" + words[1] + "\" (pamModule \"" + words[2] + "\") [ ];"), "the " + kind + " closing line is the editor's");
        }

        // --- the case set ---
        let cases = [];
        try {
            cases = JSON.parse(_cases.text());
        } catch (error) {
            fail("tests/fixtures/pam-nixos/cases.json does not parse: " + error);
            return;
        }
        assert(cases.length >= 5, "the case set is read: " + cases.length + " cases");
        for (const testCase of cases) {
            const split = testCase.split === true;
            const lists = split ? { "sudo": testCase.rows.sudo, "polkit-1": testCase.rows.polkit } : { "sudo": testCase.rows, "polkit-1": testCase.rows };
            const snippet = PamEditRules.nixosSnippet(testCase.rows, split, _facts(testCase.machine, "sudo"));
            assert(snippet.ok, testCase.name + ": the editor makes options for it: " + JSON.stringify(snippet.refusals));
            assertEqual(snippet.text, testCase.snippet, testCase.name + ": its options are the editor's");
            for (const service of ["sudo", "polkit-1"]) {
                const facts = Object.assign(_facts(testCase.machine, service), { otherService: lists[PamRuleRules.otherService(service)] });
                const lines = PamEditRules.blockLines(lists[service], facts).map(line => normalized(line));
                assertEqual(JSON.stringify(lines), JSON.stringify(testCase.lines[service] ?? null),
                            testCase.name + ": " + service + "'s lines are the editor's");
            }
        }
        const written = cases.reduce((all, testCase) => all.concat(testCase.lines.sudo ?? [], testCase.lines["polkit-1"] ?? []), []);
        for (const module of ["pam_fprintd.so", "pam_u2f.so", "pam_faillock.so", "pam_permit.so", "pam_deny.so", "pam_env.so"])
            assert(written.some(line => line.split(" ")[2] === module), "(the cases write a " + module + " line)");
    }
}
