import QtQuick
import Quickshell.Io
import qs.api
import qs.singletons
import qs.singletons.network

// The module system's rules (singletons/ModuleRules.qml and the four Module…Rules files
// beside it): the manifest, API compatibility, namespaces, the import check, search-path
// precedence, the state model, merging — on realistic and on hostile manifests. Nothing here
// may throw.
TestCase {
    id: rulesSuite
    suiteName: "ModuleRules"

    property var _changelog: FileView {
        path: Qt.resolvedUrl("../CHANGELOG.md")
        blockLoading: true
    }

    // The newest "- 1.x:" line under the first "### Module API" of a changelog's text, "" for
    // none
    function _newestApiLine(text) {
        const start = String(text).indexOf("\n### Module API\n");
        if (start < 0)
            return "";
        const section = String(text).slice(start + 1).split(/\n##+ /)[0];
        return /^- (\d+\.\d+):/m.exec(section)?.[1] ?? "";
    }

    // A probe's lines for one match of `name`: `path`, the links met ({ physical path:
    // target }), a stat line for each { path: "uid mode [gid]" } given, run by `user`
    // ("<uid>\t<gid> <gid>…") — stand-in paths, nothing on disk
    function _probeLines(name, path, links, stats, user) {
        const lines = ["user\t" + (user ?? "1000\t1000 100"), "cand\t" + name + "\t" + path];
        for (const linkPath of Object.keys(links))
            lines.push("link\t" + name + "\t" + linkPath + "\t" + links[linkPath]);
        for (const statPath of Object.keys(stats)) {
            const [uid, mode, gid] = stats[statPath].split(" ");
            lines.push("stat\t" + name + "\t" + uid + "\t" + mode + "\t" + (gid ?? "0") + "\t" + statPath);
        }
        return lines;
    }

    function _verdictOf(lines, name) {
        return ModuleRules.programVerdicts(lines, [name])[name];
    }

    // Program lookup with trust (API 1.9): the path walked as the kernel resolves it, every
    // directory passed and each link's own directory, the real file, the setuid wrapper, the
    // store (multi-user and single-user), on NixOS's and Arch's layouts and on bad ones
    function _programTrust() {
        const rules = ModuleRules;
        assert(rules.statTrusted({ uid: "0", mode: "755" }) && rules.statTrusted({ uid: "0", mode: "4511" }) && rules.statTrusted({ uid: "0", mode: "555" }),
               "stat: root's, 755, a setuid 4511, 555 — trusted");
        assert(!rules.statTrusted({ uid: "0", mode: "775" }) && !rules.statTrusted({ uid: "0", mode: "757" }) && !rules.statTrusted({ uid: "0", mode: "1777" })
               && !rules.statTrusted({ uid: "1000", mode: "755" }) && !rules.statTrusted({ uid: "0", mode: "9" }) && !rules.statTrusted(null),
               "stat: group- or other-writable (sticky too), not root's, a mode that is no octal number — untrusted");
        const walk = rules.programWalk("/bin/../usr/bin/x", { "/usr/bin/x": "../lib/x/x" });
        assertEqual(walk.real + " " + walk.visited.join(","), "/usr/lib/x/x /,/bin,/usr,/usr/bin,/usr/lib,/usr/lib/x,/usr/lib/x/x",
                    "walk: \"..\" and a relative link resolved as the kernel does, every physical directory passed");

        // The probe's own tools never come from the PATH it judges
        const toolDirs = rules.probeToolPath.split(":");
        assert(toolDirs.includes("/run/current-system/sw/bin") && toolDirs.includes("/usr/bin") && toolDirs.every(dir => dir.startsWith("/") && !dir.startsWith("/home")),
               "the probe's PATH: the system's directories, NixOS's and Arch's: " + rules.probeToolPath);
        assertEqual(rules.probeShell, "/bin/sh", "… and its shell by absolute path");
        assert(rules.programProbeScript.includes("searched=$2") && rules.programProbeScript.includes("for d in $searched"),
               "… the PATH searched is an argument, not the probe's own");

        // Arch: root's files in /usr/bin; /bin a link to usr/bin
        const archStats = { "/": "0 755", "/usr": "0 755", "/usr/bin": "0 755", "/usr/bin/timeout": "0 755" };
        const arch = _verdictOf(_probeLines("timeout", "/usr/bin/timeout", {}, archStats), "timeout");
        assert(arch.trusted && arch.path === "/usr/bin/timeout" && arch.owner === "0" && arch.mode === "755", "Arch: /usr/bin/timeout trusted: " + JSON.stringify(arch));
        const binLink = _verdictOf(_probeLines("timeout", "/bin/timeout", { "/bin": "usr/bin" }, archStats), "timeout");
        assert(binLink.trusted && binLink.path === "/bin/timeout" && binLink.real === "/usr/bin/timeout", "Arch: through the /bin link, by the path found");
        assert(_verdictOf(_probeLines("sh", "/usr/bin/sh", { "/usr/bin/sh": "bash" }, { "/": "0 755", "/usr": "0 755", "/usr/bin": "0 755", "/usr/bin/bash": "0 755" }), "sh").trusted,
               "Arch: sh, a link to bash beside it: trusted");

        // NixOS, a multi-user store: /nix/store root's, group nixbld (not the user's)
        const nixLinks = { "/run/current-system": "/nix/store/aaa-system", "/nix/store/aaa-system/sw": "/nix/store/bbb-path",
                           "/nix/store/bbb-path/bin/timeout": "/nix/store/ccc-coreutils/bin/coreutils" };
        const nixStats = { "/": "0 755", "/run": "0 755", "/nix": "0 755", "/nix/store": "0 1775 30000" };
        const nixos = _verdictOf(_probeLines("timeout", "/run/current-system/sw/bin/timeout", nixLinks, nixStats), "timeout");
        assert(nixos.trusted && nixos.reason === "in the Nix store" && nixos.real === "/nix/store/ccc-coreutils/bin/coreutils",
               "NixOS: the system profile's timeout, links into the store: trusted: " + JSON.stringify(nixos));
        const nixNoRun = Object.assign({}, nixStats);
        delete nixNoRun["/run"];
        assertEqual(_verdictOf(_probeLines("timeout", "/run/current-system/sw/bin/timeout", nixLinks, nixNoRun), "timeout").reason, "could not be checked: /run",
                    "NixOS: the directory holding the profile's link not read: untrusted");
        // A single-user store: the user owns it, so the store is judged like any path
        const single = Object.assign({}, nixStats, { "/nix/store": "1000 755 100", "/nix/store/aaa-system": "1000 555 100", "/nix/store/bbb-path": "1000 555 100",
                                                      "/nix/store/bbb-path/bin": "1000 555 100", "/nix/store/ccc-coreutils": "1000 555 100",
                                                      "/nix/store/ccc-coreutils/bin": "1000 555 100", "/nix/store/ccc-coreutils/bin/coreutils": "1000 555 100" });
        assertEqual(_verdictOf(_probeLines("timeout", "/run/current-system/sw/bin/timeout", nixLinks, single), "timeout").reason, "others than root can change /nix/store",
                    "a single-user store (the user's): untrusted");
        const singleUnread = Object.assign({}, nixStats, { "/nix/store": "1000 755 100" });
        assert(!_verdictOf(_probeLines("timeout", "/nix/store/ccc-coreutils/bin/coreutils", {}, singleUnread), "timeout").trusted,
               "… a store path straight on PATH, the store the user's: untrusted");
        assert(!_verdictOf(_probeLines("timeout", "/run/current-system/sw/bin/timeout", nixLinks, nixStats, "1000\t1000 30000"), "timeout").trusted,
               "a store whose group (it may write) is one of the user's: untrusted");
        assert(!_verdictOf(_probeLines("timeout", "/run/current-system/sw/bin/timeout", nixLinks, Object.assign({}, nixStats, { "/nix/store": "0 1777 30000" })), "timeout").trusted,
               "a store anyone may write to: untrusted");
        assert(!rules.storeTrusted({ uid: "0", mode: "1775", gid: "30000" }, null) && rules.storeTrusted({ uid: "0", mode: "1775", gid: "30000" }, { uid: "1000", groups: ["1000"] })
               && rules.storeTrusted({ uid: "0", mode: "755", gid: "0" }, null), "store: a group that may write counts only when the user's groups are known and lack it");
        // The user's profile: ~/.nix-profile leads into the store, but the link lives in a
        // directory the user owns and can be repointed
        const home = _verdictOf(_probeLines("timeout", "/home/u/.nix-profile/bin/timeout", { "/home/u/.nix-profile": "/nix/store/ddd-profile" },
            Object.assign({ "/home": "0 755", "/home/u": "1000 700" }, nixStats)), "timeout");
        assertEqual(home.reason, "others than root can change /home/u", "NixOS: ~/.nix-profile's timeout: untrusted, the user's directory named");
        assert(!rules.programInStore("/nix/store/../home/u/x") && rules.programInStore("/nix/store/a/b"), "a store path that leaves it by \"..\" is no store path");

        // The setuid wrapper (NixOS): /run/wrappers/bin leads to the wrappers' directory, where
        // pkexec is a setuid file of root's
        const wrapperLinks = { "/run/wrappers/bin": "/run/wrappers/wrappers.x" };
        const wrapperStats = { "/": "0 755", "/run": "0 755", "/run/wrappers": "0 755", "/run/wrappers/wrappers.x": "0 755", "/run/wrappers/wrappers.x/pkexec": "0 4511" };
        const wrapper = _verdictOf(_probeLines("pkexec", "/run/wrappers/bin/pkexec", wrapperLinks, wrapperStats), "pkexec");
        assert(wrapper.trusted && wrapper.path === "/run/wrappers/bin/pkexec" && wrapper.mode === "4511", "NixOS: the setuid wrapper of pkexec: trusted: " + JSON.stringify(wrapper));
        assert(!_verdictOf(_probeLines("pkexec", "/run/wrappers/bin/pkexec", wrapperLinks, Object.assign({}, wrapperStats, { "/run/wrappers/wrappers.x/pkexec": "1000 4755" })), "pkexec").trusted,
               "a setuid file that is not root's: untrusted");
        assert(_verdictOf(_probeLines("pkexec", "/usr/bin/pkexec", {}, { "/": "0 755", "/usr": "0 755", "/usr/bin": "0 755", "/usr/bin/pkexec": "0 4755" }), "pkexec").trusted,
               "Arch: the setuid /usr/bin/pkexec: trusted");

        // Every directory passed, each link's own directory, the real file
        const local = { "/": "0 755", "/home": "0 755", "/home/u": "1000 700", "/home/u/.local": "1000 755", "/home/u/.local/bin": "1000 755",
                        "/home/u/.local/bin/tailscale": "1000 755" };
        const userOwned = _verdictOf(_probeLines("tailscale", "/home/u/.local/bin/tailscale", {}, local), "tailscale");
        assert(!userOwned.trusted && userOwned.path === "/home/u/.local/bin/tailscale", "a program in a directory the user owns: untrusted, its path kept");
        assertEqual(_verdictOf(_probeLines("x", "/opt/a/bin/x", {}, { "/": "0 755", "/opt": "0 755", "/opt/a": "1000 755", "/opt/a/bin": "0 755", "/opt/a/bin/x": "0 755" }), "x").reason,
                    "others than root can change /opt/a", "a directory two above the program, the user's: untrusted, named");
        // A directory link partway: root's /opt/app → ~/link → /usr/lib/app; every directory
        // the name leads to is root's, but the user can repoint ~/link
        const partway = { "/": "0 755", "/opt": "0 755", "/home": "0 755", "/home/u": "1000 700", "/usr": "0 755", "/usr/lib": "0 755",
                          "/usr/lib/app": "0 755", "/usr/lib/app/bin": "0 755", "/usr/lib/app/bin/x": "0 755" };
        assertEqual(_verdictOf(_probeLines("x", "/opt/app/bin/x", { "/opt/app": "/home/u/link", "/home/u/link": "/usr/lib/app" }, partway), "x").reason,
                    "others than root can change /home/u", "a directory link partway through a directory the user owns: untrusted, that directory named");
        const altStats = { "/": "0 755", "/usr": "0 755", "/usr/bin": "0 755", "/usr/bin/vim": "0 755", "/etc": "0 755", "/etc/alternatives": "1000 755" };
        const altLinks = { "/usr/bin/editor": "/etc/alternatives/editor", "/etc/alternatives/editor": "/usr/bin/vim" };
        assertEqual(_verdictOf(_probeLines("editor", "/usr/bin/editor", altLinks, altStats), "editor").reason, "others than root can change /etc/alternatives",
                    "a link on the way in a directory the user owns: untrusted, though both ends are root's");
        altStats["/etc/alternatives"] = "0 755";
        assert(_verdictOf(_probeLines("editor", "/usr/bin/editor", altLinks, altStats), "editor").trusted, "… and trusted where that directory is root's");
        assert(!_verdictOf(_probeLines("timeout", "/usr/bin/timeout", {}, Object.assign({}, archStats, { "/usr/bin/timeout": "0 775" })), "timeout").trusted,
               "the real file group-writable: untrusted");
        assert(!_verdictOf(_probeLines("x", "/tmp/x", {}, { "/": "0 755", "/tmp": "0 1777", "/tmp/x": "0 755" }), "x").trusted, "a root file in /tmp (1777): untrusted");

        // A read that failed, or a forged one, is untrusted, never trusted
        const noStat = Object.assign({}, archStats);
        delete noStat["/usr/bin/timeout"];
        assertEqual(_verdictOf(_probeLines("timeout", "/usr/bin/timeout", {}, noStat), "timeout").reason, "could not be checked: /usr/bin/timeout",
                    "the real file's stat missing: untrusted, could not be checked");
        assert(!_verdictOf(_probeLines("x", "/usr/bin/x", { "/usr/bin/x": "y", "/usr/bin/y": "x" }, archStats), "x").trusted, "links in a loop: untrusted");
        const twice = _probeLines("timeout", "/usr/bin/timeout", {}, Object.assign({}, archStats, { "/usr/bin": "1000 755" }))
            .concat(["stat\ttimeout\t0\t755\t0\t/usr/bin"]);
        assertEqual(_verdictOf(twice, "timeout").reason, "two answers for /usr/bin", "two different stats for one path (a forged line): untrusted");
        assertEqual(_verdictOf(_probeLines("x", "/usr/bin/x", {}, archStats).concat(["bad\tx"]), "x").reason, "a name on the way holds a line break or a tab",
                    "a link's target with a line break or a tab (the probe says bad): untrusted");
        const badPath = rules.programVerdicts(["cand\tx\t-", "bad\tx"], ["x"]).x;
        assert(badPath.path === "" && !badPath.trusted && badPath.reason.includes("line break"), "a path found that holds a line break: no path, untrusted");
        assert(rules.programProbeScript.includes("*\"$nl\"*|*\"$tab\"*"), "the probe refuses names with a line break or a tab");

        // Parsing: not found, not answered, the first of several, hostile lines
        const notFound = rules.programVerdicts(["cand\tnope\t"], ["nope", "other"]);
        assert(notFound.nope.path === "" && !notFound.nope.trusted && notFound.nope.reason === "not found", "a name the probe found nowhere: path \"\", not found");
        assertEqual(notFound.other, undefined, "a name the probe did not get to: no verdict (the host decides)");
        const two = _probeLines("timeout", "/home/u/bin/timeout", {}, { "/": "0 755", "/home": "0 755", "/home/u": "1000 700", "/home/u/bin": "1000 755", "/home/u/bin/timeout": "1000 755" })
            .concat(_probeLines("timeout", "/usr/bin/timeout", {}, archStats).slice(1));
        assertEqual(_verdictOf(two, "timeout").path, "/home/u/bin/timeout", "with \"first\": the first on PATH is judged, untrusted or not");
        assertEqual(JSON.stringify(rules.trustedPrograms(two, "timeout")), "[\"/usr/bin/timeout\"]", "with \"all\": the trusted ones, in PATH order");
        for (const hostile of [null, undefined, 5, "cand\tx\t/x", [null, 7, "cand\t__proto__\t/x", "stat\tx\t0"], ["cand\tx\t/a\u0001b"]])
            assert(typeof rules.programVerdicts(hostile, ["x", "__proto__"]) === "object", "hostile probe output " + JSON.stringify(hostile) + ": an answer, no throw");
        assertEqual(rules.programVerdicts(["cand\tx\t/a\u0001b"], ["x"]).x.path, "", "a path with a control character: not found");
        assertEqual(rules.programVerdicts(["cand\tx\tbin/x"], ["x"]).x.path, "", "a relative path printed: not found");
        assertEqual(rules.programVerdicts(_probeLines("timeout", "/usr/bin/timeout", {}, noStat).concat(["stat\ttimeout\t0\t755\t0\t/usr/bin/timeout\textra"]),
                                          ["timeout"]).timeout.trusted, false, "a stat line with a tab in its path is no stat line");
        assertEqual(rules.programProbeScript.indexOf("command -v"), -1, "the probe looks for files, not shell builtins");

        // A module's rechecks: at most every recheckMinMs
        assertEqual(rules.recheckDelay(0, 5000, 2000), 0, "recheck: never looked: now");
        assertEqual(rules.recheckDelay(4000, 5000, 2000), 1000, "recheck: 1 s after the last: in 1 s");
        assertEqual(rules.recheckDelay(1000, 5000, 2000), 0, "recheck: 4 s after: now");
        assertEqual(rules.recheckDelay(9000, 5000, 2000), 0, "recheck: a clock that went back: now");
        assertEqual(rules.recheckMinMs, 2000, "recheck: every 2 s at most");
    }

    // Module test mode (API 1.10): where programs come from, the stand-ins' verdicts, the
    // manifest's testPrograms, and the guard that keeps a module's commands from any pkexec
    // but a module's stand-in
    function _testMode() {
        const rules = ModuleRules;
        assertEqual(rules.programSource(true, "tests/programs"), "test", "source: test mode and a testPrograms directory — the stand-ins");
        assertEqual(rules.programSource(false, "tests/programs"), "path", "… test mode off: testPrograms ignored, PATH");
        assertEqual(rules.programSource(true, ""), "path", "… test mode without testPrograms: PATH");
        assertEqual(rules.programSource("true", "x") + rules.programSource(1, "x") + rules.programSource(true, null), "pathpathpath",
                    "… only test mode that is `true`, and only a directory given");
        assertEqual(rules.testProgramsDirectory("/m/good/", "tests/programs/"), "/m/good/tests/programs", "the stand-ins' directory");
        assertEqual(rules.testProgramsDirectory("relative", "x") + rules.testProgramsDirectory("/m", ""), "", "… none for a relative module directory or no testPrograms");
        assertEqual(JSON.stringify(rules.testStandIns([{ directory: "/m/a", testPrograms: "bin" }, { directory: "/m/b", testPrograms: "" }, null])),
                    "[\"/m/a/bin/pkexec\"]", "testStandIns: one per module that names testPrograms");

        const verdicts = rules.testProgramVerdicts(["ok\ttool", "no\tsh", "ok\tother", "garbage", "ok\ttool\textra", "no\ttool"], ["tool", "sh", "absent"], "/m/a/bin");
        assertEqual(JSON.stringify(verdicts.tool), JSON.stringify({ path: "/m/a/bin/tool", real: "/m/a/bin/tool", trusted: true, reason: "test stand-in", owner: "", mode: "" }),
                    "a stand-in there: its path, trusted, \"test stand-in\"");
        assertEqual(verdicts.sh.path + "|" + verdicts.sh.trusted + "|" + verdicts.sh.reason, "|false|no stand-in", "one not there: not found, untrusted");
        assert(!("other" in verdicts) && !("absent" in verdicts), "a name not asked for is dropped; one not answered has no verdict");
        assert(Object.isFrozen(verdicts.tool), "… frozen");
        assertEqual(rules.testProgramVerdicts(["ok\ttool"], ["tool"], "relative").tool.path, "", "a relative directory: nothing found");
        assertEqual(JSON.stringify(rules.testProgramVerdicts(null, null, null)), "{}", "nothing given: nothing, no throw");

        const standIns = ["/m/a/bin/pkexec"];
        assertEqual(rules.testRunProblem(["pkexec", "true"], false, []), "", "runs off test mode: as asked");
        assert(rules.testRunProblem(["pkexec", "true"], true, standIns).startsWith("test mode:"), "test mode: pkexec by name refused (whatever PATH holds)");
        assert(rules.testRunProblem(["/usr/bin/pkexec"], true, standIns) !== "" && rules.testRunProblem(["/run/wrappers/bin/pkexec"], true, standIns) !== "",
               "… by its system paths too");
        assert(rules.testRunProblem(["/m/b/bin/pkexec"], true, standIns) !== "", "… and a pkexec that is not a module's stand-in");
        assertEqual(rules.testRunProblem(["/m/a/bin/pkexec", "/bin/true"], true, standIns), "", "a module's stand-in pkexec runs");
        assertEqual(rules.testRunProblem(["/bin/sh", "-c", "x"], true, standIns), "", "anything else runs");
        assertEqual(rules.testRunProblem(["pkexec-helper"], true, []), "", "… a name that only starts with pkexec too");
        assertEqual(rules.testRunProblem(null, true, standIns) + rules.testRunProblem([7], true, null), "", "not an argv: not this rule's to refuse (the runner does)");
        // Every word, not only the program: a pkexec handed to another program is refused too
        for (const argv of [["env", "pkexec", "true"], ["timeout", "5", "pkexec", "true"], ["setsid", "/run/wrappers/bin/pkexec", "true"],
                            ["/bin/env", "A=1", "/usr/bin/pkexec", "x"], ["sh", "/m/a/bin/pkexec", "/m/b/bin/pkexec"]])
            assert(rules.testRunProblem(argv, true, standIns).startsWith("test mode:"), "a pkexec anywhere in " + JSON.stringify(argv) + ": refused");
        assertEqual(rules.testRunProblem(["timeout", "5", "/m/a/bin/pkexec", "/bin/true"], true, standIns), "", "… a module's stand-in anywhere: runs");
        assertEqual(rules.testRunProblem(["env", "pkexec", "true"], false, []), "", "… off test mode: as asked (production unchanged)");
        assertEqual(rules.testRunProblem(["sh", "-c", "pkexec true"], true, standIns), "", "… a word inside a script is not read (a guard against mistakes)");

        assertEqual(rules.testElevateProblem(["pkexec"], false, []), "", "elevate off test mode: as set");
        assert(rules.testElevateProblem(["pkexec"], true, standIns).startsWith("test mode:"), "elevate in test mode: the default refused");
        assert(rules.testElevateProblem(["sh", "/m/a/bin/pkexec"], true, standIns) !== "", "… a stand-in handed to a shell refused: only the stand-in itself");
        assert(rules.testElevateProblem(["/m/a/bin/pkexec"], true, []) !== "" && rules.testElevateProblem(null, true, standIns) !== "",
               "… no stand-ins known, or no elevate: refused");
        assertEqual(rules.testElevateProblem(["/m/a/bin/pkexec"], true, standIns), "", "… the stand-in: runs");

        // The gate for modules written for an API below 1.10 (removed by slice Z)
        assertEqual(rules.testPkexecRule("1.10") + " " + rules.testPkexecRule("1.11") + " " + rules.testPkexecRule("2.0"), "strict strict strict",
                    "the pkexec rule: strict from 1.10 on");
        assertEqual(rules.testPkexecRule("1.9") + " " + rules.testPkexecRule("1.0"), "legacy legacy", "… below it: the gate");
        assertEqual(rules.testPkexecRule("x") + " " + rules.testPkexecRule(undefined), "strict strict", "… an API that is not major.minor: strict");
        assertEqual(rules.testCallRule(["legacy"]) + " " + rules.testCallRule(["legacy", "legacy"]), "legacy legacy", "a call only older modules make: the gate");
        assertEqual(rules.testCallRule([]) + " " + rules.testCallRule(["legacy", "strict"]) + " " + rules.testCallRule(null), "strict strict strict",
                    "… none seen, or a 1.10 module taking part: strict");
        const stack = "run@qs:@/qs/api/PrivilegedAction.qml:60\n"
            + "send@file:///m/old/Client.qml:12\n"
            + "@file:///m/old/tests/OldTest.qml:40:7\n"
            + "helper@file:///m/new%20one/Helper.qml:3\n"
            + "expression for onTriggered@qs:@/qs/tests-modules.qml:117\n"
            + "garbage line\n"
            + "x@file:///elsewhere/File.qml:1";
        assertEqual(JSON.stringify(rules.stackDirectories(stack, ["/m/old", "/m/new one", "/m/unused"])), JSON.stringify(["/m/old", "/m/new one"]),
                    "stackDirectories: the modules whose files are on the stack, innermost first, each once; the shell's files and others not");
        assertEqual(JSON.stringify(rules.stackDirectories(null, ["/m/old"])) + JSON.stringify(rules.stackDirectories(stack, null)), "[][]", "… nothing given: nothing");
        assertEqual(rules.testElevateProblem(["/anywhere/stand-in/pkexec"], true, [], "legacy"), "", "elevate under the gate: any absolute path, checked next");
        assert(rules.testElevateProblem(["pkexec"], true, standIns, "legacy").startsWith("test mode:"), "… pkexec by name: refused");
        assert(rules.testElevateProblem(null, true, standIns, "legacy") !== "" && rules.testElevateProblem(["relative/pkexec"], true, [], "legacy") !== "",
               "… no elevate, or a relative path: refused");
        assert(rules.testElevateProblem(["/anywhere/stand-in/pkexec"], true, standIns, "strict") !== "", "… the same path under the strict rule: refused");
        assertEqual(rules.testElevateVerdict(true, ["stand-in"]), "", "the elevate probe: \"stand-in\" runs");
        assert(rules.testElevateVerdict(true, ["real"]).includes("real pkexec"), "… \"real\": refused");
        for (const [ok, lines] of [[true, ["unknown"]], [false, ["stand-in"]], [true, []], [true, ["stand-in", "stand-in"]], [true, ["stand-in "]], [true, null]])
            assert(rules.testElevateVerdict(ok, lines).startsWith("test mode:"), "… anything else (" + ok + ", " + JSON.stringify(lines) + ") counts as real: refused");
        assert(rules.systemPkexecPaths.includes("/run/wrappers/bin/pkexec") && rules.systemPkexecPaths.includes("/usr/bin/pkexec"),
               "the system's pkexec: NixOS's wrapper and Arch's");
        assertEqual(rules.testGateDeprecations(true, "1.9").length, 1, "the gate in a 1.9 module's deprecations, in test mode");
        assert(rules.testGateDeprecations(true, "1.3")[0].includes("will be removed"), "… saying it will be removed");
        assertEqual(rules.testGateDeprecations(false, "1.9").length + rules.testGateDeprecations(true, "1.10").length, 0, "… not off test mode, not for 1.10");

        assertEqual(rules.missingProgramText("x", "path", "", 0), "needs the program x, which is not on PATH", "missing: on PATH");
        assertEqual(rules.missingProgramText("x", "path", "", 5), "needs the program x, which is not on PATH (the look-up did not answer within 5 s)", "… timed out");
        assertEqual(rules.missingProgramText("x", "test", "stand-ins", 0), "needs the program x, which has no stand-in in stand-ins", "… in test mode");

        // The manifest's testPrograms
        assertEqual(ModuleManifestRules.parseManifest(_manifest({ testPrograms: "tests/programs/" })).testPrograms, "tests/programs", "testPrograms: a directory inside, the trailing / dropped");
        assertEqual(ModuleManifestRules.parseManifest(_manifest()).testPrograms, "", "… none: \"\"");
        for (const bad of ["../x", "/abs", "a/../b", "", "a b", 5, ".", "a//b"]) {
            const parsed = ModuleManifestRules.parseManifest(_manifest({ testPrograms: bad }));
            assert(parsed.testPrograms === "" && _has(parsed.errors, "testPrograms") && parsed.valid, "testPrograms " + JSON.stringify(bad) + ": ignored, with an error; the module still valid");
        }
        assertEqual(ModuleManifestRules.parseManifest(_manifest({ testPrograms: "bin" })).warnings.length, 0, "… a known field, no warning");
        assertEqual(ModuleFileRules.directoryProblem("tests/programs"), "", "directoryProblem: a plain relative directory");
    }

    function _manifest(fields) {
        return JSON.stringify(Object.assign({ id: "tailscale", name: "Tailscale", version: "0.1.0", api: "1.0" }, fields ?? {}));
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }

    function run() {
        const rules = ModuleRules;

        // --- the API version ---
        assertEqual(_newestApiLine("# C\n\n### Module API\nText\n- 1.7: b\n- 1.6: a\n\n### Added\n- 2.0: no\n"), "1.7", "a changelog's newest API line is the first under \"Module API\"");
        assertEqual(_newestApiLine("# C\n\n### Module API\nText\n\n### Added\n- 2.0: no\n"), "", "… none there: none, not a line of another section");
        assertEqual(Api.version, _newestApiLine(_changelog.text()), "the module API's version is the newest \"- 1.x:\" line under \"Module API\" in CHANGELOG.md");
        assert(rules.parseApi(Api.version) !== null, "the shell's API version is major.minor");
        assert(rules.apiCompatibility("1.0", "1.0").compatible, "same version: compatible");
        assert(rules.apiCompatibility("1.0", "1.3").compatible, "an older minor on a newer shell: compatible");
        assert(!rules.apiCompatibility("1.4", "1.3").compatible, "a newer minor than the shell's: not");
        assert(_has([rules.apiCompatibility("1.4", "1.3").reason], "newer shell"), "… and it says a newer shell is needed");
        assert(!rules.apiCompatibility("2.0", "1.9").compatible, "another major (newer): not");
        assert(!rules.apiCompatibility("0.9", "1.0").compatible, "another major (older): not");
        assert(_has([rules.apiCompatibility("0.9", "1.0").reason], "needs updating"), "… the module needs updating");
        for (const bad of ["1", "1.0.0", "v1.0", " 1.0", "1.0 ", "01.0", "1.-1", "", null, undefined, 1.0, {}, [], "1.0\n"])
            assert(!rules.apiCompatibility(bad, "1.0").compatible, "not major.minor: incompatible — " + JSON.stringify(bad));
        assert(rules.parseApi("10.25").major === 10 && rules.parseApi("10.25").minor === 25, "two-digit parts");

        // --- the floor: the oldest API version whose modules still run unchanged ---
        const floor = rules.parseApi(rules.apiFloor);
        const offered = rules.parseApi(rules.apiVersion);
        assert(floor !== null && offered !== null && floor.major === offered.major && floor.minor <= offered.minor,
               "the shell's floor is major.minor, of the shell's major and not above its version");
        assert(rules.apiCompatibility(rules.apiVersion, rules.apiVersion).compatible, "a module written for this shell's version runs on it");
        assert(rules.apiCompatibility(rules.apiFloor, rules.apiVersion).compatible, "… and one written for its floor");
        assert(rules.apiCompatibility("1.26", "1.27", "1.26").compatible, "at the floor: compatible");
        assert(rules.apiCompatibility("1.27", "1.27", "1.26").compatible, "between the floor and the shell's: compatible");
        const below = rules.apiCompatibility("1.3", "1.27", "1.26");
        assert(!below.compatible, "below the floor: not");
        assertEqual(below.reason, "written for module API 1.3; this shell needs 1.26 or newer (the module needs updating)", "… and it says what the shell needs");
        assert(!rules.apiCompatibility("1.25", "1.27", "1.26").compatible, "one minor below the floor: not");
        assert(_has([rules.apiCompatibility("1.28", "1.27", "1.26").reason], "newer shell"), "above the shell's, with a floor: a newer shell is needed");
        assert(_has([rules.apiCompatibility("0.9", "1.27", "1.26").reason], "the shell has 1.27"), "another major, with a floor: the major's reason");
        // A shell of the major before the floor's, and a module of its own version: only a
        // floor keeps it out, so a call that names none fails it only by taking the shell's
        const before = (floor.major - 1) + ".5";
        const unfloored = rules.apiCompatibility(before, before);
        assert(!unfloored.compatible, "no floor given: the shell's own, which keeps out a module below it");
        assertEqual(unfloored.reason, rules.apiCompatibility(before, before, rules.apiFloor).reason, "… the same answer as naming the shell's floor");
        for (const bad of ["1", "", null, {}, "1.x", 1.0])
            assert(!rules.apiCompatibility("1.3", "1.3", bad).compatible && _has([rules.apiCompatibility("1.3", "1.3", bad).reason], "floor"),
                   "a floor that is not major.minor lets nothing through — " + JSON.stringify(bad));
        assert(!rules.apiCompatibility("1.3", "1.3", "2.0").compatible, "a floor of a later major: nothing below it runs");

        // --- a realistic manifest ---
        const tailscale = ModuleManifestRules.parseManifest(JSON.stringify({
            id: "tailscale", name: "Tailscale", version: "0.3.0-beta.1", api: "1.0",
            description: "Tailscale among the VPNs", main: "Main.qml",
            widgets: [{ type: "tailscale", name: "Tailscale", widget: "TailscaleWidget.qml",
                        popup: "tailscale", popupPanel: "TailscalePanel.qml", settings: "settings/WidgetSettings.qml" }],
            settingsPages: [{ id: "tailscale", label: "Tailscale", component: "TailscaleSettings.qml", tab: "system", parent: "network" }],
            settings: [
                { key: "mod.tailscale.showIp", label: "Show the address", type: "bool", default: true },
                { key: "mod.tailscale.poll", label: "Refresh", type: "interval", default: 5000, min: 0, max: 60000 },
                { key: "mod.tailscale.exitNodeMode", label: "Exit node", type: "enum", default: "auto",
                  options: [{ value: "auto", label: "Suggested" }, { value: "none", label: "None" }] },
                { key: "mod.tailscale.hidden", label: "Hidden devices", type: "stringList", default: [] }
            ],
            facts: [{ fact: "tailscale.connected", label: "Tailscale connected", type: "bool" },
                    { fact: "tailscale.exitNode", label: "Exit node", type: "enum", options: ["none", "mullvad"] }],
            slots: [{ slot: "network.vpn.row", component: "ExitNodeRow.qml" }],
            requires: { programs: ["tailscale"] },
            setupHints: ["Enable services.tailscale in your NixOS configuration"],
            tests: ["tests/TailscaleRulesTest.qml"]
        }));
        assert(tailscale.valid, "a realistic manifest is valid");
        assertEqual(tailscale.errors.length, 0, "… without errors: " + tailscale.errors.join("; "));
        assertEqual(tailscale.warnings.length, 0, "… without warnings");
        assertEqual(tailscale.id + " " + tailscale.version + " " + tailscale.api + " " + tailscale.main,
                    "tailscale 0.3.0-beta.1 1.0 Main.qml", "the required fields and main");
        assertEqual(tailscale.widgets.length, 1, "its widget");
        assertEqual(tailscale.widgets[0].popupPanel, "TailscalePanel.qml", "… with its popup panel");
        assertEqual(tailscale.widgets[0].multiple, false, "… multiple defaults to false");
        assertEqual(tailscale.settingsPages[0].parent, "network", "its settings page, under the network group");
        assertEqual(tailscale.settings.length, 4, "its four settings");
        assertEqual(tailscale.settings[0].group, "mod.tailscale", "a setting's group defaults to mod.<id>");
        assertEqual(tailscale.settings[2].options.length, 2, "an enum's options kept");
        assertEqual(tailscale.facts.length, 2, "its facts");
        assertEqual(tailscale.slots[0].slot, "network.vpn.row", "its slot contribution");
        assertEqual(JSON.stringify(tailscale.programs), "[\"tailscale\"]", "the programs it requires");
        assertEqual(tailscale.setupHints.length, 1, "its setup hint");
        assertEqual(tailscale.tests[0], "tests/TailscaleRulesTest.qml", "its tests");
        assertEqual(JSON.stringify(ModuleFileRules.manifestFiles(tailscale)),
                    JSON.stringify(["Main.qml", "TailscaleWidget.qml", "TailscalePanel.qml", "settings/WidgetSettings.qml",
                                    "TailscaleSettings.qml", "ExitNodeRow.qml"]),
                    "the files the import check reads: main and every component named, once");

        // A minimal one: no main, nothing else
        const minimal = ModuleManifestRules.parseManifest(_manifest());
        assert(minimal.valid && minimal.main === "" && minimal.widgets.length === 0, "only the required fields: valid, no main");

        // --- required fields ---
        for (const field of ["id", "name", "version", "api"]) {
            const object = { id: "x", name: "X", version: "1", api: "1.0" };
            delete object[field];
            const result = ModuleManifestRules.parseManifest(JSON.stringify(object));
            assert(!result.valid && _has(result.errors, "missing required field \"" + field + "\""), "missing " + field + ": invalid, said");
        }
        const wrongTypes = ModuleManifestRules.parseManifest(JSON.stringify({ id: 7, name: [], version: 3, api: 1.0, main: {} }));
        assert(!wrongTypes.valid, "every required field of the wrong type: invalid");
        assertEqual(wrongTypes.errors.length, 5, "… one error each (id, name, version, api, main)");

        // --- ids ---
        for (const good of ["tailscale", "a", "my-module", "dictation2", "x_y"])
            assert(ModuleManifestRules.validId(good) && ModuleManifestRules.parseManifest(_manifest({ id: good })).id === good, "a valid id: " + good);
        for (const bad of ["Tailscale", "1password", "-x", "my.module", "my module", "", "a".repeat(33), "ä", "x/y",
                           "__proto__", "constructor", "prototype", "hasOwnProperty", "toString"]) {
            const result = ModuleManifestRules.parseManifest(_manifest({ id: bad }));
            assert(!result.valid && result.id === "", "not a usable id: " + JSON.stringify(bad));
        }
        for (const reserved of ["lockscreen", "battery", "power", "network", "mod", "core", "api", "qs", "settings"])
            assert(_has(ModuleManifestRules.parseManifest(_manifest({ id: reserved })).errors, "reserved"), "reserved: " + reserved);
        // Every core namespace a module could collide with is reserved: the first part of every
        // core setting and fact
        const corePrefixes = [];
        for (const entry of SettingsSchema.entries ?? [])
            corePrefixes.push(String(entry.key).split(".")[0]);
        for (const type of ProfileRules.factTypes)
            corePrefixes.push(type.fact.split(".")[0]);
        const unreserved = corePrefixes.filter((prefix, index) => corePrefixes.indexOf(prefix) === index
                                               && !rules.reservedIds.includes(prefix.toLowerCase()));
        assert(corePrefixes.length > 10, "the core's settings and facts were found (" + corePrefixes.length + ")");
        assertEqual(unreserved.join(", "), "", "every core setting and fact prefix is a reserved id");

        // --- versions ---
        for (const good of ["1.0.0", "0.3.0-beta.1", "2024.11.15", "1", "1.0+git.abc"])
            assert(ModuleManifestRules.parseManifest(_manifest({ version: good })).valid, "a version: " + good);
        for (const bad of ["", " 1.0", "1.0 beta", "-1", "x".repeat(65), "1.0\n"])
            assert(!ModuleManifestRules.parseManifest(_manifest({ version: bad })).valid, "not a version: " + JSON.stringify(bad));

        // --- hostile input: nothing throws ---
        for (const text of [null, undefined, 42, "", "null", "[]", "42", "\"text\"", "true", "{", "{}}", "{\"id\":",
                            "\u0000", "[{\"id\":\"x\"}]"]) {
            let result = null;
            try {
                result = ModuleManifestRules.parseManifest(text);
            } catch (error) {
                fail("parseManifest threw on " + JSON.stringify(text) + ": " + error);
                continue;
            }
            assert(!result.valid && result.errors.length > 0, "not a manifest, said so: " + JSON.stringify(text));
        }
        assert(_has(ModuleManifestRules.parseManifest("{ not json").errors, "not valid JSON"), "not JSON: said so");
        assert(_has(ModuleManifestRules.parseManifest("[1]").errors, "not a JSON object"), "a JSON array: not an object");
        const huge = "{\"id\":\"x\",\"pad\":\"" + "a".repeat(rules.maxManifestBytes) + "\"}";
        assert(_has(ModuleManifestRules.parseManifest(huge).errors, "too large"), "a huge module.json is refused before parsing");
        // Prototype keys as fields: kept as data, never as the prototype
        const proto = ModuleManifestRules.parseManifest("{\"id\":\"x\",\"name\":\"X\",\"version\":\"1\",\"api\":\"1.0\","
                                          + "\"__proto__\":{\"valid\":true,\"main\":\"Evil.qml\"},\"constructor\":1}");
        assert(proto.valid, "a manifest with __proto__ and constructor fields is still read");
        assertEqual(proto.main, "", "… __proto__ does not inject a main");
        assert(_has(proto.warnings, "__proto__") && _has(proto.warnings, "constructor"), "… both reported as unknown fields");
        assertEqual(({}).valid, undefined, "… and Object.prototype is untouched");
        const protoEntries = ModuleManifestRules.parseManifest(_manifest({ settings: [JSON.parse("{\"__proto__\":{\"key\":\"mod.tailscale.x\"},\"label\":\"L\",\"type\":\"bool\",\"default\":true}")] }));
        assertEqual(protoEntries.settings.length, 0, "a setting whose key comes only from __proto__ is dropped");
        // Wrong types everywhere: each list not a list, each entry not an object
        const everythingWrong = ModuleManifestRules.parseManifest(_manifest({
            description: 5, main: "../escape.qml", widgets: "x", settingsPages: {}, settings: 3, facts: null,
            slots: [1, "a", null, []], requires: [], setupHints: [{}, 5, ""], tests: [7, "/abs.qml", "x.js"]
        }));
        assert(!everythingWrong.valid, "a main outside the directory: invalid (the module fails)");
        assert(_has(everythingWrong.errors, "main"), "… said so");
        assert(_has(everythingWrong.errors, "widgets: not a list") && _has(everythingWrong.errors, "settings: not a list")
               && _has(everythingWrong.errors, "settingsPages: not a list") && _has(everythingWrong.errors, "facts: not a list"),
               "lists that are not lists: one error each");
        assert(_has(everythingWrong.errors, "slots[3]: not an object"), "entries that are not objects: dropped, said");
        assert(_has(everythingWrong.errors, "requires: not an object"), "requires not an object: said");
        assertEqual(everythingWrong.setupHints.length, 0, "setup hints that are not texts: dropped");
        assertEqual(everythingWrong.tests.length, 0, "tests that are not .qml files inside: dropped");
        assert(_has(everythingWrong.warnings, "description"), "a description that is not a text: a warning");
        const tooMany = ModuleManifestRules.parseManifest(_manifest({ facts: Array.from({ length: 300 }, (_, i) => ({ fact: "tailscale.f" + i, label: "F", type: "bool" })) }));
        assertEqual(tooMany.facts.length, rules.maxEntries, "at most maxEntries entries of a list are read");
        assert(_has(tooMany.errors, "only the first"), "… said so");

        // --- unknown fields: kept, warned ---
        const newer = ModuleManifestRules.parseManifest(_manifest({ permissions: ["network"], badge: "vpn" }));
        assert(newer.valid, "a manifest with fields this shell does not know still loads");
        assertEqual(JSON.stringify(newer.unknownFields), "[\"permissions\",\"badge\"]", "… their names listed");
        assertEqual(JSON.stringify(newer.raw.permissions), "[\"network\"]", "… their values kept in raw");
        assertEqual(newer.warnings.length, 2, "… one warning each");
        const unknownInEntry = ModuleManifestRules.parseManifest(_manifest({ facts: [{ fact: "tailscale.up", label: "Up", type: "bool", color: "red" }] }));
        assert(unknownInEntry.facts.length === 1 && _has(unknownInEntry.warnings, "facts[0]: unknown field \"color\""),
               "an unknown field in an entry: the entry kept, a warning");

        // --- paths ---
        for (const good of ["Main.qml", "sub/Panel.qml", "a-b_c.qml", "x/y/z.qml"])
            assertEqual(ModuleFileRules.pathProblem(good), "", "a module file: " + good);
        for (const bad of ["/etc/x.qml", "../x.qml", "a/../../x.qml", "./x.qml", "a//b.qml", "x.js", "x", "",
                           "a b.qml", "x.qml\u0000", "file:///x.qml", "C:\\x.qml", "~/x.qml", null, 3, "a".repeat(301) + ".qml"])
            assert(ModuleFileRules.pathProblem(bad) !== "", "not a module file: " + JSON.stringify(bad));
        assertEqual(ModuleFileRules.canonicalPath("/a//b/./c/../d/"), "/a/b/d", "canonical: repeated /, ., .., trailing / gone");
        assertEqual(ModuleFileRules.canonicalPath("/../a"), "/a", "canonical: above the root stays at the root");
        for (const bad of ["a/b", "", "./a", null, 5, "~/x"])
            assertEqual(ModuleFileRules.canonicalPath(bad), "", "not absolute: " + JSON.stringify(bad));
        assertEqual(ModuleFileRules.fileUrl("/m/x/", "a/B.qml"), "file:///m/x/a/B.qml", "a file's URL");
        assertEqual(ModuleFileRules.fileUrl("/m//x/.", "B.qml"), ModuleFileRules.fileUrl("/m/x", "B.qml"), "one file, one URL, however the directory is spelled");
        assertEqual(ModuleFileRules.fileUrl("/m/a#b?c%d", "B.qml"), "file:///m/a%23b%3Fc%25d/B.qml", "what a URL cannot hold is escaped");

        // --- the module list (H2S_SHELL_MODULES) ---
        const list = ModuleFileRules.moduleDirectories("/a/x::/b/y/:relative:/a//x:/c/../b/y:/");
        assertEqual(JSON.stringify(list.directories), "[\"/a/x\",\"/b/y\"]", "canonical, in order, each once");
        assertEqual(JSON.stringify(list.ignored), "[\"relative\",\"/\"]", "what is not a module directory is reported");
        assertEqual(ModuleFileRules.moduleDirectories(["/a", 3, null, "/a/"]).directories.length, 1, "a list works as well; junk ignored");
        assertEqual(ModuleFileRules.moduleDirectories(undefined).directories.length, 0, "nothing: no directories");

        // --- namespaces ---
        assert(ModuleManifestRules.isOwnSettingKey("tailscale", "mod.tailscale.showIp"), "mod.<id>.<name>: its own setting");
        assert(ModuleManifestRules.isOwnSettingKey("tailscale", "mod.tailscale.exit.node"), "… nested");
        for (const bad of ["tailscale.showIp", "mod.tailscale", "mod.tailscale.", "mod.other.x", "lockscreen.enabled",
                           "mod.tailscalex.y", "mod.tailscale..x", "mod.tailscale.a-b", "mod.tailscale.__proto__.x.", 5])
            assert(!ModuleManifestRules.isOwnSettingKey("tailscale", bad), "not its setting: " + JSON.stringify(bad));
        assert(ModuleManifestRules.isOwnFact("tailscale", "tailscale.connected"), "<id>.<name>: its own fact");
        for (const bad of ["tailscale", "battery.percent", "tailscalex.y", "mod.tailscale.x", "tailscale.", ""])
            assert(!ModuleManifestRules.isOwnFact("tailscale", bad), "not its fact: " + JSON.stringify(bad));
        assert(ModuleManifestRules.isOwnName("tailscale", "tailscale") && ModuleManifestRules.isOwnName("tailscale", "tailscale.devices"),
               "a widget type, popup or page: <id> or <id>.<name>");
        assert(!ModuleManifestRules.isOwnName("tailscale", "clock") && !ModuleManifestRules.isOwnName("tailscale", "tailscale2"), "… not another's");

        // A violation drops that entry with an error; the module still loads
        const collisions = ModuleManifestRules.parseManifest(_manifest({
            widgets: [{ type: "clock", name: "Clock", widget: "W.qml" }, { type: "tailscale", name: "T", widget: "W.qml" },
                      { type: "tailscale.x", name: "P", widget: "W.qml", popup: "music" }],
            settings: [{ key: "lockscreen.enabled", label: "L", type: "bool", default: true },
                       { key: "mod.good.greeting", label: "G", type: "string", default: "" },
                       { key: "mod.tailscale.ok", label: "Ok", type: "bool", default: false },
                       { key: "mod.tailscale.ok", label: "Again", type: "bool", default: true }],
            facts: [{ fact: "battery.percent", label: "B", type: "percent" }, { fact: "tailscale.up", label: "U", type: "bool" }],
            settingsPages: [{ id: "lockscreen", label: "L", component: "P.qml" }, { id: "tailscale", label: "T", component: "P.qml" }]
        }));
        assert(collisions.valid, "keys outside the namespace do not fail the module");
        assertEqual(collisions.widgets.map(widget => widget.type).join(","), "tailscale", "only its own widget type kept (clock dropped, a popup of another's dropped)");
        assertEqual(collisions.settings.map(setting => setting.key).join(","), "mod.tailscale.ok", "only its own setting kept, once");
        assert(_has(collisions.errors, "lockscreen.enabled") && _has(collisions.errors, "mod.good.greeting"), "… the core's key and another module's: errors");
        assert(_has(collisions.errors, "listed twice"), "… a key listed twice: the second dropped, said");
        assertEqual(collisions.facts.map(fact => fact.fact).join(","), "tailscale.up", "only its own fact kept");
        assertEqual(collisions.settingsPages.map(page => page.id).join(","), "tailscale", "only its own settings page kept");

        // Settings: types and defaults
        const typed = ModuleManifestRules.parseManifest(_manifest({ settings: [
            { key: "mod.tailscale.a", label: "A", type: "bool", default: "yes" },
            { key: "mod.tailscale.b", label: "B", type: "number", default: "5" },
            { key: "mod.tailscale.c", label: "C", type: "slider", default: 50, min: 0, max: 10 },
            { key: "mod.tailscale.d", label: "D", type: "enum", default: "x", options: [{ value: "y", label: "Y" }] },
            { key: "mod.tailscale.e", label: "E", type: "enum", default: "x" },
            { key: "mod.tailscale.f", label: "F", type: "stringList", default: [1] },
            { key: "mod.tailscale.g", label: "G", type: "barSection", default: [] },
            { key: "mod.tailscale.h", label: "H", type: "string" },
            { key: "mod.tailscale.i", type: "bool", default: true },
            { key: "mod.tailscale.j", label: "J", type: "number", default: NaN },
            { key: "mod.tailscale.k", label: "K", type: "string", default: "", group: "lockscreen" },
            { key: "mod.tailscale.ok", label: "Ok", type: "interval", default: 0, min: 0, global: true }
        ] }));
        assertEqual(typed.settings.map(setting => setting.key).join(","), "mod.tailscale.ok", "every malformed setting dropped, the good one kept");
        assertEqual(typed.errors.length, 11, "… one error each");
        assert(typed.settings[0].global === true, "global kept");
        assert(_has(typed.errors, "core editor") || _has(typed.errors, "type \"barSection\""), "a core-only type is refused");

        // Facts
        const facts = ModuleManifestRules.parseManifest(_manifest({ facts: [
            { fact: "tailscale.a", label: "A", type: "color" }, { fact: "tailscale.b", label: "B", type: "enum" },
            { fact: "tailscale.c", type: "bool" }, { fact: "tailscale.d", label: "D", type: "percent" }] }));
        assertEqual(facts.facts.map(fact => fact.fact).join(","), "tailscale.d", "malformed facts dropped");

        // Widgets and pages
        const widgets = ModuleManifestRules.parseManifest(_manifest({
            widgets: [{ type: "tailscale", name: "T" }, { type: "tailscale.b", name: "B", widget: "/abs.qml" },
                      { type: "tailscale.c", name: "C", widget: "W.qml", popupPanel: "P.qml" },
                      { type: "tailscale.d", name: "D", widget: "W.qml", multiple: "yes" },
                      { type: "tailscale.e", name: "E", widget: "W.qml", multiple: true }],
            settingsPages: [{ id: "tailscale", label: "T", component: "P.qml", tab: "secret" },
                            { id: "tailscale.b", label: "B", component: "P.qml", parent: "Net Work" },
                            { id: "tailscale.c", label: "C", component: "P.qml" }],
            slots: [{ slot: "Network", component: "S.qml" }, { slot: "network.vpn.row", component: "../S.qml" },
                    { slot: "network.vpn.card", component: "Card.qml" }] }));
        assertEqual(widgets.widgets.map(widget => widget.type).join(","), "tailscale.e", "malformed widgets dropped");
        assertEqual(widgets.settingsPages.map(page => page.id + ":" + page.tab).join(","), "tailscale.c:behaviour",
                    "malformed pages dropped; tab defaults to behaviour");
        assertEqual(widgets.slots.map(slot => slot.slot).join(","), "network.vpn.card", "malformed slot contributions dropped");

        // Requires
        const requires = ModuleManifestRules.parseManifest(_manifest({ requires: { programs: ["tailscale", "tailscale", "../bin/x", "a b", 5, "jq"],
                                                                      services: ["tailscaled"] } }));
        assertEqual(JSON.stringify(requires.programs), "[\"tailscale\",\"jq\"]", "program names, each once; paths and junk dropped");
        assert(_has(requires.warnings, "requires: unknown field \"services\""), "an unknown requirement: a warning");
        const optional = ModuleManifestRules.parseManifest(_manifest({ requires: { programs: ["tailscale"] },
                                                                      optionalPrograms: ["curl", "tailscale", "curl", "../x", 5] }));
        assertEqual(JSON.stringify(optional.optionalPrograms), "[\"curl\"]", "optionalPrograms: each once; a required one stays required; junk dropped");
        assert(_has(optional.errors, "optionalPrograms[3]") && optional.warnings.length === 0, "… junk named as an error, the field known");
        assert(_has(ModuleManifestRules.parseManifest(_manifest({ optionalPrograms: "curl" })).errors, "optionalPrograms: not a list (ignored)"),
               "optionalPrograms: not a list");

        _programTrust();
        _testMode();

        // --- qmldir ---
        assertEqual(JSON.stringify(ModuleFileRules.qmldirFiles("module foo\nsingleton Ts 1.0 Ts.qml\nHelper 1.0 Helper.qml\n"
                                                     + "internal Hidden Hidden.qml\n# comment\nplugin x\nimport QtQuick\nBad 1.0 ../Bad.qml\n")),
                    "[\"Ts.qml\",\"Helper.qml\",\"Hidden.qml\"]", "the files a qmldir names, inside the directory");
        assertEqual(ModuleFileRules.qmldirFiles(null).length, 0, "no qmldir: none");

        // --- the import check: warnings and errors, never a refusal ---
        const header = "// A comment\n/* import qs.singletons in a block comment */\npragma Singleton\n"
            + "import QtQuick\nimport QtQuick.Layouts 1.15\nimport QtQml.Models\nimport Quickshell\nimport Quickshell.Io\n"
            + "import qs.api\nimport qs.components\nimport \".\"\nimport \"sub\" as Sub\nimport \"Rules.js\" as Rules\n"
            + "import qs.singletons\nimport Quickshell.Hyprland; import \"../core\"\nimport \"file:///etc\" as E\n"
            + "QtObject {\n    // import qs.panels after the header is not an import\n}\nimport qs.panels\n";
        assertEqual(ModuleSourceRules.importsOf(header).length, 14, "the imports of the header, block comments skipped, two on one line");
        const warnings = ModuleSourceRules.importWarnings("Main.qml", header);
        assertEqual(warnings.length, 1, "outside the allowlist: Quickshell.Hyprland a warning: " + JSON.stringify(warnings));
        assert(_has(warnings, "Main.qml imports Quickshell.Hyprland"), "… naming the file and the import");
        // (1.19) What reaches into the shell or another module: an error, not a warning
        const reaching = ModuleSourceRules.importErrors("Main.qml", header);
        assertEqual(reaching.length, 3, "qs.singletons, ../core, a file URL: errors: " + JSON.stringify(reaching));
        assert(_has(reaching, "Main.qml imports qs.singletons, the shell's own") && _has(reaching, "Main.qml imports \"../core\", outside the module's directory")
               && _has(reaching, "\"file:///etc\", outside"), "… each names the file and the import");
        assert(!warnings.some(line => reaching.includes(line)) && !_has(warnings, "qs.singletons"), "… and is no warning too");
        assertEqual(ModuleSourceRules.importErrors("A.qml", "import qs.singletons.io as Io\nimport qs.singletonsX\nimport qs.api\nimport \"sub\"\nItem {}").join("|"),
                    "A.qml imports qs.singletons.io, the shell's own: a module reaches the shell through qs.api",
                    "below qs.singletons too; not a longer name, not qs.api, not its own directory");
        assertEqual(ModuleSourceRules.importErrors("A.qml", null).length, 0, "no text: no error, no throw");
        // A JavaScript file's `.import` lines: judged as a QML file's imports
        const script = ".pragma library\n.import qs.singletons as S\n.import QtQuick.LocalStorage 2.0 as Sql\n.import \"../../other/x.js\" as X\n.import \"own.js\" as Own\n"
                     + ".import Quickshell.Hyprland as H\nfunction f() { return 1; }\n";
        assertEqual(ModuleSourceRules.importErrors("lib/util.js", script).join("|"),
                    "lib/util.js imports qs.singletons, the shell's own: a module reaches the shell through qs.api|"
                    + "lib/util.js imports \"../../other/x.js\", outside the module's directory: another module is used through `uses`",
                    "a script's .import of qs.singletons and of a file outside the module: errors");
        assertEqual(ModuleSourceRules.importErrors("lib/util.js", ".import \"../util.js\" as U\n").length, 0, "… a file of its own module through \"..\": none");
        assertEqual(ModuleSourceRules.importWarnings("lib/util.js", script).join("|").includes("Quickshell.Hyprland") && ModuleSourceRules.importWarnings("lib/util.js", script).length === 1, true,
                    "… outside the allowlist: a warning, as in QML");
        assertEqual(ModuleSourceRules.importDeprecations({ "u.js": ".import qs.components as C\n" }).length, 1, "… a deprecated import: listed");
        assert(!_has(warnings, "qs.panels"), "… nothing after the header counts");
        assertEqual(ModuleSourceRules.importWarnings("A.qml", "import QtQuick\nQtObject {}").length, 0, "an allowed file: no warning");
        assertEqual(ModuleSourceRules.importWarnings("A.qml", null).length, 0, "no text: no warning, no throw");
        assert(Array.isArray(ModuleSourceRules.importWarnings("A.qml", "import ".repeat(100000))), "a huge garbage header: no throw");
        const repeated = ModuleSourceRules.importErrors("A.qml", "import qs.singletons\n".repeat(3000) + "Item {}");
        assertEqual(repeated.length, ModuleSourceRules.maxImportWarningsPerFile + 1, "a header of 3000 forbidden imports: maxImportWarningsPerFile errors and a count");
        const repeatedWarnings = ModuleSourceRules.importWarnings("A.qml", "import Quickshell.Hyprland\n".repeat(3000) + "Item {}");
        assertEqual(repeatedWarnings.length, ModuleSourceRules.maxImportWarningsPerFile + 1, "… warnings the same");
        assertEqual(repeated[repeated.length - 1], "… and " + (3000 - ModuleSourceRules.maxImportWarningsPerFile) + " more", "… the count of the rest");
        assertEqual(JSON.stringify(ModuleSourceRules.cappedLines(["a", "b"], 2)), "[\"a\",\"b\"]", "cappedLines: up to the cap, as it is");
        assertEqual(JSON.stringify(ModuleSourceRules.cappedLines(["a", "b", "c"], 1)), "[\"a\",\"… and 2 more\"]", "… past it, the first and the count");
        const longName = "d/".repeat(500) + "A.qml";
        const longWarning = ModuleSourceRules.importErrors(longName, "import qs.singletons\nItem {}")[0];
        assert(longWarning.startsWith("d/d/") && longWarning.indexOf("… imports qs.singletons") === 79 && longWarning.length < 300,
               "a listed file's long path is cut at 80 characters in its warning: " + longWarning.slice(0, 100));
        assert(ModuleSourceRules.importErrors("A.qml", "import \"/" + "x".repeat(5000) + "\"\nItem {}")[0].length < 300, "… and so is a long quoted import");
        assert(!ModuleSourceRules.importAllowed({ name: "QtQuickX", directory: false }), "QtQuickX is not under QtQuick");
        assertEqual(JSON.stringify(ModuleSourceRules.importsOf("import qs.components; Item {}")), JSON.stringify([{ name: "qs.components", directory: false }]),
                    "an import on the line with the first \"{\" is read before stopping");
        assertEqual(ModuleSourceRules.importWarnings("A.qml", "import QtQuick\nimport Quickshell.Hyprland; Item {\n}").length, 1,
                    "… so one outside the allowlist there is warned about");
        assertEqual(ModuleSourceRules.importsOf("import QtQuick\nItem { import qs.panels }").length, 1, "what follows the \"{\" is not an import");

        // --- an import that is an old way: allowed, listed among the deprecations ---
        assert(ModuleSourceRules.importAllowed({ name: "qs.components", directory: false }) && !_has(warnings, "imports qs.components"),
               "qs.components may still be imported: no warning");
        assertEqual(JSON.stringify(ModuleSourceRules.importDeprecations({ "Main.qml": header, "Page.qml": "import QtQuick\nimport qs.api\nItem {}" })),
                    JSON.stringify(["import qs.components (in Main.qml): use the elements of qs.api (goes with the shell's next tightening)"]),
                    "… but is listed as deprecated, with the file that imports it and what to use");
        assertEqual(JSON.stringify(ModuleSourceRules.importDeprecations({ "Main.qml": header, "Page.qml": "import qs.components as C\nItem {}",
                                                                          "tests/T.qml": "import qs.components\nItem {}", "Other.qml": "import qs.api\nItem {}" })),
                    JSON.stringify(["import qs.components (in 3 files): use the elements of qs.api (goes with the shell's next tightening)"]),
                    "several files importing it: one line, saying how many");
        assertEqual(ModuleSourceRules.importDeprecations({ "A.qml": "import QtQuick\nimport qs.api\nItem {}", "B.qml": "// import qs.components\nItem {\n}\nimport qs.components\n",
                                                           "C.qml": "import \"qs.components\"\nItem {}", "D.qml": "import qs.componentsX\nItem {}" }).length, 0,
                    "a module on qs.api alone: none — a comment, a line after the header, a directory of that name and a longer name are not the import");
        assertEqual(ModuleSourceRules.importDeprecations(null).length + ModuleSourceRules.importDeprecations({}).length
                    + ModuleSourceRules.importDeprecations({ "A.qml": null }).length, 0, "no files, no text: none, no throw");
        assert(Object.keys(ModuleSourceRules.deprecatedImports).every(name => ModuleSourceRules.allowedImports.includes(name)),
               "every deprecated import is still an allowed one: listed, not warned about");

        // --- (1.19) reaching another module or the host in code: listed among the deprecations ---
        const tightening = " (goes with the shell's next tightening)";
        assertEqual(JSON.stringify(ModuleSourceRules.codeDeprecations({ "Main.qml": "import qs.api\nQtObject {\n    property var other: Api.module(\"good\")\n}\n" })),
                    JSON.stringify(["Api.module(id) (in Main.qml): use `Api.moduleStatus(id)` for another module's state, and its `exports` through `uses`" + tightening]),
                    "Api.module(id): listed, with the file and what to use");
        assertEqual(JSON.stringify(ModuleSourceRules.codeDeprecations({ "Page.qml": "Item {\n    property var module: null\n    readonly property bool t: module.host.testMode\n}\n" })),
                    JSON.stringify(["module.host (in Page.qml): gone since API 1.36; use the handle's own properties and qs.api (in a suite, ModuleTestKit)"]),
                    "module.host: listed");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "Item { readonly property var h: root.module . host; property var t: module?.host?.testMode }",
                                                         "B.qml": "Item { readonly property var h: Api.moduleAt(Qt.resolvedUrl(\".\")).host }" }).join("|"),
                    "module.host (in 2 files): gone since API 1.36; use the handle's own properties and qs.api (in a suite, ModuleTestKit)",
                    "… through a property named module, spaced, optional, or straight from Api.moduleAt: one line, how many files");
        assertEqual(ModuleSourceRules.codeDeprecations({ "Both.qml": "QtObject { property var a: Api.module(\"x\"); property var b: module.host }" }).length, 2,
                    "both in one file: two lines");
        assertEqual(ModuleSourceRules.codeDeprecations({
                        "Comments.qml": "// Api.module(\"x\") and module.host in a line comment\n/* Api.module(\"x\")\n module.host */\nQtObject {}",
                        "Strings.qml": "QtObject {\n    property string a: \"Api.module(x)\"\n    property string b: 'module.host'\n    property string c: `${\"\"} module.host`\n}",
                        "Regex.qml": "QtObject {\n    property var r: /Api.module\\(/\n}",
                        "Others.qml": "QtObject {\n    property var a: Api.moduleAt(Qt.resolvedUrl(\".\"))\n    property var b: Api.moduleStatus(\"x\")\n"
                                      + "    property var c: parsed.host\n    property var d: module.hostName\n    property var e: mymodule.host\n    property var f: Api.modules\n}"
                    }).length, 0,
                    "not counted: comments, strings, template literals, a regex literal, moduleAt, moduleStatus, another object's host, a longer name");
        assertEqual(ModuleSourceRules.codeDeprecations(null).length + ModuleSourceRules.codeDeprecations({}).length
                    + ModuleSourceRules.codeDeprecations({ "A.qml": null, "B.qml": 5 }).length, 0, "no files, no text: none, no throw");
        // Where a "/" starts a regex: after `=>` and the keywords that take an operand too, so
        // a quote inside it does not open a string that hides the rest of the file
        const apiModule = "Api.module(id) (in A.qml): use `Api.moduleStatus(id)` for another module's state, and its `exports` through `uses`" + tightening;
        const hostLine = "module.host (in A.qml): gone since API 1.36; use the handle's own properties and qs.api (in a suite, ModuleTestKit)";
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    function f(list) { return list.filter(x => /'/.test(x)); }\n"
                                                         + "    property string s: 'Api.module(id) is old'\n}\n" }).length, 0,
                    "a regex after `=>` with a quote in it: the string after it is still a string");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property var f: u => /^https?:\\/\\//.test(u) && Api.module(\"x\")\n}\n" }).join("|"),
                    apiModule, "… and its `//` does not open a comment hiding the code after it");
        for (const keyword of ["typeof", "case", "in", "of", "delete", "void", "throw", "instanceof", "new", "return"]) {
            assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    function f(x) { switch (x) { case 1: return " + keyword + " /'/; } }\n"
                                                             + "    property string s: 'Api.module(id)'\n    property var b: module.host\n}\n" }).join("|"),
                        hostLine, "a regex after `" + keyword + "`: its quote opens no string (module.host after it found, the string's text not)");
        }
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property real a: x.in / 2 / 'y'.length\n    property var b: module.host\n}\n" }).join("|"),
                    hostLine, "a property named like a keyword (x.in) divides");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property real a: n / 2 + \"half\n    property var b: module.host\n}\n" }).join("|"),
                    hostLine, "an unterminated string ends at its line's end: one line lost, not the file");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property string a: \"one \\\n module.host\"\n}\n" }).length, 0,
                    "… a string continued after a \"\\\" goes on to the next line");
        // Template literals: their text skipped, the code inside `${…}` read
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property string s: `${Api.module(\"x\").name}`\n}\n" }).join("|"),
                    apiModule, "the code inside a template's `${…}` is read");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property string s: `a ${ `b ${ {k: module.host}.k } c` } d`\n}\n" }).join("|"),
                    hostLine, "… in a template nested in one, with braces of its own");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property string s: `${s.replace(\"`\", \"\")} Api.module(x)`\n    property var b: module.host\n}\n" }).join("|"),
                    hostLine, "… a backtick in a string inside it does not end the template; its text after the substitution is still text");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property string s: `text ${'}'} module.host`\n}\n" }).length, 0,
                    "… a brace in a string inside it does not end the substitution");
        // `module` only as the whole name
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject {\n    property var a: $module.host\n    property var b: my_module.host\n    property var c: $Api.module(\"x\")\n}\n" }).length, 0,
                    "$module.host, my_module.host, $Api.module(): other names");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "module.host" }).join("|"), hostLine, "… at the start of the text, found");
        // A script of the module: its code is read the same way
        assertEqual(ModuleSourceRules.codeDeprecations({ "lib/util.js": ".pragma library\n.import qs.api as A\nfunction other() { return A.Api.module(\"x\"); }\n" }).join("|"),
                    "Api.module(id) (in lib/util.js): use `Api.moduleStatus(id)` for another module's state, and its `exports` through `uses`" + tightening,
                    "a JavaScript file's code: read too");
        // The text without comments and strings, made once by the caller: the same answers
        const sample = "import QtQuick\nItem {\n    property var module: null\n    readonly property var opener: null\n    property var b: module.host\n    Item { property int nested }\n}\n";
        const sampleCode = ModuleSourceRules.codeText(sample);
        assertEqual(ModuleSourceRules.rootProperties(sample, sampleCode).join(","), ModuleSourceRules.rootProperties(sample).join(","), "rootProperties with the code given: the same");
        assertEqual(ModuleSourceRules.openerPropertyWarning("A.qml", sample, sampleCode), ModuleSourceRules.openerPropertyWarning("A.qml", sample), "openerPropertyWarning with the code given: the same");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": sample }, { "A.qml": sampleCode }).join("|"), hostLine, "codeDeprecations with the code given: the same");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": sample }, { "A.qml": "QtObject {}" }).length, 0, "… the code given is what is read");
        assertEqual(ModuleSourceRules.codeDeprecations({ "A.qml": "QtObject { property var a: Api.module(\"x\") }", "tests/T.qml": "Item { property var a: Api.module(\"x\") }" }).join("|"),
                    "Api.module(id) (in 2 files): use `Api.moduleStatus(id)` for another module's state, and its `exports` through `uses`" + tightening,
                    "a suite counts too");

        // --- precedence: the first id wins ---
        const order = ModuleMergeRules.precedence([{ directory: "/home/m/ts", id: "tailscale" }, { directory: "/sys/m/x", id: "" },
                                        { directory: "/sys/m/ts", id: "tailscale" }, { directory: "/sys/m/y", id: "" },
                                        { directory: "/sys/m/z", id: "__proto__" }, { directory: "/sys/m/z2", id: "__proto__" }]);
        assertEqual(order.map(entry => entry.winner).join(","), "true,true,false,true,true,false", "the first of an id wins; no id never conflicts");
        assertEqual(order[2].shadowedBy, "/home/m/ts", "the later one is reported with the winner's directory");
        assertEqual(ModuleMergeRules.precedence(null).length, 0, "nothing: nothing");

        // --- the state model ---
        const base = { valid: true, compatible: true, duplicate: false, safeMode: false, settingsKnown: true, enabled: true,
                       programsKnown: true, missingPrograms: [], mainError: "" };
        const state = changes => ModuleMergeRules.stateOf(Object.assign({}, base, changes));
        assertEqual(state({}), "loaded", "all fine: loaded");
        assertEqual(state({ valid: false, duplicate: true, compatible: false }), "failed", "an unusable manifest first: failed");
        assertEqual(state({ duplicate: true, compatible: false }), "duplicate", "shadowed: duplicate (before API)");
        assertEqual(state({ compatible: false, safeMode: true }), "incompatible", "wrong API: incompatible");
        assertEqual(state({ safeMode: true, enabled: false }), "safe-mode", "safe mode: nothing loads");
        assertEqual(state({ settingsKnown: false, enabled: false }), "pending", "the config not read yet: pending (not even a disabled one runs)");
        assertEqual(state({ enabled: false, programsKnown: false }), "disabled", "turned off: disabled (its programs are not looked for)");
        assertEqual(state({ programsKnown: false }), "pending", "programs not checked yet: pending");
        assertEqual(state({ missingPrograms: ["tailscale"] }), "missing-program", "a program missing");
        assertEqual(state({ dataDirectoryKnown: false }), "pending", "its data directory not made yet (1.13): pending");
        assertEqual(state({ dataDirectoryKnown: false, missingPrograms: ["tailscale"] }), "missing-program", "… a program missing first: no directory made for it");
        assertEqual(state({ dataDirectoryKnown: false, enabled: false }), "disabled", "… nor for one turned off");
        assertEqual(state({ mainError: "Main.qml: syntax error" }), "failed", "a main that failed");
        assertEqual(ModuleMergeRules.stateOf(null), "failed", "nothing known: failed, no throw");
        // Not confirmed by the user (modules-management §5)
        assert(rules.states.includes("unconfirmed"), "the states include unconfirmed");
        assertEqual(state({ confirmed: false }), "unconfirmed", "not confirmed: unconfirmed, though the lists say on");
        assertEqual(state({ confirmed: false, enabled: false }), "unconfirmed", "… said apart from a module turned off");
        assertEqual(state({ confirmed: true }) + " " + state({ confirmed: undefined }), "loaded loaded", "confirmed, or not said: as before");
        assertEqual(state({ confirmed: false, settingsKnown: false }), "pending", "… the config not read yet: pending first");
        assertEqual(state({ confirmed: false, safeMode: true }), "safe-mode", "… safe mode first");
        assertEqual(state({ confirmed: false, compatible: false }) + " " + state({ confirmed: false, valid: false }) + " " + state({ confirmed: false, duplicate: true }),
                    "incompatible failed duplicate", "… a module that cannot load says why first");
        assertEqual(state({ confirmed: false, programsKnown: false }), "unconfirmed", "… its programs are not looked for");
        assertEqual(ModuleMergeRules.contributes("unconfirmed"), false, "an unconfirmed module contributes nothing");
        assert(rules.states.includes("approval"), "the states include approval");
        assertEqual(state({ confirmed: "approval" }) + " " + state({ confirmed: "approval", enabled: false }), "approval approval",
                    "held for approval: approval, whatever the lists say");
        assertEqual(state({ confirmed: "approval", safeMode: true }) + " " + state({ confirmed: "approval", settingsKnown: false }), "safe-mode pending",
                    "… safe mode and an unread config first");
        assertEqual(ModuleMergeRules.contributes("approval"), false, "… contributes nothing");
        for (const each of rules.states)
            assertEqual(ModuleMergeRules.contributes(each), each === "loaded", "contributions count only when loaded: " + each);
        const status = ModuleMergeRules.statusOf({ manifest: tailscale, directory: "/m/ts", state: "missing-program", enabled: true,
                                        errors: ["e"], warnings: [], missingPrograms: ["tailscale"], shadowedBy: "" });
        assertEqual(status.id + " " + status.state + " " + status.setupHints.length + " " + status.missingPrograms[0],
                    "tailscale missing-program 1 tailscale", "a status: id, state, the setup hints when a program is missing");
        assertEqual(ModuleMergeRules.statusOf({ manifest: tailscale, state: "loaded" }).setupHints.length, 0, "… not otherwise");
        assertEqual(ModuleMergeRules.statusOf(null).state, "failed", "a status of nothing: failed, no throw");
        assertEqual(Object.keys(status).sort().join(","),
                    "api,deprecations,description,directory,enabled,errors,id,missingPrograms,name,setupHints,shadowedBy,state,version,warnings",
                    "a status holds exactly these fields (plain data)");
        assertEqual(status.deprecations.length, 0, "a status of a module that uses no old way: no deprecations");
        const oldWays = [rules.deprecation("slots", "`anchors`")];
        const deprecated = ModuleMergeRules.statusOf({ manifest: tailscale, state: "loaded", warnings: [], deprecations: oldWays });
        assertEqual(deprecated.deprecations.join("|"), "slots: use `anchors` (goes with the shell's next tightening)", "the old ways a module uses are listed in its status");
        assert(deprecated.deprecations !== oldWays, "… as a copy");
        assertEqual(deprecated.warnings.length, 0, "… and are no warnings");
        // (1.19) What another module may know of one (Api.moduleStatus)
        const statusFacts = ModuleMergeRules.moduleStatusFacts(status, ["good", "tailscale"]);
        assertEqual(JSON.stringify(statusFacts), JSON.stringify({ id: "tailscale", name: tailscale.name, version: tailscale.version, state: "missing-program", active: true }),
                    "moduleStatusFacts: id, name, version, state, active — nothing else of the status");
        assert(Object.isFrozen(statusFacts), "… frozen");
        assertEqual(ModuleMergeRules.moduleStatusFacts(status, ["good"]).active + " " + ModuleMergeRules.moduleStatusFacts(status, null).active, "false false",
                    "… active only when its id is among the active ones");
        assertEqual(ModuleMergeRules.moduleStatusFacts(null, []) + " " + ModuleMergeRules.moduleStatusFacts({ id: "" }, [""]) + " " + ModuleMergeRules.moduleStatusFacts(5, []),
                    "null null null", "… null for no status, no id, not a status");

        // --- merging ---
        const zeta = ModuleManifestRules.parseManifest(JSON.stringify({ id: "zeta", name: "Z", version: "1", api: "1.0",
            widgets: [{ type: "zeta", name: "Z", widget: "Z.qml" }],
            settings: [{ key: "mod.zeta.a", label: "A", type: "bool", default: true }],
            facts: [{ fact: "zeta.a", label: "A", type: "bool" }],
            slots: [{ slot: "network.vpn.row", component: "Row.qml" }, { slot: "constructor", component: "C.qml" }] }));
        const alpha = ModuleManifestRules.parseManifest(JSON.stringify({ id: "alpha", name: "A", version: "1", api: "1.0",
            widgets: [{ type: "alpha", name: "A1", widget: "A1.qml", popup: "alpha", popupPanel: "P.qml" },
                      { type: "alpha.two", name: "A2", widget: "A2.qml" }],
            settingsPages: [{ id: "alpha", label: "A", component: "Page.qml" }],
            slots: [{ slot: "network.vpn.row", component: "Row.qml" }] }));
        // Merged with no table: every slot a slot (on this shell's table the VPN row's is read as
        // its anchor)
        const merged = ModuleMergeRules.merge([{ id: "zeta", directory: "/z", manifest: zeta }, { id: "alpha", directory: "/a/", manifest: alpha },
                                    null, { id: 5 }], []);
        assertEqual(merged.widgetEntries.map(entry => entry.type).join(","), "alpha,alpha.two,zeta",
                    "merged by module id, then manifest order — not search order");
        assertEqual(merged.widgetEntries[0].widget, "file:///a/A1.qml", "files become absolute file:// URLs");
        assertEqual(merged.widgetEntries[0].popupPanel, "file:///a/P.qml", "… the popup panel too");
        assertEqual(merged.widgetEntries[2].module, "zeta", "every entry names its module");
        assertEqual(merged.settingsPages[0].component, "file:///a/Page.qml", "a settings page's component URL");
        assertEqual(merged.settingEntries.length + "," + merged.factTypes.length, "1,1", "settings and facts merged");
        assertEqual(ModuleMergeRules.slotContributions(merged.slots, "network.vpn.row").map(entry => entry.module).join(","), "alpha,zeta",
                    "a slot's contributions, in module order");
        assertEqual(ModuleMergeRules.slotContributions(merged.slots, "constructor").length, 1, "a slot named like a prototype key is just a slot");
        assertEqual(ModuleMergeRules.slotContributions(merged.slots, "toString").length, 0, "a slot nobody fills: none (not the prototype's)");
        assertEqual(ModuleMergeRules.slotContributions(merged.slots, "hasOwnProperty").length, 0, "… none");
        assertEqual(ModuleMergeRules.slotContributions(null, "x").length, 0, "no slots: none");
        const again = ModuleMergeRules.merge([{ id: "alpha", directory: "/a", manifest: alpha }, { id: "zeta", directory: "/z", manifest: zeta }], []);
        assertEqual(JSON.stringify(again.widgetEntries), JSON.stringify(merged.widgetEntries), "stable: the input order does not matter");
        assertEqual(ModuleMergeRules.merge(null).widgetEntries.length, 0, "nothing to merge: empty lists");

        _m2(rules, alpha, zeta);
        _api13(rules);
        _api116(rules);
        _dependencies(rules);
        _anchors(rules);
    }

    // Anchors: the path rule, the table's form, a block's path, the manifest's `anchors`, the
    // slots read as anchors, which elements a host shows and in what order
    function _anchors(rules) {
        // --- the table ---
        assertEqual(rules.anchorTable.map(entry => entry.path + " " + entry.kind + " " + entry.placements.join("/") + " " + entry.view).join("; "),
                    "settings.general page append panels/settings/GeneralSettings.qml; popup.network.connections popupSection append panels/NetworkPanel.qml; "
                    + "popup.notifications popupSection prepend panels/NotificationPanel.qml; "
                    + "popup.network.connections.vpn.row row after panels/network/VpnSection.qml; "
                    + "settings.network_vpn.vpns.card.settings region prepend panels/settings/NetworkVpnSettings.qml; "
                    + "settings.network_wifi.saved.card.settings region append panels/settings/NetworkWifiSettings.qml; "
                    + "settings.network_ethernet.profiles.card.settings region append panels/settings/NetworkEthernetSettings.qml; "
                    + "settings.network_wifi.saved.card.title region append panels/settings/NetworkWifiSettings.qml; "
                    + "settings.network_ethernet.profiles.card.title region append panels/settings/NetworkEthernetSettings.qml; "
                    + "settings.network_vpn.vpns.card.title region append panels/settings/NetworkVpnSettings.qml; "
                    + "settings.network_vpn.vpns.card.actions region append panels/settings/NetworkVpnSettings.qml; "
                    + "settings.network_wifi.saved.card.actions region append panels/settings/NetworkWifiSettings.qml; "
                    + "settings.network_ethernet.profiles.card.actions region append panels/settings/NetworkEthernetSettings.qml; "
                    + "popup.network.wifi.row.title region append panels/network/WifiNetworkRow.qml; "
                    + "popup.network.connections.wired.row.title region append panels/NetworkPanel.qml",
                    "the anchor table: the views converted so far (1.21: the General page; 1.22: the network and notifications popups; 1.23: the VPN rows and cards; "
                    + "1.24: the saved networks' and wired profiles' cards; 1.25: the buttons of those cards; 1.28: their name's line; 1.29: the VPN cards' name line; "
                    + "1.32: the network popup's Wi-Fi and wired rows' name line)");
        assertEqual(rules.anchorTable.filter(entry => entry.path.endsWith(".row.title")).map(entry => entry.path + " " + entry.placements.join("/") + " " + entry.scope + " " + entry.since).join(","),
                    "popup.network.wifi.row.title append  1.32,popup.network.connections.wired.row.title append  1.32",
                    "… the popup's network rows' name lines take any module's elements, appended (1.32)");
        assertEqual(rules.anchorTable.filter(entry => entry.path.endsWith(".card.title")).map(entry => entry.path + " " + entry.placements.join("/") + " " + entry.since).join(","),
                    "settings.network_wifi.saved.card.title append 1.28,settings.network_ethernet.profiles.card.title append 1.28,settings.network_vpn.vpns.card.title append 1.29",
                    "… the saved Wi-Fi networks' and wired profiles' name lines take elements, appended (1.28), and the VPN cards' (1.29)");
        assertEqual(rules.anchorTable.find(entry => entry.path === "settings.network_vpn.vpns.card.title")?.scope, "",
                    "… the VPN cards' name line any module's, whatever the VPN's provider");
        assert(rules.anchorTable.every(entry => !("marks" in entry)), "… no row names marks any more (1.27's marks removed before any release)");
        assertEqual(rules.anchorTable.filter(entry => entry.scope === "own-provider").map(entry => entry.path).join(","),
                    "popup.network.connections.vpn.row,settings.network_vpn.vpns.card.settings,settings.network_vpn.vpns.card.actions",
                    "… the VPN places own-provider, the others not");
        assertEqual(rules.anchorTable.filter(entry => entry.takes !== "").map(entry => entry.path + " " + entry.takes).join(","),
                    "settings.network_vpn.vpns.card.actions SmallButton,settings.network_wifi.saved.card.actions SmallButton,"
                    + "settings.network_ethernet.profiles.card.actions SmallButton", "… a card's buttons take the public button, nothing else does");
        assertEqual(rules.anchorTableProblems(rules.anchorTable).join("; "), "", "… and well formed");
        const row = (path, placements, extra) => Object.assign({ path: path, kind: "page", placements: placements, takes: "",
                                                                 context: "{ editIndex }", scope: "", since: "1.20", where: "a page",
                                                                 view: "panels/settings/GeneralSettings.qml" }, extra ?? {});
        const table = [row("settings.general", ["append"]), row("popup.notifications", ["prepend"], { kind: "popupSection" }),
                       row("settings.fixture.box", ["before", "after", "prepend", "append"], { kind: "section" }),
                       row("settings.network_vpn.vpns.card.settings", ["prepend"], { kind: "region", scope: "own-provider" })];
        assertEqual(rules.anchorTableProblems(table).join("; "), "", "a suite's table, well formed");
        const badTable = rules.anchorTableProblems([row("settings.general", []), row("settings.general", ["inside"]), 5,
                                                    row("bar.clock", ["append"], { kind: "widget", scope: "mine", since: "1", where: "", view: "../x.qml" }),
                                                    row("settings.other", ["append"], { view: undefined }),
                                                    row("settings.x.card.settings", ["append"], { kind: "region", takes: "Dropdown" }),
                                                    row("settings.x.card.actions", ["append"], { kind: "region" })]);
        for (const fragment of ["placements are not", "twice", "not an object", "does not start with", "kind \"widget\"", "scope \"mine\"",
                                "since \"1\"", "where not empty", "view \"../x.qml\" is not a file", "view undefined is not a file",
                                "takes \"Dropdown\" is not", "settings.x.card.actions): a card's actions take a SmallButton"])
            assert(_has(badTable, fragment), "a bad table row: " + fragment);
        assertEqual(rules.anchorTableProblems([row("settings.y.card", [], { kind: "card" })]).join("; ").includes("placements are not"), true,
                    "… a row offering no placement: refused (a card's own row takes no marks any more)");
        assertEqual(ModuleMergeRules.anchorErrors({ anchors: [{ at: "settings.general", place: "before", component: "A.qml" }] }, table).join(""),
                    "anchors: \"settings.general\" does not take \"before\" (it takes: append)",
                    "anchorErrors: a placement the place does not take, refused, said so with what it takes");
        assert(typeof rules.setMark === "undefined" && typeof rules.cardMarks === "undefined" && typeof rules.markTip === "undefined",
               "the marks' rules are gone (1.28)");
        assertEqual(rules.anchorTableProblems(null).length, 1, "… not a list: one problem, no throw");
        assertEqual(JSON.stringify(rules.anchorRow(table, "popup.notifications")?.placements), "[\"prepend\"]", "anchorRow: the row of a path");
        assertEqual(rules.anchorRow(table, "popup.network") + "," + rules.anchorRow(null, "x"), "null,null", "… none: null");

        // --- the path rule ---
        for (const good of ["settings.general", "popup.network.connections", "popup.network.connections.vpn.row", "popup.tray-menu",
                            "settings.network_vpn.vpns.card.settings", "settings.network_wifi.saved.card.actions", "settings.network_ethernet.profiles.card.title",
                            "settings.general.box2.deep", "popup.network.wifi.row.title", "popup.network.connections.wired.row.title"])
            assertEqual(rules.anchorPathProblem(good), "", "a place's name: " + good);
        for (const bad of ["", null, 5, {}, "settings", "bar.clock", "lockscreen.password", "screensaver.clock", "Settings.general",
                           "settings.General", "settings.general.Top", "settings.general.top-x", "settings.general.1a", "settings..x",
                           "settings.general.", "settings.general.settings", "settings.general.actions", "settings.general.title", "settings.x.card.title.more", "settings.x.saved.settings",
                           "settings.x.card.settings.more", "settings.x.card.actions.row", "settings.card.settings",
                           "popup.network.wifi.row.settings", "popup.network.wifi.row.actions", "popup.network.wired.title", "popup.network.wifi.row.title.more", "popup.row.title",
                           "settings.general." + "a".repeat(65), "settings.g" + ".abcdefgh".repeat(25)])
            assert(rules.anchorPathProblem(bad) !== "", "not a place's name: " + JSON.stringify(bad));
        assertEqual(rules.anchorNameProblem("saved") + rules.anchorNameProblem("connections2"), "", "a block's name: a word");
        for (const bad of ["", "Saved", "top-x", "a.b", "settings", "actions", "title", 3, null])
            assert(rules.anchorNameProblem(bad) !== "", "not a block's name: " + JSON.stringify(bad));

        // --- where a block stands ---
        const paths = (parent, isBase, anchor, kind) => JSON.stringify(rules.anchorBlockPaths(parent, isBase, anchor, kind ?? "section"));
        assertEqual(paths("settings.general", true, "", "page"), JSON.stringify({ path: "settings.general", childPath: "settings.general" }),
                    "a view's root (a page) with no anchor: the base is its path");
        assertEqual(paths("popup.notifications", true, "", "popupSection"), JSON.stringify({ path: "popup.notifications", childPath: "popup.notifications" }),
                    "… a popup section with no anchor at the base: the panel's root, the base its path");
        assertEqual(paths("popup.network.connections", false, "", "popupSection"), JSON.stringify({ path: "", childPath: "popup.network.connections" }),
                    "… a popup section with no anchor inside a block: not addressable, adds no level");
        assertEqual(paths("settings.general", true, "", "section") + paths("settings.general", true, "", undefined),
                    JSON.stringify({ path: "", childPath: "settings.general" }).repeat(2),
                    "… a section (or a block of no kind) with no anchor right at the base: not addressable, adds no level");
        assertEqual(paths("settings.general.box", false, "", "page"), JSON.stringify({ path: "", childPath: "settings.general.box" }),
                    "… a page with no anchor inside a block: not the view's root, not addressable");
        assertEqual(paths("settings.general", true, "box"), JSON.stringify({ path: "settings.general.box", childPath: "settings.general.box" }),
                    "… with an anchor: a level under the base");
        assertEqual(paths("settings.general.box", false, "card"), JSON.stringify({ path: "settings.general.box.card", childPath: "settings.general.box.card" }),
                    "a block in a block: the enclosing path and its own name");
        assertEqual(paths("settings.general.box", false, ""), JSON.stringify({ path: "", childPath: "settings.general.box" }),
                    "a block with no anchor: not addressable, adds no level");
        assertEqual(paths("settings.general.box.card", false, "settings"), JSON.stringify({ path: "", childPath: "" }),
                    "a block named like a region: not addressable, nor anything in it");
        assertEqual(paths("settings.general", false, "Bad name"), JSON.stringify({ path: "", childPath: "" }), "… a name that is not one: the same");
        assertEqual(paths("settings.general.saved.card", false, "settings", "region") + paths("settings.general.saved.card", false, "actions", "region")
                    + paths("settings.general.saved.card", false, "title", "region"),
                    JSON.stringify({ path: "settings.general.saved.card.settings", childPath: "" })
                    + JSON.stringify({ path: "settings.general.saved.card.actions", childPath: "" })
                    + JSON.stringify({ path: "settings.general.saved.card.title", childPath: "" }),
                    "a card's region: the card's path and the region's name; nothing addressable inside it");
        assertEqual(paths("popup.network.wifi.row", false, "title", "region") + paths("popup.network.wifi.row", false, "settings", "region")
                    + paths("popup.network.wired", false, "title", "region"),
                    JSON.stringify({ path: "popup.network.wifi.row.title", childPath: "" }) + JSON.stringify({ path: "", childPath: "" }).repeat(2),
                    "a row's region (1.32): only `title`, right under a row named \"row\"");
        assertEqual([paths("settings.general.saved", false, "settings", "region"), paths("settings.general.saved.card.actions", false, "settings", "region"),
                     paths("settings.general.saved.card", false, "box", "region"), paths("settings.general.saved.card", false, "", "region"),
                     paths("settings.general.saved.card", true, undefined, "region"), paths("", false, "settings", "region")].join(""),
                    JSON.stringify({ path: "", childPath: "" }).repeat(6),
                    "… not right under a card named \"card\" (under a section, under a region), not a region's name, no name, no card: not addressable");
        assertEqual(paths("", true, "box") + paths(undefined, false, "") + paths("nowhere", true, "", "page"), JSON.stringify({ path: "", childPath: "" }).repeat(3),
                    "no base and no enclosing block (or a base that is not a place): nothing addressable");

        // --- which block's host shows a row's elements ---
        const sectionRow = row("settings.fixture.box", ["before", "append"], { kind: "section" });
        assert(rules.anchorBlockFits(sectionRow, "section", ["before", "after", "prepend", "append"], "append"),
               "anchorBlockFits: a block of the row's kind with the placement");
        assert(!rules.anchorBlockFits(sectionRow, "card", ["before", "append"], "append"), "… not one of another kind");
        assert(!rules.anchorBlockFits(sectionRow, "section", ["prepend"], "append"), "… not a placement the block has no host for");
        assert(!rules.anchorBlockFits(sectionRow, "section", ["prepend", "after"], "after"), "… not a placement the row does not take");
        assert(!rules.anchorBlockFits(null, "section", ["append"], "append") && !rules.anchorBlockFits(sectionRow, undefined, null, "append"),
               "… no row, no kind, no placements: no (no throw)");

        // --- today's slots ---
        assertEqual(rules.slotAliases.map(alias => alias.slot).join(","), rules.slotNames.filter(name => name !== "network.vpn.page").join(","),
                    "every slot but network.vpn.page has an alias, in the slot table's order");
        for (const alias of rules.slotAliases) {
            assert(rules.anchorPathProblem(alias.at) === "" && rules.anchorPlacements.includes(alias.place) && rules.isObject(alias.context),
                   "an alias names a place and a placement: " + alias.slot + " → " + alias.at + ", " + alias.place);
            const slotContext = rules.slotTable.find(entry => entry.name === alias.slot).context;
            assert(Array.isArray(alias.needs) && alias.needs.length > 0
                   && alias.needs.concat(Object.keys(alias.context)).every(key => new RegExp("\\b" + key + "\\b").test(slotContext)),
                   "… what the block's context must give: keys the slot's context documents — " + alias.slot);
            assert(!/lock|screensaver/.test(alias.at), "… never on the lock screen");
        }
        assertEqual(rules.slotAlias("network.vpn.card")?.at + " " + rules.slotAlias("network.vpn.card")?.place + " " + rules.slotAlias("network.vpn.card")?.context.open,
                    "settings.network_vpn.vpns.card.settings prepend true", "slotAlias: the VPN card's, its context still saying open");
        assertEqual(rules.slotAlias("network.vpn.page") + "," + rules.slotAlias("constructor"), "null,null", "… none for the page or a name that is no slot");

        // --- the guard for slots read as anchors (tests/AnchorsTest.qml runs it on the files) ---
        const generalRow = [row("settings.general", ["append"])];
        const converted = "SettingsPage {\n    context: ({ editIndex: root.editIndex })\n}";
        assertEqual(rules.slotAliasProblems([], rules.slotAliases, { "settings.general.bottom": ["x.qml"] }, {}).join("; "), "",
                    "slotAliasProblems: an alias whose place is not published is not checked");
        assertEqual(rules.slotAliasProblems(generalRow, rules.slotAliases, {}, { "panels/settings/GeneralSettings.qml": converted }).join("; "), "",
                    "… a converted view: no slot left, the page built, editIndex in its context");
        const still = rules.slotAliasProblems(generalRow, rules.slotAliases, { "settings.general.bottom": ["panels/settings/GeneralSettings.qml"] },
                                              { "panels/settings/GeneralSettings.qml": "ColumnLayout {\n}" });
        for (const fragment of ["the slot is still built in panels/settings/GeneralSettings.qml", "builds no SettingsPage",
                                "gives no editIndex in the block's context"])
            assert(_has(still, fragment), "… a view not converted: " + fragment + " — " + still.join("; "));
        const cardRow = [row("settings.network_vpn.vpns.card.settings", ["prepend"], { kind: "region", scope: "own-provider", view: "panels/settings/VpnSettings.qml" })];
        const cardProblems = rules.slotAliasProblems(cardRow, rules.slotAliases, {}, { "panels/settings/VpnSettings.qml": "SettingsCard {\n    anchor: \"vpns\"\n}" });
        assert(_has(cardProblems, "names no block \"card\"") && _has(cardProblems, "gives no vpnId"),
               "… a region: its card named \"card\" in the view, the item's keys given — " + cardProblems.join("; "));
        assert(_has(rules.slotAliasProblems(cardRow, rules.slotAliases, {}, {}), "cannot be read"), "… a view not read: said so");

        // --- the manifest's anchors ---
        const read = (anchors) => {
            const errors = [];
            const warnings = [];
            const kept = ModuleManifestRules.readAnchors({ anchors: anchors }, errors, warnings);
            return { kept: kept, errors: errors, warnings: warnings };
        };
        const fine = read([{ at: "settings.general", place: "append", component: "Row.qml" },
                           { at: "settings.general", place: "prepend", component: "Row.qml" },
                           { at: "settings.general", place: "append", component: "sub/Other.qml" }]);
        assertEqual(JSON.stringify(fine.kept), JSON.stringify([{ at: "settings.general", place: "append", component: "Row.qml" },
                                                               { at: "settings.general", place: "prepend", component: "Row.qml" },
                                                               { at: "settings.general", place: "append", component: "sub/Other.qml" }]),
                    "anchors: { at, place, component } kept in manifest order");
        assertEqual(fine.errors.length + fine.warnings.length, 0, "… no error, no warning");
        const twice = read([{ at: "settings.general", place: "append", component: "Row.qml" }, { at: "settings.general", place: "append", component: "Row.qml" }]);
        assertEqual(twice.kept.length, 1, "the same three twice: the second dropped");
        assertEqual(twice.errors.join("|"), "anchors: \"Row.qml\" is named twice for \"settings.general\", \"append\" (the second is ignored)", "… said");
        const wrong = read([{ at: "bar.clock", place: "append", component: "A.qml" }, { at: "settings.general", place: "inside", component: "A.qml" },
                            { at: "settings.general", place: "append", component: "../A.qml" }, { at: "settings.general", place: "append" },
                            { at: "settings.general", place: "append", component: "A.qml", order: 3 }, "x"]);
        assertEqual(wrong.kept.length, 1, "malformed entries dropped, the last kept");
        for (const fragment of ["anchors[0]: at: \"bar.clock\" does not start with", "anchors[1]: place \"inside\" is not one of before, after, prepend, append",
                                "anchors[2]: component", "anchors[3]: component is missing", "anchors[5]: not an object"])
            assert(_has(wrong.errors, fragment), "… said: " + fragment);
        assert(_has(wrong.warnings, "anchors[4]: unknown field \"order\""), "an unknown field of an entry: a warning");
        const notList = read({ at: "settings.general" });
        assertEqual(notList.kept.length + " " + notList.errors.join(""), "0 anchors: not a list (ignored)", "anchors not a list: ignored, said");
        assertEqual(read(undefined).kept.length + read(undefined).errors.length, 0, "no anchors: none, nothing said");

        // --- against the table ---
        const manifest = { anchors: [{ at: "settings.general", place: "append", component: "Row.qml" },
                                     { at: "settings.general", place: "prepend", component: "Row.qml" },
                                     { at: "settings.nowhere", place: "append", component: "Gone.qml" },
                                     { at: "settings.fixture.box", place: "before", component: "Box.qml" }],
                           slots: [{ slot: "settings.general.bottom", component: "Bottom.qml" }, { slot: "network.vpn.row", component: "VpnRow.qml" },
                                   { slot: "network.vpn.page", component: "Page.qml" }, { slot: "settings.general.bottom", component: "Row.qml" },
                                   { slot: "network.vpn.card", component: "Card.qml" }] };
        assertEqual(ModuleMergeRules.anchorErrors(manifest, table).join("|"),
                    "anchors: \"settings.general\" does not take \"prepend\" (it takes: append)|anchors: \"settings.nowhere\" is not a place this shell offers (module API "
                    + rules.apiVersion + ")", "anchorErrors: a placement the place does not take, a place not offered");
        assertEqual(ModuleMergeRules.anchorErrors(manifest, rules.anchorTable).join("|"),
                    "anchors: \"settings.general\" does not take \"prepend\" (it takes: append)|anchors: \"settings.nowhere\" is not a place this shell offers (module API "
                    + rules.apiVersion + ")|anchors: \"settings.fixture.box\" is not a place this shell offers (module API " + rules.apiVersion + ")",
                    "… on this shell's table: General's append taken, the rest errors");
        assertEqual(ModuleMergeRules.anchorErrors(null, table).length + ModuleMergeRules.anchorErrors({}, null).length, 0, "… nothing to check: none, no throw");
        const asAnchors = ModuleMergeRules.slotsAsAnchors(manifest, table);
        assertEqual(asAnchors.map(entry => entry.slot + ">" + entry.at + "," + entry.place + "," + entry.component).join("|"),
                    "settings.general.bottom>settings.general,append,Bottom.qml|settings.general.bottom>settings.general,append,Row.qml|network.vpn.card>settings.network_vpn.vpns.card.settings,prepend,Card.qml",
                    "slotsAsAnchors: the slots whose alias the table offers, in manifest order — not network.vpn.row (its view not converted), never the page");
        assertEqual(JSON.stringify(asAnchors[0].context) + JSON.stringify(asAnchors[2].context),
                    JSON.stringify({ slot: "settings.general.bottom" }) + JSON.stringify({ open: true, slot: "network.vpn.card" }),
                    "… each one's context carrying its slot, the card's open: true");
        assertEqual(ModuleMergeRules.slotsAsAnchors(manifest, rules.anchorTable).map(entry => entry.slot + ">" + entry.at + "," + entry.component).join("|"),
                    "settings.general.bottom>settings.general,Bottom.qml|network.vpn.row>popup.network.connections.vpn.row,VpnRow.qml|"
                    + "settings.general.bottom>settings.general,Row.qml|network.vpn.card>settings.network_vpn.vpns.card.settings,Card.qml",
                    "… on this shell's table: the General slot's and the VPN row's and card's, never the page");
        assertEqual(ModuleMergeRules.slotDeprecations(manifest, table)[0],
                    "slots (\"settings.general.bottom\"): use `anchors`: \"settings.general\", \"append\" (goes with the shell's next tightening)",
                    "slotDeprecations: a slot read as an anchor is an old way, listed");
        assertEqual(ModuleMergeRules.slotDeprecations(manifest, table).length + "," + ModuleMergeRules.slotDeprecations(manifest, []).length, "3,0",
                    "… one per slot read as an anchor; none while the slot stays a slot");
        const entries = ModuleMergeRules.anchorEntries(manifest, table);
        assertEqual(entries.map(entry => entry.at + "," + entry.place + "," + entry.component).join("|"),
                    "settings.general,append,Row.qml|settings.fixture.box,before,Box.qml|settings.general,append,Bottom.qml|settings.network_vpn.vpns.card.settings,prepend,Card.qml",
                    "anchorEntries: the anchors the table takes, then the slots read as anchors — the slot naming a file already there left out");
        assertEqual(JSON.stringify(entries[0].context) + JSON.stringify(entries[2].context), "{}" + JSON.stringify({ slot: "settings.general.bottom" }),
                    "… an anchor's own context empty, a slot's its name");
        assertEqual(ModuleMergeRules.anchorEntries({}, table).length + ModuleMergeRules.anchorEntries(null, null).length, 0, "… none: empty, no throw");

        // --- what one host shows ---
        const merged = [
            { module: "zeta", at: "settings.general", place: "append", component: "file:///z/A.qml", context: {} },
            { module: "alpha", at: "settings.general", place: "append", component: "file:///a/Second.qml", context: {} },
            { module: "alpha", at: "settings.general", place: "prepend", component: "file:///a/Top.qml", context: {} },
            { module: "beta", at: "settings.general", place: "append", component: "file:///b/B.qml", context: {} },
            { module: "alpha", at: "settings.general", place: "append", component: "file:///a/First.qml", context: {} },
            { module: "alpha", at: "settings.general.box", place: "append", component: "file:///a/Box.qml", context: {} },
            null, { at: "settings.general", place: "append" }];
        const shown = ModuleMergeRules.anchorContent(merged, "settings.general", "append");
        assertEqual(shown.map(entry => entry.module + ":" + entry.component.split("/").pop()).join(","), "alpha:Second.qml,alpha:First.qml,beta:B.qml,zeta:A.qml",
                    "anchorContent: by module id, a module's together in their order — whatever order they came in");
        assertEqual(shown[0].key, "alpha|file:///a/Second.qml", "… each with its key (module and file)");
        assertEqual(ModuleMergeRules.anchorContent(merged, "settings.general", "prepend").length + ","
                    + ModuleMergeRules.anchorContent(merged, "settings.general.box", "append").length, "1,1", "… only that path and placement");
        assertEqual(ModuleMergeRules.anchorContent(merged, "settings.general", "append", "beta").map(entry => entry.module).join(","), "beta",
                    "… scoped: only the module the item belongs to");
        assertEqual(ModuleMergeRules.anchorContent(merged, "settings.general", "append", "").length, 0, "… scoped to no module: none");
        assertEqual(ModuleMergeRules.anchorContent(null, "x", "append").length + ModuleMergeRules.anchorContent(merged, "", "append").length
                    + ModuleMergeRules.anchorContent(merged, "settings.general", null).length, 0, "… nothing asked: none, no throw");
        assertEqual(merged[0].key, undefined, "… the merged list untouched");

        // --- the manifest, the file check and the merge (API 1.20) ---
        const anchored = ModuleManifestRules.parseManifest(_manifest({ id: "anch", api: "1.20",
            anchors: [{ at: "settings.general", place: "append", component: "Row.qml" }, { at: "settings.fixture.box", place: "before", component: "sub/Box.qml" }],
            slots: [{ slot: "settings.general.bottom", component: "Bottom.qml" }, { slot: "network.vpn.row", component: "VpnRow.qml" }] }));
        assert(anchored.valid && anchored.anchors.length === 2 && anchored.warnings.length === 0 && anchored.errors.length === 0,
               "parseManifest: anchors read, a known field: " + anchored.warnings.concat(anchored.errors).join("; "));
        const olderAnchors = ModuleManifestRules.parseManifest(_manifest({ id: "anch", api: "1.19", anchors: [{ at: "settings.general", place: "append", component: "Row.qml" }] }));
        assert(olderAnchors.valid && olderAnchors.anchors.length === 1 && _has(olderAnchors.warnings, "anchors: a field of API 1.20, the manifest asks for API 1.19 (read all the same)"),
               "anchors with api 1.19: read all the same, with a warning");
        assertEqual(ModuleManifestRules.parseManifest(_manifest({ id: "anch", api: "1.20", anchors: [{ at: "x", place: "append", component: "A.qml" }] })).errors.length, 1,
                    "… a malformed entry: an error, the module valid");
        assert(ModuleFileRules.manifestFiles(anchored).includes("Row.qml") && ModuleFileRules.manifestFiles(anchored).includes("sub/Box.qml"),
               "the file check reads the anchors' files (their imports, their roots' properties)");
        const badAnchorFile = ModuleFileRules.withoutBadFiles(anchored, { "sub/Box.qml": "is not a regular file" }, "");
        assertEqual(badAnchorFile.manifest.anchors.map(entry => entry.component).join(",") + " | " + badAnchorFile.errors.join(""),
                    "Row.qml | anchors settings.fixture.box, before: sub/Box.qml is not a regular file (dropped)", "… an anchor whose file fails it: dropped, said");
        const mergedAnchors = ModuleMergeRules.merge([{ id: "anch", directory: "/m/anch", manifest: anchored }], table);
        assertEqual(JSON.stringify(mergedAnchors.anchors), JSON.stringify([
            { module: "anch", at: "settings.general", place: "append", component: "file:///m/anch/Row.qml", context: {} },
            { module: "anch", at: "settings.fixture.box", place: "before", component: "file:///m/anch/sub/Box.qml", context: {} },
            { module: "anch", at: "settings.general", place: "append", component: "file:///m/anch/Bottom.qml", context: { slot: "settings.general.bottom" } }]),
                    "merge with a table: the anchors it takes and the slots read as anchors, by URL, naming the module");
        assertEqual(Object.keys(mergedAnchors.slots).join(","), "network.vpn.row", "… a slot read as an anchor leaves the slots");
        const mergedHere = ModuleMergeRules.merge([{ id: "anch", directory: "/m/anch", manifest: anchored }]);
        assertEqual(mergedHere.anchors.map(entry => entry.component.replace("file:///m/anch/", "")).join(",") + " " + Object.keys(mergedHere.slots).join(","),
                    "Row.qml,Bottom.qml,VpnRow.qml ", "merge on this shell's table: the General page's anchor, its slot and the VPN row's slot read as anchors");
    }

    // API 1.18: a module's API for other modules — `exports` and `uses` in the manifest, the
    // dependency plan (order, each reason, cycles, duplicates), what a main may offer
    function _dependencies(rules) {
        // --- the manifest ---
        const provider = ModuleManifestRules.parseManifest(_manifest({ id: "prov", api: "1.18", exports: { version: "1.2" } }));
        assert(provider.valid && provider.exports?.version === "1.2" && provider.warnings.length === 0, "exports: { version } read, no warning");
        const olderApi = ModuleManifestRules.parseManifest(_manifest({ id: "prov", api: "1.17", exports: { version: "1.2" }, uses: { zeta: "1.0" } }));
        assert(olderApi.valid && olderApi.exports?.version === "1.2" && olderApi.uses.length === 1, "exports and uses with api 1.17: read all the same");
        assert(_has(olderApi.warnings, "exports: a field of API 1.18, the manifest asks for API 1.17")
               && _has(olderApi.warnings, "uses: a field of API 1.18, the manifest asks for API 1.17"), "… each said in a warning: " + olderApi.warnings.join("; "));
        assertEqual(ModuleManifestRules.parseManifest(_manifest({ api: "1.18", uses: { zeta: "1.0" } })).warnings.length, 0, "uses with api 1.18: no warning");
        assertEqual(ModuleManifestRules.parseManifest(_manifest({ api: "1.17" })).warnings.length, 0, "api 1.17 without them: no warning");
        const plain = ModuleManifestRules.parseManifest(_manifest());
        assert(plain.exports === null && plain.uses.length === 0, "none given: exports null, uses []");
        for (const bad of [7, "1.0", [], { version: "1" }, { version: 1.2 }, {}]) {
            const parsed = ModuleManifestRules.parseManifest(_manifest({ exports: bad }));
            assert(!parsed.valid && parsed.exports === null && _has(parsed.errors, "exports"), "exports " + JSON.stringify(bad) + ": the module fails, said: " + parsed.errors.join("; "));
        }
        assert(_has(ModuleManifestRules.parseManifest(_manifest({ exports: { version: "1.0", extra: 1 } })).warnings, "exports: unknown field \"extra\""),
               "exports: an unknown field is a warning");
        const user = ModuleManifestRules.parseManifest(_manifest({ uses: { zeta: "1.0", alpha: "2.3" } }));
        assert(user.valid, "uses: valid");
        assertEqual(JSON.stringify(user.uses), "[{\"id\":\"zeta\",\"version\":\"1.0\",\"optional\":false,\"source\":\"\"},{\"id\":\"alpha\",\"version\":\"2.3\",\"optional\":false,\"source\":\"\"}]",
                    "uses: [{ id, version, optional, source }] in the manifest's order, a version alone hard, no source");
        // (1.30) The object form: soft with optional true, hard without
        const soft = ModuleManifestRules.parseManifest(_manifest({ api: "1.30", uses: { zeta: { version: "1.2", optional: true }, alpha: { version: "2.0" },
                                                                                     beta: { version: "1.0", optional: false } } }));
        assertEqual(JSON.stringify(soft.uses.map(use => use.id + " " + use.version + " " + use.optional)), JSON.stringify(["zeta 1.2 true", "alpha 2.0 false", "beta 1.0 false"]),
                    "uses as objects: optional true is soft, none or false is hard");
        assert(soft.valid && soft.warnings.length === 0, "… valid, no warning with api 1.30: " + soft.warnings.join("; "));
        const softOld = ModuleManifestRules.parseManifest(_manifest({ api: "1.29", uses: { zeta: { version: "1.2", optional: true } } }));
        assert(softOld.valid && softOld.uses[0]?.optional === true && _has(softOld.warnings, "uses: an entry as an object is a form of API 1.30, the manifest asks for API 1.29"),
               "the object form with api 1.29: read all the same, said in a warning: " + softOld.warnings.join("; "));
        const softExtra = ModuleManifestRules.parseManifest(_manifest({ api: "1.30", uses: { zeta: { version: "1.2", optinal: true } } }));
        assert(softExtra.valid && softExtra.uses[0]?.optional === false && _has(softExtra.warnings, "uses.zeta: unknown field \"optinal\" (ignored)"),
               "an unknown field in a use: a warning, the use hard: " + softExtra.warnings.join("; "));
        for (const bad of [{ zeta: { optional: true } }, { zeta: { version: "1", optional: true } }, { zeta: { version: "1.0", optional: "yes" } },
                           { zeta: { version: "1.0", optional: 1 } }, { zeta: {} }]) {
            const parsed = ModuleManifestRules.parseManifest(_manifest({ api: "1.30", uses: bad }));
            assert(!parsed.valid && _has(parsed.errors, "uses.zeta"), "uses " + JSON.stringify(bad) + ": the module fails, said: " + parsed.errors.join("; "));
        }
        for (const bad of [[], "zeta", 3, { "Zeta": "1.0" }, { "battery": "1.0" }, { "zeta": "1" }, { "zeta": 1 }, { "constructor": "1.0" }]) {
            const parsed = ModuleManifestRules.parseManifest(_manifest({ uses: bad }));
            assert(!parsed.valid && _has(parsed.errors, "uses"), "uses " + JSON.stringify(bad) + ": the module fails, said: " + parsed.errors.join("; "));
        }
        assert(ModuleManifestRules.parseManifest(_manifest({ uses: { tailscale: "1.0" } })).valid, "uses itself: read (the plan names it)");
        assert(!ModuleManifestRules.parseManifest('{"id":"x","name":"X","version":"1","api":"1.0","uses":{"__proto__":"1.0"}}').valid,
               "uses: \"__proto__\" is no module id");
        assert(rules.states.includes("missing-module"), "the states include missing-module");

        // --- (1.36) author, privileged, a use's source ---
        const declaring = ModuleManifestRules.parseManifest(_manifest({ author: "Anna Nowak", optionalPrograms: ["tailscale", "pkexec"],
                                                                         requires: { programs: ["systemctl"] },
                                                                         privileged: { why: "Connect, change Tailscale's settings", programs: ["tailscale", "systemctl", "tailscale"] } }));
        assert(declaring.valid && declaring.errors.length === 0 && declaring.warnings.length === 0,
               "author and privileged: valid, no warning — read whatever api the manifest asks for (1.0 here): " + declaring.errors.concat(declaring.warnings).join("; "));
        assertEqual(declaring.author, "Anna Nowak", "author read");
        assertEqual(JSON.stringify(declaring.privileged), JSON.stringify({ why: "Connect, change Tailscale's settings", programs: ["tailscale", "systemctl"] }),
                    "privileged: { why, programs } — names among requires.programs and optionalPrograms, a repeat kept once");
        assert(!declaring.unknownFields.includes("author") && !declaring.unknownFields.includes("privileged"), "… neither is an unknown field");
        const undeclaring = ModuleManifestRules.parseManifest(_manifest());
        assert(undeclaring.author === "" && undeclaring.privileged === null, "none given: author \"\", privileged null");
        assert(ModuleManifestRules.parseManifest(_manifest({ privileged: { why: "Print", programs: [] } })).privileged?.programs.length === 0,
               "privileged with no programs: valid (module.privileged.start may run nothing)");
        for (const bad of [7, "", " ", "Anna\nNowak", "Anna\u202eNowak", "x".repeat(101), ["Anna"], null]) {
            const parsed = ModuleManifestRules.parseManifest(_manifest({ author: bad }));
            assert(!parsed.valid && parsed.author === "" && _has(parsed.errors, "author:"), "author " + JSON.stringify(bad) + ": the module fails, said: " + parsed.errors.join("; "));
        }
        assert(ModuleManifestRules.parseManifest(_manifest({ author: "x".repeat(100) })).valid, "author of 100 characters: fine");
        const programsGiven = { optionalPrograms: ["tailscale"] };
        for (const bad of [true, "tailscale", ["tailscale"], null, {}, { why: "Connect" }, { programs: ["tailscale"] },
                           { why: "", programs: ["tailscale"] }, { why: "Two\nlines", programs: ["tailscale"] }, { why: "x".repeat(201), programs: ["tailscale"] },
                           { why: 3, programs: ["tailscale"] }, { why: "Connect", programs: "tailscale" }, { why: "Connect", programs: ["nft"] },
                           { why: "Connect", programs: [7] }, { why: "Connect", programs: ["tailscale", "/usr/bin/tailscale"] }]) {
            const parsed = ModuleManifestRules.parseManifest(_manifest(Object.assign({ privileged: bad }, programsGiven)));
            assert(!parsed.valid && parsed.privileged === null && _has(parsed.errors, "privileged"),
                   "privileged " + JSON.stringify(bad) + ": the module fails, never silently ignored: " + parsed.errors.join("; "));
        }
        const extraField = ModuleManifestRules.parseManifest(_manifest(Object.assign({ privileged: { why: "Connect", programs: ["tailscale"], sandbox: true } }, programsGiven)));
        assert(extraField.valid && _has(extraField.warnings, "privileged: unknown field \"sandbox\""), "privileged: an unknown field is a warning");
        assert(!ModuleManifestRules.parseManifest('{"id":"Bad","name":"X","version":"1","api":"1.0","privileged":{"why":"x","programs":[]}}').valid,
               "privileged without a usable id: invalid all the same");
        const sourced = ModuleManifestRules.parseManifest(_manifest({ api: "1.36", uses: {
            clipboard: { version: "0.2", source: "https://github.com/anna/h2s-clipboard#v0.2.0" },
            agenda: { version: "1.0", optional: true, source: "ext::sh -c touch% /tmp/x" },
            notes: { version: "1.0", source: 5 } } }));
        assert(sourced.valid, "a use's source that is no address: the module still loads: " + sourced.errors.join("; "));
        assertEqual(JSON.stringify(sourced.uses.map(use => use.id + " " + use.source)),
                    JSON.stringify(["clipboard https://github.com/anna/h2s-clipboard#v0.2.0", "agenda ", "notes "]),
                    "uses' sources: an address kept, others void");
        assert(_has(sourced.errors, "uses.agenda.source:") && _has(sourced.errors, "uses.notes.source:") && !_has(sourced.errors, "uses.clipboard")
               && sourced.warnings.length === 0, "… each void source an error, no unknown-field warning: " + sourced.errors.concat(sourced.warnings).join("; "));

        // --- the version check ---
        assert(ModuleMergeRules.usesFit("1.1", "1.2").fits && ModuleMergeRules.usesFit("1.2", "1.2").fits, "uses: the same major, the provider's minor at least the one asked");
        assertEqual(ModuleMergeRules.usesFit("1.3", "1.2").reason, "has 1.2", "… an older minor: \"has 1.2\"");
        assert(!ModuleMergeRules.usesFit("1.0", "2.0").fits && !ModuleMergeRules.usesFit("2.0", "1.9").fits, "… another major: not");
        assert(!ModuleMergeRules.usesFit("1.0", "x").fits && !ModuleMergeRules.usesFit(null, "1.0").fits, "… unreadable: not");

        // --- the plan ---
        const module = (id, uses, exportsVersion) => ({ id: id, uses: Object.keys(uses ?? {}).map(other => ({ id: other, version: uses[other] })),
                                                        exports: exportsVersion ? { version: exportsVersion } : null });
        const all = (ids, state) => {
            const states = {};
            for (const id of ids)
                states[id] = { state: state ?? "loaded", exports: "" };
            return states;
        };
        const summary = plan => plan.modules.map(entry => entry.id + ":" + entry.state).join(",");
        const reasons = (plan, id) => (ModuleMergeRules.planned(plan, id)?.reasons ?? []).join("; ");

        let plan = ModuleMergeRules.dependencyPlan([module("app", { lib: "1.0" }), module("lib", { base: "1.0" }, "1.0"), module("base", {}, "1.4"),
                                                    module("alone")], all(["app", "lib", "base", "alone"]));
        assertEqual(plan.order.join(","), "alone,base,lib,app", "order: by id, each after what it uses");
        assertEqual(summary(plan), "alone:loaded,base:loaded,lib:loaded,app:loaded", "all there and fitting: all loaded, in that order");
        assertEqual(plan.cycles.length, 0, "… no cycle");

        plan = ModuleMergeRules.dependencyPlan([module("app", { lib: "1.0" })], all(["app"]));
        assertEqual(summary(plan), "app:missing-module", "a provider not there: missing-module");
        assertEqual(reasons(plan, "app"), "needs module lib 1.0: not installed", "… \"not installed\"");

        const pair = [module("app", { lib: "1.3" }), module("lib", {}, "1.2")];
        plan = ModuleMergeRules.dependencyPlan(pair, all(["app", "lib"]));
        assertEqual(summary(plan) + " " + reasons(plan, "app"), "lib:loaded,app:missing-module needs module lib 1.3: has 1.2", "an older exports version: \"has 1.2\"");
        plan = ModuleMergeRules.dependencyPlan([module("app", { lib: "1.0" }), module("lib", {}, "2.0")], all(["app", "lib"]));
        assertEqual(reasons(plan, "app"), "needs module lib 1.0: has 2.0", "another major: \"has 2.0\"");
        plan = ModuleMergeRules.dependencyPlan([module("app", { lib: "1.0" }), module("lib")], all(["app", "lib"]));
        assertEqual(reasons(plan, "app"), "needs module lib 1.0: exports no API", "a provider without exports: \"exports no API\"");

        const fits = [module("app", { lib: "1.0" }), module("lib", {}, "1.0")];
        for (const [state, said] of [["disabled", "turned off"], ["failed", "failed"], ["incompatible", "incompatible with this shell"],
                                     ["missing-program", "missing a program"], ["safe-mode", "not loaded (safe mode)"],
                                     ["unconfirmed", "new, not enabled yet"], ["approval", "waiting for approval"]]) {
            const states = all(["app", "lib"]);
            states.lib.state = state;
            plan = ModuleMergeRules.dependencyPlan(fits, states);
            assertEqual(summary(plan) + " " + reasons(plan, "app"), "lib:" + state + ",app:missing-module needs module lib 1.0: " + said,
                        "a provider " + state + ": the dependent missing-module, \"" + said + "\"");
        }
        let states = all(["app", "lib"]);
        states.lib.state = "pending";
        assertEqual(summary(ModuleMergeRules.dependencyPlan(fits, states)), "lib:pending,app:pending", "a provider pending: the dependent waits (pending)");
        states = all(["app", "lib"]);
        states.lib.exports = "it declares exports but its main has no `exports` property";
        plan = ModuleMergeRules.dependencyPlan(fits, states);
        assertEqual(summary(plan) + " " + reasons(plan, "app"), "lib:loaded,app:missing-module needs module lib 1.0: gives no exports object",
                    "a provider whose main gives no exports object: loaded itself, its dependent missing-module");
        states = all(["app", "lib"]);
        states.lib.exports = undefined;
        assertEqual(summary(ModuleMergeRules.dependencyPlan(fits, states)), "lib:loaded,app:loaded", "… not known yet (its main not made): taken as there");
        for (const state of ["disabled", "pending", "failed", "incompatible"]) {
            states = all(["app", "lib"]);
            states.app.state = state;
            states.lib.state = "disabled";
            plan = ModuleMergeRules.dependencyPlan(fits, states);
            assertEqual(ModuleMergeRules.planned(plan, "app").state + "|" + reasons(plan, "app"), state + "|", "a dependent " + state + " itself keeps that state, no reason added");
        }

        // A chain: a provider failing leaves its dependent missing a module, and that one's too
        states = all(["top", "mid", "low"]);
        states.low.state = "failed";
        plan = ModuleMergeRules.dependencyPlan([module("top", { mid: "1.0" }), module("mid", { low: "1.0" }, "1.0"), module("low", {}, "1.0")], states);
        assertEqual(summary(plan), "low:failed,mid:missing-module,top:missing-module", "a chain follows its provider");
        assertEqual(reasons(plan, "top"), "needs module mid 1.0: missing a module", "… \"missing a module\"");
        // Several reasons at once
        plan = ModuleMergeRules.dependencyPlan([module("app", { gone: "1.0", old: "1.5" }), module("old", {}, "1.0")], all(["app", "old"]));
        assertEqual(reasons(plan, "app"), "needs module gone 1.0: not installed; needs module old 1.5: has 1.0", "one reason per provider, in the manifest's order");

        // Cycles
        plan = ModuleMergeRules.dependencyPlan([module("a", { b: "1.0" }, "1.0"), module("b", { a: "1.0" }, "1.0"), module("c", { a: "1.0" })],
                                               all(["a", "b", "c"]));
        assertEqual(summary(plan), "b:failed,a:failed,c:missing-module", "a cycle: both failed; one using it missing-module (after them)");
        assertEqual(reasons(plan, "a"), "uses form a cycle: a → b → a", "… the cycle named, from the module");
        assertEqual(reasons(plan, "b"), "uses form a cycle: b → a → b", "… from the other");
        assertEqual(reasons(plan, "c"), "needs module a 1.0: failed", "… its dependent: the provider failed");
        assertEqual(JSON.stringify(plan.cycles), "[[\"a\",\"b\"]]", "… listed");
        plan = ModuleMergeRules.dependencyPlan([module("x", { y: "1.0" }, "1.0"), module("y", { z: "1.0" }, "1.0"), module("z", { x: "1.0" }, "1.0")],
                                               all(["x", "y", "z"]));
        assertEqual(reasons(plan, "x") + " | " + reasons(plan, "z"), "uses form a cycle: x → y → z → x | uses form a cycle: z → x → y → z", "a cycle of three named in its order");
        plan = ModuleMergeRules.dependencyPlan([module("self", { self: "1.0" }, "1.0")], all(["self"]));
        assertEqual(summary(plan) + " " + reasons(plan, "self"), "self:failed uses itself", "a module using itself: failed, \"uses itself\"");
        states = all(["a", "b"]);
        states.a.state = "disabled";
        plan = ModuleMergeRules.dependencyPlan([module("a", { b: "1.0" }, "1.0"), module("b", { a: "1.0" }, "1.0")], states);
        assertEqual(summary(plan), "b:failed,a:disabled", "a cycle: a member turned off stays off; the other fails");

        // (1.30) Soft uses: loaded with or without the provider, after it when it is there
        const softModule = (id, hard, soft, exportsVersion) => {
            const made = module(id, hard, exportsVersion);
            made.uses = made.uses.concat(Object.keys(soft ?? {}).map(other => ({ id: other, version: soft[other], optional: true })));
            return made;
        };
        const optional = (plan, id) => (ModuleMergeRules.planned(plan, id)?.optional ?? []).join(",");
        const notes = (plan, id) => (ModuleMergeRules.planned(plan, id)?.notes ?? []).join("; ");
        const softPair = [softModule("app", {}, { lib: "1.0" }), module("lib", {}, "1.2")];
        plan = ModuleMergeRules.dependencyPlan(softPair, all(["app", "lib"]));
        assertEqual(plan.order.join(",") + " " + summary(plan) + " " + optional(plan, "app"), "lib,app lib:loaded,app:loaded lib",
                    "soft, the provider there and fitting: after it, loaded, given it");
        assertEqual(plan.modules.find(entry => entry.id === "app").reasons.length + notes(plan, "app"), "0", "… no reason, no note");
        plan = ModuleMergeRules.dependencyPlan([softModule("app", {}, { lib: "1.0" })], all(["app"]));
        assertEqual(summary(plan) + " [" + optional(plan, "app") + "] [" + notes(plan, "app") + "]", "app:loaded [] []",
                    "soft, the provider not installed: loaded without it, nothing said");
        for (const [state, noted] of [["disabled", ""], ["failed", ""], ["missing-module", ""], ["incompatible", ""]]) {
            states = all(["app", "lib"]);
            states.lib.state = state;
            plan = ModuleMergeRules.dependencyPlan(softPair, states);
            assertEqual(summary(plan) + " [" + optional(plan, "app") + "] [" + notes(plan, "app") + "]", "lib:" + state + ",app:loaded [] [" + noted + "]",
                        "soft, the provider " + state + ": loaded without it, nothing said (its own status says it)");
        }
        states = all(["app", "lib"]);
        states.lib.state = "pending";
        assertEqual(summary(ModuleMergeRules.dependencyPlan(softPair, states)), "lib:pending,app:pending", "soft, the provider pending: the dependent waits for it");
        plan = ModuleMergeRules.dependencyPlan([softModule("app", {}, { lib: "2.0" }), module("lib", {}, "1.2")], states);
        assertEqual(summary(plan) + " [" + optional(plan, "app") + "] " + notes(plan, "app"), "lib:pending,app:loaded [] can use module lib 2.0: has 1.2",
                    "soft, the provider pending at a version that does not fit: not waited for, loaded without it, noted");
        plan = ModuleMergeRules.dependencyPlan([softModule("app", {}, { lib: "1.0" }), module("lib")], states);
        assertEqual(summary(plan) + " " + notes(plan, "app"), "lib:pending,app:loaded can use module lib 1.0: exports no API",
                    "soft, the provider pending and exporting nothing: not waited for either");
        plan = ModuleMergeRules.dependencyPlan([module("app", { lib: "2.0" }), module("lib", {}, "1.2")], states);
        assertEqual(summary(plan), "lib:pending,app:pending", "hard, the provider pending at a version that does not fit: waits (it says why once the provider settles)");
        plan = ModuleMergeRules.dependencyPlan([softModule("app", {}, { lib: "1.3" }), module("lib", {}, "1.2")], all(["app", "lib"]));
        assertEqual(summary(plan) + " [" + optional(plan, "app") + "] " + notes(plan, "app"), "lib:loaded,app:loaded [] can use module lib 1.3: has 1.2",
                    "soft, an older exports version: loaded without it, noted");
        plan = ModuleMergeRules.dependencyPlan([softModule("app", {}, { lib: "1.0" }), module("lib")], all(["app", "lib"]));
        assertEqual(notes(plan, "app"), "can use module lib 1.0: exports no API", "soft, a provider without exports: noted");
        states = all(["app", "lib"]);
        states.lib.exports = "no exports property";
        plan = ModuleMergeRules.dependencyPlan(softPair, states);
        assertEqual(summary(plan) + " [" + optional(plan, "app") + "] " + notes(plan, "app"), "lib:loaded,app:loaded [] can use module lib 1.0: gives no exports object",
                    "soft, a provider without its exports object: loaded without it, noted");
        plan = ModuleMergeRules.dependencyPlan([softModule("app", { must: "1.0" }, { lib: "1.0" }), module("lib", {}, "1.0")], all(["app", "lib"]));
        assertEqual(summary(plan) + " " + reasons(plan, "app") + " [" + optional(plan, "app") + "]", "lib:loaded,app:missing-module needs module must 1.0: not installed []",
                    "a hard use missing beside a soft one there: missing-module, the soft one not given");
        // Cycles through soft edges: broken, never an error
        plan = ModuleMergeRules.dependencyPlan([softModule("a", {}, { b: "1.0" }, "1.0"), module("b", { a: "1.0" }, "1.0")], all(["a", "b"]));
        assertEqual(plan.order.join(",") + " " + summary(plan) + " " + plan.cycles.length, "a,b a:loaded,b:loaded 0",
                    "a cycle closed by a soft edge (a softly uses b, b needs a): broken, b after a, both loaded, no cycle");
        assertEqual("[" + optional(plan, "a") + "] " + notes(plan, "a"), "[] can use module b 1.0: left out, a cycle of uses", "… a does not get b, noted");
        plan = ModuleMergeRules.dependencyPlan([softModule("a", {}, { b: "1.0" }, "1.0"), softModule("b", {}, { a: "1.0" }, "1.0")], all(["a", "b"]));
        assertEqual(plan.order.join(",") + " " + summary(plan) + " a[" + optional(plan, "a") + "] b[" + optional(plan, "b") + "]", "b,a b:loaded,a:loaded a[b] b[]",
                    "two soft edges in a cycle: the first by id kept (a gets b), the other broken");
        plan = ModuleMergeRules.dependencyPlan([softModule("x", {}, { y: "1.0" }, "1.0"), module("y", { z: "1.0" }, "1.0"), module("z", { x: "1.0" }, "1.0")],
                                               all(["x", "y", "z"]));
        assertEqual(plan.order.join(",") + " " + summary(plan) + " " + notes(plan, "x"), "x,z,y x:loaded,z:loaded,y:loaded can use module y 1.0: left out, a cycle of uses",
                    "a cycle of three with one soft edge: broken there, the hard chain in order");
        plan = ModuleMergeRules.dependencyPlan([softModule("self", {}, { self: "1.0" }, "1.0")], all(["self"]));
        assertEqual(summary(plan) + " " + notes(plan, "self"), "self:loaded can use module self 1.0: left out, a cycle of uses", "a module softly using itself: loaded, noted");
        plan = ModuleMergeRules.dependencyPlan([softModule("a", { b: "1.0" }, { c: "1.0" }, "1.0"), module("b", { a: "1.0" }, "1.0"), module("c", {}, "1.0")],
                                               all(["a", "b", "c"]));
        assertEqual(summary(plan), "b:failed,c:loaded,a:failed", "a hard cycle stays an error with a soft edge beside it");

        // Duplicates: the first manifest of an id counts; one provider serves several
        plan = ModuleMergeRules.dependencyPlan([module("lib", {}, "1.0"), module("lib", { gone: "1.0" }, "0.1"), module("one", { lib: "1.0" }),
                                                module("two", { lib: "1.0" })], all(["lib", "one", "two"]));
        assertEqual(summary(plan), "lib:loaded,one:loaded,two:loaded", "a second manifest of an id ignored; two dependents of one provider both loaded");
        assertEqual(plan.order.length, 3, "… one entry per id");

        // Hostile input: no throw, nothing planned from garbage
        for (const input of [null, undefined, 7, "x", [null, 7, "a", { id: 3 }, { id: "" }, { id: "ok", uses: "no" }, { id: "ok2", uses: [null, { id: 1 }] }]]) {
            plan = ModuleMergeRules.dependencyPlan(input, null);
            assert(Array.isArray(plan.order) && Array.isArray(plan.modules), "dependencyPlan(" + JSON.stringify(input) + "): no throw");
        }
        assertEqual(summary(ModuleMergeRules.dependencyPlan([{ id: "ok", uses: "no" }], {})), "ok:failed", "a module whose state is not given: failed");
        assertEqual(ModuleMergeRules.planned(null, "x"), null, "planned(nothing): null");

        // --- what a main may offer as exports ---
        const qtObject = extra => Object.assign({ objectName: "", destroy: () => {} }, extra ?? {});
        const offered = qtObject();
        assertEqual(rules.exportsOf({ exports: offered }).object, offered, "a plain QtObject of its own: given");
        assertEqual(rules.exportsOf({ exports: offered }).problem, "", "… no problem");
        assert(_has([rules.exportsOf(null).problem], "no main"), "no main: said");
        assert(_has([rules.exportsOf({}).problem], "no `exports` property"), "no exports property: said");
        assert(_has([rules.exportsOf({ exports: null }).problem], "null"), "exports null: said");
        const mainItself = qtObject();
        mainItself.exports = mainItself;
        assert(_has([rules.exportsOf(mainItself).problem], "the main itself"), "the main itself: refused");
        assert(_has([rules.exportsOf({ exports: { greet: () => "hi" } }).problem], "not a QtObject"), "plain data: refused");
        assert(_has([rules.exportsOf({ exports: qtObject({ parent: null }) }).problem], "`parent`"), "something with a parent (an Item): refused");
        assertEqual(rules.exportsOf({ exports: 7 }).object, null, "a number: nothing given");
        const handleLike = qtObject({ moduleId: "provider" });
        const hostLike = qtObject();
        assert(_has([rules.exportsOf({ exports: handleLike }, [hostLike, handleLike]).problem], "the shell's"), "a module's handle: refused");
        assertEqual(rules.exportsOf({ exports: handleLike }, [hostLike, handleLike]).object, null, "… nothing given");
        assert(_has([rules.exportsOf({ exports: hostLike }, [hostLike, handleLike]).problem], "the shell's"), "the host: refused");
        assertEqual(rules.exportsOf({ exports: offered }, [hostLike, handleLike]).object, offered, "an object of its own, beside the refused: given");
    }

    // API 1.3: Api.networks and Api.vpnsUp — the pure mappings, on realistic and hostile input
    function _api13(rules) {
        // Profiles as Nmcli.profiles reads them
        const profile = (uuid, name, kind, state, port) => ({ uuid: uuid, name: name, type: kind, kind: kind, device: "",
            autoconnect: true, priority: 0, lastUsed: 0, active: state !== "", port: port ?? "", state: state });
        const profiles = [
            profile("u-home", "Home", "wifi", ""),
            profile("u-hotspot", "Hotspot", "wifi", "activated"),
            profile("u-office", "Office LAN", "ethernet", "activated"),
            profile("u-wg", "wg0", "vpn", "activated"),
            profile("u-bridge", "br0", "bridge", "activated"),
            profile("u-port", "br0 port", "ethernet", "activated", "bridge"),
            profile("u-lo", "lo", "loopback", "activated"),
            profile("u-cafe", "Cafe", "wifi", "activated"),
            profile("u-train", "Train", "wifi", "activating")
        ];
        const wifi = { "u-home": { ssid: "home", mode: "infrastructure" }, "u-hotspot": { ssid: "mine", mode: "ap" },
                       "u-cafe": { ssid: "cafe", mode: "infrastructure" }, "u-train": { ssid: "train", mode: "infrastructure" } };
        assertEqual(JSON.stringify(rules.apiNetworks(profiles, wifi)), JSON.stringify([
            { id: "u-office", name: "Office LAN", kind: "ethernet", active: true },
            { id: "u-cafe", name: "Cafe", kind: "wifi", active: true },
            { id: "u-home", name: "Home", kind: "wifi", active: false },
            { id: "u-train", name: "Train", kind: "wifi", active: false }]),
            "apiNetworks: Wi-Fi and Ethernet, active first (\"activated\" only), no hotspot, VPN, bridge, port or loopback");
        // The context of an element in a saved network's card (1.24): the network as Api.networks
        // names it, under the key networkId
        assertEqual(JSON.stringify([profile("u-cafe", "Cafe", "wifi", "activated"), profile("u-train", "Train\nnow", "wifi", "activating"),
                                    profile("u-office", "Office LAN", "ethernet", "")].map(rules.networkContext)),
                    JSON.stringify([{ networkId: "u-cafe", name: "Cafe", kind: "wifi", active: true, ssid: "" },
                                    { networkId: "u-train", name: "Train now", kind: "wifi", active: false, ssid: "" },
                                    { networkId: "u-office", name: "Office LAN", kind: "ethernet", active: false }]),
                    "networkContext: the profile's UUID, its name on one line, its kind, up only when \"activated\"; a Wi-Fi one's ssid \"\" when the profile has none");
        assertEqual(JSON.stringify(rules.networkContext(Object.assign(profile("u-cafe", "Cafe", "wifi", ""), { ssid: "Cafe\u202e\nfree" }))),
                    JSON.stringify({ networkId: "u-cafe", name: "Cafe", kind: "wifi", active: false, ssid: "Cafe free" }),
                    "networkContext (1.32): a Wi-Fi network's ssid, plain, on one line, no bidi override (a settings card's row has it)");
        assertEqual(JSON.stringify(["a\u202ab\u202bc\u202cd\u202de\u202ef", "g\u2066h\u2067i\u2068j\u2069k", "l\u200em\u2028n"].map(name => rules.networkRow("id", name, "wifi", true).name)),
                    JSON.stringify(["abcdef", "ghijk", "l\u200em n"]),
                    "a name from outside: bidi embeddings, overrides and isolates (U+202A–U+202E, U+2066–U+2069) go, a line separator becomes a space, a plain mark stays");
        assertEqual(JSON.stringify([undefined, null, {}].map(rules.networkContext)),
                    JSON.stringify([0, 1, 2].map(() => ({ networkId: "", name: "", kind: "", active: false }))),
                    "networkContext: no profile (a card being made) — empty fields, not up");
        // The context on the network popup's rows (1.32): the profile as the cards give it
        const used = (entry, lastUsed, device) => Object.assign(entry, { lastUsed: lastUsed, device: device ?? "" });
        const rowProfiles = [used(profile("u-home", "Home", "wifi", ""), 30), used(profile("u-home2", "Home (old)", "wifi", ""), 50),
                             used(profile("u-cafe", "Cafe", "wifi", "activated"), 10, "wlan0"), used(profile("u-cafe2", "Cafe 2", "wifi", ""), 90),
                             used(profile("u-hotspot", "Hotspot", "wifi", ""), 99), used(profile("u-unread", "Unread", "wifi", ""), 99),
                             used(profile("u-wired", "Wired", "ethernet", "activated"), 5, "eth0"), used(profile("u-lab", "Lab", "ethernet", ""), 50),
                             used(profile("u-port", "Port", "ethernet", "activated", "br0"), 60, "eth1"),
                             used(profile("u-dock", "Dock", "ethernet", "activating"), 1, "eth2")];
        const rowWifi = { "u-home": { ssid: "Home", mode: "infrastructure" }, "u-home2": { ssid: "Home", mode: "infrastructure" },
                          "u-cafe": { ssid: "Cafe", mode: "infrastructure" }, "u-cafe2": { ssid: "Cafe", mode: "infrastructure" },
                          "u-hotspot": { ssid: "Mine", mode: "ap" } };
        assertEqual(JSON.stringify(["Home", "Cafe", "Mine", "Street\nnet", "", undefined].map(ssid => rules.wifiRowContext(ssid, rowProfiles, rowWifi))),
                    JSON.stringify([{ networkId: "u-home2", name: "Home (old)", kind: "wifi", active: false, ssid: "Home" },
                                    { networkId: "u-cafe", name: "Cafe", kind: "wifi", active: true, ssid: "Cafe" },
                                    { networkId: "", name: "Mine", kind: "wifi", active: false, ssid: "Mine" },
                                    { networkId: "", name: "Street net", kind: "wifi", active: false, ssid: "Street net" },
                                    { networkId: "", name: "", kind: "wifi", active: false, ssid: "" },
                                    { networkId: "", name: "", kind: "wifi", active: false, ssid: "" }]),
                    "wifiRowContext: of the profiles saved for the SSID, the one up, else the last used; a hotspot's or an unread one's none — "
                    + "not saved: no networkId, the SSID on one line as the name; ssid the scanned SSID either way");
        assertEqual(JSON.stringify([rules.wifiRowContext("Home", null, null), rules.wifiRowContext("Home", [5, null, { uuid: "u-home" }], { "u-home": "junk" })]),
                    JSON.stringify([0, 1].map(() => ({ networkId: "", name: "Home", kind: "wifi", active: false, ssid: "Home" }))),
                    "… garbage: as not saved, no throw");
        // Of several, fully up beats coming up beats last used
        const ranked = [used(profile("u-r-old", "Old", "wifi", ""), 90), used(Object.assign(profile("u-r-coming", "Coming", "wifi", "activating"), { active: true }), 10),
                        used(profile("u-r-up", "Up", "wifi", "activated"), 5)];
        const rankedWifi = { "u-r-old": { ssid: "R", mode: "infrastructure" }, "u-r-coming": { ssid: "R", mode: "infrastructure" }, "u-r-up": { ssid: "R", mode: "infrastructure" } };
        assertEqual([ranked, ranked.slice(0, 2), ranked.slice(0, 1)].map(list => rules.wifiRowContext("R", list, rankedWifi).networkId).join(" "), "u-r-up u-r-coming u-r-old",
                    "wifiRowContext: of several, the one fully up, else the one coming up, else the one last used");
        assertEqual(rules.wifiRowContext("Bad\u2067name\u202e", [], {}).ssid + "|" + rules.wifiRowContext("x".repeat(300), [], {}).ssid.length, "Badname|200",
                    "… ssid plain: no bidi isolate or override, capped");
        // "Saved" is one rule for the row (its Forget, its password field: savedSsids) and its
        // context: a hotspot's SSID, a profile whose details are not read yet, details left from
        // a profile gone — not saved on either side
        const savedProfiles = rowProfiles.concat([used(profile("u-lan", "Lan", "wifi", ""), 1)]);
        const savedWifi = Object.assign({}, rowWifi, { "u-gone": { ssid: "Gone", mode: "infrastructure" }, "u-unread-lan": { ssid: "Unread", mode: "infrastructure" } });
        assertEqual(JSON.stringify(rules.savedWifiSsids(savedProfiles, savedWifi)), JSON.stringify(["Home", "Cafe"]),
                    "savedWifiSsids: the listed client profiles' SSIDs, each once — no hotspot, no unread profile, no details of a profile gone");
        const ssidsTried = ["Home", "Cafe", "Mine", "Gone", "Unread", "Lan", "Street"];
        assertEqual(ssidsTried.map(ssid => rules.savedWifiSsids(savedProfiles, savedWifi).includes(ssid) === (rules.wifiRowContext(ssid, savedProfiles, savedWifi).networkId !== "")).join(","),
                    ssidsTried.map(() => "true").join(","),
                    "… and the row's context has a profile exactly for those SSIDs");
        assertEqual(JSON.stringify([rules.savedWifiSsids(null, null), rules.savedWifiSsids([5, { uuid: "u-x", kind: "wifi" }], { "u-x": { ssid: "", mode: "infrastructure" } })]), "[[],[]]",
                    "… garbage or an empty SSID: none, no throw");
        assertEqual(JSON.stringify(["eth0", "eth1", "eth2", "eth9", "", null].map(device => rules.wiredRowContext(rowProfiles, device))),
                    JSON.stringify([{ networkId: "u-wired", name: "Wired", kind: "ethernet", active: true },
                                    { networkId: "", name: "", kind: "ethernet", active: false },
                                    { networkId: "u-dock", name: "Dock", kind: "ethernet", active: false },
                                    { networkId: "", name: "", kind: "ethernet", active: false },
                                    { networkId: "", name: "", kind: "ethernet", active: false },
                                    { networkId: "", name: "", kind: "ethernet", active: false }]),
                    "wiredRowContext: the wired profile up on the device (coming up: not active yet); a port, none up or no device: no networkId, no name");
        assertEqual(JSON.stringify(rules.wiredRowContext("junk", "eth0")), JSON.stringify({ networkId: "", name: "", kind: "ethernet", active: false }),
                    "… garbage: none, no throw");
        assertEqual(rules.apiNetworks([profile("u-unread", "New", "wifi", "")], {}).length, 0,
                    "apiNetworks: a Wi-Fi profile whose details are not read yet is left out (it could be a hotspot)");
        // Whether a saved network's card is a place: as Api.networks lists it
        const read = { "u-home": { mode: "infrastructure" }, "u-spot": { mode: "ap" }, "u-odd": "junk" };
        assertEqual([profile("u-home", "Home", "wifi", ""), profile("u-unread", "New", "wifi", ""), profile("u-spot", "Spot", "wifi", ""),
                     profile("u-odd", "Odd", "wifi", ""), profile("u-lan", "LAN", "ethernet", ""),
                     profile("u-port", "Port", "ethernet", "", "bond0"), null, { uuid: "u-x", kind: "vpn" }]
                    .map(each => rules.networkListed(each, read)).join(","), "true,false,false,false,true,false,false,false",
                    "networkListed: a Wi-Fi profile once its details say it is no hotspot (not while unread, nor junk); Ethernet that is no port; nothing else");
        assertEqual(rules.networkListed(profile("u-home", "Home", "wifi", ""), null) + " " + rules.networkListed(profile("u-lan", "LAN", "ethernet", ""), "junk"),
                    "false true", "… no details read: no Wi-Fi, Ethernet still");
        assertEqual(rules.apiNetworks([], {}).length, 0, "apiNetworks: no profiles, none");
        for (const bad of [null, undefined, "x", 3, {}, [null, 1, "x", [], {}, { uuid: "" }, { uuid: 5, kind: "wifi" }]])
            assertEqual(rules.apiNetworks(bad, null).length, 0, "apiNetworks: garbage skipped — " + JSON.stringify(bad));
        assertEqual(JSON.stringify(rules.apiNetworks([{ uuid: "u-bare", kind: "ethernet" }, { uuid: "constructor", kind: "wifi", name: 7 }],
                                                     { constructor: { mode: "infrastructure" } })),
                    JSON.stringify([{ id: "u-bare", name: "", kind: "ethernet", active: false },
                                    { id: "constructor", name: "", kind: "wifi", active: false }]),
                    "apiNetworks: missing fields defaulted; a prototype-named UUID is just a UUID");
        assertEqual(rules.apiNetworks([{ uuid: "constructor", kind: "wifi" }], "junk").length, 0,
                    "apiNetworks: details that are no object: no Wi-Fi row (not even through the prototype)");

        // VPNs as VpnManager.activeVpns has them
        const vpns = [
            { uuid: "u-wg", name: "wg-home", type: "wireguard", active: true, state: "activated", device: "wg0" },
            { uuid: "tailscale:main", name: "Tailscale", type: "provider", provider: "tailscale", entryId: "main", state: "activated" },
            { uuid: "u-ovpn", name: "Work", type: "vpn", provider: "sneaky", state: "activated" }
        ];
        const unknown = { fullTunnel: null, setsDns: null, routes: null };
        const row = (name, type, provider) => Object.assign({ name: name, type: type, provider: provider }, unknown);
        assertEqual(JSON.stringify(rules.apiVpnsUp(vpns)), JSON.stringify([
            row("wg-home", "wireguard", ""), row("Tailscale", "provider", "tailscale"), row("Work", "vpn", "")]),
            "apiVpnsUp: name, type, and the providerId only for a provider's VPN, in order; without details nothing known of the routing");
        assertEqual(rules.apiVpnsUp([]).length, 0, "apiVpnsUp: none up, none");
        for (const bad of [null, undefined, "x", 3, {}, [null, 1, "x", []]])
            assertEqual(rules.apiVpnsUp(bad).length, 0, "apiVpnsUp: garbage skipped — " + JSON.stringify(bad));
        assertEqual(JSON.stringify(rules.apiVpnsUp([{ type: "provider", provider: 3 }, {}])),
                    JSON.stringify([row("", "provider", ""), row("", "", "")]),
                    "apiVpnsUp: missing or wrong fields defaulted");

        // What Api hands out: frozen, the list and each entry
        const rows = rules.frozenRows(JSON.stringify([{ id: "a" }]));
        assert(Object.isFrozen(rows) && Object.isFrozen(rows[0]) && rows[0].id === "a", "frozenRows: the list and its entries frozen");
        for (const bad of ["", "{", "{}", "null", undefined])
            assertEqual(rules.frozenRows(bad).length, 0, "frozenRows: not a JSON list → [] — " + JSON.stringify(bad));
        assert(Array.isArray(Api.networks) && Object.isFrozen(Api.networks), "Api.networks: a frozen list");
        assert(Array.isArray(Api.vpnsUp) && Object.isFrozen(Api.vpnsUp), "Api.vpnsUp: a frozen list");
        assert(Api.networks.every(network => Object.isFrozen(network) && typeof network.id === "string"
                                  && (network.kind === "wifi" || network.kind === "ethernet")), "Api.networks: frozen entries of the shape");
    }

    // API 1.16: network facts — networksReady, a Wi-Fi row only with its details, the VPNs'
    // routing, the local networks, the test kit's facts
    function _api116(rules) {
        const profile = (uuid, kind, state, port) => ({ uuid: uuid, name: uuid, type: kind, kind: kind, state: state ?? "", port: port ?? "" });
        const wifiRead = { "u-cafe": { ssid: "cafe", mode: "infrastructure" }, "u-ap": { ssid: "mine", mode: "ap" } };
        // networksReady
        assert(!rules.apiNetworksReady(false, [], {}), "apiNetworksReady: the list not read — not ready");
        assert(rules.apiNetworksReady(true, [], {}), "… read and empty — ready (no network at all)");
        assert(rules.apiNetworksReady(true, [profile("u-lan", "ethernet"), profile("u-wg", "vpn")], {}), "… Ethernet and VPNs need no details");
        assert(!rules.apiNetworksReady(true, [profile("u-cafe", "wifi"), profile("u-new", "wifi")], wifiRead),
               "… a Wi-Fi profile whose details are not read — not ready");
        assert(rules.apiNetworksReady(true, [profile("u-cafe", "wifi"), profile("u-ap", "wifi"), profile("u-port", "wifi", "", "bond")], wifiRead),
               "… every Wi-Fi profile's details read (a hotspot's too; a port is not looked at) — ready");
        for (const bad of [null, "x", 3, [null], [{ uuid: "u-new", kind: "wifi" }]])
            assert(!rules.apiNetworksReady(true, [profile("u-new", "wifi")], bad), "… details unreadable — not ready: " + JSON.stringify(bad));
        assert(rules.apiNetworksReady(true, "junk", null) && rules.apiNetworksReady(true, [null, 3, { kind: "wifi" }], null),
               "… profiles that are garbage are not waited for");
        // The hotspot for a moment: the list read, the details not yet
        assertEqual(rules.apiNetworks([profile("u-ap", "wifi", "activated")], {}).length, 0,
                    "apiNetworks: a Wi-Fi profile before its details — not listed (it may be a hotspot)");
        assertEqual(JSON.stringify(rules.apiNetworks([profile("u-cafe", "wifi", "activated"), profile("u-ap", "wifi", "activated")], wifiRead).map(network => network.id)),
                    JSON.stringify(["u-cafe"]), "… with the details: the network, not the hotspot");
        assertEqual(rules.apiNetworks([{ uuid: "u-x", name: "A\nB\u0007C".concat("x".repeat(300)), kind: "ethernet" }], {})[0].name,
                    "A B C" + "x".repeat(195), "… a name on one line, capped at 200");

        // VPNs: NetworkManager's from their details (NetworkRules.vpnDetails' shape)
        const wireguard = { uuid: "u-wg", name: "wg-home", type: "wireguard", state: "activated" };
        const plugin = { uuid: "u-ovpn", name: "Work", type: "vpn", state: "activated" };
        const detail = fields => Object.assign({ dns: [], neverDefault4: false, neverDefault6: false, ipv6Disabled: false, allowedIps: null, peerRoutes: true,
                                                 gateways: [], routes: [], up: true }, fields);
        const routing = (vpn, fields) => JSON.stringify(rules.vpnRouting(vpn, fields === null ? null : detail(fields)));
        const known = (fullTunnel, setsDns, routes) => JSON.stringify({ fullTunnel: fullTunnel, setsDns: setsDns, routes: routes });
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/0", "::/0"], dns: ["10.35.53.1"] }), known(true, true, ["0.0.0.0/0", "::/0"]),
                    "vpnRouting: WireGuard with /0 peers — a full tunnel, with its own DNS");
        assertEqual(routing(wireguard, { allowedIps: ["10.8.0.5/24", "10.8.0.0/24", "bad", "fd00::1/64"] }), known(false, false, ["10.8.0.0/24", "fd00::/64"]),
                    "… a split one: its networks canonical and once, the unreadable left out; no DNS read while up");
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/0"], neverDefault4: true }), known(false, false, ["0.0.0.0/0"]),
                    "… /0 with never-default on — not a full tunnel");
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/0", "::/0"], neverDefault4: true, neverDefault6: null }), known(null, false, ["0.0.0.0/0", "::/0"]),
                    "… never-default not read for the family with /0 — unknown");
        assertEqual(routing(wireguard, { allowedIps: null }), known(null, false, null), "… peers not read — routes and full tunnel unknown");
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/0"], up: false }), known(true, null, ["0.0.0.0/0"]),
                    "… read while not up: its DNS unknown, its peers known");
        assertEqual(routing(plugin, { gateways: ["10.9.0.1"], routes: ["0.0.0.0/0", "10.9.0.0/24", "fe80::/64"], dns: ["10.9.0.1"] }),
                    known(true, true, ["0.0.0.0/0", "10.9.0.0/24"]), "… a plugin VPN with a gateway: a full tunnel; link-local routes left out");
        assertEqual(routing(plugin, { routes: ["172.16.0.0/12"] }), known(false, false, ["172.16.0.0/12"]), "… no gateway, no /0 — split");
        assertEqual(routing(plugin, { gateways: ["10.9.0.1"], neverDefault4: true, neverDefault6: true }), known(false, false, []),
                    "… never-default on in both families — not a full tunnel");
        assertEqual(routing(plugin, { up: false }), known(null, null, null), "… not read while up — nothing known");
        // Read while it was still activating (NetworkRules.vpnDetails: up only when "activated")
        const activating = NetworkRules.vpnDetails([{ "connection.uuid": "u-ovpn", "vpn.service-type": "org.freedesktop.NetworkManager.openvpn",
                                                      "GENERAL.STATE": "activating", "GENERAL.IP-IFACE": "tun0", "ipv4.never-default": "no", "ipv6.never-default": "no" }]);
        assertEqual(JSON.stringify(rules.vpnRouting(plugin, activating["u-ovpn"])), known(null, null, null),
                    "… a plugin VPN read while activating (no DNS, gateway or route yet) — unknown, not a split tunnel without DNS");
        const wireguardActivating = NetworkRules.vpnDetails([{ "connection.uuid": "u-wg", "wireguard.peers": "K= allowed-ips=10.8.0.0/24",
                                                               "GENERAL.STATE": "activating", "GENERAL.IP-IFACE": "wg0", "ipv4.never-default": "no", "ipv6.never-default": "no" }]);
        assertEqual(JSON.stringify(rules.vpnRouting(wireguard, wireguardActivating["u-wg"])), known(false, null, ["10.8.0.0/24"]),
                    "… WireGuard read while activating: its routes from the profile, its DNS unknown");
        // WireGuard: peer-routes, IPv6 disabled, all traffic as two halves
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/0"], peerRoutes: false }), known(null, false, null),
                    "… peer-routes off — its routes and whether it takes all unknown");
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/0"], peerRoutes: false, neverDefault4: true, neverDefault6: true }), known(false, false, null),
                    "… peer-routes off, never-default on in both families — not a full tunnel, routes unknown");
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/0"], peerRoutes: null }), known(true, false, ["0.0.0.0/0"]),
                    "… peer-routes not read (an older nmcli) — on, as NetworkManager had it before the setting");
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/1", "128.0.0.0/1"], neverDefault4: true }), known(true, false, ["0.0.0.0/1", "128.0.0.0/1"]),
                    "… all IPv4 as its two halves — a full tunnel, never-default or not (they are no default route)");
        assertEqual(routing(wireguard, { allowedIps: ["::/1", "8000::/1", "10.0.0.0/8"] }), known(true, false, ["::/1", "8000::/1", "10.0.0.0/8"]),
                    "… all IPv6 as its two halves — a full tunnel");
        assertEqual(routing(wireguard, { allowedIps: ["0.0.0.0/1"] }), known(false, false, ["0.0.0.0/1"]), "… one half alone — not");
        assertEqual(routing(wireguard, { allowedIps: ["10.0.0.0/8", "::/0"], ipv6Disabled: true }), known(false, false, ["10.0.0.0/8"]),
                    "… ::/0 with IPv6 disabled — not carried, not a full tunnel");
        assertEqual(routing(plugin, { routes: ["0.0.0.0/1", "128.0.0.0/1"] }), known(true, false, ["0.0.0.0/1", "128.0.0.0/1"]),
                    "… a plugin VPN's two halves — a full tunnel");
        assertEqual(routing(plugin, null), known(null, null, null), "… no details — nothing known");
        assertEqual(JSON.stringify(rules.vpnRouting(null, null)), known(null, null, null), "… no VPN — nothing known");
        // A provider's: what its entry reported, checked
        assertEqual(JSON.stringify(rules.vpnRouting({ type: "provider", fullTunnel: false, setsDns: true, routes: ["100.64.0.0/10", "fd7a:115c:a1e0::/48"] }, detail({ dns: [] }))),
                    known(false, true, ["100.64.0.0/10", "fd7a:115c:a1e0::/48"]), "… a provider's: its own, not the details");
        assertEqual(JSON.stringify(rules.vpnRouting({ type: "provider", fullTunnel: "yes", setsDns: 1, routes: "0.0.0.0/0" }, null)), known(null, null, null),
                    "… wrong fields — unknown, never false");
        const fields = rules.vpnRoutingFields({ fullTunnel: true, routes: ["10.0.0.1/8", 5, "x", "10.0.0.0/8"] });
        assertEqual(JSON.stringify(fields.fields), known(true, null, ["10.0.0.0/8"]), "vpnRoutingFields: routes canonical and once; absent null");
        assertEqual(fields.problems.length, 1, "… the wrong routes named once: " + fields.problems.join("; "));
        const manyRoutes = count => Array.from({ length: count }, (unused, i) => "10." + (i >> 8) + "." + (i & 255) + ".0/24");
        assertEqual(rules.vpnRoutingFields({ routes: manyRoutes(rules.maxRoutes) }).fields.routes.length, rules.maxRoutes, "… up to maxRoutes routes kept");
        const tooMany = rules.vpnRoutingFields({ routes: manyRoutes(rules.maxRoutes + 1) });
        assertEqual(JSON.stringify([tooMany.fields.routes, tooMany.problems.length]), "[null,1]", "… more — routes unknown (null), never cut, and said: " + tooMany.problems.join("; "));
        assertEqual(rules.vpnRoutingFields({ routes: manyRoutes(rules.maxRoutes).concat(manyRoutes(rules.maxRoutes)) }).fields.routes.length, rules.maxRoutes,
                    "… repeated ones count once");
        assertEqual(routing(wireguard, { allowedIps: manyRoutes(rules.maxRoutes + 1) }), known(null, false, null), "vpnRouting: more WireGuard routes than that — unknown");
        assertEqual(routing(plugin, { routes: manyRoutes(rules.maxRoutes + 1) }), known(null, false, null), "… a plugin VPN's too");
        assertEqual(routing(plugin, { routes: manyRoutes(rules.maxRoutes + 1), gateways: ["10.9.0.1"] }), known(true, false, null), "… a gateway still a full tunnel");
        const routesProblems = rules.vpnRoutesProblems([wireguard, plugin, { uuid: "u-small", name: "Small", type: "vpn" }],
                                                       { "u-wg": detail({ allowedIps: manyRoutes(300) }), "u-ovpn": detail({ routes: manyRoutes(300) }),
                                                         "u-small": detail({ routes: ["10.0.0.0/8"] }) });
        assertEqual(routesProblems.length, 2, "vpnRoutesProblems: one sentence per VPN with too many routes: " + routesProblems.join("; "));
        for (const bad of [null, undefined, 3, "x", []])
            assertEqual(JSON.stringify(rules.vpnRoutingFields(bad).fields), known(null, null, null), "… garbage — unknown: " + JSON.stringify(bad));
        // apiVpnsUp with the details
        assertEqual(JSON.stringify(rules.apiVpnsUp([wireguard, plugin, { uuid: "tailscale:main", name: "Tailscale", type: "provider", provider: "tailscale", setsDns: false }],
                                                   { "u-wg": detail({ allowedIps: ["0.0.0.0/0"] }), "tailscale:main": detail({ dns: ["1.1.1.1"] }) })),
                    JSON.stringify([
                        { name: "wg-home", type: "wireguard", provider: "", fullTunnel: true, setsDns: false, routes: ["0.0.0.0/0"] },
                        { name: "Work", type: "vpn", provider: "", fullTunnel: null, setsDns: null, routes: null },
                        { name: "Tailscale", type: "provider", provider: "tailscale", fullTunnel: null, setsDns: false, routes: null }]),
                    "apiVpnsUp: each VPN with its routing; no details — unknown; a provider's from its entry");
        assertEqual(rules.apiVpnsUp([{ uuid: "constructor", name: "x", type: "vpn" }], "junk")[0].routes, null, "… details that are garbage — unknown");

        // Local networks, from Nmcli.devices' rows
        const device = (name, type, ipv4, ipv6) => ({ device: name, type: type, ipv4: ipv4 ?? [], ipv6: ipv6 ?? [] });
        const local = (name, kind, family, address, network) => ({ device: name, kind: kind, family: family, address: address, network: network });
        assertEqual(JSON.stringify(rules.apiLocalNetworks([device("wlan0", "wifi", ["192.168.1.23/24"], ["fe80::1/64", "2001:db8:0:1::17/64"])], [])),
                    JSON.stringify([local("wlan0", "wifi", 4, "192.168.1.23", "192.168.1.0/24"), local("wlan0", "wifi", 6, "2001:db8:0:1::17", "2001:db8:0:1::/64")]),
                    "apiLocalNetworks: Wi-Fi — its IPv4 and global IPv6, not the link-local");
        assertEqual(JSON.stringify(rules.apiLocalNetworks([device("enp13s0", "ethernet", ["10.0.5.2/16"])], [])),
                    JSON.stringify([local("enp13s0", "ethernet", 4, "10.0.5.2", "10.0.0.0/16")]), "… Ethernet");
        assertEqual(JSON.stringify(rules.apiLocalNetworks([device("enp13s0", "ethernet", [], ["2001:DB8::5/64", "fe80::5/64", "FD12:3456::5/48"])], [])),
                    JSON.stringify([local("enp13s0", "ethernet", 6, "2001:db8::5", "2001:db8::/64"), local("enp13s0", "ethernet", 6, "fd12:3456::5", "fd12:3456::/48")]),
                    "… IPv6 only: global and unique local, canonical; the link-local left out");
        assertEqual(rules.apiLocalNetworks([device("enp13s0", "ethernet"), device("wlan0", "wifi", [], ["fe80::1/64"]),
                                            device("eth1", "ethernet", ["169.254.3.4/16"])], []).length, 0,
                    "… none: no address, link-local only, a self-assigned IPv4");
        const several = rules.apiLocalNetworks([
            device("lo", "loopback", ["127.0.0.1/8"], ["::1/128"]),
            device("enp13s0", "ethernet", ["192.168.1.5/24", "192.168.1.5/24"]),
            device("wlan0", "wifi", ["10.20.0.7/22"]),
            device("docker0", "bridge", ["172.17.0.1/16"]),
            device("wwan0", "gsm", ["100.70.1.2/30"]),
            device("bond0", "bond", ["192.168.9.2/24"]),
            device("tailscale0", "tun", ["100.101.102.103/32"], ["fd7a:115c:a1e0::1/128"]),
            device("wg0", "wireguard", ["10.8.0.2/24"]),
            device("tun0", "unknown", ["10.9.0.6/24"]),
            device("ts1", "dummy", ["100.64.0.9/10"]),
            device("gre1", "ip-tunnel", ["10.99.0.1/30"]),
            device("p2p-dev-wlan0", "wifi-p2p", ["192.168.49.1/24"]),
            device("bad/name", "ethernet", ["192.168.7.1/24"]),
            device("x".repeat(16), "ethernet", ["192.168.8.1/24"]),
            device("eth9", "ethernet", ["224.0.0.5/4", "0.0.0.0/0", "192.168.1.300/24", "10.1.1.1", "ff02::1/16"])
        ], ["tun0", "ts1"]);
        assertEqual(JSON.stringify(several.map(row => row.device + " " + row.kind + " " + row.network)), JSON.stringify([
            "enp13s0 ethernet 192.168.1.0/24", "wlan0 wifi 10.20.0.0/22", "docker0 bridge 172.17.0.0/16",
            "wwan0 modem 100.70.1.0/30", "bond0 other 192.168.9.0/24"]),
            "… several: each address once; no loopback, tun, WireGuard, IP tunnel or P2P device, none named as a VPN's or a provider's; "
            + "a bad device name, multicast, unspecified, unreadable or prefix-less addresses left out");
        for (const bad of [null, undefined, "x", 3, {}, [null, 1, "x", [], {}, { device: 5, ipv4: ["10.0.0.1/8"] }, { device: "eth0", ipv4: "10.0.0.1/8" }]])
            assertEqual(rules.apiLocalNetworks(bad, "junk").length, 0, "… garbage skipped — " + JSON.stringify(bad));
        assertEqual(rules.apiLocalNetworks(Array.from({ length: 100 }, (unused, i) => device("eth" + i, "ethernet", ["10." + i + ".0.1/24"])), null).length, 64,
                    "… at most 64");
        assertEqual(rules.localNetworkRow("eth0", "weird", "10.0.0.1/8").kind, "other", "localNetworkRow: a kind it does not know — other");
        assertEqual(JSON.stringify([rules.localNetworkRow("eth0", "ethernet", "2001:db8::5/128"), rules.localNetworkRow("eth0", "ethernet", "203.0.113.7/32")]),
                    JSON.stringify([local("eth0", "ethernet", 6, "2001:db8::5", null), local("eth0", "ethernet", 4, "203.0.113.7", null)]),
                    "localNetworkRow: a host prefix (/128 from DHCPv6, /32) — the address, no network");
        // An IPsec VPN reports the physical interface it runs on: the device stays, less its address
        const ipsec = rules.apiLocalNetworks([device("wlan0", "wifi", ["192.168.1.5/24", "10.10.10.2/32"]), device("tun0", "tun", ["10.9.0.6/24"])],
                                             ["wlan0", "tun0"], ["10.10.10.2/32"], null);
        assertEqual(JSON.stringify(ipsec.map(row => row.device + " " + row.address)), JSON.stringify(["wlan0 192.168.1.5"]),
                    "apiLocalNetworks: a Wi-Fi device a VPN runs on — kept, less the VPN's own address");
        assertEqual(rules.apiLocalNetworks([device("br0", "bridge", ["192.168.1.5/24"])], ["br0"], [], null).length, 0, "… a bridge named as a VPN's — left out");
        assertEqual(rules.apiLocalNetworks([device("enp1s0", "ethernet", ["192.168.1.5/24", "10.10.10.2/24"])], [], ["10.10.10.2"], null).length, 1,
                    "… a VPN's address left out wherever it shows (written without prefix too)");
        // A modem: its IP interface, not its control device
        assertEqual(JSON.stringify(rules.apiLocalNetworks([Object.assign(device("cdc-wdm0", "gsm", ["100.70.1.2/30"]), { ipIface: "wwan0" })], ["cdc-wdm0"], [], null)),
                    JSON.stringify([]), "… a device named as a VPN's by its device name — left out with its IP interface");
        assertEqual(JSON.stringify(rules.apiLocalNetworks([Object.assign(device("cdc-wdm0", "gsm", ["100.70.1.2/30"]), { ipIface: "wwan0" })], [], [], null)),
                    JSON.stringify([local("wwan0", "modem", 4, "100.70.1.2", "100.70.1.0/30")]), "… a modem by the interface its IP runs on");
        // IPv6 privacy addresses: the deprecated ones left out by their flags
        const privacy = device("wlan0", "wifi", [], ["2001:db8:0:1::1/64", "2001:db8:0:1::aaaa/64", "2001:db8:0:1::bbbb/64"]);
        const privacyFlags = { "wlan0 2001:db8:0:1::1": { temporary: false, deprecated: false }, "wlan0 2001:db8:0:1::aaaa": { temporary: true, deprecated: false },
                               "wlan0 2001:db8:0:1::bbbb": { temporary: true, deprecated: true } };
        assertEqual(JSON.stringify(rules.apiLocalNetworks([privacy], [], [], privacyFlags).map(row => row.address)),
                    JSON.stringify(["2001:db8:0:1::1", "2001:db8:0:1::aaaa"]), "… IPv6: the stable and the current temporary address, not a deprecated one");
        assertEqual(rules.apiLocalNetworks([privacy], [], [], null).length, 3, "… flags not known — every address kept");

        // The test kit's facts
        const defaults = rules.testNetworkFacts(null);
        assertEqual(JSON.stringify(defaults), JSON.stringify({ facts: { networksReady: true, networks: [], localNetworksReady: true, localNetworks: [], vpnsUp: [] },
                                                                problems: [] }), "testNetworkFacts: the defaults — read, none");
        const given = rules.testNetworkFacts({ networksReady: "no", networks: [{ id: "u", kind: "wifi" }, { id: "", kind: "wifi" }, { id: "v", kind: "vpn" }],
                                               localNetworks: [{ device: "eth0", kind: "ethernet", address: "10.0.0.1/8" }, { device: "eth0", address: "10.0.0.1" }],
                                               vpnsUp: "x", extra: 1 });
        assertEqual(JSON.stringify([given.facts.networksReady, given.facts.networks.length, given.facts.localNetworks.length, given.facts.vpnsUp.length]),
                    "[true,1,1,0]", "… wrong fields and rows left out");
        assertEqual(given.problems.length, 6, "… each named: " + given.problems.join("; "));
        assertEqual(rules.testNetworkFacts("x").problems.length, 1, "… not an object: named");
        const notRead = rules.testNetworkFacts({ localNetworksReady: false, localNetworks: [{ device: "eth0", kind: "ethernet", address: "10.0.0.1/8" }],
                                                 networksReady: false, networks: [{ id: "u", kind: "ethernet" }] });
        assertEqual(JSON.stringify([notRead.facts.localNetworks, notRead.problems.length, notRead.facts.networks.length]), "[[],1,1]",
                    "… local networks while not read — left out and named, as the shell lists none then; networks may show (Ethernet before the Wi-Fi details)");

        // What Api hands out (pure: Api itself, outside module test mode, reads the real
        // NetworkProfiles, VpnManager and IpManager — created by the first suite that
        // touches Api, here _version's Api.version, and VpnManager by VpnProvidersTest)
        const frozen = rules.frozenRows(JSON.stringify([{ name: "x", routes: ["10.0.0.0/8"] }]));
        assert(Object.isFrozen(frozen) && Object.isFrozen(frozen[0]) && Object.isFrozen(frozen[0].routes), "frozenRows: the list, its entries and the lists inside frozen");
        const upRow = rules.vpnUpRow("wg", "wireguard", "", { fullTunnel: true, setsDns: null, routes: ["0.0.0.0/0"] });
        assertEqual(JSON.stringify(Object.keys(upRow)), JSON.stringify(["name", "type", "provider", "fullTunnel", "setsDns", "routes"]), "vpnUpRow: the routing fields in every row");
    }

    // M2: the API version's home, presetDefaults, the slot table, the registries' merges, the
    // values a module hands over, the file check, the start guard
    function _m2(rules, alpha, zeta) {
        assertEqual(rules.apiVersion, Api.version, "Api.version is ModuleRules.apiVersion");

        // presetDefaults
        const presets = ModuleManifestRules.parseManifest(_manifest({ widgets: [
            { type: "tailscale", name: "T", widget: "W.qml", presetDefaults: { showIp: true, hosts: ["a"] } },
            { type: "tailscale.b", name: "B", widget: "W.qml", presetDefaults: [] },
            { type: "tailscale.c", name: "C", widget: "W.qml", presetDefaults: { "bad key": 1 } },
            { type: "tailscale.d", name: "D", widget: "W.qml", presetDefaults: { big: "x".repeat(20000) } }] }));
        assertEqual(presets.widgets.map(widget => widget.type).join(","), "tailscale", "presetDefaults: only a small object of names kept");
        assertEqual(presets.widgets[0].presetDefaults.hosts[0], "a", "… its values kept");
        assertEqual(presets.warnings.length, 0, "… presetDefaults is a known field");

        // The slot table
        assert(rules.slotNames.length >= 3 && rules.slotTable.every(slot => slot.name && slot.where && slot.context && slot.since),
               "the slot table: each slot with where, context, since");
        assertEqual(ModuleMergeRules.unknownSlotWarnings({ slots: [{ slot: "network.popup.sections", component: "A.qml" },
                                                        { slot: "network.popup.nowhere", component: "B.qml" }] }).length, 1,
                    "a contribution to a slot not offered: one warning");
        for (const slot of rules.slotNames)
            assert(!/lock|screensaver/.test(slot), "no slot on the lock screen: " + slot);

        // Registries: no module → the core's list, unchanged
        const core = [{ type: "clock", popup: "calendar" }, { type: "tray" }];
        assert(ModuleMergeRules.mergeWidgetEntries(core, []) === core, "widgets, no module: the core's list itself");
        const widgets = ModuleMergeRules.mergeWidgetEntries(core, [{ type: "alpha", popup: "alpha", module: "alpha" },
            { type: "clock", module: "x" }, { type: "x2", popup: "calendar", module: "x" }, { type: "x3", popup: "tray-menu", module: "x" }]);
        assertEqual(widgets.map(entry => entry.type).join(","), "clock,tray,alpha", "widgets: the core's first; a module's type or popup the core has is dropped");
        const pageCore = [{ id: "general", tab: "behaviour" }, { id: "network", tab: "system", group: true },
                          { id: "network_vpn", tab: "system", parent: "network" }, { id: "themes", tab: "appearance" }];
        assert(ModuleMergeRules.mergeSettingsPages(pageCore, []).pages === pageCore, "pages, no module: the core's list itself");
        const pages = ModuleMergeRules.mergeSettingsPages(pageCore, [
            { id: "ts", label: "T", tab: "behaviour", component: "file:///t/P.qml", module: "ts", parent: "network" },
            { id: "ts.top", label: "Top", tab: "appearance", component: "file:///t/Q.qml", module: "ts" },
            { id: "ts.lost", label: "Lost", tab: "behaviour", component: "file:///t/R.qml", module: "ts", parent: "nowhere" },
            { id: "general", label: "Mine", tab: "behaviour", component: "file:///t/S.qml", module: "ts" }]);
        assertEqual(pages.pages.map(page => page.id + (page.parent ? "<" + page.parent : "")).join(","),
                    "general,network,network_vpn<network,ts<network,themes,ts.top,modules,ts.lost<modules",
                    "pages: under a core group after its pages (on its tab), at the end of their tab, the rest under Modules");
        assertEqual(pages.pages.find(page => page.id === "ts").tab, "system", "… a group's page takes the group's tab");
        assertEqual(pages.pages.find(page => page.id === "ts").url, "file:///t/P.qml", "… a module's page has a url");
        assertEqual(pages.problems.length, 2, "… the lost parent and the core's id: said");
        const settingCore = [{ key: "general.debug" }];
        assert(ModuleMergeRules.mergeSettingEntries(settingCore, []) === settingCore, "settings, no module: the core's list itself");
        assertEqual(ModuleMergeRules.mergeSettingEntries(settingCore, [{ key: "general.debug" }, { key: "mod.x.a" }]).length, 2, "settings: a core key dropped");
        const factCore = [{ fact: "power.onBattery" }];
        assert(ModuleMergeRules.mergeFactTypes(factCore, []) === factCore, "facts, no module: the core's list itself");
        assertEqual(JSON.stringify(ModuleMergeRules.mergePresetDefaults({ clock: { format: "x" } }, [{ type: "alpha", presetDefaults: { a: 1 } }, { type: "clock", presetDefaults: { format: "evil" } }])),
                    "{\"clock\":{\"format\":\"x\"},\"alpha\":{\"a\":1}}", "preset defaults: a module's added, never over the core's");

        // Facts a module sets
        assert(rules.factValue("bool", true).ok && !rules.factValue("bool", 1).ok, "a bool fact");
        assert(rules.factValue("percent", 100).ok && !rules.factValue("percent", 101).ok && !rules.factValue("percent", NaN).ok, "a percent fact");
        assert(rules.factValue("enum", "a", ["a"]).ok && !rules.factValue("enum", "b", ["a"]).ok, "an enum fact");
        assert(rules.factValue("number", -5.5).ok && !rules.factValue("number", "5").ok, "a number fact");
        assert(!rules.factValue("string", "x".repeat(201)).ok, "a string fact: at most 200");
        assertEqual(rules.factValue("bool", null).value, null, "null: not known");
        assert(!rules.factValue("color", "red").ok, "an unknown type: refused");
        for (const hostile of [{}, [], () => 1, { valueOf: () => { throw "x"; } }])
            assert(!rules.factValue("number", hostile).ok, "hostile values: refused, no throw");
        assertEqual(rules.ownFactName("ts", "up"), "ts.up", "ownFactName: <name>");
        assertEqual(rules.ownFactName("ts", "x.y"), "ts.x.y", "ownFactName: a dotted name is its own too");
        assertEqual(rules.ownFactName("ts", "") + rules.ownFactName("ts", 5), "", "ownFactName: nothing, not a name");
        assertEqual(rules.ownSettingKey("ts", "a"), "mod.ts.a", "ownSettingKey: <name>");
        assertEqual(rules.ownSettingKey("ts", "mod.other.a"), "", "ownSettingKey: not another's");
        const enumEntry = { type: "enum", options: [{ value: "a", label: "A" }] };
        assert(rules.settingValueProblem(enumEntry, "a") === "" && rules.settingValueProblem(enumEntry, "b") !== "", "a setting's value: enum");
        assert(rules.settingValueProblem({ type: "number", min: 0, max: 5 }, 6) !== "", "… a number out of range");
        assert(rules.settingValueProblem({ type: "stringList" }, ["a", 1]) !== "", "… a list with a number");
        assert(rules.settingValueProblem(null, 1) !== "", "… an undeclared key");

        // The store
        assertEqual(rules.storeText({ a: 1 }), "{\"a\":1}", "storeText");
        assertEqual(rules.storeText({ huge: "x".repeat(rules.maxStoreBytes) }), null, "storeText: too large");
        const cyclic = {};
        cyclic.self = cyclic;
        assertEqual(rules.storeText(cyclic), null, "storeText: not plain JSON");
        assertEqual(JSON.stringify(rules.parseStore("[1]")) + JSON.stringify(rules.parseStore("{")) + JSON.stringify(rules.parseStore(null)), "{}{}{}",
                    "parseStore: anything but an object is an empty store");

        // Contexts compared by value
        const object = Qt.createQmlObject("import QtQuick; QtObject {}", this);
        const close = () => 1;
        assert(rules.sameContext({ slot: "a", n: [1, { b: 2 }] }, { slot: "a", n: [1, { b: 2 }] }), "sameContext: equal plain data");
        assert(!rules.sameContext({ slot: "a" }, { slot: "b" }), "… a changed value");
        assert(!rules.sameContext({ slot: "a" }, { slot: "a", x: 1 }), "… a key more");
        assert(rules.sameContext({ provider: object, close: close }, { provider: object, close: close }), "… the same object and function");
        assert(!rules.sameContext({ close: close }, { close: () => 1 }), "… another function");
        assert(!rules.sameContext(null, {}) && rules.sameContext(null, null), "… null");
        object.destroy();

        // A popup panel's opener (API 1.15)
        const opener = rules.popupOpener({ widgetType: "good", preset: "Alpha" }, "left", true);
        assertEqual(JSON.stringify(opener), JSON.stringify({ widgetType: "good", preset: "Alpha", edge: "left", byTouch: true }),
                    "popupOpener: the widget type, its preset, the bar's edge, a tap");
        assert(Object.isFrozen(opener), "… frozen");
        assertEqual(JSON.stringify(rules.popupOpener({ widgetType: "good" }, "top", "yes")),
                    JSON.stringify({ widgetType: "good", preset: "", edge: "top", byTouch: false }), "… no preset: \"\"; byTouch only when true");
        assertEqual(JSON.stringify(rules.popupOpener({ widgetType: "good", preset: 3 }, undefined, false)),
                    JSON.stringify({ widgetType: "good", preset: "", edge: "", byTouch: false }), "… a preset or edge that is no text: \"\"");
        assertEqual(rules.popupOpener({ widgetType: "x".repeat(100), preset: "p".repeat(100) }, "top", false)?.preset.length, 64, "… texts kept to 64 characters");
        assertEqual(rules.popupOpener({ menu: {}, direction: "down" }, "top", false), null, "… a tray menu's request: none");
        assertEqual(rules.popupOpener(null, "top", false), null, "… nothing: none");
        assertEqual(rules.popupOpener({ widgetType: "" }, "top", false), null, "… an empty type: none");
        assert(rules.sameOpener(opener, rules.popupOpener({ widgetType: "good", preset: "Alpha" }, "left", true)), "sameOpener: by value");
        assert(!rules.sameOpener(opener, rules.popupOpener({ widgetType: "good", preset: "Beta" }, "left", true)), "… another preset");
        assert(!rules.sameOpener(opener, null) && rules.sameOpener(null, null), "… null");
        assertEqual(ModuleMergeRules.contributionKey({ module: "a", component: "file:///x" }), "a|file:///x", "a contribution's identity");
        assertEqual(ModuleFileRules.directoryIndexOf(["/m/a", "/m/a/b"], "file:///m/a/b/c/X.qml"), 1, "directoryIndexOf: the deepest");
        assertEqual(ModuleFileRules.directoryIndexOf(["/m/a"], "file:///m/ab/X.qml"), -1, "… not a prefix of another name");
        assertEqual(ModuleFileRules.directoryIndexOf(["/m/a"], "file:///m/a/../b/X.qml"), -1, "… .. leaves it");
        assertEqual(ModuleFileRules.directoryIndexOf(["/m/a b"], "file:///m/a%20b/X.qml"), 0, "… escaped");

        // --- a module's icon (API 1.26) ---
        const icon = given => ModuleManifestRules.parseManifest(_manifest({ id: "iconic", api: "1.26", icon: given }));
        assertEqual(JSON.stringify(icon({ glyph: "\uf0e8" }).icon), JSON.stringify({ kind: "glyph", glyph: "\uf0e8", file: "", colors: "theme" }),
                    "icon: a glyph of the icon font");
        assertEqual(icon({ glyph: "\u{F0001}" }).icon?.glyph, "\u{F0001}", "… one above U+FFFF (two UTF-16 units) is one character");
        assertEqual(JSON.stringify(icon({ svg: "icons/mark.svg" }).icon), JSON.stringify({ kind: "svg", glyph: "", file: "icons/mark.svg", colors: "theme" }),
                    "… an SVG, painted in the theme's colour by default");
        assertEqual(icon({ svg: "mark.SVG", colors: "own" }).icon?.colors, "own", "… an SVG in its own colours");
        assertEqual(JSON.stringify(icon({ image: "mark.png" }).icon), JSON.stringify({ kind: "image", glyph: "", file: "mark.png", colors: "own" }),
                    "… a PNG picture, in its own colours");
        assertEqual(icon({ image: "mark.webp" }).icon?.file, "mark.webp", "… a WebP picture");
        const goodIcon = icon({ svg: "mark.svg" });
        assert(goodIcon.valid && goodIcon.errors.length === 0 && goodIcon.warnings.length === 0, "… no error, no warning: " + goodIcon.errors.concat(goodIcon.warnings).join("; "));
        assertEqual(ModuleManifestRules.parseManifest(_manifest({ id: "iconic", api: "1.0" })).icon, null, "no icon: null");
        const refusals = [
            [{ glyph: "ab" }, "icon: the glyph \"ab\" is 2 characters, not one (no icon)", "two characters"],
            [{ glyph: "" }, "icon: the glyph \"\" is not a character (no icon)", "an empty glyph"],
            [{ glyph: 7 }, "icon: the glyph 7 is not a character (no icon)", "a glyph that is no text"],
            [{ glyph: " " }, "is white space", "white space"],
            [{ glyph: "\u00a0" }, "is white space", "a no-break space"],
            [{ glyph: "\n" }, "is white space", "a line break"],
            [{ glyph: "\u0007" }, "is a control character", "a control character"],
            [{ glyph: "\u200b" }, "is a format character", "a format character (zero width space)"],
            [{ glyph: "\u202e" }, "is a format character", "… (right-to-left override)"],
            [{ glyph: "\ud800" }, "is a format character", "a lone surrogate"],
            [{ glyph: "\uf023" }, "is one of the shell's status marks", "the lock of PrivilegedMark"],
            [{ glyph: "\uf05e" }, "is one of the shell's status marks", "its no-entry sign"],
            [{ glyph: "x" }, "is not an icon of the icon font (a private-use character)", "an ordinary letter"],
            [{ glyph: "\u{1F600}" }, "is not an icon of the icon font", "an emoji (drawn in its own colours)"],
            [{ glyph: "\u2764" }, "is not an icon of the icon font", "a symbol that has an emoji form"],
            [{ glyph: "\u0301" }, "is not an icon of the icon font", "a combining mark"],
            [{ glyph: "\ufe0f" }, "is not an icon of the icon font", "a variation selector"],
            [{ glyph: "\u{E0100}" }, "is not an icon of the icon font", "… a supplementary one"],
            [{ glyph: "\uf456" }, "looks like one of the shell's status marks (a lock or a no-entry sign)", "another lock of the icon font (oct-lock)"],
            [{ glyph: "\u{F033E}" }, "looks like one of the shell's status marks", "… md-lock, above U+FFFF"],
            [{ glyph: "\uf4f4" }, "looks like one of the shell's status marks", "… a no-entry sign (oct-no_entry)"],
            [{ svg: "mark.gif" }, "icon: svg \"mark.gif\": not a .svg file (no icon)", "an SVG of another format"],
            [{ image: "mark.svg" }, "icon: image \"mark.svg\": not a .png or .webp file (no icon)", "a picture of another format"],
            [{ image: "mark.jpg" }, "not a .png or .webp file", "… a JPEG"],
            [{ svg: "icons/../../other/mark.svg" }, "leaves the module's directory or is not a plain path", "outside the module"],
            [{ svg: "../other/mark.svg" }, "has characters a module file name may not have", "… starting with \"..\""],
            [{ svg: "/usr/share/icons/mark.svg" }, "an absolute path", "an absolute path"],
            [{ svg: "a//mark.svg" }, "leaves the module's directory or is not a plain path", "an empty part"],
            [{ svg: "mark\n.svg" }, "has characters a module file name may not have", "a line break in the name"],
            [{ svg: "mark.svg", colors: "rainbow" }, "icon: colors \"rainbow\" is not \"theme\" or \"own\" (no icon)", "colours neither theme nor own"],
            [{ glyph: "x", svg: "mark.svg" }, "icon: names glyph and svg of glyph, svg and image; one (no icon)", "two kinds"],
            [{}, "icon: names none of glyph, svg and image; one (no icon)", "no kind"],
            ["mark.svg", "icon: not an object", "a plain file name"]
        ];
        for (const [given, expected, what] of refusals) {
            const read = icon(given);
            assert(read.valid && read.icon === null && read.errors.length === 1 && read.errors[0].includes(expected),
                   "icon refused, " + what + ": no icon, one error, the module valid — " + JSON.stringify(read.errors));
        }
        assertEqual(["\ue000", "\uf8ff", "\u{F0000}", "\u{FFFFD}", "\u{100000}", "\u{10FFFD}"].map(glyph => icon({ glyph: glyph }).icon?.glyph === glyph).join(","),
                    "true,true,true,true,true,true", "icon: a glyph from each private-use range, its ends included");
        assertEqual(["\udfff", "\uf900", "\u{EFFFF}", "\u{FFFFE}", "\u{10FFFF}"].map(glyph => icon({ glyph: glyph }).icon === null).join(","), "true,true,true,true,true",
                    "… just outside them: refused");
        assert(_has(icon({ glyph: "\uf0e8", size: 3 }).warnings, "icon: unknown field \"size\" (ignored)") && icon({ glyph: "\uf0e8", size: 3 }).icon !== null,
               "icon: an unknown field warned about, the icon kept");
        assert(_has(icon({ glyph: "\uf0e8", colors: "own" }).warnings, "icon: unknown field \"colors\""), "… colors on a glyph: unknown there");
        const olderIcon = ModuleManifestRules.parseManifest(_manifest({ id: "iconic", api: "1.25", icon: { glyph: "\uf0e8" } }));
        assert(olderIcon.icon !== null && _has(olderIcon.warnings, "icon: a field of API 1.26, the manifest asks for API 1.25 (read all the same)"),
               "icon with api 1.25: read all the same, with a warning");
        // PrivilegedMark's two marks are the reserved glyphs
        const mark = Qt.createQmlObject("import qs.components; PrivilegedMark {}", rulesSuite);
        const marks = [];
        for (const need of ["auth", "no"]) {
            mark.need = need;
            marks.push(mark.text);
        }
        mark.destroy();
        assertEqual(JSON.stringify(marks.slice().sort()), JSON.stringify(ModuleManifestRules.reservedGlyphs.slice().sort()),
                    "reservedGlyphs: PrivilegedMark's lock and no-entry sign");
        // The file check takes the icon's file: its size only, the cap its kind's
        assertEqual(JSON.stringify(ModuleFileRules.iconCheck(icon({ svg: "mark.svg" }))), JSON.stringify({ file: "mark.svg", cap: "t65536" }),
                    "iconCheck: an SVG at most 64 KiB, its text read (to refuse external references)");
        assertEqual(ModuleFileRules.iconCheck(icon({ image: "mark.png" })).cap, "m262144", "… a picture at most 256 KiB, its first bytes read");
        assertEqual(ModuleFileRules.iconCheck(icon({ glyph: "\uf0e8" })) + " " + ModuleFileRules.iconCheck(icon({ glyph: "ab" })), "null null",
                    "… a glyph, or no icon: no file");
        assert(!ModuleFileRules.filesToCheck(icon({ svg: "mark.svg" }), "").some(entry => entry.file === "mark.svg")
               && !ModuleFileRules.manifestFiles(icon({ svg: "mark.svg" })).includes("mark.svg"), "… never read as a QML file");
        const badIcon = ModuleFileRules.withoutBadFiles(icon({ svg: "mark.svg" }), { "mark.svg": "is larger than 65536 bytes" }, "");
        assertEqual(badIcon.manifest.icon + " | " + badIcon.errors.join("") + " | " + badIcon.fatal, "null | icon mark.svg is larger than 65536 bytes (no icon) | ",
                    "withoutBadFiles: an icon whose file fails the check: none, said, the module loads");
        assertEqual(ModuleFileRules.withoutBadFiles(icon({ svg: "mark.svg" }), {}, "").manifest.icon?.file, "mark.svg", "… a good one kept");
        assert(ModuleFileRules.fileCheckScript.includes("t*) cap=${cap#t}; whole=3") && ModuleFileRules.fileCheckScript.includes("m*) cap=${cap#m}; whole=4"),
               "the check's script knows the text and first-bytes caps");
        // The icon's content (iconContentProblem): an SVG with no external reference, a
        // picture whose first bytes are its name's type
        const svgIcon = { kind: "svg", file: "mark.svg" };
        const svgOf = body => ModuleManifestRules.iconContentProblem(svgIcon, body);
        const clean = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 16 16">'
            + '<defs><linearGradient id="g"><stop offset="0" stop-color="#000"/></linearGradient><path id="p" d="M0 0h16v16z"/></defs>'
            + '<style>.a { fill: url(#g); }</style><use xlink:href="#p"/><use href="#p"/><rect class="a" style="fill: url( \'#g\')" width="4" height="4"/></svg>';
        assertEqual(svgOf(clean), "", "iconContentProblem: a clean SVG (internal references only) is fine");
        assertEqual(svgOf("\ufeff<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- made by hand -->\n<!-- twice -->\n<svg viewBox=\"0 0 1 1\"/>"), "",
                    "… after a byte order mark, the XML declaration (UTF-8) and comments");
        const svgRefusals = [
            ['<svg><image xlink:href="/etc/passwd" width="1" height="1"/></svg>', "(<image>)", "an <image> by absolute path"],
            ['<svg><image href="data:image/png;base64,AAAA"/></svg>', "(<image>)", "… even of embedded data"],
            ['<svg><svg:image xmlns:svg="http://www.w3.org/2000/svg" href="x.png"/></svg>', "(<image>)", "… prefixed"],
            ['<svg><IMAGE\nhref="x.png"/></svg>', "(<image>)", "… in another case"],
            ['<svg><use xlink:href="other.svg#p"/></svg>', "an href not starting with #", "a <use> of another file"],
            ['<svg><use href=" #p"/></svg>', "an href not starting with #", "… an href with a space before its #"],
            ['<svg><a href="https://example.org/"><rect/></a></svg>', "an href not starting with #", "any other href"],
            ['<svg><use h&#114;ef="x.svg"/></svg>', "an href not starting with #", "… one not in the raw text"],
            ['<svg><use href="&#x2F;etc/x.svg#p"/></svg>', "an href not starting with #", "… one whose # is spelt as a reference"],
            ['<!DOCTYPE svg [<!ENTITY e SYSTEM "file:///etc/passwd">]><svg>&e;</svg>', "is not an SVG drawing", "a document type before it"],
            ['<svg><!ENTITY e "x"></svg>', "a document type or entity declaration", "an entity declaration inside"],
            ['<?xml-stylesheet href="s.css"?><svg/>', "is not an SVG drawing", "a style sheet before it"],
            ['<svg><?xml-stylesheet type="text/css" href="s.css"?></svg>', "a processing instruction", "… inside"],
            ['<svg><style>@import "s.css";</style></svg>', "@import", "an @import"],
            ['<svg><style>rect { fill: url(other.svg#g); }</style></svg>', "a url( not starting with #", "a style's url( out of the file"],
            ['<svg><rect style="fill:url(/tmp/x.svg#g)"/></svg>', "a url( not starting with #", "… in a style attribute"],
            ['<svg><rect fill="url(x.svg#g)"/></svg>', "a url( not starting with #", "… in a presentation attribute"],
            ['<svg><rect style="fill:&#117;rl(x.svg#g)"/></svg>', "a url( not starting with #", "… spelt with a character reference"],
            ['<svg><style>rect { fill: u\\72l(x.svg#g); }</style></svg>', "a backslash", "a CSS escape"],
            ['<svg><foreignObject><div/></foreignObject></svg>', "(<foreignobject>)", "a <foreignObject>"],
            ['<svg><script>x()</script></svg>', "(<script>)", "a <script>"],
            ['<?xml version="1.0" encoding="UTF-16"?><svg/>', "is not UTF-8 text (the XML declaration names \"UTF-16\")", "another encoding declared"],
            ['<?xml version="1.0" encoding="UTF-7"?><svg>+ADw-image href=+ACI-x+ACI-/+AD4-</svg>', "is not UTF-8 text", "… UTF-7, which hides an <image>"],
            ['<svg>\ufffd</svg>', "is not UTF-8 text", "a byte that is not UTF-8 (read as U+FFFD)"],
            ['<svg>\u0001</svg>', "is not UTF-8 text", "a control character"],
            ['this is no picture', "is not an SVG drawing (it does not start with <svg>)", "no SVG at all"],
            ['<html><svg/></html>', "is not an SVG drawing", "something else holding one"],
            ['<svgx/>', "is not an SVG drawing", "an element only starting like it"]
        ];
        for (const [body, expected, what] of svgRefusals) {
            const problem = svgOf(body);
            assert(problem.includes(expected), "iconContentProblem refuses " + what + ": " + JSON.stringify(problem));
        }
        assertEqual(svgOf(undefined), "could not be read", "… an SVG not read: refused (never \"fine\")");
        const pictureOf = (file, hex) => ModuleManifestRules.iconContentProblem({ kind: "image", file: file }, hex);
        assertEqual(pictureOf("mark.png", "89504e470d0a1a0a0000000d49484452"), "", "… a PNG's first bytes in a .png: fine");
        assertEqual(pictureOf("mark.webp", "524946462400000057454250565038"), "", "… a WebP's in a .webp: fine");
        assertEqual(pictureOf("mark.png", "3c73766720786d6c6e733d2268747470"), "is not a PNG picture", "… an SVG in a .png: refused (Qt would draw it as SVG)");
        assertEqual(pictureOf("mark.png", "49492a00080000000e00fe0004000100"), "is not a PNG picture", "… a TIFF in a .png: refused");
        assertEqual(pictureOf("mark.webp", "89504e470d0a1a0a0000000d49484452"), "is not a WebP picture", "… a PNG in a .webp: refused");
        assertEqual(pictureOf("mark.webp", "52494646240000004156492000000000"), "is not a WebP picture", "… a RIFF that is not WebP (AVI): refused");
        assertEqual(pictureOf("mark.png", "") + " | " + pictureOf("mark.png", "garbage") + " | " + pictureOf("mark.png", null),
                    "is not a PNG picture | could not be read | could not be read", "… an empty file, garbage, nothing read: refused");
        assertEqual(ModuleManifestRules.iconContentProblem({ kind: "glyph", glyph: "\uf0e8" }, undefined) + ModuleManifestRules.iconContentProblem(null, ""), "",
                    "… a glyph or no icon: nothing to judge");
        // withIconContent: the host's answers with the content judged
        const answers = { "Main.qml": "ok", "mark.svg": "ok" };
        assertEqual(JSON.stringify(ModuleFileRules.withIconContent(icon({ svg: "mark.svg" }), answers, { "mark.svg": '<svg><image href="/x"/></svg>' })),
                    JSON.stringify({ "Main.qml": "ok", "mark.svg": "refers to something outside it (<image>)" }),
                    "withIconContent: a refused SVG fails as a bad file, the others as they were");
        assertEqual(ModuleFileRules.withIconContent(icon({ svg: "mark.svg" }), answers, { "mark.svg": "<svg/>" }), answers, "… a clean one: the answers unchanged");
        assertEqual(ModuleFileRules.withIconContent(icon({ svg: "mark.svg" }), answers, {})["mark.svg"], "could not be read", "… its text missing: refused");
        assertEqual(ModuleFileRules.withIconContent(icon({ svg: "mark.svg" }), { "mark.svg": "is larger than 65536 bytes" }, {})["mark.svg"], "is larger than 65536 bytes",
                    "… a file the check failed already: its answer kept");
        const refusedIcon = ModuleFileRules.withoutBadFiles(icon({ image: "mark.png" }),
                                                            { "mark.png": ModuleFileRules.withIconContent(icon({ image: "mark.png" }), { "mark.png": "ok" }, { "mark.png": "3c737667" })["mark.png"] }, "");
        assertEqual(refusedIcon.manifest.icon + " | " + refusedIcon.errors.join(""), "null | icon mark.png is not a PNG picture (no icon)",
                    "… and withoutBadFiles: no icon, said in the status");
        assertEqual(JSON.stringify(ModuleRules.iconShown({ kind: "svg", glyph: "", file: "icons/a b.svg", colors: "theme" }, "/m/iconic")),
                    JSON.stringify({ kind: "svg", glyph: "", url: "file:///m/iconic/icons/a b.svg", colors: "theme" }), "iconShown: a file by its URL");
        assertEqual(ModuleRules.iconShown(null, "/m"), null, "… none: null");
        assertEqual(ModuleRules.iconLetter("tailscale VPN", "tailscale") + ModuleRules.iconLetter("  ëlan", "x") + ModuleRules.iconLetter("123 go", "x")
                    + ModuleRules.iconLetter("日本", "nihon") + ModuleRules.iconLetter("", "") + ModuleRules.iconLetter(null, "zed"), "TËGN?Z",
                    "iconLetter: the name's first letter, upper case; the id's when the name has none; ? for neither");

        // The file check
        const files = ModuleFileRules.filesToCheck(alpha, "singleton S 1.0 S.qml\n");
        assertEqual(files.map(entry => entry.file + ":" + entry.kind).join(","), "A1.qml:entry,P.qml:entry,A2.qml:entry,Page.qml:entry,Row.qml:entry,S.qml:qmldir",
                    "filesToCheck: every file named, each once, with its kind");
        assertEqual(ModuleFileRules.listing("ok", "./Main.qml\n./lib/util.js\n./notes.txt\n./lib/x.mjs\nstatus 0").files.join(","), "Main.qml,lib/util.js",
                    "listing: QML and JavaScript files, nothing else");
        const listed = ModuleFileRules.listing("ok", "./Main.qml\n./sections/Row.qml\n./../Out.qml\n/abs.qml\n./sub//X.qml\n./a\tb.qml\n./Main.qml\n./line\nbreak.qml\nstatus 0");
        assertEqual(JSON.stringify(listed.files), JSON.stringify(["Main.qml", "sections/Row.qml"]), "listing: the listing's QML files inside the directory, each once");
        assertEqual(listed.skipped + " " + listed.more + " " + listed.failed, "5 false false",
                    "… the ones left out counted (a \"..\" part, absolute, an empty part, a control character, a name with a line break once)");
        assertEqual(ModuleFileRules.scanWarning(listed, 0), "imports not checked in 5 files", "scanWarning: says how many files were not checked");
        const many = ModuleFileRules.listing("ok", Array.from({ length: 103 }, (unused, i) => "./F" + i + ".qml").join("\n") + "\nstatus 0");
        assertEqual(many.files.length + " " + many.skipped, ModuleFileRules.maxScannedFiles + " 3", "… at most maxScannedFiles, the rest counted");
        const depthPath = levels => "./" + Array.from({ length: levels }, (unused, i) => "d" + i + "/").join("") + "F.qml";
        const deep = ModuleFileRules.listing("ok", depthPath(ModuleFileRules.scanDepth) + "\n" + depthPath(ModuleFileRules.scanDepth + 1) + "\nstatus 0");
        assertEqual(deep.files.length + " " + deep.skipped + " " + deep.more, "1 1 true",
                    "… a file " + ModuleFileRules.scanDepth + " directories deep is read, one deeper counted, and more may be below it");
        const cut = ModuleFileRules.listing("ok", Array.from({ length: ModuleFileRules.maxListedLines }, (unused, i) => "./F" + i + ".qml").join("\n"));
        assert(cut.more && !cut.failed, "… cut at maxListedLines (no status line): more than it counted");
        assertEqual(ModuleFileRules.scanWarning(cut, 2), "imports not checked in " + (ModuleFileRules.maxListedLines - ModuleFileRules.maxScannedFiles + 2) + " or more files",
                    "… said so, with the files it could not read");
        assert(ModuleFileRules.listing("ok", "./A.qml\nstatus 1").failed, "… find failing on a directory: not read whole");
        assert(ModuleFileRules.listing("ok", "./A.qml").failed, "… no status line and not cut: not read whole");
        assert(ModuleFileRules.listing(undefined, undefined).failed && ModuleFileRules.listing("cannot be listed", "").failed, "… no answer, or a refusal: failed");
        assertEqual(ModuleFileRules.scanWarning(ModuleFileRules.listing(undefined, undefined), 0), "imports not checked: the file list could not be read",
                    "scanWarning: a list that could not be read is said, never \"no warnings\"");
        assertEqual(ModuleFileRules.scanWarning(ModuleFileRules.listing("ok", "./A.qml\nstatus 0"), 0), "", "… every file read: nothing");
        assertEqual(ModuleFileRules.scanWarning(ModuleFileRules.listing("ok", "./A.qml\nstatus 0"), 1), "imports not checked in 1 file", "… a file it could not read");
        assertEqual(ModuleFileRules.scanWarning(ModuleFileRules.listing("ok", "status 0"), 0), "", "… an empty module: nothing");
        const order = ModuleFileRules.checkOrder([{ id: "A main" }, { id: "A scan 1", optional: true }, { id: "A scan 2", optional: true },
                                                  { id: "B main" }, { id: "B scan", optional: true }, { id: "B entry" }]);
        assertEqual(order.map(entry => entry.id).join(", "), "A main, B main, B entry, A scan 1, A scan 2, B scan",
                    "checkOrder: every module's required files before any module's scan reads");
        assertEqual(JSON.stringify(ModuleFileRules.scanOnly(["A1.qml", "sections/Row.qml", "S.qml"], files)), JSON.stringify(["sections/Row.qml"]),
                    "scanOnly: the listed files the check does not read already");
        assertEqual(JSON.stringify(ModuleFileRules.parseFileCheck(["0\tok", "1\tis not a regular file", "junk", "2\t"])),
                    "{\"0\":\"ok\",\"1\":\"is not a regular file\",\"2\":\"\"}", "parseFileCheck");
        const checked = ModuleFileRules.withoutBadFiles(alpha, { "P.qml": "is not a regular file", "Row.qml": "leaves the module directory through a link" }, "");
        assertEqual(checked.manifest.widgets.map(widget => widget.type).join(","), "alpha.two", "withoutBadFiles: a widget with a bad file dropped");
        assertEqual(checked.manifest.slots.length, 0, "… a slot with one dropped");
        assertEqual(checked.errors.length, 2, "… each said");
        assertEqual(checked.fatal, "", "… the module still loads");
        assertEqual(alpha.widgets.length, 2, "… the manifest given is not changed");
        assert(ModuleFileRules.withoutBadFiles({ main: "Main.qml" }, { "Main.qml": "x" }, "").fatal !== "", "a bad main: fatal");
        assert(ModuleFileRules.withoutBadFiles({}, { "S.qml": "x" }, "singleton S 1.0 S.qml").fatal !== "", "a bad qmldir file: fatal");

        // The start guard
        assertEqual(JSON.stringify(ModuleFileRules.startGuard("0 77:")), JSON.stringify({ safeMode: false, count: 0, identity: "77:", reason: "" }), "guard: a fresh process, 0");
        assert(!ModuleFileRules.startGuard("1 77:5").safeMode, "guard: one relaunch after a crash — not yet");
        assert(ModuleFileRules.startGuard("2 77:6").safeMode && ModuleFileRules.startGuard("17 77:9").safeMode, "guard: 2 or more in a row — safe mode");
        assertEqual(ModuleFileRules.startGuard("2 77:6").identity, "77:6", "… its identity, to clear it with");
        assert(ModuleFileRules.startGuard("refused 77:").reason !== "", "guard: a counter that is not a plain file — said, not counted");
        for (const junk of ["", "abc", "2", "-3 1:2", "99999 1:2", null, "refused", "1\n2", "2 x:y"])
            assert(!ModuleFileRules.startGuard(junk).safeMode, "guard: garbage counts as 0 — " + JSON.stringify(junk));
        assertEqual(ModuleFileRules.guardClearMs, 30000, "the guard's window is the launcher's quick-death window (30 s)");

        // What a root object declares (the initial properties the core gives it)
        const declared = ModuleSourceRules.rootProperties("import QtQuick\n// property var top\nItem {\n    property var module: null\n    readonly property int x: 1\n"
            + "    required property var context\n    Rectangle { property var inner }\n    property list<string> names\n    // property var commented\n"
            + "    /* property var blocked */ property string text: \"property var fake; {\"\n    default property alias content: c.data\n}\n");
        assertEqual(declared.join(","), "module,context,names,text,content", "rootProperties: the root's own, writable ones; not nested, commented or quoted");
        assertEqual(JSON.stringify(ModuleSourceRules.initialProperties(["module"], { module: 1, context: 2 })), "{\"module\":1}", "initialProperties: only the declared");
        assertEqual(ModuleSourceRules.rootProperties(null).length, 0, "rootProperties: no text, none");
        // A regex literal holding a brace does not throw the depth off
        assertEqual(ModuleSourceRules.rootProperties("Item {\n    function f(s) { return /[{]+/.test(s) && s.split(/{/).length > 0; }\n    property var module\n    property var context: x.replace(/\\{/g, \"\")\n}\n").join(","),
                    "module,context", "rootProperties: braces inside regex literals ignored");
        // Only `property var module` gets the handle; other spellings get a warning
        assertEqual(ModuleSourceRules.rootProperties("Item {\n    property int module\n    property var context\n}\n").join(","), "context", "rootProperties: `property int module` is not a module property");
        assertEqual(ModuleSourceRules.rootProperties("Item {\n    readonly property var module: null\n}\n").length, 0, "rootProperties: a readonly module is not one");
        assert(ModuleSourceRules.modulePropertyWarning("W.qml", "Item {\n    property int module\n}\n").includes("only `property var module`"), "modulePropertyWarning: property int module");
        assert(ModuleSourceRules.modulePropertyWarning("W.qml", "Item {\n    readonly property var module: null\n}\n").includes("readonly"), "modulePropertyWarning: readonly");
        assertEqual(ModuleSourceRules.modulePropertyWarning("W.qml", "Item {\n    property var module: null\n    Item { property int module }\n}\n"), "", "modulePropertyWarning: the right spelling (a nested object's is not the root's)");
        // A popup panel's `opener` the same (API 1.15)
        assertEqual(ModuleSourceRules.rootProperties("Item {\n    readonly property var opener: null\n    property string opener2\n}\n").join(","), "opener2", "rootProperties: a readonly opener is not one");
        assertEqual(ModuleSourceRules.rootProperties("Item {\n    property string opener\n}\n").length, 0, "rootProperties: `property string opener` is not one");
        assertEqual(ModuleSourceRules.rootProperties("Base {\n    property var module\n}\n").join(","), "module", "rootProperties: an inherited opener is not the root's own");
        assert(ModuleSourceRules.openerPropertyWarning("P.qml", "Item {\n    readonly property var opener: null\n}\n").includes("only `property var opener` is given the widget that opened it"), "openerPropertyWarning: readonly");
        assert(ModuleSourceRules.openerPropertyWarning("P.qml", "Item {\n    property int opener\n}\n").startsWith("P.qml: its root declares `property int opener`"), "openerPropertyWarning: property int opener");
        assertEqual(ModuleSourceRules.openerPropertyWarning("P.qml", "Item {\n    property var opener: null\n    property var openers\n}\n"), "", "openerPropertyWarning: the right spelling, another name beginning alike");

        // The file check's texts (A1: read in the check's process, never on the GUI thread)
        const texts = ModuleFileRules.fileTexts(["0:{\"a\":", "0:1}", "0\tok", "1:half", "2\tis not a regular file", "3:", "3\tok", "4:x", "4:", "4\tok"]);
        assertEqual(JSON.stringify(texts), "{\"0\":\"{\\\"a\\\":\\n1}\",\"3\":\"\",\"4\":\"x\\n\"}",
                    "fileTexts: the lines of each answered file joined; a text without its ok (cut short) dropped; the last line break kept");

        // A2: Api.openUrl's rule
        for (const good of ["https://login.tailscale.com/a/1", "http://example.org", "mailto:me@example.org", "HTTPS://X"])
            assertEqual(rules.openUrlProblem(good), "", "openUrl: " + good + " is opened");
        for (const bad of ["", "/etc/passwd", "file:///etc/passwd", "x.desktop", "/usr/share/applications/evil.desktop", "-help", "--version",
                           "javascript:alert(1)", "ftp://x", "smb://host/share", "steam://run/1", "https://a\nb", "https://" + "a".repeat(5000), "www.example.org"])
            assert(rules.openUrlProblem(bad) !== "", "openUrl refuses " + JSON.stringify(bad.slice(0, 40)) + ": " + rules.openUrlProblem(bad));
        assertEqual(rules.openUrlProblem("file:///home/me/x.txt", { allowFile: true }), "", "openUrl: file: with { allowFile: true }");
        assert(rules.openUrlProblem("/home/me/x.txt", { allowFile: true }) !== "", "… but never a bare path");
        assert(rules.openUrlProblem("smb://x", { allowFile: true }) !== "", "… and allowFile allows file: only");
        assert(rules.openUrlProblem("file:///x", { allowFile: "yes" }) !== "", "… exactly true");
        assertEqual(Api.openUrl("file:///etc/passwd"), false, "Api.openUrl refuses (nothing run)");
        assertEqual(Api.openUrl("/etc/passwd"), false, "Api.openUrl refuses a bare path");

        // A4: notify-send's argv — every option, then "--", then summary and body
        const argv = Notifier.command("-a evil", { body: "--action=x=y", urgency: "low", actions: [{ id: "ok", label: "OK" }] });
        const dash = argv.indexOf("--");
        assert(dash > 0 && argv[dash + 1] === "-a evil" && argv[dash + 2] === "--action=x=y" && argv.length === dash + 3,
               "Notifier.command: summary and body after \"--\": " + JSON.stringify(argv));
        assert(argv.indexOf("--wait") > 0 && argv.indexOf("--wait") < dash && argv.indexOf("--action=ok=OK") < dash, "… options (--wait, --action) before it");
        assertEqual(JSON.stringify(Notifier.command("Hi")), "[\"notify-send\",\"--app-name=H2S Shell\",\"--\",\"Hi\"]", "Notifier.command: the plain case");

        // Popup modes of module widget types: never core entries (a new config's Full must
        // not freeze a module's default)
        assert(!SettingsSchema.coreEntries.some(entry => entry.module !== undefined || !WidgetRegistry.coreEntries.some(widget => entry.key === "widgets." + widget.type + ".popupMode") && entry.group === "popupMode"),
               "SettingsSchema.coreEntries: only the core widget types' popup modes");

        // The import check: qs.tests only in a module's tests
        assertEqual(ModuleSourceRules.importWarnings("tests/T.qml", "import qs.tests\nItem {}", true).length, 0, "a test suite may import qs.tests");
        assertEqual(ModuleSourceRules.importWarnings("tests/T.qml", "import \"..\"\nItem {}", true).length, 0, "a suite in tests/ importing \"..\": the module's own directory");
        assertEqual(ModuleSourceRules.importErrors("tests/T.qml", "import \"../..\"\nItem {}").length + " " + ModuleSourceRules.importWarnings("tests/T.qml", "import \"../..\"\nItem {}", true).length,
                    "1 0", "… \"../..\" leaves it: an error");
        assertEqual(ModuleSourceRules.importWarnings("Main.qml", "import qs.tests\nItem {}", false).length, 1, "… a module's own file may not (the shell has no qs.tests)");

        // Reserved ids: every core IPC target and settings page id shaped like a module id
        for (const target of ["tablet", "locktest", "shelltest", "lockscreen", "settings", "modules", "profiles", "fakevpn",
                              "authentication", "wallpaper", "popups", "controls", "tray-menu"])
            assert(rules.reservedIds.includes(target), "reserved: " + target);

        // A module's notification never takes the shell's own categories (its toast)
        const shellLike = rules.moduleNotifyOptions({ category: "x-qs-shell", body: "b", hints: { category: " X-QS-shell", "x-other": 1 } });
        assertEqual(JSON.stringify(shellLike), "{\"body\":\"b\",\"hints\":{\"x-other\":1}}", "moduleNotifyOptions: an x-qs- category dropped, as an option and as a hint");
        const given = { category: "im.received", hints: { category: "transfer" } };
        assertEqual(JSON.stringify(rules.moduleNotifyOptions(given)), JSON.stringify(given), "moduleNotifyOptions: another category kept");
        const hinted = { hints: { category: "x-qs-shell" } };
        rules.moduleNotifyOptions(hinted);
        assertEqual(hinted.hints.category, "x-qs-shell", "moduleNotifyOptions: the module's own object untouched");
        assertEqual(JSON.stringify(rules.moduleNotifyOptions(null)) + JSON.stringify(rules.moduleNotifyOptions("x")), "{}{}", "moduleNotifyOptions: not an object → {}");
        // (1.33) Every hint key of the shell's own namespace dropped, in plain notifications too,
        // however it is disguised: what the server would receive is judged
        const disguised = rules.moduleNotifyOptions({ hints: {
            "x-qs-announce": "9", "X-QS-progress-state": "done", " x-qs-progress-run": "r", "\u0000x-qs-progress-handle": "1",
            "\ud800x-qs-announce": "2", "\udc00\u0000X-Qs-progress-run": "3", "x-qsnot": 1, "a-x-qs-": 2, "urgency": 1
        } });
        assertEqual(JSON.stringify(disguised), JSON.stringify({ hints: { "x-qsnot": 1, "a-x-qs-": 2, "urgency": 1 } }),
                    "moduleNotifyOptions: every x-qs- hint key dropped (case, white space, a NUL or lone surrogate in front), others kept");
        assertEqual(rules.moduleNotifyOptions({ category: "\u0000x-qs-shell" }).category, undefined, "… a category behind a NUL too");
        // (1.33) progress and toast
        const job = rules.moduleNotifyOptions({ progress: 40, toast: "forever" });
        assertEqual(JSON.stringify(job), JSON.stringify({ progress: 40, toast: "brief" }), "moduleNotifyOptions: a bad toast → \"brief\"");
        assertEqual(rules.moduleNotifyOptions({ progress: -1 }).toast, "brief", "… none given → \"brief\"");
        assertEqual(rules.moduleNotifyOptions({ progress: 0, toast: "whileRunning" }).toast, "whileRunning", "… \"whileRunning\" kept");
        for (const bad of ["40", NaN, Infinity, null, true]) {
            const plain = rules.moduleNotifyOptions({ progress: bad, toast: "whileRunning", body: "b" });
            assertEqual(JSON.stringify(plain), "{\"body\":\"b\"}", "moduleNotifyOptions: progress " + String(bad) + " is not a number: dropped, and its toast");
        }
        assertEqual(JSON.stringify(rules.moduleNotifyOptions({ toast: "whileRunning" })), "{}", "… a toast without progress dropped");
        assertEqual(rules.moduleNotifyOptions({ progress: 10, urgency: "critical" }).urgency, "normal", "moduleNotifyOptions: a progress notification is never critical");
        assertEqual(rules.moduleNotifyOptions({ progress: 10, urgency: "low" }).urgency, "low", "… another urgency kept");
        assertEqual(rules.moduleNotifyOptions({ urgency: "critical" }).urgency, "critical", "… a plain notification may be critical");
        assertEqual(JSON.stringify(rules.moduleNotifyOptions({ progress: 10, hints: { urgency: 2, " URGENCY": 2, "\u0000Urgency": 2, other: 1 } }).hints),
                    "{\"other\":1}", "… nor by an urgency hint, however written");
    }
}
