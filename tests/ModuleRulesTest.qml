import QtQuick
import Quickshell.Io
import qs.api
import qs.singletons

// The module system's rules (singletons/ModuleRules.qml and the four Module…Rules files
// beside it): the manifest, API compatibility, namespaces, the import check, search-path
// precedence, the state model, merging — on realistic and on hostile manifests. Nothing here
// may throw.
TestCase {
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
        const newer = ModuleManifestRules.parseManifest(_manifest({ permissions: ["network"], icon: "vpn" }));
        assert(newer.valid, "a manifest with fields this shell does not know still loads");
        assertEqual(JSON.stringify(newer.unknownFields), "[\"permissions\",\"icon\"]", "… their names listed");
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

        // --- the import check: warnings, never a refusal ---
        const header = "// A comment\n/* import qs.singletons in a block comment */\npragma Singleton\n"
            + "import QtQuick\nimport QtQuick.Layouts 1.15\nimport QtQml.Models\nimport Quickshell\nimport Quickshell.Io\n"
            + "import qs.api\nimport qs.components\nimport \".\"\nimport \"sub\" as Sub\nimport \"Rules.js\" as Rules\n"
            + "import qs.singletons\nimport Quickshell.Hyprland; import \"../core\"\nimport \"file:///etc\" as E\n"
            + "QtObject {\n    // import qs.panels after the header is not an import\n}\nimport qs.panels\n";
        assertEqual(ModuleSourceRules.importsOf(header).length, 14, "the imports of the header, block comments skipped, two on one line");
        const warnings = ModuleSourceRules.importWarnings("Main.qml", header);
        assertEqual(warnings.length, 4, "outside the allowlist: qs.singletons, Quickshell.Hyprland, ../core, a file URL");
        assert(_has(warnings, "Main.qml imports qs.singletons"), "… each names the file and the import");
        assert(!_has(warnings, "qs.panels"), "… nothing after the header counts");
        assertEqual(ModuleSourceRules.importWarnings("A.qml", "import QtQuick\nQtObject {}").length, 0, "an allowed file: no warning");
        assertEqual(ModuleSourceRules.importWarnings("A.qml", null).length, 0, "no text: no warning, no throw");
        assert(Array.isArray(ModuleSourceRules.importWarnings("A.qml", "import ".repeat(100000))), "a huge garbage header: no throw");
        const repeated = ModuleSourceRules.importWarnings("A.qml", "import qs.singletons\n".repeat(3000) + "Item {}");
        assertEqual(repeated.length, ModuleSourceRules.maxImportWarningsPerFile + 1, "a header of 3000 forbidden imports: maxImportWarningsPerFile warnings and a count");
        assertEqual(repeated[repeated.length - 1], "… and " + (3000 - ModuleSourceRules.maxImportWarningsPerFile) + " more", "… the count of the rest");
        assertEqual(JSON.stringify(ModuleSourceRules.cappedLines(["a", "b"], 2)), "[\"a\",\"b\"]", "cappedLines: up to the cap, as it is");
        assertEqual(JSON.stringify(ModuleSourceRules.cappedLines(["a", "b", "c"], 1)), "[\"a\",\"… and 2 more\"]", "… past it, the first and the count");
        const longName = "d/".repeat(500) + "A.qml";
        const longWarning = ModuleSourceRules.importWarnings(longName, "import qs.singletons\nItem {}")[0];
        assert(longWarning.startsWith("d/d/") && longWarning.indexOf("… imports qs.singletons") === 79 && longWarning.length < 300,
               "a listed file's long path is cut at 80 characters in its warning: " + longWarning.slice(0, 100));
        assert(ModuleSourceRules.importWarnings("A.qml", "import \"/" + "x".repeat(5000) + "\"\nItem {}")[0].length < 300, "… and so is a long quoted import");
        assert(!ModuleSourceRules.importAllowed({ name: "QtQuickX", directory: false }), "QtQuickX is not under QtQuick");
        assertEqual(JSON.stringify(ModuleSourceRules.importsOf("import qs.components; Item {}")), JSON.stringify([{ name: "qs.components", directory: false }]),
                    "an import on the line with the first \"{\" is read before stopping");
        assertEqual(ModuleSourceRules.importWarnings("A.qml", "import QtQuick\nimport qs.singletons; Item {\n}").length, 1,
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
        const merged = ModuleMergeRules.merge([{ id: "zeta", directory: "/z", manifest: zeta }, { id: "alpha", directory: "/a/", manifest: alpha },
                                    null, { id: 5 }]);
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
        const again = ModuleMergeRules.merge([{ id: "alpha", directory: "/a", manifest: alpha }, { id: "zeta", directory: "/z", manifest: zeta }]);
        assertEqual(JSON.stringify(again.widgetEntries), JSON.stringify(merged.widgetEntries), "stable: the input order does not matter");
        assertEqual(ModuleMergeRules.merge(null).widgetEntries.length, 0, "nothing to merge: empty lists");

        _m2(rules, alpha, zeta);
        _api13(rules);
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
                       "u-cafe": { ssid: "cafe", mode: "infrastructure" } };
        assertEqual(JSON.stringify(rules.apiNetworks(profiles, wifi)), JSON.stringify([
            { id: "u-office", name: "Office LAN", kind: "ethernet", active: true },
            { id: "u-cafe", name: "Cafe", kind: "wifi", active: true },
            { id: "u-home", name: "Home", kind: "wifi", active: false },
            { id: "u-train", name: "Train", kind: "wifi", active: false }]),
            "apiNetworks: Wi-Fi and Ethernet, active first (\"activated\" only), no hotspot, VPN, bridge, port or loopback");
        assertEqual(rules.apiNetworks([profile("u-unread", "New", "wifi", "")], {}).length, 1,
                    "apiNetworks: a Wi-Fi profile whose details are not read yet is kept");
        assertEqual(rules.apiNetworks([], {}).length, 0, "apiNetworks: no profiles, none");
        for (const bad of [null, undefined, "x", 3, {}, [null, 1, "x", [], {}, { uuid: "" }, { uuid: 5, kind: "wifi" }]])
            assertEqual(rules.apiNetworks(bad, null).length, 0, "apiNetworks: garbage skipped — " + JSON.stringify(bad));
        assertEqual(JSON.stringify(rules.apiNetworks([{ uuid: "u-bare", kind: "ethernet" }, { uuid: "constructor", kind: "wifi", name: 7 }], "junk")),
                    JSON.stringify([{ id: "u-bare", name: "", kind: "ethernet", active: false },
                                    { id: "constructor", name: "", kind: "wifi", active: false }]),
                    "apiNetworks: missing fields defaulted; a prototype-named UUID is just a UUID");

        // VPNs as VpnManager.activeVpns has them
        const vpns = [
            { uuid: "u-wg", name: "wg-home", type: "wireguard", active: true, state: "activated", device: "wg0" },
            { uuid: "tailscale:main", name: "Tailscale", type: "provider", provider: "tailscale", entryId: "main", state: "activated" },
            { uuid: "u-ovpn", name: "Work", type: "vpn", provider: "sneaky", state: "activated" }
        ];
        assertEqual(JSON.stringify(rules.apiVpnsUp(vpns)), JSON.stringify([
            { name: "wg-home", type: "wireguard", provider: "" },
            { name: "Tailscale", type: "provider", provider: "tailscale" },
            { name: "Work", type: "vpn", provider: "" }]),
            "apiVpnsUp: name, type, and the providerId only for a provider's VPN, in order");
        assertEqual(rules.apiVpnsUp([]).length, 0, "apiVpnsUp: none up, none");
        for (const bad of [null, undefined, "x", 3, {}, [null, 1, "x", []]])
            assertEqual(rules.apiVpnsUp(bad).length, 0, "apiVpnsUp: garbage skipped — " + JSON.stringify(bad));
        assertEqual(JSON.stringify(rules.apiVpnsUp([{ type: "provider", provider: 3 }, {}])),
                    JSON.stringify([{ name: "", type: "provider", provider: "" }, { name: "", type: "", provider: "" }]),
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

        // The file check
        const files = ModuleFileRules.filesToCheck(alpha, "singleton S 1.0 S.qml\n");
        assertEqual(files.map(entry => entry.file + ":" + entry.kind).join(","), "A1.qml:entry,P.qml:entry,A2.qml:entry,Page.qml:entry,Row.qml:entry,S.qml:qmldir",
                    "filesToCheck: every file named, each once, with its kind");
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
        assertEqual(ModuleSourceRules.importWarnings("tests/T.qml", "import \"../..\"\nItem {}", true).length, 1, "… \"../..\" leaves it");
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
    }
}
