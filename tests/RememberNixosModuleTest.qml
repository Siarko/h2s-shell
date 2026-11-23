import QtQuick
import Quickshell.Io
import qs.singletons

// The NixOS module's remembered administrator authorization (nix/remember.nix) against
// RememberRules, from their text: the minutes' range and default are the setting's, the
// option is the one RememberRules.nixLine names. And the case set tests/system/nixos/remember.sh
// evaluates on NixOS (tests/fixtures/remember-nixos/cases.json): each case's rules are
// RememberRules.ruleText's for its users with the timeout from the case's coreutils (one per
// user, a user named twice once), its conf confText's above polkit's own length and none
// otherwise, and a rules file holding a case's rules reads back as the shell's own for each user.
TestCase {
    suiteName: "RememberNixosModule"

    property var _module: FileView {
        path: Qt.resolvedUrl("../nix/remember.nix")
        blockLoading: true
    }
    property var _cases: FileView {
        path: Qt.resolvedUrl("fixtures/remember-nixos/cases.json")
        blockLoading: true
    }

    function _nixInt(text, name) {
        const match = new RegExp("\\n  " + name + " = (\\d+);").exec(text);
        return match ? Number(match[1]) : null;
    }

    function run() {
        const text = _module.text();
        assert(text.length > 0, "nix/remember.nix is read");

        // --- the module's names and ranges are the shell's ---
        const setting = SettingsSchema.entry("system.rememberAdminMinutes");
        assertEqual(_nixInt(text, "minMinutes"), setting?.min, "the minutes' lowest is the setting's");
        assertEqual(_nixInt(text, "maxMinutes"), setting?.max, "the minutes' highest is the setting's");
        assertEqual(_nixInt(text, "defaultMinutes"), RememberRules.defaultSeconds / 60, "polkit's own length is RememberRules'");
        assertEqual(_nixInt(text, "defaultMinutes"), setting?.default, "the minutes' default is the setting's");
        const line = RememberRules.nixLine("alex", 15);
        const option = line.slice(0, line.indexOf(" = {"));
        assert(option !== "" && text.includes("options." + option + " = {"), "the module declares the option nixLine names: " + option);
        for (const name of ["enable", "users", "minutes"])
            assert(line.includes("\n  " + name + " = ") && text.includes("\n    " + name + " = "), "nixLine and the module both have " + name);

        // --- the case set ---
        let fixture = null;
        try {
            fixture = JSON.parse(_cases.text());
        } catch (error) {
            fail("tests/fixtures/remember-nixos/cases.json does not parse: " + error);
            return;
        }
        const facts = user => ({ system: "nixos", user, timeout: fixture.coreutils + "/bin/timeout", program: fixture.coreutils + "/bin/coreutils" });
        assert(fixture.cases.length >= 5, "the case set is read: " + fixture.cases.length + " cases");
        for (const testCase of fixture.cases) {
            const users = testCase.users.filter((user, index) => testCase.users.indexOf(user) === index);
            for (const user of users)
                assert(RememberRules.validUser(user), testCase.name + ": " + user + " is a user name to RememberRules");
            assertEqual(JSON.stringify(testCase.rules), JSON.stringify(users.map(user => RememberRules.ruleText(facts(user)))),
                        testCase.name + ": its rules are RememberRules'");
            assertEqual(testCase.conf, testCase.minutes * 60 > RememberRules.defaultSeconds ? RememberRules.confText(testCase.minutes * 60) : "",
                        testCase.name + ": its conf is RememberRules'");
            // As NixOS writes it: its own admin rule, then security.polkit.extraConfig
            const file = "polkit.addAdminRule(function(action, subject) {\n  return [\"unix-group:wheel\"];\n});\n\n"
                + testCase.rules.join("") + "\n";
            for (const user of users)
                assertEqual(RememberRules.state({ rule: file, confs: {} }, facts(user)).rule, "ours",
                            testCase.name + ": the rules file reads back as the shell's for " + user);
        }
        assert(fixture.cases.some(testCase => testCase.conf === "") && fixture.cases.some(testCase => testCase.conf !== ""),
               "(the cases have a conf and none)");
        assert(fixture.invalidUsers.length >= 5, "the refused names are read");
        for (const user of fixture.invalidUsers)
            assert(!RememberRules.validUser(user), JSON.stringify(user) + " is no user name to RememberRules either");
    }
}
