pragma Singleton

import Quickshell
import QtQuick

// The build of a NixOS system with the shell's settings (tests/NixBuildRulesTest.qml): the
// user's configuration evaluated with only the shell's file replaced by a candidate, built
// as the user without a password (distributions/nixos/NixosBuild.qml runs it), or — for a
// root-owned configuration the user cannot build — by the root step's `build`, asked only by
// the click that starts the build. Pure.
//
// The system is nixos_toplevel of scripts/root/nixos-toplevel.sh, the file the root step
// joins before its own (expression() reads it out of that text), with the same inputs on
// both sides: the flake's reference by flakeRef (nixos-toplevel.sh's flake_ref), the host,
// the candidate as a file named h2s-shell.json, and for classic the system's own nixpkgs
// (systemNixpkgs, as the root step's system_nixpkgs) and the configuration's file, each by
// -I. So the drvPath the user builds is the one the root step checks before it switches.
//
// The words are handed to the program as they are, never to a shell. nix's progress comes as
// internal-json lines (`@nix {…}`) on stderr: step() folds each into the progress — the
// phase (Evaluating, Building N of M, Downloading N of M), done/expected, and the last
// lines, each plain text, capped — and outcome() reads the end: the built drvPath and out
// path from nix's --json answer, or why it failed.
Singleton {
    id: root

    // The file holding nixos_toplevel, in scripts/root/
    readonly property string toplevelFile: "nixos-toplevel.sh"
    // The candidate's name: the shell's file's, so that its store path is the real file's
    readonly property string candidateName: "h2s-shell.json"
    // How long the user's build may take; the root step's is the longest a run as
    // administrator may take
    readonly property int timeoutMs: 2 * 60 * 60 * 1000
    readonly property int rootTimeoutMs: PrivilegedRules.maxTimeoutMs
    // How many of the last lines the progress keeps, each at most lineMaxLength characters;
    // nix's error at most errorMaxLength
    readonly property int keptLines: 200
    readonly property int lineMaxLength: 500
    readonly property int errorMaxLength: 8000
    // nix's own words: activity types and result types (nix's logging.hh)
    readonly property var _activity: ({ copyPaths: 103, builds: 104, build: 105, substitute: 108 })
    readonly property var _result: ({ buildLogLine: 101, progress: 105 })

    readonly property var texts: ({
        // Before the build
        notFound: "No NixOS configuration was found.",
        realPath: "Where the configuration's folder really is could not be read.",
        host: "The host is not a name the shell can pass on.",
        entry: "The configuration's file is not one the shell can pass on.",
        candidate: "The new settings could not be checked.",
        gitUnknown: "Whether git knows h2s-shell.json could not be read.",
        untracked: "git does not know h2s-shell.json yet: run git add h2s-shell.json once.",
        nixpath: "The system's nixpkgs could not be found.",
        expression: "The shell's build description could not be read.",
        scratch: "There is no private folder to build in.",
        needsRoot: "The configuration can be built only with your password.",
        rootOnly: "Only a configuration that is root's alone is built with your password.",
        running: "A build is already running.",
        // How a build ended
        features: "Nix's flakes are turned off on this system.",
        failed: "The build failed.",
        timedOut: "The build did not end within 2 hours.",
        rootTimedOut: "The build did not end within an hour.",
        rootFailed: "The build as administrator failed.",
        start: "The build could not be started.",
        unclear: "The build's answer could not be read.",
        hold: "The built system could not be kept for Apply now.",
        cancelled: "The build was stopped."
    })

    function refusal(code) {
        return { code, text: _text(code) };
    }

    function _text(code) {
        return typeof code === "string" && Object.prototype.hasOwnProperty.call(texts, code) ? texts[code] : NixosApplyRules.refusal(code).text;
    }

    function _refused(code) {
        return { argv: null, environment: null, files: null, outLink: "", refusal: refusal(code) };
    }

    // ---- The system's description, shared with the root step ----

    // nixos-toplevel.sh's text → the expression between `nixos_toplevel='` and the next `'`
    // (a line of its own start to end), "" when it is not there
    function expression(text) {
        const match = /^nixos_toplevel='([^']*)'$/m.exec(String(text ?? ""));
        return match !== null && match[1].trim() !== "" ? match[1] : "";
    }

    // /etc/set-environment's text → the nixpkgs entry of its NIX_PATH (the first line
    // `export NIX_PATH="…"`, its first nixpkgs=), "" when there is none or it is not a plain
    // path — as the root step's system_nixpkgs
    function systemNixpkgs(text) {
        const match = /^export NIX_PATH="(.*)"$/m.exec(String(text ?? ""));
        if (match === null)
            return "";
        const entry = match[1].split(":").find(part => part.startsWith("nixpkgs="));
        const path = entry === undefined ? "" : entry.slice("nixpkgs=".length);
        return RootScriptRules.plainPath(path) ? path : "";
    }

    // The flake's reference for its real folder: git+file:// where it holds a .git (`git` the
    // reading's: present, also when unreadable), path: where it holds none, "" unknown — as the
    // root step's flake_ref
    function flakeRef(realFolder, git) {
        if (!RootScriptRules.plainPath(realFolder))
            return "";
        return git === "present" ? "git+file://" + realFolder : git === "absent" ? "path:" + realFolder : "";
    }

    // Whether the user cannot build it, known before trying: a git repository that is neither
    // the user's nor root's (NixosConfigRules.gitAccess "") — nix's git opens only the
    // repository of the one running, and is told only root's is safe
    function needsRootBefore(reading) {
        return reading?.git === "present" && reading?.gitAccess === "";
    }

    // The checks both ways of building share → { refusal (null or { code, text }), folder (the
    // real folder), entry, host ("-" for classic), flake, text (the candidate), sha256 }.
    // `nixpkgs`: the system's, for classic; null where the root step reads it itself.
    function _checked(reading, candidateText, nixpkgs) {
        const fail = code => ({ refusal: refusal(code) });
        const configuration = reading?.configuration;
        if (configuration?.found !== true)
            return fail("notFound");
        const folder = reading.real;
        if (!RootScriptRules.plainPath(folder))
            return fail("realPath");
        const entry = configuration.entry;
        const isFlake = configuration.type === "flake";
        if (!NixosApplyRules.validEntry(entry) || (entry === "flake.nix") !== isFlake)
            return fail("entry");
        if (isFlake && !NixosApplyRules.validHost(reading.host))
            return fail("host");
        // A flake in git sees only what git knows: the override would build while the real
        // file is untracked, and the root step's evaluation then fail
        if (reading.git === "present" && reading.gitKnowsFile !== "tracked")
            return fail(reading.gitKnowsFile === "untracked" ? "untracked" : "gitUnknown");
        if (reading.git !== "present" && reading.git !== "absent")
            return fail("gitUnknown");
        const text = candidateText;
        if (typeof text !== "string" || !text.startsWith("{") || text.includes("\u0000") || NixosApplyRules.byteLength(text) > NixosApplyRules.maxBytes)
            return fail("candidate");
        if (!isFlake && nixpkgs !== null && !RootScriptRules.plainPath(nixpkgs))
            return fail("nixpath");
        return {
            refusal: null, folder, entry, host: isFlake ? reading.host : "-", flake: isFlake ? flakeRef(folder, reading.git) : "",
            text, sha256: PamEditRules.sha256(text)
        };
    }

    // ---- The user's build ----

    // `request` { reading (NixosConfigRules.reading's, git asked), candidate (the shell's file
    // as it would be), expression (expression()'s), nixpkgs (systemNixpkgs'), nix (the absolute
    // nix), scratch (a private folder of the user's, plain and absolute), home (the user's
    // HOME), xdg ({ XDG_CONFIG_HOME, XDG_CACHE_HOME, XDG_DATA_HOME, XDG_STATE_HOME } as the
    // shell has them) } → { argv, environment (added to the shell's), files { candidate (its
    // path), gitconfig (the text of a scratch HOME's .gitconfig, "" none) }, outLink (the GC
    // root nix leaves), refusal }. For a repository root owns nix runs with a scratch HOME
    // whose .gitconfig names that folder safe and includes the user's own (the XDG folders kept
    // at the user's): root's repository is trusted at least as much as the user's own.
    function plan(request) {
        if (typeof request?.expression !== "string" || request.expression === "")
            return _refused("expression");
        if (!RootScriptRules.plainPath(request?.scratch))
            return _refused("scratch");
        if (typeof request?.nix !== "string" || !request.nix.startsWith("/"))
            return _refused("start");
        const reading = request.reading;
        const checked = _checked(reading, request.candidate, typeof request.nixpkgs === "string" ? request.nixpkgs : "");
        if (checked.refusal !== null)
            return _refused(checked.refusal.code);
        if (needsRootBefore(reading))
            return _refused("needsRoot");
        const scratch = request.scratch;
        const candidate = scratch + "/" + candidateName;
        const outLink = scratch + "/result";
        const environment = { H2S_FLAKE: checked.flake, H2S_HOST: checked.host === "-" ? "" : checked.host, H2S_CANDIDATE: candidate };
        let gitconfig = "";
        if (reading.git === "present" && reading.gitAccess === "root") {
            const home = request.home;
            gitconfig = (RootScriptRules.plainPath(home) ? "[include]\n\tpath = " + home + "/.gitconfig\n" : "")
                + "[safe]\n\tdirectory = " + checked.folder + "\n";
            environment.HOME = scratch + "/home";
            // The user's own places for nix's configuration and cache, as with the real HOME
            const defaults = { XDG_CONFIG_HOME: "/.config", XDG_CACHE_HOME: "/.cache", XDG_DATA_HOME: "/.local/share", XDG_STATE_HOME: "/.local/state" };
            for (const name of Object.keys(defaults)) {
                const given = request.xdg?.[name];
                const value = typeof given === "string" && given.startsWith("/") ? given : RootScriptRules.plainPath(home) ? home + defaults[name] : "";
                if (value !== "")
                    environment[name] = value;
            }
        }
        const classic = checked.host === "-" ? ["-I", "nixpkgs=" + request.nixpkgs, "-I", "nixos-config=" + checked.folder + "/" + checked.entry] : [];
        // NIX_PATH and NIX_CONFIG taken away, as the root step runs nix without them
        const argv = ["env", "-u", "NIX_PATH", "-u", "NIX_CONFIG", request.nix, "build", "--impure", "--extra-experimental-features", "nix-command flakes"]
            .concat(classic)
            .concat(["--log-format", "internal-json", "-v", "--json", "--out-link", outLink, "--expr", request.expression]);
        return { argv, environment, files: { candidate, gitconfig }, outLink, refusal: null };
    }

    // The words that keep a store path the root step built: the user's own GC root for it
    // (`nix build` of a path in the store builds nothing)
    function holdArgv(nix, outLink, outPath) {
        return ["env", "-u", "NIX_PATH", "-u", "NIX_CONFIG", nix, "build", "--extra-experimental-features", "nix-command flakes",
                "--out-link", outLink, "--", outPath];
    }

    // ---- The root step's build ----

    // The root step's `build` (scripts/root/nixos-apply.sh): `request` { reading, candidate },
    // `paths`, `live`, `scripts`, `shell` as NixosApplyRules.plan takes them → { argv,
    // expected, what, refusal }. Only for a root-owned configuration (reading.rootWrites), and
    // only ever started by the click that starts the build.
    function rootPlan(request, paths, live, scripts, shell) {
        const refused = code => ({ argv: null, expected: null, what: "", refusal: refusal(code) });
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return refused("arguments");
        if (NixosApplyRules.pathsRefusal(paths, live) !== "")
            return refused("paths");
        const script = RootScriptRules.script(scripts);
        if (script === "")
            return refused("script");
        const base = RootScriptRules.base(paths, ["bin", "profile", "store", "backups"], NixosApplyRules.livePaths);
        const reading = request?.reading;
        const checked = _checked(reading, request?.candidate, null);
        if (checked.refusal !== null)
            return refused(checked.refusal.code);
        const folder = reading.configuration.folder;
        if (!RootScriptRules.plainPath(folder) || (base !== "" && !folder.startsWith(base + "/")))
            return refused("paths");
        if (reading.rootWrites !== true)
            return refused("rootOnly");
        return {
            argv: [shell, "-c", script, "sh", base, "build", folder, checked.entry, checked.host, checked.sha256, checked.text],
            expected: { op: "build", store: paths.store },
            what: what(checked.folder, checked.host),
            refusal: null
        };
    }

    // What the prompt says the root build is for: the folder (its real path) and, for a flake,
    // the host; a long folder or host shortened in the middle
    function what(folder, host) {
        const flake = host !== "-";
        const make = (shownFolder, shownHost) => "Build NixOS from " + shownFolder + (flake ? " for " + shownHost : "") + " as administrator";
        const full = make(folder, host);
        if (full.length <= PrivilegedRules.whatMaxLength)
            return full;
        const room = PrivilegedRules.whatMaxLength - make("", "").length;
        const hostRoom = flake ? Math.min(host.length, Math.floor(room / 3)) : 0;
        return make(NixosApplyRules._middle(folder, room - hostRoom), NixosApplyRules._middle(host, hostRoom));
    }

    // ---- Progress ----

    function fresh() {
        return {
            builds: null, copies: null, buildsId: null, copiesId: null, buildStarted: false, evaluated: 0,
            lines: [], error: ""
        };
    }

    // A line of nix's output as plain text: colours and other control characters taken out
    function plain(text) {
        return String(text ?? "").replace(/\u001b\[[0-9;?]*[ -\/]*[@-~]/g, "").replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "");
    }

    function _withLines(state, text) {
        const more = plain(text).split("\n").map(line => line.replace(/\s+$/, "")).filter(line => line !== "")
            .map(line => line.length > lineMaxLength ? line.slice(0, lineMaxLength - 1) + "…" : line);
        if (more.length === 0)
            return state;
        return Object.assign({}, state, { lines: state.lines.concat(more).slice(-keptLines) });
    }

    function _counts(fields) {
        if (!Array.isArray(fields) || fields.length < 3 || fields.slice(0, 3).some(value => typeof value !== "number" || value < 0))
            return null;
        return { done: fields[0], expected: fields[1], running: fields[2] };
    }

    // The progress after one line of nix's output (`stream` "stdout" | "stderr"): only
    // stderr carries nix's progress; a line that is not internal-json is kept as it is. A new
    // state, the one given unchanged.
    function step(state, line, stream) {
        const current = state ?? fresh();
        if (stream === "stdout")
            return current;
        const text = String(line ?? "");
        if (!text.startsWith("@nix {"))
            return _withLines(current, text);
        let event = null;
        try {
            event = JSON.parse(text.slice(5));
        } catch (error) {
            return _withLines(current, text);
        }
        switch (event.action) {
        case "msg": {
            const level = Number(event.level);
            if (level >= 4)
                return Object.assign({}, current, { evaluated: current.evaluated + 1 });
            const message = typeof event.msg === "string" ? event.msg : "";
            const next = _withLines(current, message);
            if (level !== 0)
                return next;
            const error = plain(message).trim();
            return Object.assign({}, next, { error: error.length > errorMaxLength ? error.slice(0, errorMaxLength - 1) + "…" : error });
        }
        case "start": {
            const type = event.type;
            if (type === _activity.builds)
                return Object.assign({}, current, { buildsId: event.id });
            if (type === _activity.copyPaths)
                return Object.assign({}, current, { copiesId: event.id });
            if (type === _activity.build || type === _activity.substitute) {
                const next = type === _activity.build ? Object.assign({}, current, { buildStarted: true }) : current;
                return Number(event.level) <= 3 && typeof event.text === "string" ? _withLines(next, event.text) : next;
            }
            return current;
        }
        case "result": {
            if (event.type === _result.buildLogLine)
                return Array.isArray(event.fields) && typeof event.fields[0] === "string" ? _withLines(current, event.fields[0]) : current;
            if (event.type !== _result.progress)
                return current;
            const counts = _counts(event.fields);
            if (counts === null)
                return current;
            if (current.buildsId !== null && event.id === current.buildsId)
                return Object.assign({}, current, { builds: counts });
            if (current.copiesId !== null && event.id === current.copiesId)
                return Object.assign({}, current, { copies: counts });
            return current;
        }
        default:
            return current;
        }
    }

    // What the panel shows of a state → { phase ("evaluating" | "building" | "downloading"),
    // label, done, expected, fraction (0…1; -1 while evaluating: no measure, a moving bar),
    // lines }. Building while a build runs, or once one started and nothing is downloading;
    // downloading while a download runs and nothing builds.
    function progress(state) {
        const current = state ?? fresh();
        const builds = current.builds, copies = current.copies;
        const view = (phase, label, counts) => {
            const done = counts ? Math.min(counts.done, Math.max(counts.expected, counts.done)) : 0;
            const expected = counts ? Math.max(counts.expected, counts.done) : 0;
            return {
                phase, label: counts ? label + " " + done + " of " + expected : label, done, expected,
                fraction: counts ? (expected > 0 ? done / expected : 0) : -1, lines: current.lines
            };
        };
        if (builds !== null && builds.running > 0)
            return view("building", "Building", builds);
        if (copies !== null && copies.running > 0)
            return view("downloading", "Downloading", copies);
        if (current.buildStarted && builds !== null)
            return view("building", "Building", builds);
        return view("evaluating", "Evaluating", null);
    }

    // Why nix failed, from its error and last lines → "untracked" (git does not know a file
    // the build reads), "needsRoot" (a file or repository the user may not read), "features"
    // (the experimental features off), "failed" (anything else)
    function failureReason(state) {
        const text = [state?.error ?? ""].concat(state?.lines ?? []).join("\n");
        if (/is not tracked by Git|`git add` it/.test(text))
            return "untracked";
        if (/Permission denied|not owned by current user|libgit2 error code = 7/.test(text))
            return "needsRoot";
        if (/experimental Nix feature|requires experimental feature|experimental feature '[^']*' is disabled/.test(text))
            return "features";
        return "failed";
    }

    // nix's --json answer (stdout) → { drvPath, outPath } for one derivation built, each a
    // path of `store`; null for anything else
    function built(stdout, store) {
        let answer = null;
        try {
            answer = JSON.parse(String(stdout ?? "").trim());
        } catch (error) {
            return null;
        }
        if (!Array.isArray(answer) || answer.length !== 1)
            return null;
        const drvPath = answer[0]?.drvPath, outPath = answer[0]?.outputs?.out;
        return NixosApplyRules.storePath(drvPath, store, true) && NixosApplyRules.storePath(outPath, store, false) ? { drvPath, outPath } : null;
    }

    function _ended(kind, reason, state, more) {
        return Object.assign({
            ok: kind === "built", quiet: false, kind, reason, error: reason === "" ? "" : _text(reason), drvPath: "", outPath: "",
            lines: state?.lines ?? []
        }, more ?? {});
    }

    // The user's build ended (CommandRunner's result, the progress state, the store) → { ok,
    // quiet (always false here), kind ("built" | "failed" | "cancelled"), reason ("" when built;
    // untracked, needsRoot, features, failed, timedOut, start, unclear, cancelled), error (the
    // text), drvPath, outPath, lines }
    function outcome(result, state, store) {
        if (result?.cancelled === true)
            return _ended("cancelled", "cancelled", state);
        if (result?.timedOut === true)
            return _ended("failed", "timedOut", state);
        if (result?.failedToStart === true || (result?.error ?? "") !== "")
            return _ended("failed", "start", state);
        if (result?.code === 0) {
            const paths = built(result.stdout, store);
            return paths === null ? _ended("failed", "unclear", state) : _ended("built", "", state, paths);
        }
        return _ended("failed", failureReason(state), state);
    }

    // The root step's build ended (PrivilegedRules' result, the progress state, rootPlan's
    // expected) → as outcome; quiet when nothing ran (a prompt dismissed, polkit's refusal,
    // the session locked). Only its last line counts, with its exit code: `built <drv> <out>`
    // exit 0, `failed build` exit 1 (a fixed text: the root step passes on only nix's progress,
    // never its messages, which could quote what only root may read), `refused <code>` exit 3.
    function rootOutcome(result, state, expected) {
        const lastLine = text => String(text ?? "").trim().split("\n").pop().trim().split(" ");
        const said = lastLine(result?.stderr);
        const code = result?.code;
        if (code === 0 && said.length === 3 && said[0] === "built" && NixosApplyRules.storePath(said[1], expected?.store, true)
                && NixosApplyRules.storePath(said[2], expected?.store, false))
            return _ended("built", "", state, { drvPath: said[1], outPath: said[2] });
        if (code === 1 && said.length === 2 && said[0] === "failed" && said[1] === "build")
            return _ended("failed", "rootFailed", state);
        if (code === 3 && said.length === 2 && said[0] === "refused" && /^[a-z]+$/.test(said[1]))
            return _ended("failed", said[1], state);
        const cancelled = result?.cancelled === true;
        if ((result?.blocked ?? "") !== "" || (!cancelled && ((result?.dismissed === true && code === 126) || (result?.refused === true && code === 127))))
            return _ended("failed", "", state, { quiet: true });
        if (result?.timedOut === true)
            return _ended("failed", "rootTimedOut", state);
        return _ended("failed", "unclear", state);
    }
}
