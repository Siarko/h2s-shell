import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// NixBuildRules: the system's description read out of scripts/root/nixos-toplevel.sh (the
// file the root step joins), the system's nixpkgs and the flake's reference as the root step
// takes them; the user's build word for word (tests/fixtures/nixos-build/argv.json, which
// tests/system/nixos/build.sh runs against the root step's evaluation) and every refusal
// before it; the root step's build; nix's internal-json progress on the lines nix printed
// (tests/fixtures/nixos-build/: a real build of 15 derivations, dry runs of a built system
// and of an override, and an evaluation that failed on a file git does not know); the
// failures mapped; the end of a build, as the user and through the root step. Pure.
TestCase {
    id: suite
    suiteName: "NixBuildRules"

    property var _toplevel: FileView { path: Qt.resolvedUrl("../scripts/root/nixos-toplevel.sh"); blockLoading: true }
    property var _argv: FileView { path: Qt.resolvedUrl("fixtures/nixos-build/argv.json"); blockLoading: true }
    property var _build: FileView { path: Qt.resolvedUrl("fixtures/nixos-build/build.jsonl"); blockLoading: true }
    property var _built: FileView { path: Qt.resolvedUrl("fixtures/nixos-build/build.json"); blockLoading: true }
    property var _dryBuilt: FileView { path: Qt.resolvedUrl("fixtures/nixos-build/dry-run-built.jsonl"); blockLoading: true }
    property var _dryOverride: FileView { path: Qt.resolvedUrl("fixtures/nixos-build/dry-run-override.jsonl"); blockLoading: true }
    property var _untracked: FileView { path: Qt.resolvedUrl("fixtures/nixos-build/dry-run-untracked-error.jsonl"); blockLoading: true }

    function _replay(rules, text, stream) {
        let state = rules.fresh();
        for (const line of String(text).split("\n").filter(line => line !== ""))
            state = rules.step(state, line, stream ?? "stderr");
        return state;
    }

    function _msg(level, message) {
        return "@nix " + JSON.stringify({ action: "msg", level, msg: message });
    }

    function run() {
        const rules = NixBuildRules;
        const show = value => JSON.stringify(value);
        const sha = PamEditRules.sha256;

        // ── The system's description ──
        const fileText = String(_toplevel.text());
        const expression = rules.expression(fileText);
        assert(expression.startsWith("let\n") && expression.includes("programs.h2s-shell.settingsFile = lib.mkForce candidate;")
                   && expression.endsWith(".config.system.build.toplevel"), "expression: nixos_toplevel read out of nixos-toplevel.sh");
        assert(!(expression.includes("'")), "expression: no quote in it");
        assertEqual(rules.expression("nixos_toplevel='let x = 1; in x'\n"), "let x = 1; in x", "expression: one line");
        assertEqual(rules.expression("nixos_toplevel='let x = 'y'; in x'\n"), "", "expression: a quote inside — not taken");
        assertEqual(rules.expression("other='x'\n"), "", "expression: none");
        assertEqual(rules.expression("  nixos_toplevel='x'\n"), "", "expression: only at a line's start");
        assertEqual(rules.expression(null), "", "expression: no text");

        assertEqual(rules.systemNixpkgs("export FOO=1\nexport NIX_PATH=\"nixpkgs=/nix/store/42h7-source\"\n"), "/nix/store/42h7-source", "nixpkgs: the system's");
        assertEqual(rules.systemNixpkgs("export NIX_PATH=\"nixos-config=/etc/nixos/c.nix:nixpkgs=/a:nixpkgs=/b\"\n"), "/a", "nixpkgs: the first nixpkgs= entry");
        assertEqual(rules.systemNixpkgs("export NIX_PATH=\"nixos-config=/etc/nixos/c.nix\"\n"), "", "nixpkgs: none in NIX_PATH");
        assertEqual(rules.systemNixpkgs("export NIX_PATH=\"nixpkgs=/a b\"\n"), "", "nixpkgs: not a plain path");
        assertEqual(rules.systemNixpkgs("export NIX_PATH=\"nixpkgs=/a\" # x\n"), "", "nixpkgs: only the exact line");
        assertEqual(rules.systemNixpkgs(""), "", "nixpkgs: no file");

        assertEqual(rules.flakeRef("/etc/nixos", "present"), "git+file:///etc/nixos", "flake: git");
        assertEqual(rules.flakeRef("/etc/nixos", "absent"), "path:/etc/nixos", "flake: no git");
        assertEqual(rules.flakeRef("/etc/nixos", "unknown"), "", "flake: git unknown");
        assertEqual(rules.flakeRef("/etc/ni xos", "absent"), "", "flake: not a plain folder");

        // ── The user's build ──
        const golden = JSON.parse(String(_argv.text()));
        const nix = "/run/current-system/sw/bin/nix";
        const scratch = "/run/user/1000/h2s-shell-nixos-build";
        const folder = "/etc/nixos";
        const nixpkgs = "/nix/store/42h7k7nz90k8hi5qd9mr2ijnfvbircz4-source";
        const candidate = "{\"version\":1,\"idle\":{\"hibernateDelay\":\"3h\"}}";
        const fill = (template, values) => JSON.parse(JSON.stringify(template).replace(/@([A-Z]+)@/g, (all, name) => JSON.stringify(values[name]).slice(1, -1)));
        const values = { NIX: nix, SCRATCH: scratch, FOLDER: folder, HOST: "laptop", NIXPKGS: nixpkgs, EXPR: expression };
        const reading = more => Object.assign({
            configuration: { found: true, folder, entry: "flake.nix", type: "flake" },
            real: folder, rootWrites: true, host: "laptop", git: "absent", gitAccess: "", gitKnowsFile: ""
        }, more ?? {});
        const classicReading = more => reading(Object.assign({ configuration: { found: true, folder, entry: "configuration.nix", type: "classic" }, host: "nixos" }, more ?? {}));
        const request = more => Object.assign({ reading: reading(), candidate, expression, nixpkgs, nix, scratch, home: "/home/ola", xdg: {} }, more ?? {});
        const code = planned => planned.refusal?.code ?? "";

        const flake = rules.plan(request());
        assertEqual(flake.refusal, null, "flake: planned");
        assertEqual(show(flake.argv), show(fill(golden.flake.argv, values)), "flake: the words, as argv.json's");
        assertEqual(show(flake.environment), show(fill(golden.flake.environment, values)), "flake: path:, the host and the candidate");
        assertEqual(show(flake.files), show({ candidate: scratch + "/h2s-shell.json", gitconfig: "" }), "flake: the candidate in the private folder");
        assertEqual(flake.outLink, scratch + "/result", "flake: the GC root in the private folder");
        assertEqual(flake.argv[flake.argv.length - 1], expression, "flake: the expression one word, never through a shell");

        const git = rules.plan(request({ reading: reading({ git: "present", gitAccess: "user", gitKnowsFile: "tracked" }) }));
        assertEqual(show(git.argv), show(fill(golden.git.argv, values)), "git: the words, as argv.json's");
        assertEqual(show(git.environment), show(fill(golden.git.environment, values)), "git: git+file://, the user's own HOME");
        assertEqual(git.files.gitconfig, "", "git: the user's repository — no scratch HOME");

        const classic = rules.plan(request({ reading: classicReading() }));
        assertEqual(show(classic.argv), show(fill(golden.classic.argv, values)), "classic: the system's nixpkgs and the configuration, each by -I");
        assertEqual(show(classic.environment), show(fill(golden.classic.environment, values)), "classic: no flake, no host");

        const rootRepo = rules.plan(request({ reading: reading({ git: "present", gitAccess: "root", gitKnowsFile: "tracked" }),
                                              xdg: { XDG_CACHE_HOME: "/var/cache/ola" } }));
        assertEqual(rootRepo.files.gitconfig, "[include]\n\tpath = /home/ola/.gitconfig\n[safe]\n\tdirectory = /etc/nixos\n",
                    "root's repository: a scratch HOME naming it safe, the user's own config included");
        assertEqual(show(rootRepo.environment), show({
            H2S_FLAKE: "git+file:///etc/nixos", H2S_HOST: "laptop", H2S_CANDIDATE: scratch + "/h2s-shell.json", HOME: scratch + "/home",
            XDG_CONFIG_HOME: "/home/ola/.config", XDG_CACHE_HOME: "/var/cache/ola", XDG_DATA_HOME: "/home/ola/.local/share",
            XDG_STATE_HOME: "/home/ola/.local/state" }), "root's repository: HOME the scratch one, the XDG folders the user's");
        const oddHome = rules.plan(request({ reading: reading({ git: "present", gitAccess: "root", gitKnowsFile: "tracked" }), home: "/home/o la" }));
        assertEqual(oddHome.files.gitconfig, "[safe]\n\tdirectory = /etc/nixos\n", "root's repository: a HOME not plain is not included");
        assertEqual(oddHome.environment.XDG_CONFIG_HOME, undefined, "root's repository: no made-up XDG folder");
        const symlinked = rules.plan(request({ reading: reading({ configuration: { found: true, folder: "/etc/nixos", entry: "flake.nix", type: "flake" }, real: "/srv/nixos" }) }));
        assertEqual(symlinked.environment.H2S_FLAKE, "path:/srv/nixos", "the folder's real path, as the root step takes it");

        assertEqual(code(rules.plan(request({ expression: "" }))), "expression", "refused: no expression");
        assertEqual(code(rules.plan(request({ scratch: "" }))), "scratch", "refused: no private folder");
        assertEqual(code(rules.plan(request({ scratch: "/run/user/1000/a b" }))), "scratch", "refused: a private folder not plain");
        assertEqual(code(rules.plan(request({ nix: "nix" }))), "start", "refused: nix not absolute");
        assertEqual(code(rules.plan(request({ reading: reading({ configuration: { found: false } }) }))), "notFound", "refused: no configuration");
        assertEqual(code(rules.plan(request({ reading: reading({ real: "" }) }))), "realPath", "refused: the real folder unknown");
        assertEqual(code(rules.plan(request({ reading: reading({ configuration: { found: true, folder, entry: "flake.nix", type: "classic" } }) }))), "entry",
                    "refused: entry and type disagree");
        assertEqual(code(rules.plan(request({ reading: reading({ configuration: { found: true, folder, entry: "a b.nix", type: "classic" } }) }))), "entry",
                    "refused: an entry not plain");
        assertEqual(code(rules.plan(request({ reading: reading({ host: "lap top" }) }))), "host", "refused: a host not a plain name");
        assertEqual(code(rules.plan(request({ reading: reading({ host: "" }) }))), "host", "refused: no host");
        assertEqual(code(rules.plan(request({ reading: classicReading({ host: "" }) }))), "", "classic: no host needed");
        assertEqual(code(rules.plan(request({ reading: reading({ git: "present", gitAccess: "user", gitKnowsFile: "untracked" }) }))), "untracked",
                    "refused: git does not know the shell's file");
        assertEqual(rules.plan(request({ reading: reading({ git: "present", gitAccess: "user", gitKnowsFile: "untracked" }) })).refusal.text,
                    "git does not know h2s-shell.json yet: run git add h2s-shell.json once.", "refused: what to do, said");
        assertEqual(code(rules.plan(request({ reading: reading({ git: "present", gitAccess: "user", gitKnowsFile: "unknown" }) }))), "gitUnknown",
                    "refused: whether git knows it unknown");
        assertEqual(code(rules.plan(request({ reading: reading({ git: "present", gitAccess: "user", gitKnowsFile: "" }) }))), "gitUnknown",
                    "refused: git not asked yet");
        assertEqual(code(rules.plan(request({ reading: reading({ git: "unknown" }) }))), "gitUnknown", "refused: whether there is git unknown");
        assertEqual(code(rules.plan(request({ candidate: "[]" }))), "candidate", "refused: a candidate not an object");
        assertEqual(code(rules.plan(request({ candidate: "{\u0000}" }))), "candidate", "refused: a NUL in the candidate");
        assertEqual(code(rules.plan(request({ candidate: "{" + "x".repeat(65536) }))), "candidate", "refused: a candidate over 64 KiB");
        assertEqual(code(rules.plan(request({ candidate: "{" + "x".repeat(65535) }))), "", "a candidate of 64 KiB");
        assertEqual(code(rules.plan(request({ candidate: null }))), "candidate", "refused: no candidate");
        assertEqual(code(rules.plan(request({ reading: classicReading(), nixpkgs: "" }))), "nixpath", "refused: classic without the system's nixpkgs");
        assertEqual(code(rules.plan(request({ nixpkgs: "" }))), "", "a flake needs no nixpkgs");
        assertEqual(code(rules.plan(request({ reading: reading({ git: "present", gitAccess: "", gitKnowsFile: "tracked" }) }))), "needsRoot",
                    "refused: a repository neither the user's nor root's — the build needs root");
        assert(rules.needsRootBefore(reading({ git: "present", gitAccess: "" })), "needs root before: another's repository");
        assert(!(rules.needsRootBefore(reading({ git: "present", gitAccess: "root" }))), "root's repository: built as the user");
        assert(!(rules.needsRootBefore(reading({ git: "absent", gitAccess: "" }))), "no git: built as the user");
        assertEqual(show(rules.holdArgv(nix, scratch + "/result", "/nix/store/x-system")),
                    show(["env", "-u", "NIX_PATH", "-u", "NIX_CONFIG", nix, "build", "--extra-experimental-features", "nix-command flakes", "--out-link",
                          scratch + "/result", "--", "/nix/store/x-system"]), "hold: the user's GC root for a store path");

        // ── The root step's build ──
        const live = NixosApplyRules.livePaths;
        const base = "/scratch";
        const paths = { bin: base + live.bin, profile: base + live.profile, store: base + live.store, backups: base + live.backups };
        const scripts = ["lib\n", "file\n", "top\n", "step\n"];
        const rootFolder = base + "/etc/nixos";
        const rootReading = more => reading(Object.assign({ configuration: { found: true, folder: rootFolder, entry: "flake.nix", type: "flake" }, real: rootFolder }, more ?? {}));
        const rootPlan = (more, options) => rules.rootPlan(Object.assign({ reading: rootReading(), candidate }, more ?? {}), options?.paths ?? paths,
                                                          options?.live ?? false, options?.scripts ?? scripts, options?.shell ?? "/bin/sh");
        const asRoot = rootPlan();
        assertEqual(asRoot.refusal, null, "root: planned");
        assertEqual(show(asRoot.argv), show(["/bin/sh", "-c", "lib\nfile\ntop\nstep\n", "sh", base, "build", rootFolder, "flake.nix", "laptop", sha(candidate), candidate]),
                    "root: the four files' text, the base, build, folder, entry, host, the candidate's hash, the candidate");
        assertEqual(show(asRoot.expected), show({ op: "build", store: paths.store }), "root: what the reply must say");
        assertEqual(rules.rootTimeoutMs, 3600000, "root: the longest a run as administrator may take, an hour");
        assertEqual(rules.timeoutMs, 7200000, "the user's build: 2 hours");
        assertEqual(asRoot.what, "Build NixOS from " + rootFolder + " for laptop as administrator", "root: the prompt names the folder and the host");
        const rootClassic = rootPlan({ reading: rootReading({ configuration: { found: true, folder: rootFolder, entry: "configuration.nix", type: "classic" } }) });
        assertEqual(show(rootClassic.argv.slice(5)), show(["build", rootFolder, "configuration.nix", "-", sha(candidate), candidate]), "root classic: host -");
        assertEqual(rootClassic.what, "Build NixOS from " + rootFolder + " as administrator", "root classic: no host in the prompt");
        assertEqual(code(rootPlan({ reading: rootReading({ rootWrites: false }) })), "rootOnly", "root: refused for a configuration not root's alone");
        assertEqual(code(rootPlan({ reading: rootReading({ git: "present", gitAccess: "", gitKnowsFile: "untracked" }) })), "untracked", "root: refused when git does not know the file");
        assertEqual(code(rootPlan({}, { live: true })), "paths", "root: a stand-in's places never go to the system's pkexec");
        assertEqual(code(rootPlan({}, { scripts: ["lib\n", ""] })), "script", "root: a script file missing");
        assertEqual(code(rootPlan({}, { shell: "sh" })), "arguments", "root: the shell not absolute");
        assertEqual(code(rootPlan({ reading: rootReading({ configuration: { found: true, folder: "/etc/nixos", entry: "flake.nix", type: "flake" } }) })), "paths",
                    "root: a folder outside the stand-in's base");
        assertEqual(code(rootPlan({ candidate: "x" })), "candidate", "root: the candidate checked");
        assertEqual(code(rootPlan({ reading: rootReading({ git: "present", gitAccess: "", gitKnowsFile: "tracked" }) })), "", "root: another's repository is root's to build");
        const fixedWords = "Build NixOS from  for  as administrator".length;
        const exactHost = "h".repeat(100);
        const exact = "/" + "f".repeat(PrivilegedRules.whatMaxLength - fixedWords - exactHost.length - 1);
        assertEqual(rules.what(exact, exactHost), "Build NixOS from " + exact + " for " + exactHost + " as administrator", "root: a prompt of exactly the most characters, whole");
        const longClassic = rules.what("/" + "f".repeat(300), "-");
        assertEqual(longClassic.length, PrivilegedRules.whatMaxLength, "root classic: a long folder takes all the room");
        const flakeRoom = PrivilegedRules.whatMaxLength - fixedWords;
        const shownHost = rules.what("/" + "f".repeat(300), "h".repeat(250)).split(" for ")[1].split(" as administrator")[0];
        assertEqual(shownHost.length, Math.floor(flakeRoom / 3), "root: a long host takes a third of the room");
        const longWhat = rules.what("/" + "f".repeat(300), "h".repeat(250));
        assert(longWhat.length <= PrivilegedRules.whatMaxLength && longWhat.startsWith("Build NixOS from /fff") && longWhat.endsWith("hh as administrator"),
                   "root: a long folder and host shortened in the middle");

        assertEqual(rules.refusal("owner").text, NixosApplyRules.texts.owner, "texts: the root step's codes, its texts");
        assertEqual(rules.refusal("constructor").text, NixosApplyRules.texts.arguments, "texts: a name like an object's own, the request's");
        assertEqual(rules.refusal(5).text, NixosApplyRules.texts.arguments, "texts: not a code");

        // ── Progress: a real build ──
        let state = rules.fresh();
        const seen = [];
        const buildLines = String(_build.text()).split("\n").filter(line => line !== "");
        let firstBuilding = -1, evaluatingBefore = true;
        for (let i = 0; i < buildLines.length; i++) {
            state = rules.step(state, buildLines[i], "stderr");
            const view = rules.progress(state);
            if (seen[seen.length - 1] !== view.label)
                seen.push(view.label);
            if (view.phase === "building" && firstBuilding < 0)
                firstBuilding = i;
            if (firstBuilding < 0 && view.phase !== "evaluating")
                evaluatingBefore = false;
        }
        const end = rules.progress(state);
        assertEqual(seen[0], "Evaluating", "progress: evaluating first");
        assert(evaluatingBefore, "progress: nothing but evaluating before the first build");
        const firstStart = buildLines.findIndex(line => { const event = JSON.parse(line.slice(5)); return event.action === "start" && event.type === 105; });
        assertEqual(firstBuilding, firstStart, "progress: building from the first build's start, not while nix only counts what it will build");
        assertEqual(end.phase, "building", "progress: building at the end");
        assertEqual(end.label, "Building 15 of 16", "progress: nix's own count, done of expected");
        assertEqual(end.done, 15, "progress: done");
        assert(Math.abs(end.fraction - 15 / 16) < 1e-9, "progress: the fraction");
        assert(seen.includes("Building 1 of 16") && seen.includes("Building 8 of 16"), "progress: each build counted: " + seen.join(", "));
        assert(!(seen.some(label => label.startsWith("Downloading"))), "progress: nothing downloaded in this build");
        assertEqual(state.evaluated, buildLines.filter(line => line.startsWith("@nix {\"action\":\"msg\",\"level\":4,")).length, "progress: the evaluation's lines counted, not kept");
        assert(!(end.lines.some(line => line.startsWith("evaluating file"))), "progress: no evaluation line in the output");
        assert(end.lines.includes("building '/nix/store/5dc5cpxzxrjy2h6di0kc1ll5qn2vfqnn-h2s-helper-2.1.0.drv'"), "progress: each build named");
        assert(end.lines.includes("Running phase: unpackPhase"), "progress: the builds' own lines");
        assert(end.lines.includes("these 15 derivations will be built:"), "progress: nix's messages");
        assert(end.lines.includes("warning: not writing modified lock file of flake 'path:/tmp/h2s-build.capture/conf':"), "progress: a warning, its colours taken out");
        assert(!(end.lines.some(line => /[\u0000-\u0008\u000b-\u001f]/.test(line))), "progress: no control character left");
        assertEqual(state.error, "", "progress: no error in a build that passed");

        // Dry runs: a system built already says nothing, an override names what it would build
        const builtView = rules.progress(_replay(rules, _dryBuilt.text()));
        assertEqual(builtView.phase, "evaluating", "dry run, built: nothing but evaluating");
        assertEqual(builtView.lines.length, 0, "dry run, built: nothing to show");
        const overrideView = rules.progress(_replay(rules, _dryOverride.text()));
        assertEqual(overrideView.phase, "evaluating", "dry run, override: nothing built");
        assertEqual(overrideView.lines[0], "these 15 derivations will be built:", "dry run, override: what would be built");
        assertEqual(overrideView.fraction, -1, "evaluating: no measure (a moving bar)");

        // An evaluation that failed: git does not know the file
        const untracked = _replay(rules, _untracked.text());
        assert(untracked.error.startsWith("error:") && untracked.error.includes("Failed assertions:"), "error: nix's error kept, plain");
        assert(!(/\u001b/.test(untracked.error)), "error: no colour codes");
        assertEqual(untracked.lines[0], "warning: Git tree '/tmp/h2s-spike.Gl0N7D/revconf' is dirty", "error: the warning before it");
        assertEqual(rules.failureReason(untracked), "untracked", "error: git does not know a file");
        const untrackedEnd = rules.outcome({ ok: false, code: 1, stdout: "", stderr: "" }, untracked, "/nix/store");
        assertEqual(show([untrackedEnd.ok, untrackedEnd.kind, untrackedEnd.reason]), show([false, "failed", "untracked"]), "outcome: failed, untracked");
        assertEqual(untrackedEnd.error, rules.texts.untracked, "outcome: what to do");

        // Failures mapped
        const reason = message => rules.failureReason(_replay(rules, _msg(0, message)));
        assertEqual(reason("\u001b[31;1merror:\u001b[0m opening file '\u001b[35;1m/etc/nixos/secret.nix\u001b[0m': Permission denied"), "needsRoot",
                    "error: a file the user may not read — the build needs root");
        assertEqual(reason("error: repository path '/etc/nixos/' is not owned by current user (libgit2 error code = 7)"), "needsRoot",
                    "error: a repository the user may not open — the build needs root");
        assertEqual(reason("error: Path 'h2s-shell.json' in the repository \"/etc/nixos\" is not tracked by Git."), "untracked", "error: nix's own untracked message");
        assertEqual(reason("error: experimental Nix feature 'flakes' is disabled; add '--extra-experimental-features flakes' to enable it"), "features",
                    "error: flakes off");
        assertEqual(reason("error: builder for '/nix/store/x.drv' failed with exit code 1"), "failed", "error: anything else");
        assertEqual(rules.failureReason(_replay(rules, "error: opening file '/etc/x': Permission denied")), "needsRoot", "error: a plain line read too");

        // Downloads, synthetic (no fixture downloads)
        let download = rules.fresh();
        for (const event of [{ action: "start", id: 7, level: 0, type: 103, text: "" }, { action: "start", id: 8, level: 0, type: 104, text: "" },
                             { action: "result", id: 7, type: 105, fields: [1, 4, 1, 0] }])
            download = rules.step(download, "@nix " + JSON.stringify(event), "stderr");
        assertEqual(show([rules.progress(download).phase, rules.progress(download).label, rules.progress(download).fraction]), show(["downloading", "Downloading 1 of 4", 0.25]),
                    "progress: downloading while a download runs");
        download = rules.step(download, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [0, 3, 1, 0] }), "stderr");
        assertEqual(rules.progress(download).label, "Building 0 of 3", "progress: a running build wins over a download");
        assertEqual(rules.progress(rules.step(download, "@nix " + JSON.stringify({ action: "result", id: 99, type: 105, fields: [9, 9, 1, 0] }), "stderr")).label,
                    "Building 0 of 3", "progress: another activity's counts are not taken");
        assertEqual(rules.progress(rules.step(download, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [5, 3, 0, 0] }), "stderr")).label,
                    "Downloading 1 of 4", "progress: done over expected is not shown as a build (none running)");
        assertEqual(rules.step(download, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [-1, 3, 1, 0] }), "stderr"), download,
                    "progress: counts that are not counts change nothing");

        // Lines: capped in number and length, odd lines kept plain, stdout not read
        let many = rules.fresh();
        for (let i = 0; i < 300; i++)
            many = rules.step(many, "line " + i, "stderr");
        assertEqual(many.lines.length, rules.keptLines, "lines: the last ones kept");
        assertEqual(many.lines[many.lines.length - 1], "line 299", "lines: the newest last");
        assertEqual(many.lines[0], "line 100", "lines: the oldest dropped");
        assertEqual(rules.step(rules.fresh(), "y".repeat(rules.lineMaxLength), "stderr").lines[0], "y".repeat(rules.lineMaxLength), "lines: one of the most characters, whole");
        const long = rules.step(rules.fresh(), "x".repeat(2000), "stderr").lines[0];
        assertEqual(long.length, rules.lineMaxLength, "lines: a long one cut");
        assertEqual(rules.step(rules.fresh(), "@nix {broken", "stderr").lines[0], "@nix {broken", "lines: internal-json that is not JSON kept as it is");
        const same = rules.fresh();
        assertEqual(rules.step(same, "@nix {\"action\":\"other\",\"msg\":\"x\"}", "stderr"), same, "lines: an action it does not know adds nothing");
        assertEqual(rules.step(same, "@nix 5", "stderr").lines[0], "@nix 5", "lines: a line that is not internal-json kept as it is");
        assertEqual(rules.step(same, "[{\"drvPath\":\"x\"}]", "stdout"), same, "lines: stdout is nix's answer, not progress");
        assertEqual(rules.step(same, _msg(4, "evaluating file 'x'"), "stderr").lines.length, 0, "lines: verbose messages counted only");
        const bigError = rules.step(same, _msg(0, "e".repeat(20000)), "stderr");
        assertEqual(bigError.error.length, rules.errorMaxLength, "error: capped");
        assertEqual(rules.step(same, _msg(0, "e".repeat(rules.errorMaxLength)), "stderr").error, "e".repeat(rules.errorMaxLength), "error: one of the most characters, whole");
        assertEqual(rules.step(same, "@nix " + JSON.stringify({ action: "result", id: 1, type: 101, fields: [5] }), "stderr"), same, "lines: a build's line that is no text adds nothing");
        assertEqual(rules.step(same, "@nix " + JSON.stringify({ action: "start", id: 2, level: 3, type: 0, text: "copying x" }), "stderr"), same,
                    "lines: other activities' texts are not shown");
        assertEqual(rules.step(same, "@nix " + JSON.stringify({ action: "start", id: 3, level: 4, type: 105, text: "building y" }), "stderr").lines.length, 0,
                    "lines: a build's text of a verbose level not shown");
        assertEqual(rules.step(same, "@nix " + JSON.stringify({ action: "start", id: 4, level: 3, type: 108, text: "copying path 'z' from 'https://cache.nixos.org'" }), "stderr").lines[0],
                    "copying path 'z' from 'https://cache.nixos.org'", "lines: a download named");
        assertEqual(rules.step(same, "@nix " + JSON.stringify({ action: "start", id: 4, level: 3, type: 108, text: "x" }), "stderr").buildStarted, false,
                    "a download is not a build");
        const evaluating = rules.progress(same);
        assertEqual(show([evaluating.done, evaluating.expected]), show([0, 0]), "evaluating: nothing counted");
        let counting = rules.step(same, "@nix " + JSON.stringify({ action: "start", id: 8, level: 0, type: 104, text: "" }), "stderr");
        counting = rules.step(counting, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [0, 0, 1, 0] }), "stderr");
        assertEqual(rules.progress(counting).fraction, 0, "progress: nothing expected yet — no fraction");
        counting = rules.step(counting, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [1, 1, 1, 0] }), "stderr");
        assertEqual(rules.progress(counting).fraction, 1, "progress: one of one");
        assertEqual(rules.step(counting, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: "x" }), "stderr"), counting, "progress: fields that are no list");
        assertEqual(rules.step(counting, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [1, 2] }), "stderr"), counting, "progress: too few fields");
        assertEqual(rules.step(counting, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [1, 2, 1] }), "stderr").builds.expected, 2,
                    "progress: done, expected and running are all it reads");
        assertEqual(rules.step(counting, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [1, 2, 1, "x"] }), "stderr").builds.expected, 2,
                    "progress: … what follows them is not looked at");
        assertEqual(rules.step(counting, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [1, "2", 1, 0] }), "stderr"), counting, "progress: a field that is no number");
        assertEqual(rules.step(counting, "@nix " + JSON.stringify({ action: "result", id: 8, type: 105, fields: [2, 3, 1, 0, "more"] }), "stderr").builds.done, 2,
                    "progress: more fields than nix gives today, the first ones read");
        const copying = rules.step(rules.step(same, "@nix " + JSON.stringify({ action: "start", id: 7, level: 0, type: 103, text: "" }), "stderr"),
                                   "@nix " + JSON.stringify({ action: "result", id: 7, type: 105, fields: [1, 4, 1, 0] }), "stderr");
        assertEqual(rules.step(copying, "@nix " + JSON.stringify({ action: "result", id: 99, type: 105, fields: [9, 9, 1, 0] }), "stderr"), copying,
                    "progress: another activity's counts are not the downloads'");

        // ── The end of a build ──
        const store = "/nix/store";
        const answer = String(_built.text());
        assertEqual(show(rules.built(answer, store)), show({
            drvPath: "/nix/store/86f4485i1vmk8whfp8wbmbqa6vlsmbv8-nixos-system-nixos-26.05.20261101.9bb5222.drv",
            outPath: "/nix/store/aayigsnwrdbys1xrj2c6fsxg78nvj3n4-nixos-system-nixos-26.05.20261101.9bb5222" }), "built: drvPath and out path from nix's answer");
        assertEqual(rules.built(answer, "/other/store"), null, "built: paths of another store refused");
        const entry = JSON.parse(answer)[0];
        assertEqual(rules.built(JSON.stringify([entry, entry]), store), null, "built: not one derivation");
        assertEqual(rules.built(JSON.stringify([{ drvPath: entry.drvPath, outputs: { out: "/nix/store/x" } }]), store), null, "built: an out path not one of the store's");
        assertEqual(rules.built(JSON.stringify([{ drvPath: "/nix/store/x.drv", outputs: entry.outputs }]), store), null, "built: a drvPath not one of the store's");
        assertEqual(rules.built("[{\"drvPath\":\"/nix/store/x.drv\",\"outputs\":{\"out\":\"/nix/store/y\"}}]", store), null, "built: not store paths");
        assertEqual(rules.built("built", store), null, "built: no JSON");
        const ok = rules.outcome({ ok: true, code: 0, stdout: answer.trim(), stderr: "" }, state, store);
        assertEqual(show([ok.ok, ok.kind, ok.reason, ok.error]), show([true, "built", "", ""]), "outcome: built");
        assertEqual(ok.outPath, "/nix/store/aayigsnwrdbys1xrj2c6fsxg78nvj3n4-nixos-system-nixos-26.05.20261101.9bb5222", "outcome: the out path");
        assertEqual(ok.lines.length, state.lines.length, "outcome: the last lines kept");
        assertEqual(rules.outcome({ code: 0, stdout: "" }, state, store).reason, "unclear", "outcome: exit 0 without an answer is no build");
        assertEqual(rules.outcome({ code: 0, stdout: answer, cancelled: true }, state, store).kind, "cancelled", "outcome: cancelled wins");
        assertEqual(rules.outcome({ code: 124, timedOut: true }, state, store).reason, "timedOut", "outcome: the 2 hours");
        assertEqual(rules.outcome({ code: -1, failedToStart: true }, state, store).reason, "start", "outcome: nix did not start");
        assertEqual(rules.outcome({ code: -1, error: "argv" }, state, store).reason, "start", "outcome: refused by the runner");
        assertEqual(rules.outcome({ code: 1 }, rules.fresh(), store).reason, "failed", "outcome: a failure without words");

        // The root step's build
        const expected = { op: "build", store };
        const drv = ok.drvPath, out = ok.outPath;
        const root = (result, from) => rules.rootOutcome(result, from ?? rules.fresh(), expected);
        const rootBuilt = root({ code: 0, stderr: "x\nbuilt " + drv + " " + out + "\n", stdout: "built " + drv + " " + out });
        assertEqual(show([rootBuilt.ok, rootBuilt.kind, rootBuilt.drvPath, rootBuilt.outPath]), show([true, "built", drv, out]), "root: built");
        assertEqual(root({ code: 1, stderr: "built " + drv + " " + out }).reason, "unclear", "root: built with another exit is no build");
        assertEqual(root({ code: 0, stderr: "built " + drv + " /elsewhere/x" }).reason, "unclear", "root: a path outside the store is no build");
        assertEqual(root({ code: 0, stderr: "built " + drv }).reason, "unclear", "root: a line short of a path");
        const denied = _replay(rules, _msg(0, "error: opening file '/etc/nixos/secret.nix': Permission denied"));
        const rootFailed = root({ code: 1, stderr: "failed build" }, denied);
        assertEqual(show([rootFailed.reason, rootFailed.error]), show(["rootFailed", "The build as administrator failed."]),
                    "root: failed — a fixed text: the root step passes on nothing of nix's error");
        const refusedOwner = root({ code: 3, stderr: "refused owner" });
        assertEqual(show([refusedOwner.kind, refusedOwner.reason, refusedOwner.error]), show(["failed", "owner", NixosApplyRules.texts.owner]), "root: a refusal, its text");
        assertEqual(root({ code: 3, stderr: "refused owner" }).error, NixosApplyRules.texts.owner, "root: a refusal's text, the root step's");
        assertEqual(root({ code: 1, stderr: "refused owner" }).reason, "unclear", "root: a refusal with another exit");
        assertEqual(root({ code: 3, stderr: "refused owner now" }).reason, "unclear", "root: a refusal of more words");
        assertEqual(root({ code: 3, stderr: "denied owner" }).reason, "unclear", "root: another word, exit 3");
        assertEqual(root({ code: 3, stderr: "refused Owner!" }).reason, "unclear", "root: a code that is no code");
        assertEqual(root({ code: 0, stderr: "failed build" }).reason, "unclear", "root: failed build with exit 0");
        assertEqual(root({ code: 1, stderr: "failed build now" }).reason, "unclear", "root: failed build of more words");
        assertEqual(root({ code: 1, stderr: "failed switch" }).reason, "unclear", "root: failed, not the build");
        assertEqual(root({ code: 1, stderr: "stopped build" }).reason, "unclear", "root: another word, exit 1");
        assert(!root({ code: 5, dismissed: true }).quiet, "root: dismissed with another exit is not quiet");
        assert(!root({ code: 126 }).quiet, "root: 126 without a dismissed prompt is not quiet");
        assert(!root({ code: 5, refused: true }).quiet, "root: polkit's refusal with another exit is not quiet");
        assert(!root({ code: 127 }).quiet, "root: 127 without polkit's refusal is not quiet");
        assert(root({ code: 126, dismissed: true }).quiet, "root: a dismissed prompt is quiet");
        assert(root({ code: 127, refused: true }).quiet, "root: polkit's refusal is quiet");
        assert(root({ code: -1, blocked: "locked" }).quiet, "root: not started while locked is quiet");
        assert(!(root({ code: 126, dismissed: true, cancelled: true }).quiet), "root: cancelled is never quiet");
        assertEqual(root({ code: 124, timedOut: true }).reason, "rootTimedOut", "root: the hour");
        assertEqual(root({ code: 124, timedOut: true }).error, "The build did not end within an hour.", "root: the hour, said");
        assertEqual(root({ code: 0, stderr: "" }).reason, "unclear", "root: no line");
    }
}
