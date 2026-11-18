import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.io

// What the shell knows of the system (module API 1.13, Api.system): SystemFactsRules from
// made-up readings — as on NixOS, as on Arch, and readings that failed or say something
// unexpected — then the reader (singletons/io/SystemFactsReader.qml) on made-up files passed
// in as paths, and the data directories' rules. Asynchronous: the reader's name is a process
// and user-dirs.dirs is read without blocking.
TestCase {
    id: suite
    suiteName: "SystemFacts"
    asynchronous: true

    readonly property var rules: SystemFactsRules

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
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
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        _reader?.destroy();
        _sh("rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    function runAsync() {
        _pure();
        _then("the made-up files are written", () => _written, () => _readerAsOnNixos());
        _clock.start();
        _sh([
            "set -e; d=$1; mkdir -p \"$d/nixos/config\" \"$d/arch/config\" \"$d/proc\" \"$d/a-directory\"",
            "printf 'Name:\\tquickshell\\nUmask:\\t0022\\nUid:\\t1000\\t1000\\t1000\\t1000\\nGid:\\t100\\t100\\t100\\t100\\n' > \"$d/proc/status\"",
            "printf 'nixbox\\n' > \"$d/proc/hostname\"",
            "printf '1\\n' > \"$d/proc/ip_forward\"; printf '0\\n' > \"$d/proc/forwarding6\"; printf 'x\\n' > \"$d/proc/garbage\"",
            // home-manager's user-dirs.dirs (xdg.userDirs) is a link into the store
            "printf 'XDG_DESKTOP_DIR=\"$HOME/Desktop\"\\nXDG_DOWNLOAD_DIR=\"$HOME/Hämtningar\"\\n' > \"$d/store-user-dirs\"",
            "ln -s \"$d/store-user-dirs\" \"$d/nixos/config/user-dirs.dirs\"",
            // xdg-user-dirs-update's file, with its comments
            "printf '# This file is written by xdg-user-dirs-update\\n# If you want to change or add directories, just edit the line you are\\n#\\nXDG_DOWNLOAD_DIR=\"/data/downloads\"\\n' > \"$d/arch/config/user-dirs.dirs\""
        ].join("\n"), [_scratch], () => suite._written = true);
    }

    // ---- The rules, from made-up readings ----

    function _pure() {
        // The base directories
        const nixosEnvironment = { HOME: "/home/alice", XDG_RUNTIME_DIR: "/run/user/1000" };
        const base = rules.baseDirectories(nixosEnvironment);
        assertEqual(JSON.stringify(base), JSON.stringify({ home: "/home/alice", configHome: "/home/alice/.config",
                                                           dataHome: "/home/alice/.local/share", runtimeDirectory: "/run/user/1000" }),
                    "NixOS, Arch alike: no XDG_* set — the defaults below HOME; XDG_RUNTIME_DIR from logind");
        const set = rules.baseDirectories({ HOME: "/home/bob/", XDG_CONFIG_HOME: "/home/bob/conf/", XDG_DATA_HOME: "/srv/bob-data",
                                            XDG_RUNTIME_DIR: "/run/user/1001" });
        assertEqual(set.home + " " + set.configHome + " " + set.dataHome, "/home/bob /home/bob/conf /srv/bob-data",
                    "XDG_CONFIG_HOME and XDG_DATA_HOME taken; the trailing \"/\" dropped");
        const relative = rules.baseDirectories({ HOME: "/home/bob", XDG_CONFIG_HOME: "conf", XDG_DATA_HOME: "", XDG_RUNTIME_DIR: "run" });
        assertEqual(relative.configHome + " " + relative.dataHome + " [" + relative.runtimeDirectory + "]",
                    "/home/bob/.config /home/bob/.local/share []", "a relative or empty XDG_* ignored (the XDG spec); XDG_RUNTIME_DIR has no default");
        const noHome = rules.baseDirectories({});
        assertEqual(JSON.stringify(noHome), JSON.stringify({ home: "", configHome: "", dataHome: "", runtimeDirectory: "" }),
                    "nothing set (a failed read): everything unknown, never a guess");
        assertEqual(rules.baseDirectories({ HOME: "relative/home" }).home, "", "a relative HOME: unknown");
        assertEqual(rules.baseDirectories({ HOME: "/home/a\nb" }).home, "", "a HOME with a line break: unknown");
        assertEqual(rules.baseDirectories({ HOME: "/home/a/../root" }).home, "", "… with a \"..\" part: unknown");
        assertEqual(rules.baseDirectories({ HOME: "/", XDG_DATA_HOME: undefined }).dataHome, "/.local/share", "HOME \"/\": its defaults without a doubled \"/\"");
        assertEqual(rules.baseDirectories(null).home, "", "no environment at all: no throw");

        // The user id
        const status = "Name:\tquickshell\nUmask:\t0022\nState:\tS (sleeping)\nUid:\t1000\t1001\t1000\t1000\nGid:\t100\t100\t100\t100\n";
        assertEqual(rules.uid(status), 1000, "/proc/self/status: the real id, the first of four");
        assertEqual(rules.uid("Uid:\t0\t0\t0\t0"), 0, "root: 0, a real id (no trailing line break)");
        assertEqual(rules.uid(""), null, "not read: null");
        assertEqual(rules.uid("Name:\tx\n"), null, "no Uid line: null");
        assertEqual(rules.uid("Uid:\tabc\t1\n"), null, "a Uid that is no number: null");
        assertEqual(rules.uid("Uid:\t99999999999\t1\n"), null, "out of range: null");
        assertEqual(rules.uid(undefined), null, "nothing: null, no throw");

        // Names
        assertEqual(rules.oneName("alice\n"), "alice", "`id -un`: the name, its line break dropped");
        assertEqual(rules.oneName("nixbox\n"), "nixbox", "the host name file");
        assertEqual(rules.oneName("archlinux"), "archlinux", "… without a line break");
        assertEqual(rules.oneName(""), "", "empty: unknown");
        assertEqual(rules.oneName("a\nb\n"), "", "two lines: unknown");
        assertEqual(rules.oneName("a b"), "", "white space: unknown");
        assertEqual(rules.oneName("a\u001b[31m"), "", "a control character: unknown");
        assertEqual(rules.oneName("x".repeat(300)), "", "too long: unknown");
        assertEqual(rules.oneName(null), "", "nothing: unknown");

        // The download folder
        const found = text => ({ answered: true, found: true, failed: false, text: text });
        assertEqual(rules.downloadDirectory(found("XDG_DESKTOP_DIR=\"$HOME/Desktop\"\nXDG_DOWNLOAD_DIR=\"$HOME/Hämtningar\"\n"), "/home/u"),
                    "/home/u/Hämtningar", "\"$HOME/…\" (home-manager on NixOS, xdg-user-dirs on Arch)");
        assertEqual(rules.downloadDirectory(found("# written by xdg-user-dirs-update\nXDG_DOWNLOAD_DIR=\"/data/dl/\"\n"), "/home/u"),
                    "/data/dl", "an absolute folder, its trailing \"/\" dropped");
        assertEqual(rules.downloadDirectory({ answered: true, found: false }, "/home/u"), "/home/u/Downloads",
                    "no user-dirs.dirs (NixOS without home-manager, Arch without xdg-user-dirs): ~/Downloads");
        assertEqual(rules.downloadDirectory(found(""), "/home/u"), "/home/u/Downloads", "an empty file: ~/Downloads");
        assertEqual(rules.downloadDirectory(found("XDG_DOCUMENTS_DIR=\"$HOME/Docs\"\n"), "/home/u"), "/home/u/Downloads", "no XDG_DOWNLOAD_DIR in it: ~/Downloads");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"$HOME/\"\n"), "/home/u"), "/home/u/Downloads", "\"$HOME/\" (none there): ~/Downloads");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"$HOME\"\n"), "/home/u"), "/home/u/Downloads", "\"$HOME\": ~/Downloads");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"$(rm -rf ~)\"\n"), "/home/u"), "/home/u/Downloads",
                    "a command substitution: no folder, never run");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"`id`\"\n"), "/home/u"), "/home/u/Downloads", "backquotes: no folder");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"$USER/dl\"\n"), "/home/u"), "/home/u/Downloads", "another variable: no folder");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"${HOME}/dl\"\n"), "/home/u"), "/home/u/Downloads", "${HOME}: not what xdg-user-dirs writes");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"$HOMEdir/dl\"\n"), "/home/u"), "/home/u/Downloads", "$HOMEdir is no $HOME");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"dl\"\n"), "/home/u"), "/home/u/Downloads", "a relative path: no folder");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=$HOME/dl\n"), "/home/u"), "/home/u/Downloads", "unquoted: no folder");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"$HOME/../../etc\"\n"), "/home/u"), "/home/u/Downloads", "a \"..\" part: no folder");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"$HOME/a\\\"b\"\n"), "/home/u"), "/home/u/a\"b", "an escaped quote kept as written");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"/a\"\nXDG_DOWNLOAD_DIR=\"/b\"\n"), "/home/u"), "/b", "the last assignment counts");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"/a\"\nXDG_DOWNLOAD_DIR=\"$(x)\"\n"), "/home/u"), "/home/u/Downloads",
                    "… also when it is no folder");
        assertEqual(rules.downloadDirectory({ answered: true, found: true, failed: true }, "/home/u"), "",
                    "user-dirs.dirs there and not readable: unknown, not a guessed ~/Downloads");
        assertEqual(rules.downloadDirectory({ answered: true, found: false }, ""), "", "no home: unknown");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"$HOME/dl\"\n"), ""), "", "\"$HOME/…\" with no home: unknown");
        assertEqual(rules.downloadDirectory(found("XDG_DOWNLOAD_DIR=\"/data/dl\"\n"), ""), "/data/dl", "an absolute one with no home: taken");

        // Forwarding
        assertEqual(JSON.stringify(rules.forwardingOf("1\n", "0\n")), "{\"ipv4\":true,\"ipv6\":false}", "/proc's switches: on, off");
        assert(Object.isFrozen(rules.forwardingOf("1", "1")), "… frozen");
        assertEqual(JSON.stringify(rules.forwardingOf(null, "")), "{\"ipv4\":null,\"ipv6\":null}", "not read, empty: null (unknown), never false");
        assertEqual(JSON.stringify(rules.forwardingOf("on\n", "2\n")), "{\"ipv4\":null,\"ipv6\":true}", "no number: null; a number not 0: on");

        // Every fact together
        const nixos = rules.facts({
            environment: nixosEnvironment, statusText: status, hostNameText: "nixbox\n",
            userName: { answered: true, ok: true, text: "alice\n" },
            userDirs: found("XDG_DOWNLOAD_DIR=\"$HOME/Hämtningar\"\n")
        });
        assertEqual(JSON.stringify(nixos), JSON.stringify({
            ready: true, userName: "alice", uid: 1000, hostName: "nixbox", home: "/home/alice", configHome: "/home/alice/.config",
            dataHome: "/home/alice/.local/share", runtimeDirectory: "/run/user/1000", downloadDirectory: "/home/alice/Hämtningar"
        }), "as on NixOS: every fact");
        const arch = rules.facts({
            environment: { HOME: "/home/bob", XDG_CONFIG_HOME: "/home/bob/.config", XDG_RUNTIME_DIR: "/run/user/1001" },
            statusText: "Uid:\t1001\t1001\t1001\t1001\n", hostNameText: "archlinux\n",
            userName: { answered: true, ok: true, text: "bob\n" }, userDirs: { answered: true, found: false }
        });
        assertEqual(arch.userName + " " + arch.uid + " " + arch.hostName + " " + arch.downloadDirectory, "bob 1001 archlinux /home/bob/Downloads",
                    "as on Arch, without user-dirs.dirs: every fact, ~/Downloads");
        const failed = rules.facts({
            environment: {}, statusText: "", hostNameText: "",
            userName: { answered: true, ok: false, text: "id: cannot find name for user ID 1000\n" },
            userDirs: { answered: true, found: true, failed: true }
        });
        assertEqual(JSON.stringify(failed), JSON.stringify({
            ready: true, userName: "", uid: null, hostName: "", home: "", configHome: "", dataHome: "", runtimeDirectory: "", downloadDirectory: ""
        }), "every reading failed: ready (all answered), every fact unknown");
        const waiting = rules.facts({ environment: nixosEnvironment, userName: { answered: false }, userDirs: { answered: true, found: false } });
        assertEqual(waiting.ready + " [" + waiting.userName + "] " + waiting.home, "false [] /home/alice", "the name not answered yet: not ready; what is known is there");
        assertEqual(rules.facts({ environment: nixosEnvironment, userName: { answered: true, ok: true, text: "a\n" } }).ready, false,
                    "user-dirs.dirs not answered yet: not ready");
        assertEqual(rules.facts(null).ready, false, "nothing read: not ready, no throw");
        assertEqual(rules.userDirsPath("/home/u/.config"), "/home/u/.config/user-dirs.dirs", "user-dirs.dirs in the config home");
        assertEqual(rules.userDirsPath(""), "", "… none without one");

        // Test mode: setSystem's facts over the defaults
        const defaults = rules.testDefaults("/run/user/1000/h2s-module-data.abc");
        assertEqual(defaults.dataHome + " " + defaults.downloadDirectory, "/run/user/1000/h2s-module-data.abc/.local/share /run/user/1000/h2s-module-data.abc/Downloads",
                    "test defaults: the directories below the temporary home");
        assertEqual(rules.testDefaults("").home + rules.testDefaults("").dataHome, "", "… none while it is not made");
        const given = rules.testFacts({ userName: "carol", uid: 0, hostName: "", ipForwarding: { ipv4: true } }, defaults);
        assertEqual(given.facts.userName + " " + given.facts.uid + " [" + given.facts.hostName + "] " + JSON.stringify(given.facts.ipForwarding)
                    + " " + given.problems.length, "carol 0 [] {\"ipv4\":true,\"ipv6\":null} 0",
                    "setSystem: the fields given, \"\" for unknown; a switch not given in ipForwarding: null");
        assertEqual(given.facts.home, defaults.home, "… the rest from the defaults");
        const wrong = rules.testFacts({ uid: "1000", home: "relative", userName: "two\nlines", ready: 1, ipForwarding: { ipv4: "yes" }, colour: "red" }, defaults);
        assertEqual(JSON.stringify(wrong.problems.map(problem => problem.split(":")[0])), JSON.stringify(["uid", "home", "userName", "ready", "ipForwarding", "colour"]),
                    "a field of the wrong kind, or none Api.system has: named, left out");
        assertEqual(wrong.facts.uid + " " + wrong.facts.home + " " + wrong.facts.ready, "1000 " + defaults.home + " true", "… the defaults kept");
        assertEqual(rules.testFacts(null, defaults).facts.userName, "tester", "null: the defaults");
        assertEqual(rules.testFacts([], defaults).problems[0], "the facts are not an object", "an array: refused");
        const proto = rules.testFacts(JSON.parse("{\"__proto__\": {\"userName\": \"x\"}}"), defaults);
        assertEqual(proto.problems.join() + " " + proto.facts.userName, "__proto__: no such fact tester", "\"__proto__\": no such fact, nothing taken from it");

        // The data directories
        assertEqual(rules.dataRoot("/home/u/.local/share"), "/home/u/.local/share/h2s-shell/module-data", "the root: <dataHome>/h2s-shell/module-data");
        assertEqual(rules.dataRoot(""), "", "no data home: no root");
        assertEqual(rules.dataDirectory("/d/h2s-shell/module-data", "tailscale"), "/d/h2s-shell/module-data/tailscale", "a module's: <root>/<id>");
        assertEqual(rules.dataDirectory("/d", "../etc"), "", "an id that is no module id: none");
        assertEqual(rules.dataDirectory("", "tailscale"), "", "no root: none");
        assert(rules.within("/d/m/tailscale/helper", "/d/m") && rules.within("/d/m", "/d/m"), "within: below the root, or the root");
        assert(!rules.within("/d/mx/helper", "/d/m") && !rules.within("/usr/bin/x", "") && !rules.within("relative", "/d"),
               "… not a neighbour with the same start, not with no root, not a relative path");
        const answers = rules.makeAnswers(["home /run/user/1000/h2s-module-data.x1", "made good", "failed other", "made unasked"], ["good", "other", "silent"]);
        assertEqual(JSON.stringify(answers), JSON.stringify({ home: "/run/user/1000/h2s-module-data.x1", made: { good: true, other: false, silent: false } }),
                    "the script's lines: made, failed, an id not answered for is failed; one not asked for ignored");
        assertEqual(JSON.stringify(rules.makeAnswers(["root-failed"], ["good"]).made), "{\"good\":false}", "the root failed: every id failed");
        assertEqual(rules.makeAnswers(null, null).home, "", "nothing: no throw");
    }

    // ---- The reader, on made-up files ----

    property var _reader: null
    property bool _written: false
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-system-facts-test-" + Date.now()

    property Component _readerComponent: Component {
        SystemFactsReader {}
    }

    function _readerAsOnNixos() {
        _reader = _readerComponent.createObject(suite, {
            environment: { HOME: "/home/alice", XDG_CONFIG_HOME: _scratch + "/nixos/config", XDG_RUNTIME_DIR: "/run/user/1000" },
            statusPath: _scratch + "/proc/status", hostNamePath: _scratch + "/proc/hostname",
            ipv4ForwardingPath: _scratch + "/proc/ip_forward", ipv6ForwardingPath: _scratch + "/proc/forwarding6",
            nameCommand: ["printf", "alice\\n"]
        });
        _then("the reader is ready (as on NixOS)", () => _reader.ready, () => {
            const facts = _reader.facts;
            assertEqual(facts.userName + " " + facts.uid + " " + facts.hostName, "alice 1000 nixbox", "the reader: name, id and host name from its files and command");
            assertEqual(facts.downloadDirectory, "/home/alice/Hämtningar", "… the download folder from a user-dirs.dirs that links into the store");
            assertEqual(facts.dataHome + " " + facts.runtimeDirectory, "/home/alice/.local/share /run/user/1000", "… the base directories from its environment");
            assertEqual(JSON.stringify(_reader.readIpForwarding()), "{\"ipv4\":true,\"ipv6\":false}", "readIpForwarding(): read now, from the two files");
            _reader.destroy();
            _readerAsOnArch();
        });
    }

    function _readerAsOnArch() {
        _reader = _readerComponent.createObject(suite, {
            environment: { HOME: "/home/bob" }, userDirsPath: _scratch + "/arch/config/user-dirs.dirs",
            statusPath: _scratch + "/proc/status", hostNamePath: _scratch + "/proc/hostname",
            nameCommand: ["printf", "bob\\n"]
        });
        _then("the reader is ready (as on Arch)", () => _reader.ready, () => {
            assertEqual(_reader.facts.downloadDirectory, "/data/downloads", "xdg-user-dirs' file, with its comments: the absolute folder");
            // Changed, then read again: the new value once the new reading came
            _sh("printf 'XDG_DOWNLOAD_DIR=\"$HOME/Hämtat\"\\n' > \"$1/arch/config/user-dirs.dirs\"", [_scratch], () => {
                suite._reader.nameCommand = ["sh", "-c", "sleep 0.5; echo old"];
                suite._reader.refresh();
                // A newer refresh at once: the first one's answer must not win
                suite._reader.nameCommand = ["printf", "newer\\n"];
                suite._reader.refresh();
            });
        });
        _then("the second reading came, and the first run ended", () => _reader.facts.downloadDirectory === "/home/bob/Hämtat"
              && _reader.facts.userName === "newer" && _reader._runner.running === 0, () => {
            assertEqual(_reader.facts.userName, "newer", "refresh(): the newer reading wins over a late answer from before it");
            assertEqual(_reader.facts.downloadDirectory, "/home/bob/Hämtat", "refresh(): user-dirs.dirs read again");
            _reader.destroy();
            _readerFailing();
        });
    }

    function _readerFailing() {
        _reader = _readerComponent.createObject(suite, {
            environment: { HOME: "home/relative" }, userDirsPath: _scratch + "/a-directory",
            statusPath: _scratch + "/proc/missing", hostNamePath: _scratch + "/proc/missing",
            ipv4ForwardingPath: _scratch + "/proc/missing", ipv6ForwardingPath: _scratch + "/proc/garbage",
            nameCommand: ["sh", "-c", "echo 'id: cannot find name' >&2; exit 1"]
        });
        _then("the failing reader answered", () => _reader.ready, () => {
            const facts = _reader.facts;
            assertEqual(JSON.stringify(facts), JSON.stringify({
                ready: true, userName: "", uid: null, hostName: "", home: "", configHome: "", dataHome: "", runtimeDirectory: "", downloadDirectory: ""
            }), "every reading failed (missing files, a failing command, a directory for user-dirs.dirs, a relative HOME): every fact unknown");
            assertEqual(JSON.stringify(_reader.readIpForwarding()), "{\"ipv4\":null,\"ipv6\":null}", "a missing switch, a garbled one: null each");
            _reader.destroy();
            _reader = null;
            _readerNameMissing();
        });
    }

    function _readerNameMissing() {
        _reader = _readerComponent.createObject(suite, {
            environment: { HOME: "/home/u" }, userDirsPath: _scratch + "/no-such-user-dirs",
            statusPath: _scratch + "/proc/status", hostNamePath: _scratch + "/proc/hostname",
            nameCommand: [_scratch + "/no-such-program"]
        });
        _then("the reader with no name program answered", () => _reader.ready, () => {
            assertEqual(_reader.facts.userName + "|" + _reader.facts.downloadDirectory, "|/home/u/Downloads",
                        "a name program that is not there: the name unknown; no user-dirs.dirs: ~/Downloads");
            _reader.destroy();
            _reader = null;
        });
    }

    // Runs a shell script with arguments; done(exit code, output)
    function _sh(script, args, done) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            property var done: null
            property string output: ""
            stdout: SplitParser {
                splitMarker: ""
                onRead: data => _process.output += data
            }
            onExited: code => {
                _process.done?.(code, _process.output);
                _process.destroy();
            }
        }
    }
}
