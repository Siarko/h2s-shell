import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.io

// Which distribution the shell runs on (DistributionRules): os-release's parsing, which
// os-release file counts, the distribution.json schema, and detection from the fixture
// os-release files (tests/fixtures/distribution/: Arch, NixOS, EndeavourOS — an ID_LIKE
// match —, Fedora and Linux Mint — systems the shell has no distribution for). Then the
// shipped distributions/*/distribution.json: each valid, and each fact equal to the value
// the code uses today where the code keeps it in a rule.
TestCase {
    id: suite
    suiteName: "DistributionRules"

    readonly property var rules: DistributionRules

    property Component _rememberReader: Component {
        RememberedAdminReader {}
    }

    property FileView _file: FileView {
        blockAllReads: true
        printErrors: false
    }

    function _read(relative) {
        _file.path = Quickshell.shellDir + "/" + relative;
        _file.reload();
        const text = _file.text();
        _file.path = "";
        return text;
    }

    function _shipped() {
        const texts = {};
        for (const id of rules.ids)
            texts[id] = _read("distributions/" + id + "/distribution.json");
        return texts;
    }

    function _osRelease(name) {
        return [{ state: "text", text: _read("tests/fixtures/distribution/" + name + ".os-release") }, { state: "absent", text: "" }];
    }

    // Every reading answered: the shipped manifests, the marker as given, os-release as given
    function _detect(osRelease, marker, override) {
        return rules.detect({ override: override ?? "", manifests: _shipped(), markers: { "/etc/NIXOS": marker ?? "absent" }, osRelease: osRelease });
    }

    function run() {
        _parsing();
        _whichFile();
        _manifests();
        _detection();
        _todaysValues();
    }

    function _parsing() {
        const values = rules.parseOsRelease("# a comment\n\nNAME=\"Some \\\"OS\\\" \\$x\"\nID='some'\nID_LIKE=\"one two\"\nVERSION_ID=1\r\n"
                                            + "lower=no\nBAD=two words\nID=again\n");
        assertEqual(values.NAME, "Some \"OS\" $x", "a double-quoted value, its escapes undone");
        assertEqual(values.ID_LIKE, "one two", "… spaces kept inside quotes");
        assertEqual(values.VERSION_ID, "1", "a bare value, a CR line end dropped");
        assertEqual(values.ID, "again", "a later assignment wins");
        assert(!("lower" in values) && !("BAD" in values), "a lower-case name and a bare value with a space: no assignment");
        assert(Object.isFrozen(values), "frozen");
        assertEqual(rules.parseOsRelease(null), null, "no text: none");
        assertEqual(rules.parseOsRelease("ID=x\n".repeat(20000)), null, "too long: none");
        const strict = rules.parseOsRelease("  ID=indented\nA=\"one \"inner\" two\"\nB=\"trailing\\\"\nC='it's'\nD=\"ok \\\"x\\\" \\\\\"\n");
        assertEqual(strict.ID, "indented", "white space before the name: ignored, as systemd does");
        assert(!("A" in strict), "an unescaped quote inside double quotes: no assignment");
        assert(!("B" in strict), "a backslash escaping the closing quote: no assignment");
        assert(!("C" in strict), "a quote inside single quotes: no assignment");
        assertEqual(strict.D, "ok \"x\" \\", "escaped quotes and a final escaped backslash: kept");
        assertEqual(rules.parseOsRelease(_read("tests/fixtures/distribution/endeavouros.os-release")).ID_LIKE, "arch",
                    "single quotes (EndeavourOS)");
    }

    function _whichFile() {
        const text = state => ({ state: state, text: state === "text" ? "ID=arch\n" : "" });
        let answer = rules.osReleaseOf([text("text"), text("text")]);
        assert(answer.answered && answer.known && answer.values.ID === "arch", "/etc/os-release there: it is read");
        answer = rules.osReleaseOf([text("absent"), text("text")]);
        assert(answer.known && answer.values.ID === "arch", "/etc/os-release not there: /usr/lib/os-release");
        answer = rules.osReleaseOf([text("failed"), text("text")]);
        assert(answer.answered && !answer.known, "/etc/os-release unreadable: unknown, the next is not taken in its place");
        answer = rules.osReleaseOf([text("absent"), text("absent")]);
        assert(answer.answered && answer.known && JSON.stringify(answer.values) === "{}", "neither there: known, without values");
        assert(!rules.osReleaseOf([text("absent"), null]).answered, "one not answered yet: not answered");
        assert(!rules.osReleaseOf(null).answered, "nothing: not answered");
        answer = rules.osReleaseOf([{ state: "text", text: "ID=x\n".repeat(20000) }, text("absent")]);
        assert(answer.answered && !answer.known, "an os-release too long: unknown");
        answer = rules.osReleaseOf([{ state: "text", text: "<html>not os-release</html>\n" }, text("absent")]);
        assert(answer.answered && !answer.known, "an os-release without one assignment: unknown");
        answer = rules.osReleaseOf([{ state: "text", text: "" }, text("absent")]);
        assert(answer.answered && !answer.known, "an empty os-release: unknown");
    }

    function _manifests() {
        const shipped = _shipped();
        for (const id of rules.ids) {
            const facts = rules.manifest(shipped[id], id);
            assert(facts !== null, id + ": distribution.json is valid");
            assert(facts !== null && Object.isFrozen(facts) && Object.isFrozen(facts.pamDirectories), id + ": frozen, its lists too");
        }
        assertEqual(rules.manifest(shipped.arch, "nixos"), null, "an id that is not the directory's: refused");
        const arch = JSON.parse(shipped.arch);
        const changed = change => {
            const copy = JSON.parse(JSON.stringify(arch));
            change(copy);
            return rules.manifest(JSON.stringify(copy), "arch");
        };
        assert(changed(() => {}) !== null, "the copy unchanged: valid");
        assertEqual(changed(copy => copy.extra = 1), null, "a key more: refused");
        assertEqual(changed(copy => delete copy.helper), null, "a key missing: refused");
        assertEqual(changed(copy => copy.helper = "download"), null, "helper neither package nor build: refused");
        assertEqual(changed(copy => copy.builtinModules = "/usr/share"), null, "builtinModules neither package nor dataHome: refused");
        assertEqual(changed(copy => copy.etcManaged = "no"), null, "etcManaged no boolean: refused");
        assertEqual(changed(copy => copy.polkitRulesInstallable = 1), null, "polkitRulesInstallable no boolean: refused");
        assertEqual(changed(copy => copy.matches = ["Arch Linux"]), null, "a match that is no os-release identifier: refused");
        assertEqual(changed(copy => copy.markers = ["etc/NIXOS"]), null, "a relative marker: refused");
        assertEqual(changed(copy => copy.programDirectories = ["/usr/../tmp"]), null, "a directory with a \"..\" part: refused");
        assertEqual(changed(copy => copy.pamDirectories = "/etc/pam.d"), null, "a list that is a text: refused");
        assertEqual(changed(copy => copy.pamModuleDirectories = ["/usr/lib/security"]), null, "a PAM module directory without its \"/\": refused");
        assertEqual(changed(copy => copy.setuidWrapperDirectory = "run/wrappers"), null, "a relative setuid directory: refused");
        assertEqual(changed(copy => copy.polkitRulesDirectory = ""), null, "no polkit directory: refused");
        assertEqual(changed(copy => copy.label = "Arch\nLinux"), null, "a label of two lines: refused");
        assertEqual(changed(copy => copy.label = ""), null, "an empty label: refused");
        assertEqual(rules.manifest("{oops", "arch"), null, "not JSON: refused");
        assertEqual(rules.manifest("[]", "arch"), null, "a list: refused");
        assertEqual(rules.manifest(undefined, "arch"), null, "no text: refused");
    }

    function _detection() {
        const expect = (answer, id, how, message) => {
            assertEqual(answer.id + "/" + answer.how, id + "/" + how, message);
            assert(answer.ready && answer.problem === "" && answer.facts !== null && answer.facts.id === id, message + ": ready, with its facts");
        };
        expect(_detect(_osRelease("arch")), "arch", "id", "Arch's os-release (ID=arch): arch");
        expect(_detect(_osRelease("nixos"), "present"), "nixos", "marker", "NixOS with /etc/NIXOS: nixos, by the marker");
        expect(_detect(_osRelease("nixos")), "nixos", "id", "NixOS's os-release without /etc/NIXOS: nixos, by ID");
        expect(_detect(_osRelease("fedora"), "present"), "nixos", "marker", "/etc/NIXOS there, whatever os-release says: nixos");
        expect(_detect(_osRelease("endeavouros")), "arch", "like", "EndeavourOS (ID_LIKE=arch): arch");
        expect(_detect(_osRelease("fedora")), "generic", "fallback", "Fedora: generic");
        expect(_detect(_osRelease("linuxmint")), "generic", "fallback", "Linux Mint (ID_LIKE=\"ubuntu debian\"): generic");
        expect(_detect([{ state: "absent" }, { state: "absent" }]), "generic", "fallback", "no os-release at all: generic");
        expect(_detect(_osRelease("arch"), "failed"), "nixos", "marker", "the marker there but unreadable, os-release says arch: nixos (it exists, as `test -e` has it)");
        expect(_detect([{ state: "absent" }, { state: "text", text: "ID=nixos\n" }]), "nixos", "id", "only /usr/lib/os-release: read");
        expect(_detect(_osRelease("nixos"), "present", "arch"), "arch", "override", "H2S_DISTRIBUTION=arch on NixOS: arch");
        expect(_detect(_osRelease("arch"), "absent", "generic"), "generic", "override", "H2S_DISTRIBUTION=generic: generic");

        // Unknown: never a default system
        const unknown = (answer, ready, message) => {
            assert(answer.ready === ready && answer.id === "" && answer.facts === null && answer.how === "", message + ": no id, no facts");
            assert(ready ? answer.problem !== "" : answer.problem === "", message + (ready ? ": the problem said" : ": no problem yet"));
        };
        unknown(_detect(_osRelease("arch"), "absent", "plan9"), true, "H2S_DISTRIBUTION naming no distribution");
        unknown(_detect([{ state: "failed" }, { state: "text", text: "ID=arch\n" }]), true, "os-release unreadable, no marker");
        expect(_detect([{ state: "failed" }, { state: "absent" }], "failed"), "nixos", "marker", "os-release and the marker unreadable: nixos, by the marker");
        unknown(_detect([{ state: "text", text: "ID=arch\n".repeat(10000) }, { state: "absent" }]), true, "an os-release too long, no marker");
        unknown(_detect([null, null]), false, "os-release not answered yet");
        unknown(rules.detect({ manifests: _shipped(), markers: {}, osRelease: _osRelease("arch") }), false, "the marker not answered yet");
        const partial = _shipped();
        delete partial.generic;
        unknown(rules.detect({ manifests: partial, markers: { "/etc/NIXOS": "absent" }, osRelease: _osRelease("arch") }), false,
                "a distribution.json not answered yet");
        const broken = Object.assign(_shipped(), { arch: "{" });
        unknown(rules.detect({ manifests: broken, markers: { "/etc/NIXOS": "absent" }, osRelease: _osRelease("fedora") }), true,
                "a distribution.json that cannot be used");
        const failed = Object.assign(_shipped(), { nixos: { failed: true } });
        unknown(rules.detect({ manifests: failed, markers: {}, osRelease: _osRelease("arch") }), true, "a distribution.json unreadable");
        unknown(rules.detect(null), false, "nothing read");
        assert(Object.isFrozen(_detect(_osRelease("arch"))), "the answer is frozen");

        // Every shipped distribution's facts, whichever this one is
        const shippedOf = answer => answer.shipped === null ? "null" : rules.ids.map(id => answer.shipped[id]?.id ?? "?").join(",");
        assertEqual(shippedOf(_detect(_osRelease("fedora"))), "nixos,arch,generic", "shipped: every distribution's facts, also on generic");
        assert(Object.isFrozen(_detect(_osRelease("arch")).shipped), "… frozen");
        assertEqual(shippedOf(_detect([{ state: "failed" }, { state: "absent" }])), "nixos,arch,generic",
                    "… also when this system cannot be told (os-release unreadable)");
        assertEqual(shippedOf(rules.detect({ manifests: _shipped(), markers: {}, osRelease: _osRelease("arch") })), "nixos,arch,generic",
                    "… once the manifests are read, before the markers have answered");
        assertEqual(shippedOf(rules.detect({ manifests: broken, markers: { "/etc/NIXOS": "absent" }, osRelease: _osRelease("arch") })), "null",
                    "… none when one cannot be used");
        assertEqual(shippedOf(rules.detect({ manifests: partial, markers: {}, osRelease: _osRelease("arch") })), "null",
                    "… none before every one has answered");
        _unions();
    }

    function _unions() {
        const shipped = {
            nixos: { list: ["/n/one", "/both"] },
            arch: { list: ["/a/one", "/both", "/a/three"] },
            generic: { list: ["/a/one"] }
        };
        assertEqual(rules.unionOf(shipped, "list").join(" "), "/n/one /a/one /both /a/three",
                    "a union: each one's first entries, then the second ones…, each once, each distribution's order kept");
        assertEqual(rules.unionOf({ arch: { list: ["/x"] }, nixos: { list: "/y" } }, "list").join(" "), "/x", "… what is no list left out");
        assertEqual(rules.unionOf(null, "list").length + rules.unionOf({}, "list").length, 0, "… none without facts");
    }

    // The facts against what the code holds in its rules today
    function _todaysValues() {
        const facts = {};
        const shipped = _shipped();
        for (const id of rules.ids)
            facts[id] = rules.manifest(shipped[id], id);
        if (rules.ids.some(id => facts[id] === null))
            return;
        const same = (actual, expected, message) => assertEqual(JSON.stringify(actual), JSON.stringify(expected), message);
        same(facts.nixos.pamDirectories, PamStackRules.nixosDirectories, "NixOS's PAM directories: PamStackRules.nixosDirectories");
        same(facts.arch.pamDirectories, [PamApplyRules.livePaths.system, PamApplyRules.livePaths.vendor],
             "Arch's PAM directories: the ones the Arch editor writes and checks (PamApplyRules.livePaths)");
        // The values the code held before they came from the facts: each system gets its own
        // part of what every system was given, and nothing else
        const before = {
            pamModules: ["/usr/lib/security/", "/lib/security/", "/usr/lib64/security/", "/lib64/security/",
                "/usr/lib/x86_64-linux-gnu/security/", "/lib/x86_64-linux-gnu/security/",
                "/usr/lib/aarch64-linux-gnu/security/", "/lib/aarch64-linux-gnu/security/"],
            nixosPamModules: ["/run/current-system/sw/lib/security/"],
            probeToolPath: "/run/current-system/sw/bin:/usr/bin:/bin",
            pkexecSearchPath: "/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin",
            vpnDirectories: ["/usr/lib/NetworkManager/VPN", "/etc/NetworkManager/VPN", "/run/current-system/sw/lib/NetworkManager/VPN"]
        };
        same(facts.arch.pamModuleDirectories, before.pamModules, "Arch's PAM module directories: the editor's list before");
        same(facts.nixos.pamModuleDirectories, before.nixosPamModules, "NixOS's: the system profile's alone, as before");
        assertEqual(ModuleRules.probeToolPath(facts.nixos), "/run/current-system/sw/bin", "NixOS's probe tools: the system profile");
        assertEqual(ModuleRules.probeToolPath(facts.arch), "/usr/bin:/bin", "Arch's: /usr/bin, /bin");
        assertEqual(ModuleRules.probeToolPath(facts.nixos) + ":" + ModuleRules.probeToolPath(facts.arch), before.probeToolPath,
                    "… together the PATH every system had before, in its order");
        assertEqual(PrivilegedRules.pkexecSearchPath(facts.nixos), "/run/wrappers/bin:/run/current-system/sw/bin",
                    "NixOS's pkexec search path: the setuid wrappers, then the system profile");
        assertEqual(PrivilegedRules.pkexecSearchPath(facts.arch), "/usr/bin:/bin", "Arch's: /usr/bin, /bin");
        assertEqual(PrivilegedRules.pkexecSearchPath(facts.nixos) + ":" + PrivilegedRules.pkexecSearchPath(facts.arch), before.pkexecSearchPath,
                    "… together the search path every system had before, in its order");
        assertEqual(PrivilegedRules.pkexecSearchPath(null), "", "the distribution not known: no search path, never another system's");
        const vpn = rules.unionOf(facts, "networkManagerVpnDirectories");
        assert(vpn.length === before.vpnDirectories.length && before.vpnDirectories.every(dir => vpn.includes(dir))
               && vpn.indexOf("/usr/lib/NetworkManager/VPN") < vpn.indexOf("/etc/NetworkManager/VPN"),
               "VPN plugins: every system still reads every shipped distribution's directories, Arch's before /etc as before: " + vpn.join(" "));
        assertEqual(facts.arch.polkitRulesDirectory + "/40-h2s-shell.rules", RememberRules.rulePath,
                    "Arch's polkit rules directory: where RememberRules installs its rule");
        assert(facts.arch.polkitRulesInstallable && !facts.nixos.polkitRulesInstallable, "polkit rules installed on Arch, not on NixOS");
        const reader = _rememberReader.createObject(suite);
        assertEqual(facts.nixos.polkitRulesDirectory + "/10-nixos.rules", reader.nixosRulePath,
                    "NixOS's polkit rules directory: where RememberedAdminReader reads NixOS's rule");
        reader.destroy();
        const packageText = _read("nix/package.nix");
        const launcherText = _read("scripts/launch.sh");
        assert(/export H2S_SHELL_LIBEXEC=/.test(packageText) && /export H2S_SHELL_BUILTIN_MODULES="\$out\/share\//.test(packageText),
               "the NixOS package hands over its helper and its built-in modules (nix/package.nix)");
        assert(launcherText.includes('export H2S_SHELL_BUILTIN_MODULES="${XDG_DATA_HOME:-$HOME/.local/share}/h2s-shell/builtin"')
               && launcherText.includes("build-helper.sh"),
               "without the package, the launcher takes the data home's built-in modules and builds the helper (scripts/launch.sh)");
        same(facts.nixos.markers, ["/etc/NIXOS"], "NixOS's marker: /etc/NIXOS, as the code tests it");
        assert(facts.nixos.etcManaged && !facts.arch.etcManaged && !facts.generic.etcManaged, "/etc generated on NixOS only");
        assertEqual([facts.nixos.helper, facts.arch.helper, facts.generic.helper].join(","), "package,build,build",
                    "the helper: the package's on NixOS, built elsewhere (nix/package.nix, launch.sh)");
        assertEqual([facts.nixos.builtinModules, facts.arch.builtinModules, facts.generic.builtinModules].join(","), "package,dataHome,dataHome",
                    "the built-in modules: the package's on NixOS, the data home's copy elsewhere (launch.sh)");
        // A system the shell has no distribution for gets today's answers for "not NixOS"
        const withoutNames = record => Object.assign({}, record, { id: "", label: "", matches: [] });
        same(withoutNames(facts.generic), withoutNames(facts.arch), "generic: Arch's facts (what a system that is not NixOS gets today)");
        assertEqual(facts.generic.matches.length + facts.generic.markers.length, 0, "generic matches nothing: it is the fallback");
    }
}
