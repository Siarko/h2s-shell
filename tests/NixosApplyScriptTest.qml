import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// The root step of applying a NixOS build (scripts/root/nixos-apply.sh, after replace-lib.sh,
// replace-file.sh and nixos-toplevel.sh, the text exactly the four files joined) run for real, but as the
// user: through the shell's trusted timeout as the stand-in for the shell's runs as
// administrator does (no pkexec), under a scratch base holding the system's places, with the
// stand-in nix, nix-env, systemd-run and switch-to-configuration of tests/fixtures/
// nixos-apply/ that record their words in order and answer as the suite says. Never pkexec,
// never the real profile, store or /etc. Covered: apply on a flake (the evaluation's words
// and environment, the file written with a backup, the profile set, the switch under
// systemd-run, nothing left behind), on a git flake and on a classic configuration; the
// configuration changed since the build (drvPath or out path), a failed evaluation, a system
// not built; the profile not set (the old file back); the activation's exit 4 and a failed
// one; switch on a folder others may write in (nothing written), its file not the candidate;
// create, and again; restore, a backup not there, a name not a backup's; one run at a time;
// the caller's PATH and NIX_PATH not used; build (as root: its words and environment, its GC
// root, only nix's progress passed on, nothing written; nix failed and nothing of its error
// passed on, an answer that is no build, classic, a folder others may write in, the hash);
// a .git that is a link, a gitdir: file or others may write in, and an entry file others may
// write in or a link, refused for build and apply; and each argument refusal.
TestCase {
    id: suite
    suiteName: "NixosApplyScript"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-nixos-apply-test-" + Date.now()
    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/nixos-apply"
    readonly property string _out: _scratch + "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-nixos-system-test"
    readonly property string _drv: _scratch + "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-nixos-system-test.drv"
    readonly property string _folder: _scratch + "/etc/nixos"
    readonly property string _first: "{\"version\":1}"
    readonly property string _second: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"3h\"}}"
    readonly property string _third: "{\"version\":1,\"idle\":{\"hibernateDelay\":\"2h\"}}"
    readonly property string _stampPattern: "[0-9]{8}T[0-9]{6}Z(-[1-9])?"

    property string _script: ""
    property bool _ready: false
    property var _cases: []
    property var _result: null
    // Backup names seen, for the restore cases
    property string _applyBackup: ""

    function _sha(text) {
        return PamEditRules.sha256(text);
    }

    // apply's words for the flake folder: current, candidate, its JSON, and what was built
    function _apply(current, json, more) {
        const words = ["apply", more?.folder ?? _folder, more?.entry ?? "flake.nix", more?.host ?? "laptop", current,
                       more?.sha ?? _sha(json), more?.drv ?? _drv, more?.out ?? _out, json];
        return words;
    }

    // ---- The cases, run one after another: setup (shell, $1 the base), the script's words,
    // then a look at the tree ----
    function _case(name, setup, words, check, more) {
        _cases.push({ name, setup, words, check, base: more?.base, env: more?.env ?? [], folder: more?.folder ?? _folder, script: more?.script });
    }

    function _next() {
        const next = _cases.shift();
        if (!next) {
            _exec(["rm", "-rf", "--", _scratch], () => suite.finish());
            return;
        }
        // Every case starts from the stand-ins' answers for success and an empty record
        const reset = "set -e; cd \"$1\"; : > log/calls; : > ctl/eval.err; echo 0 > ctl/eval.code; echo 0 > ctl/switch.code; echo 0 > ctl/nix-env.code; : > ctl/nix-env.touch; echo 0 > ctl/valid.code; echo 3 > ctl/active.code; echo 0 > ctl/systemd-run.code; "
            + ": > ctl/build.err; echo 0 > ctl/build.code; printf '[{\"drvPath\":\"%s\",\"outputs\":{\"out\":\"%s\"}}]\\n' \"$2\" \"$3\" > ctl/build.out; "
            + "printf '%s %s\\n' \"$2\" \"$3\" > ctl/eval.out; put() { printf '%s' \"$1\" > etc/nixos/h2s-shell.json; }; ";
        _exec(["sh", "-c", reset + (next.setup ?? ""), "sh", _scratch, _drv, _out], code => {
            suite.assertEqual(code, 0, next.name + ": set up");
            const words = ["/bin/sh", "-c", next.script ? next.script() : suite._script, "sh", next.base ?? suite._scratch].concat(typeof next.words === "function" ? next.words() : next.words);
            const timed = PrivilegedRules.shellArgv(CommandTools.timeout, words);
            const command = ["env"].concat(next.env).concat(["sh", "-c", "umask 000; exec \"$@\"", "sh"]).concat(timed.slice(1));
            suite._exec(command, (runCode, stdout, stderr) => {
                const run = { code: runCode, stdout, stderr, last: stderr.trim().split("\n").pop() };
                suite._look(next.folder, state => {
                    try {
                        next.check(run, state);
                    } catch (error) {
                        suite.fail(next.name + ": threw " + error);
                    }
                    suite._next();
                });
            });
        });
    }

    // The tree after a run: the folder's file (null for none), its listing, the backups, the
    // stand-ins' record, the profile's link
    function _look(folder, done) {
        const script = "cd \"$1\"; f=$2/h2s-shell.json; printf '== file\\n'; if [ -f \"$f\" ] && [ ! -L \"$f\" ]; then cat \"$f\"; printf '\\n.\\n'; else printf '(none)\\n'; fi; "
            + "printf '== listing\\n'; ls -A \"$2\"; printf '== backups\\n'; ls var/lib/h2s-shell/nixos-backup 2> /dev/null; "
            + "printf '== calls\\n'; cat log/calls; printf '== profile\\n'; readlink nix/var/nix/profiles/system; "
            + "printf '== backupMode\\n'; stat -c %a var/lib/h2s-shell/nixos-backup 2> /dev/null; true";
        _exec(["sh", "-c", script, "sh", _scratch, folder], (code, stdout) => {
            const sections = {};
            let name = "";
            for (const line of stdout.split("\n")) {
                if (line.startsWith("== ")) {
                    name = line.slice(3);
                    sections[name] = [];
                } else if (name !== "") {
                    sections[name].push(line);
                }
            }
            const lines = key => (sections[key] ?? []).filter(line => line !== "");
            const file = sections.file[0] === "(none)" ? null : sections.file.slice(0, sections.file.lastIndexOf(".")).join("\n");
            done({ file, listing: lines("listing"), backups: lines("backups"), calls: lines("calls"), profile: lines("profile")[0] ?? "",
                   backupMode: lines("backupMode")[0] ?? "" });
        });
    }

    function _names(calls) {
        return calls.map(line => line.split(" ")[0]).join(",");
    }

    function _refused(code, name) {
        return (run, state) => {
            assertEqual(run.code + " " + run.last, "3 refused " + code, name + ": refused " + code);
            assertEqual(state.calls.filter(line => ["nix-env", "systemd-run", "switch"].includes(line.split(" ")[0])).length, 0, name + ": … nothing set or switched");
        };
    }

    function runAsync() {
        const S = _scratch;
        // apply on the flake: evaluated as built, written with a backup, the profile set, switched
        _case("apply", "put '" + _first + "'", _apply(_sha(_first), _second), (run, state) => {
            const pattern = new RegExp("^applied 2 (h2s-shell\\.json\\." + _stampPattern + ")$");
            const match = pattern.exec(run.last);
            assert(match !== null, "apply: applied, generation 2, its backup: " + run.last);
            assertEqual(run.code, 0, "apply: exit 0");
            assertEqual(run.stdout.trim(), run.last, "apply: the last line on stdout too");
            suite._applyBackup = match?.[1] ?? "";
            assertEqual(state.file, _second, "apply: the file holds the candidate");
            assertEqual(JSON.stringify(state.listing), JSON.stringify(["flake.nix", "h2s-shell.json"]), "apply: no temporary file left");
            assertEqual(JSON.stringify(state.backups), JSON.stringify([suite._applyBackup]), "apply: one backup");
            assertEqual(state.profile, "system-2-link", "apply: the profile at the new generation");
            assertEqual(_names(state.calls), "nix,nix-vars,nix-home,nix-candidate,nix-store,systemctl,nix-env,systemd-run,switch",
                        "apply: evaluated, checked, then the profile set, then switched, in that order");
            assertEqual(state.calls[0], "nix eval --raw --impure --extra-experimental-features nix-command flakes --expr EXPR --apply APPLY",
                        "apply: the evaluation's words (a flake: no -I)");
            assertEqual(state.calls[1], "nix-vars flake=path:" + _folder + " host=laptop nixpath=unset override=yes",
                        "apply: path: for a folder without git, the host, no NIX_PATH, the shell's file overridden");
            assertEqual(state.calls[2], "nix-home [safe]  directory = " + _folder + " ", "apply: the folder a safe directory for nix's git");
            assertEqual(state.calls[3], "nix-candidate h2s-shell.json " + _sha(_second), "apply: the candidate evaluated, under the file's name");
            assertEqual(state.calls[4], "nix-store --check-validity -- " + _out, "apply: the built system valid in the store");
            assertEqual(state.calls[5], "systemctl is-active --quiet -- nixos-rebuild-switch-to-configuration.service", "apply: no other activation running");
            assertEqual(state.calls[6], "nix-env -p " + S + "/nix/var/nix/profiles/system --set " + _out, "apply: the system profile set to the built system");
            assertEqual(state.calls[7], "systemd-run --collect --no-ask-password --pipe --quiet --service-type=exec --unit=nixos-rebuild-switch-to-configuration --wait",
                        "apply: the switch under systemd-run, as nixos-rebuild runs it");
            assertEqual(state.calls[8], "switch switch", "apply: the built system's switch-to-configuration switch");
            assert(run.stderr.includes("activating the configuration..."), "apply: the activation's output passed on");
        });
        _case("the configuration changed since the build",
              "printf '%s %s\\n' \"$(dirname \"$2\")/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system-test.drv\" \"$3\" > ctl/eval.out",
              _apply(_sha(_second), _third), (run, state) => {
            _refused("changed", "a different drvPath")(run, state);
            assertEqual(state.file, _second, "a different drvPath: nothing written");
            assertEqual(state.backups.length, 1, "a different drvPath: no backup");
        });
        _case("another out path", "printf '%s %s-other\\n' \"$2\" \"$3\" > ctl/eval.out", _apply(_sha(_second), _third), (run, state) => {
            _refused("changed", "a different out path")(run, state);
            assertEqual(state.file, _second, "a different out path: nothing written");
        });
        _case("a failed evaluation", "echo 1 > ctl/eval.code; printf 'error: attribute missing\\n' > ctl/eval.err", _apply(_sha(_second), _third), (run, state) => {
            _refused("evaluation", "a failed evaluation")(run, state);
            assert(run.stderr.includes("error: attribute missing\nrefused evaluation"), "a failed evaluation: nix's last lines before the refusal");
            assertEqual(state.file, _second, "a failed evaluation: nothing written");
        });
        _case("another out path named", "", _apply(_sha(_second), _third, { out: _out + "x" }), (run, state) => {
            _refused("changed", "the out path the user names not the one evaluated")(run, state);
        });
        _case("not built, as evaluated", "printf '%s %sx\\n' \"$2\" \"$3\" > ctl/eval.out", _apply(_sha(_second), _third, { out: _out + "x" }), (run, state) => {
            _refused("notbuilt", "a system not in the store")(run, state);
            assertEqual(state.file, _second, "not built: nothing written");
        });
        _case("the profile not set", "echo 1 > ctl/nix-env.code", _apply(_sha(_second), _third), (run, state) => {
            const match = new RegExp("^restored " + _sha(_second) + " h2s-shell\\.json\\." + _stampPattern + "$").exec(run.last);
            assert(match !== null, "the profile not set: the old file restored: " + run.last);
            assertEqual(run.code, 1, "the profile not set: exit 1");
            assertEqual(state.file, _second, "the profile not set: the old file back");
            assertEqual(state.backups.length, 3, "the profile not set: the old file's backup and the candidate's");
            assertEqual(_names(state.calls), "nix,nix-vars,nix-home,nix-candidate,nix-store,systemctl,nix-env", "the profile not set: nothing switched");
            assertEqual(state.profile, "system-2-link", "the profile not set: still the generation before");
            assertEqual(JSON.stringify(state.listing), JSON.stringify(["flake.nix", "h2s-shell.json"]), "the profile not set: no temporary file left");
        });
        _case("applied with errors", "echo 4 > ctl/switch.code", _apply(_sha(_second), _third), (run, state) => {
            assert(new RegExp("^applied-with-errors 3 h2s-shell\\.json\\." + _stampPattern + "$").test(run.last), "exit 4 of the switch: applied with errors: " + run.last);
            assertEqual(run.code, 4, "applied with errors: exit 4");
            assertEqual(state.file, _third, "applied with errors: the file kept");
        });
        _case("a failed activation", "echo 1 > ctl/switch.code", _apply(_sha(_third), _second), (run, state) => {
            assert(new RegExp("^failed 4 h2s-shell\\.json\\." + _stampPattern + "$").test(run.last), "a failed switch: failed, the generation set: " + run.last);
            assertEqual(run.code, 1, "a failed switch: exit 1");
            assertEqual(state.file, _second, "a failed switch: the file kept (restore puts it back)");
        });
        _case("not valid in the store", "echo 1 > ctl/valid.code", _apply(_sha(_second), _third), (run, state) => {
            _refused("notbuilt", "a system the store does not hold as valid")(run, state);
            assertEqual(state.file, _second, "not valid: nothing written");
        });
        _case("another activation running", "echo 0 > ctl/active.code", _apply(_sha(_second), _third), (run, state) => {
            _refused("busy", "another switch-to-configuration unit active")(run, state);
            assertEqual(state.file, _second, "another activation: nothing written");
        });
        _case("the activation not started", "echo 1 > ctl/systemd-run.code", _apply(_sha(_second), _third), (run, state) => {
            const match = new RegExp("^not-activated 4 " + _sha(_second) + " h2s-shell\\.json\\." + _stampPattern + "$").exec(run.last);
            assert(match !== null, "systemd-run failed: not activated, the generation before and the old file back: " + run.last);
            assertEqual(run.code, 5, "not activated: exit 5");
            assertEqual(state.profile, "system-4-link", "not activated: the profile back at the generation before");
            assertEqual(state.file, _second, "not activated: the old file back");
            assertEqual(state.calls.filter(line => line.startsWith("nix-env ")).pop(), "nix-env -p " + S + "/nix/var/nix/profiles/system --switch-generation 4",
                        "not activated: the generation before switched back to");
            assertEqual(state.calls.filter(line => line.startsWith("switch ")).length, 0, "not activated: switch-to-configuration never ran");
        });
        _case("the old file not put back", "echo 1 > ctl/nix-env.code; echo etc/nixos/h2s-shell.json > ctl/nix-env.touch", _apply(_sha(_second), _third), (run, state) => {
            assert(new RegExp("^not-restored " + _sha(_third) + " h2s-shell\\.json\\." + _stampPattern + "$").test(run.last),
                   "the file changed before the restore: not restored, the candidate still written: " + run.last);
            assertEqual(run.code, 6, "not restored: exit 6, not a refusal's 3");
            assertEqual(state.file, _third + "x", "not restored: the file as it was left");
            assertEqual(JSON.stringify(state.listing), JSON.stringify(["flake.nix", "h2s-shell.json"]), "not restored: no temporary file left");
        });
        _case("compare-and-swap", "put '" + _second + "'", _apply(_sha(_third), _first), (run, state) => {
            _refused("changed", "the file not as the shell read it")(run, state);
            assertEqual(state.calls.length, 0, "the file not as read: not even evaluated");
        });
        _case("a file where the shell read none", "", _apply("absent", _first), _refused("changed", "a file where the shell read none"));
        _case("the target a link", "mv etc/nixos/h2s-shell.json etc/real.json; ln -s ../real.json etc/nixos/h2s-shell.json",
              _apply(_sha(_second), _first), (run, state) => {
            _refused("link", "the shell's file a link")(run, state);
        });
        _case("restore of a backup not there", "rm etc/nixos/h2s-shell.json; mv etc/real.json etc/nixos/h2s-shell.json",
              ["restore", _folder, "h2s-shell.json.20200101T000000Z", _sha(_second)], (run, state) => {
            assertEqual(run.last, "refused nobackup", "restore of a backup not there: refused nobackup");
        });
        // A git flake and a classic configuration
        _case("a git flake", "mkdir -p etc/git/.git; : > etc/git/flake.nix",
              _apply("absent", _second, { folder: S + "/etc/git", host: "work_2-b" }), (run, state) => {
            assert(run.last.startsWith("applied 6 h2s-shell.json."), "a git flake: applied: " + run.last);
            assertEqual(state.calls[1], "nix-vars flake=git+file://" + S + "/etc/git host=work_2-b nixpath=unset override=yes", "a git flake: git+file://");
            assertEqual(state.file, _second, "a git flake: the file written");
            assert(state.backups.some(name => name.endsWith(".absent")), "a git flake: a backup of no file");
        }, { folder: S + "/etc/git" });
        _case("classic", "mkdir -p etc/classic; : > etc/classic/configuration.nix; "
              + "printf 'export PATH=\"/nowhere\"\\nexport NIX_PATH=\"other=/x:nixpkgs=/nix/store/abc-source:/nix/var/channels\"\\n' > etc/set-environment",
              _apply("absent", _second, { folder: S + "/etc/classic", entry: "configuration.nix", host: "-" }), (run, state) => {
            assert(run.last.startsWith("applied 7 "), "classic: applied: " + run.last);
            assertEqual(state.calls[0], "nix eval --raw --impure --extra-experimental-features nix-command flakes -I nixpkgs=/nix/store/abc-source -I nixos-config="
                        + S + "/etc/classic/configuration.nix --expr EXPR --apply APPLY", "classic: the system's nixpkgs and the configuration, each by -I");
            assertEqual(state.calls[1], "nix-vars flake= host= nixpath=unset override=yes", "classic: no flake");
        }, { folder: S + "/etc/classic" });
        _case("classic, another entry", "printf 'x' > etc/classic/machine.nix",
              _apply(_sha(_second), _third, { folder: S + "/etc/classic", entry: "machine.nix", host: "-" }), (run, state) => {
            assert(run.last.startsWith("applied 8 "), "classic, another entry: applied: " + run.last);
            assert(state.calls[0]?.includes(" -I nixos-config=" + S + "/etc/classic/machine.nix "), "classic: the configuration's own file: " + state.calls[0]);
        }, { folder: S + "/etc/classic" });
        _case("classic with a host", "", _apply(_sha(_third), _second, { folder: S + "/etc/classic", entry: "configuration.nix" }),
              _refused("arguments", "classic with a host"), { folder: S + "/etc/classic" });
        _case("classic without the system's nixpkgs", "printf 'export NIX_PATH=\"other=/x\"\\n' > etc/set-environment",
              _apply(_sha(_third), _second, { folder: S + "/etc/classic", entry: "configuration.nix", host: "-" }),
              _refused("nixpath", "no nixpkgs in the system's NIX_PATH"), { folder: S + "/etc/classic" });
        _case("classic, nixpkgs not plain", "printf 'export NIX_PATH=\"nixpkgs=https://example.org/x.tar.gz\"\\n' > etc/set-environment",
              _apply(_sha(_third), _second, { folder: S + "/etc/classic", entry: "configuration.nix", host: "-" }),
              _refused("nixpath", "nixpkgs not a plain path"), { folder: S + "/etc/classic" });
        _case("flake without flake.nix", "", _apply(_sha(_third), _second, { folder: S + "/etc/classic" }),
              _refused("entry", "flake.nix not in the folder"), { folder: S + "/etc/classic" });
        // build: the system built as root, for a root-owned configuration only; nothing written
        // but the store and its GC root; of nix's output only its progress passed on (no
        // message, no build line, no text: they could quote what only root may read)
        const progress = ["@nix {\"action\":\"start\",\"id\":8,\"level\":0,\"parent\":0,\"text\":\"\",\"type\":104}",
                          "@nix {\"action\":\"start\",\"id\":11,\"level\":0,\"parent\":0,\"text\":\"\",\"type\":105}",
                          "@nix {\"action\":\"result\",\"fields\":[1,2,1,0],\"id\":8,\"type\":105}",
                          "@nix {\"action\":\"result\",\"fields\":[101,0],\"id\":9,\"type\":106}",
                          "@nix {\"action\":\"stop\",\"id\":11}"];
        _case("build", "cp '" + _fixtures + "/build-output' ctl/build.err",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "0 built " + _drv + " " + _out, "build: built, its drvPath and out path");
            assertEqual(run.stdout.trim(), run.last, "build: the last line on stdout too");
            assertEqual(state.calls[0], "nix build --impure --extra-experimental-features nix-command flakes --log-format internal-json --out-link "
                        + S + "/nix/var/nix/gcroots/h2s-shell/build --json --expr EXPR",
                        "build: nix build of nixos_toplevel, its progress as internal-json, held by a GC root in root's own place until the user's");
            assertEqual(state.calls[1], "nix-vars flake=path:" + _folder + " host=laptop nixpath=unset override=yes", "build: the flake, the host, the override");
            assertEqual(state.calls[2], "nix-home [safe]  directory = " + _folder + " ", "build: the folder a safe directory for nix's git");
            assertEqual(state.calls[3], "nix-candidate h2s-shell.json " + _sha(_third), "build: the candidate, by the shell's file's name");
            assertEqual(_names(state.calls), "nix,nix-vars,nix-home,nix-candidate", "build: nothing but nix");
            assertEqual(JSON.stringify(run.stderr.trim().split("\n")), JSON.stringify(progress.concat([run.last])),
                        "build: nix's progress passed on, and nothing else of its output");
            assertEqual(JSON.stringify(state.listing), JSON.stringify(["flake.nix", "h2s-shell.json"]), "build: nothing written in the folder");
        });
        _case("build, nix failed", "echo 1 > ctl/build.code; cp '" + _fixtures + "/build-output' ctl/build.err",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "1 failed build", "build: nix failed — failed build");
            assert(!run.stderr.includes("secret") && !run.stdout.includes("secret"), "build: nix's error not passed on: " + run.stderr);
        });
        // nix's git trusts only a .git that is a folder of root's alone; the entry file the same
        _case("build, .git a link", "mkdir -p etc/real-git; ln -s ../real-git etc/nixos/.git",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], _refused("owner", "build, .git a link"));
        _case("build, .git a file naming another folder", "rm etc/nixos/.git; printf 'gitdir: %s/etc/real-git\\n' \"$1\" > etc/nixos/.git",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], _refused("owner", "build, .git a gitdir: file"));
        _case("build, .git others may write in", "rm etc/nixos/.git; mkdir etc/nixos/.git; chmod 775 etc/nixos/.git",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], _refused("owner", "build, .git group-writable"));
        _case("apply, .git a link", "rmdir etc/nixos/.git; ln -s ../real-git etc/nixos/.git; put '" + _third + "'",
              () => _apply(_sha(_third), _second), _refused("owner", "apply (root's evaluation), .git a link"));
        _case("build, a .git of root's alone", "rm etc/nixos/.git; mkdir etc/nixos/.git",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "0 built " + _drv + " " + _out, "build, a .git of root's: built");
            assertEqual(state.calls[2], "nix-home [safe]  directory = " + _folder + " ", "build, git: named safe");
        });
        _case("build, the entry others may write in", "rmdir etc/nixos/.git; chmod 664 etc/nixos/flake.nix",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], _refused("owner", "build, flake.nix group-writable"));
        _case("build, the entry a link", "chmod 644 etc/nixos/flake.nix; mv etc/nixos/flake.nix etc/real-flake.nix; ln -s ../real-flake.nix etc/nixos/flake.nix",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], _refused("owner", "build, flake.nix a link"));
        _case("apply, the entry others may write in", "rm etc/nixos/flake.nix; mv etc/real-flake.nix etc/nixos/flake.nix; chmod 666 etc/nixos/flake.nix; put '" + _third + "'",
              () => _apply(_sha(_third), _second), (run, state) => {
            _refused("owner", "apply, flake.nix writable by others")(run, state);
            assertEqual(state.file, _third, "apply, entry refused: nothing written");
        });
        _case("build, the entry put right", "chmod 644 etc/nixos/flake.nix; put '" + _second + "'",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "0 built " + _drv + " " + _out, "build: built again");
        });
        _case("build, an answer that is no build", "printf 'built\\n' > ctl/build.out",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "1 failed build", "build: nix's answer not one derivation in the store — failed build");
        });
        _case("build, paths outside the store", "printf '[{\"drvPath\":\"/x/a.drv\",\"outputs\":{\"out\":\"/x/b\"}}]\\n' > ctl/build.out",
              ["build", _folder, "flake.nix", "laptop", _sha(_third), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "1 failed build", "build: paths outside the store — failed build");
        });
        _case("build, classic", "printf 'export NIX_PATH=\"nixpkgs=/nix/store/abc-source\"\\n' > etc/set-environment",
              ["build", S + "/etc/classic", "configuration.nix", "-", _sha(_third), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "0 built " + _drv + " " + _out, "build, classic: built");
            assertEqual(state.calls[0], "nix build --impure --extra-experimental-features nix-command flakes -I nixpkgs=/nix/store/abc-source -I nixos-config="
                        + S + "/etc/classic/configuration.nix --log-format internal-json --out-link " + S + "/nix/var/nix/gcroots/h2s-shell/build --json --expr EXPR", "build, classic: each by -I");
        }, { folder: S + "/etc/classic" });
        _case("build, a folder others may write in", "mkdir -p home/open; chmod 775 home/open; : > home/open/flake.nix",
              ["build", S + "/home/open", "flake.nix", "laptop", _sha(_third), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "3 refused owner", "build: only a configuration that is root's alone");
            assertEqual(state.calls.length, 0, "build: nix not run");
        }, { folder: S + "/home/open" });
        _case("build, the candidate not its hash", "", ["build", _folder, "flake.nix", "laptop", _sha(_second), _third], (run, state) => {
            assertEqual(run.code + " " + run.last, "3 refused hash", "build: the candidate's hash checked");
            assertEqual(state.calls.length, 0, "build: … before nix runs");
        });
        _case("build, a word short", "", ["build", _folder, "flake.nix", "laptop", _sha(_third)], _refused("arguments", "build, a word short"));
        _case("build, classic with a host", "", ["build", S + "/etc/classic", "configuration.nix", "laptop", _sha(_third), _third],
              _refused("arguments", "build, classic with a host"), { folder: S + "/etc/classic" });
        // A folder others may write in: switch only
        _case("switch", "mkdir -p home/cfg; chmod 775 home/cfg; : > home/cfg/flake.nix; printf '%s' '" + _second + "' > home/cfg/h2s-shell.json",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_second), _drv, _out, _second], (run, state) => {
            assertEqual(run.last + " " + run.code, "applied 9 - 0", "switch: applied, no backup");
            assertEqual(state.file, _second, "switch: the file as the user wrote it");
            assertEqual(JSON.stringify(state.listing), JSON.stringify(["flake.nix", "h2s-shell.json"]), "switch: nothing written in the folder");
            assertEqual(_names(state.calls), "nix,nix-vars,nix-home,nix-candidate,nix-store,systemctl,nix-env,systemd-run,switch", "switch: evaluated, set, switched");
        }, { folder: S + "/home/cfg" });
        // A .git not root's alone: trusted in a folder of the user's (root runs the user's code
        // there anyway), refused in a folder of root's (it would put the user's repository there)
        _case("switch, a git folder of the user's", "mkdir home/cfg/.git; chmod 775 home/cfg/.git; printf '%s %s-x\\n' \"$2\" \"$3\" > ctl/eval.out",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_second), _drv, _out, _second], (run, state) => {
            assertEqual(run.code + " " + run.last, "3 refused changed", "switch, the user's folder and .git: evaluated (here as changed), not refused for the .git");
            assertEqual(state.calls[2], "nix-home [safe]  directory = " + S + "/home/cfg ", "switch, the user's folder: named safe");
        }, { folder: S + "/home/cfg" });
        _case("switch, a .git not root's in a folder of root's", "rmdir home/cfg/.git; mkdir etc/nixos/.git; chmod 775 etc/nixos/.git; put '" + _second + "'",
              ["switch", _folder, "flake.nix", "laptop", _sha(_second), _drv, _out, _second], _refused("owner", "switch, root's folder, a .git others may write in"));
        _case("switch, an entry not root's in a folder of root's", "rmdir etc/nixos/.git; chmod 664 etc/nixos/flake.nix",
              ["switch", _folder, "flake.nix", "laptop", _sha(_second), _drv, _out, _second], _refused("owner", "switch, root's folder, flake.nix others may write in"));
        _case("switch, the entry put back", "chmod 644 etc/nixos/flake.nix", ["create", _folder], (run, state) => {
            assertEqual(run.last, "refused changed", "switch cases: root's folder as it was (create refuses: a file is there)");
        });
        _case("switch, the activation not started", "echo 1 > ctl/systemd-run.code",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_second), _drv, _out, _second], (run, state) => {
            assertEqual(run.code + " " + run.last, "5 not-activated 9 - -", "switch: not activated, the generation before back, nothing written");
            assertEqual(state.profile, "system-9-link", "switch: not activated: the profile back");
        }, { folder: S + "/home/cfg" });
        _case("switch, the file not the candidate", "",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_third), _drv, _out, _third],
              _refused("changed", "switch: the file not the candidate"), { folder: S + "/home/cfg" });
        _case("switch, the profile not set", "echo 1 > ctl/nix-env.code",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_second), _drv, _out, _second],
              (run, state) => {
            assertEqual(run.code + " " + run.last, "3 refused profile", "switch: the profile not set: refused profile");
            assertEqual(_names(state.calls), "nix,nix-vars,nix-home,nix-candidate,nix-store,systemctl,nix-env", "switch: the profile not set: nothing switched");
            assertEqual(state.profile, "system-9-link", "switch: the profile not set: the generation before");
        }, { folder: S + "/home/cfg" });
        _case("switch, changed since the build", "printf '%s %s-x\\n' \"$2\" \"$3\" > ctl/eval.out",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_second), _drv, _out, _second],
              _refused("changed", "switch: changed since the build"), { folder: S + "/home/cfg" });
        _case("switch, a failed evaluation", "echo 1 > ctl/eval.code; printf 'error: root:secret-from-shadow\\n' > ctl/eval.err",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_second), _drv, _out, _second], (run, state) => {
            _refused("evaluation", "switch: a failed evaluation")(run, state);
            assert(!run.stderr.includes("secret-from-shadow") && !run.stdout.includes("secret-from-shadow"),
                   "switch: the evaluation's messages of a configuration of the user's not passed on: " + run.stderr);
        }, { folder: S + "/home/cfg" });
        _case("switch, a FIFO for the file", "rm home/cfg/h2s-shell.json; mkfifo home/cfg/h2s-shell.json",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_second), _drv, _out, _second], (run, state) => {
            assert(run.code === 3 && (run.last === "refused changed" || run.last === "refused unreadable"),
                   "switch: a FIFO in place of the user's file read without waiting, refused: " + run.code + " " + run.last);
            assertEqual(state.calls.length, 0, "switch: a FIFO: not evaluated");
        }, { folder: S + "/home/cfg" });
        _case("switch, a link for the file", "rm home/cfg/h2s-shell.json; ln -s /dev/zero home/cfg/h2s-shell.json",
              ["switch", S + "/home/cfg", "flake.nix", "laptop", _sha(_second), _drv, _out, _second],
              _refused("link", "switch: a link in place of the user's file"), { folder: S + "/home/cfg" });
        _case("apply where others may write", "", _apply(_sha(_second), _third, { folder: S + "/home/cfg" }), (run, state) => {
            _refused("owner", "apply in a folder others may write in")(run, state);
            assertEqual(state.calls.length, 0, "… not even evaluated");
        }, { folder: S + "/home/cfg" });
        _case("apply through a link", "ln -sfn ../home/cfg etc/linked", _apply(_sha(_second), _third, { folder: S + "/etc/linked" }),
              _refused("owner", "apply in a folder reached through a link: its real path's chain"), { folder: S + "/home/cfg" });
        _case("apply under a parent others may write in", "mkdir -p open/cfg; chmod 777 open; : > open/cfg/flake.nix",
              _apply("absent", _third, { folder: S + "/open/cfg" }), _refused("owner", "a parent folder others may write in"), { folder: S + "/open/cfg" });
        _case("create where others may write", "", ["create", S + "/home/cfg"], _refused("owner", "create in a folder others may write in"), { folder: S + "/home/cfg" });
        _case("restore where others may write", "", ["restore", S + "/home/cfg", suite._applyBackup || "h2s-shell.json.20200101T000000Z", _sha(_second)],
              _refused("owner", "restore in a folder others may write in"), { folder: S + "/home/cfg" });
        // create
        _case("create", "mkdir -p etc/new", ["create", S + "/etc/new"], (run, state) => {
            assert(new RegExp("^created " + _sha("{\"version\":1}\n") + " h2s-shell\\.json\\." + _stampPattern + "\\.absent$").test(run.last),
                   "create: created, a backup of no file: " + run.last);
            assertEqual(state.file, "{\"version\":1}\n", "create: {\"version\":1}");
            assertEqual(state.calls.length, 0, "create: nothing evaluated or switched");
        }, { folder: S + "/etc/new" });
        _case("create again", "", ["create", S + "/etc/new"], _refused("changed", "create where the file is"), { folder: S + "/etc/new" });
        // One run at a time; the caller's PATH and NIX_PATH
        _case("busy", "( (flock 9; touch held; while [ ! -e release ]; do sleep 0.05; done) 9>> var/lib/h2s-shell/nixos-backup/.lock; touch gone ) > /dev/null 2>&1 < /dev/null & "
              + "while [ ! -e held ]; do sleep 0.05; done",
              _apply(_sha(_second), _third), (run, state) => {
            _refused("busy", "another run holds the lock")(run, state);
        });
        _case("the caller's PATH and NIX_PATH", "touch release; while [ ! -e gone ]; do sleep 0.05; done; rm -f held release gone; mkdir -p evil; for t in flock sha256sum mktemp stat; do printf '#!/bin/sh\\ntouch \"%s/evil-ran\"\\nexit 1\\n' \"$1\" > evil/$t; chmod 755 evil/$t; done",
              _apply(_sha(_second), _third), (run, state) => {
            assert(run.last.startsWith("applied 11 "), "the caller's PATH and NIX_PATH: applied all the same: " + run.last);
            assertEqual(state.calls[1].split(" ")[3], "nixpath=unset", "… no NIX_PATH reaches nix");
            suite._exec(["test", "-e", S + "/evil-ran"], code => suite.assertEqual(code, 1, "… no program from the caller's PATH ran"));
        }, { env: ["NIX_PATH=nixpkgs=/evil", "PATH=" + S + "/evil:" + (Quickshell.env("PATH") ?? "")] });
        // The arguments
        const big = "{\"version\":1,\"pad\":\"" + "x".repeat(65536) + "\"}";
        const refusals = [
            ["a host not plain", _apply(_sha(_third), _first, { host: "lap top" }), "arguments"],
            ["an empty host", _apply(_sha(_third), _first, { host: "" }), "arguments"],
            ["JSON over 64 KiB", _apply(_sha(_third), big), "json"],
            ["JSON not an object", _apply(_sha(_third), "[1]"), "json"],
            ["a sha256 not one", _apply("abc", _first), "arguments"],
            ["a drvPath outside the store", _apply(_sha(_third), _first, { drv: "/tmp/zyxwvsrqpnmlkjihgfdcba9876543210-x.drv" }), "arguments"],
            ["a drvPath not a .drv", _apply(_sha(_third), _first, { drv: _out }), "arguments"],
            ["an out path that is a .drv", _apply(_sha(_third), _first, { out: _drv }), "arguments"],
            ["a store hash with letters base-32 has not", _apply(_sha(_third), _first, { out: S + "/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-nixos-system-test" }), "arguments"],
            ["a store path in a folder below", _apply(_sha(_third), _first, { out: _out + "/bin" }), "arguments"],
            ["an entry with a folder", _apply(_sha(_third), _first, { entry: "../flake.nix" }), "arguments"],
            ["an entry not a .nix", _apply(_sha(_third), _first, { entry: "flake.lock" }), "arguments"],
            ["a relative folder", _apply(_sha(_third), _first, { folder: "etc/nixos" }), "paths"],
            ["a folder with ..", _apply(_sha(_third), _first, { folder: S + "/etc/../etc/nixos" }), "paths"],
            ["a folder outside the base", _apply(_sha(_third), _first, { folder: "/tmp" }), "paths"],
            ["a folder not there", _apply(_sha(_third), _first, { folder: S + "/nowhere" }), "folder"],
            ["an op it does not know", ["rebuild", _folder], "arguments"],
            ["too few words", _apply(_sha(_third), _first).slice(0, 8), "arguments"],
            ["too many words", _apply(_sha(_third), _first).concat(["x"]), "arguments"],
            ["no words", [], "arguments"],
            ["restore of a name not a backup's", ["restore", _folder, "nonsense", _sha(_third)], "arguments"],
            ["restore of an empty name", ["restore", _folder, "", _sha(_third)], "arguments"],
            ["restore of a name with a character no backup has", ["restore", _folder, "h2s-shell.json.20200101T000000Z/", _sha(_third)], "arguments"],
            ["restore with a current not a sha256", ["restore", _folder, "h2s-shell.json.20200101T000000Z", ""], "arguments"]
        ];
        _case("the candidate's sha256 not its text's", "", _apply(_sha(_third), _first, { sha: _sha(_second) }), (run, state) => {
            _refused("hash", "the candidate's sha256 not its text's")(run, state);
            assertEqual(state.calls.length, 0, "… not evaluated");
        });
        for (const [name, words, code] of refusals)
            _case(name, "", words, _refused(code, name));
        _case("a relative base", "", ["create", _folder], _refused("paths", "a relative base"), { base: "scratch" });
        _case("a base in /etc", "", ["create", "/etc/nixos"], _refused("paths", "a base under /etc"), { base: "/etc" });
        _case("the tools missing", "mv run/current-system/sw/bin/nix-env run/current-system/sw/bin/nix-env.away", _apply(_sha(_second), _third), (run, state) => {
            _refused("tools", "a tool not in its place")(run, state);
            assertEqual(state.calls.length, 0, "… nothing run");
        });
        _case("the tools back", "mv run/current-system/sw/bin/nix-env.away run/current-system/sw/bin/nix-env", _apply(_sha(_third), _second), (run, state) => {
            assert(run.last.startsWith("applied 12 "), "the tools back: applied: " + run.last);
            assertEqual(state.backupMode, "700", "the backups' folder: 700");
        });
        _case("restore", "", () => ["restore", _folder, suite._applyBackup, _sha(_second)], (run, state) => {
            assert(new RegExp("^restored " + _sha(_first) + " h2s-shell\\.json\\." + _stampPattern + "$").test(run.last), "restore: the first backup back: " + run.last);
            assertEqual(run.code, 0, "restore: exit 0");
            assertEqual(state.file, _first, "restore: the file as it was before the first apply");
            assertEqual(state.calls.length, 0, "restore: nothing evaluated or switched");
        });
        // A program the root step runs gone, or not executable, after its checks: under set -e
        // the shell would end with 127 or 126 — which the shell reads as pkexec's own answers
        // (dismissed, not authorised: nothing ran) — so the root step ends `failed` instead
        const broken = program => () => {
            const at = "  activate \"$backup_name\";;";
            suite.assert(suite._script.includes(at), "the apply op ends with its activation, where the broken program is put");
            return suite._script.replace(at, "  \"$bin/" + program + "\"\n" + at);
        };
        for (const [name, program, setup, current, json] of [["a program gone mid-run", "gone", "", _first, _second],
                                                             ["a program not executable mid-run", "not-executable",
                                                              ": > run/current-system/sw/bin/not-executable", _second, _third]]) {
            _case(name, setup, _apply(_sha(current), json), (run, state) => {
                assert(new RegExp("^failed unknown h2s-shell\\.json\\." + _stampPattern + "$").test(run.last), name + ": failed, its backup named: " + run.last);
                assertEqual(run.code, 1, name + ": exit 1, never 126 or 127");
                assertEqual(state.file, json, name + ": the file written before it is kept (restore puts it back)");
            }, { script: broken(program) });
        }
        _then();
    }

    function _then() {
        if (!_ready || _script === "" || !CommandTools.known) {
            Qt.callLater(() => _wait.restart());
            return;
        }
        _next();
    }

    // Waits on the tree, the script and the shell's timeout, then runs the cases
    property Timer _wait: Timer {
        interval: 25
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (waited > 20000) {
                suite.fail("timed out waiting for the scratch tree, the script or the shell's timeout");
                suite.finish();
                return;
            }
            suite._then();
        }
    }

    Component.onCompleted: {
        if (!selected)
            return;
        _exec(["cat", "--", Quickshell.shellDir + "/scripts/root/replace-lib.sh", Quickshell.shellDir + "/scripts/root/replace-file.sh",
               Quickshell.shellDir + "/scripts/root/nixos-toplevel.sh", Quickshell.shellDir + "/scripts/root/nixos-apply.sh"], (code, stdout) => suite._script = code === 0 ? stdout : "");
        const tree = "set -e; umask 022; S=$1; F=$2; mkdir -p \"$S/etc/nixos\" \"$S/run/current-system/sw/bin\" \"$S/nix/var/nix/profiles\" \"$S/ctl\" \"$S/log\" \"$3/bin\"; "
            + "for t in nix nix-env nix-store systemctl systemd-run; do cp \"$F/$t\" \"$S/run/current-system/sw/bin/\"; done; cp \"$F/switch-to-configuration\" \"$3/bin/\"; "
            + ": > \"$S/etc/nixos/flake.nix\"; ln -s /nowhere \"$S/nix/var/nix/profiles/system-1-link\"; ln -s system-1-link \"$S/nix/var/nix/profiles/system\"";
        _exec(["sh", "-c", tree, "sh", _scratch, _fixtures, _out], code => {
            suite.assertEqual(code, 0, "the scratch tree made");
            suite._ready = true;
        });
    }

    function _exec(command, done) {
        const process = _process.createObject(suite, { command: command });
        process.finished.connect((code, stdout, stderr) => done?.(code, stdout, stderr));
        process.running = true;
    }

    property Component _process: Component {
        Process {
            id: _run
            signal finished(int code, string stdout, string stderr)
            property bool _exited: false
            property bool _finished: false
            property bool _errorFinished: false
            property int _code: -1
            property string _stdout: ""
            property string _stderr: ""
            function _over() {
                if (!(_exited && _finished && _errorFinished))
                    return;
                _run.finished(_code, _stdout, _stderr);
                _run.destroy();
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    _run._stdout = text;
                    _run._finished = true;
                    _run._over();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    _run._stderr = text;
                    _run._errorFinished = true;
                    _run._over();
                }
            }
            onExited: code => {
                _run._code = code;
                _run._exited = true;
                _run._over();
            }
        }
    }
}
