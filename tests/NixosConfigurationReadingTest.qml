import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.distributions.nixos

// The NixOS configuration's reading (distributions/nixos/NixosConfiguration.qml) run for
// real — scripts/nixos-config.sh and git's check — on made-up system trees (its `base`) with
// stand-in git programs that answer only to the exact read-only words: a connected flake in
// git whose file is in force; /etc/nixos a link to a classic configuration in a "home"
// folder, nothing published; an empty system; a chosen folder whose settings.json cannot be
// read; a chosen folder that is gone; git that does not know the file, and git that fails;
// and a read replaced by another before it answered.
TestCase {
    id: suite
    suiteName: "NixosConfigurationReading"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-nixos-config-test-" + Date.now()
    property var _readers: ({})
    property int _waited: 0
    property string _sha256: ""

    function runAsync() {
        const json = JSON.stringify({ version: 1, idle: { hibernateDelay: "3h" } });
        const published = JSON.stringify({ version: 1, settings: { idle: { hibernateDelay: "3h" } }, inForce: { idle: { hibernateDelay: "3h" } } });
        _sh([
            "set -e; d=$1; json=$2; published=$3",
            // A connected flake in git: the module's files, settings.json, generations
            "s=$d/connected; mkdir -p $s/etc/nixos/.git $s/etc/h2s-shell $s/etc/pam.d $s/run/current-system/sw/bin $s/nix/var/nix/profiles",
            ": > $s/etc/nixos/flake.nix; printf '%s' \"$json\" > $s/etc/nixos/h2s-shell.json; printf '%s\\n' \"$published\" > $s/etc/h2s-shell/settings.json",
            "printf 'testhost\\n' > $s/etc/hostname; : > $s/etc/pam.d/h2s-shell-password; : > $s/run/current-system/sw/bin/h2s-shell",
            "for n in 1 2 3; do ln -s /nowhere/$n $s/nix/var/nix/profiles/system-$n-link; done; ln -s system-3-link $s/nix/var/nix/profiles/system",
            "mkdir $s/nix/var/nix/profiles/per-user",
            // /etc/nixos a link to a classic configuration in a home folder; nothing published
            "s=$d/linked; mkdir -p $s/etc/pam.d $s/run/current-system/sw/bin $d/home/nixos-config",
            ": > $d/home/nixos-config/configuration.nix; ln -s $d/home/nixos-config $s/etc/nixos",
            ": > $s/etc/pam.d/h2s-shell-password; : > $s/run/current-system/sw/bin/h2s-shell",
            // An empty system
            "mkdir -p $d/empty/etc",
            // A chosen folder, with the module and a settings.json that cannot be read
            "s=$d/locked; mkdir -p $s/etc/h2s-shell $s/etc/pam.d $s/run/current-system/sw/bin $d/chosen/.git",
            ": > $d/chosen/flake.nix; printf '%s' \"$json\" > $d/chosen/h2s-shell.json",
            "printf '%s\\n' \"$published\" > $s/etc/h2s-shell/settings.json; chmod 000 $s/etc/h2s-shell/settings.json",
            ": > $s/etc/pam.d/h2s-shell-password; : > $s/run/current-system/sw/bin/h2s-shell",
            // Stand-in gits: each answers its code only to the exact read-only words for its folder, else 2
            "mkdir -p $d/bin",
            "stand_in() { printf '#!/bin/sh\\n[ \"$*\" = \"%s--no-optional-locks -C %s ls-files --error-unmatch -- h2s-shell.json\" ] || exit 2\\nexit %s\\n' \"$4\" \"$2\" \"$3\" > $d/bin/$1; chmod +x $d/bin/$1; }",
            "off='-c core.fsmonitor=false '",
            "stand_in git-tracked $d/connected/etc/nixos 0 \"$off\"; stand_in git-untracked $d/chosen 1 \"$off\"; stand_in git-broken $d/chosen 128 \"$off\"",
            "stand_in git-root $d/rootowned/etc/nixos 0 \"$off-c safe.directory=$d/rootowned/etc/nixos \"",
            // A stand-in stat that says every folder and file is root's, mode 755: a root-owned tree
            "mkdir -p $d/rootbin; printf '#!/bin/sh\\necho 0 755\\n' > $d/rootbin/stat; chmod +x $d/rootbin/stat",
            "cp -a $d/connected $d/rootowned",
            // /etc/nixos a link to a folder whose name holds a line break: its real path is unknown
            "s=$d/oddlink; mkdir -p $s/etc \"$d/odd\nname\"; : > \"$d/odd\nname/flake.nix\"; ln -s \"$d/odd\nname\" $s/etc/nixos",
            "sha256sum $d/connected/etc/nixos/h2s-shell.json | cut -d' ' -f1 > $d/sha256"
        ].join("\n"), [_scratch, json, published], code => {
            suite.assertEqual(code, 0, "the made-up trees are written");
            suite._start();
        });
    }

    function _make(name, properties) {
        const reader = _readerComponent.createObject(suite, Object.assign({ chosenFolder: "", chosenHost: "", nixPath: "", acknowledged: [],
                                                                             git: _scratch + "/bin/git-broken" }, properties));
        _readers[name] = reader;
        reader.read();
        return reader;
    }

    function _start() {
        const base = name => _scratch + "/" + name;
        _make("connected", { base: base("connected"), git: _scratch + "/bin/git-tracked" });
        _make("linked", { base: base("linked") });
        _make("empty", { base: base("empty") });
        _make("locked", { base: base("locked"), chosenFolder: _scratch + "/chosen", chosenHost: "laptop", git: _scratch + "/bin/git-untracked" });
        _make("lockedBrokenGit", { base: base("locked"), chosenFolder: _scratch + "/chosen" });
        _make("rootowned", { base: base("rootowned"), git: _scratch + "/bin/git-root",
                             environment: { PATH: _scratch + "/rootbin:" + (Quickshell.env("PATH") ?? "") } });
        _make("oddlink", { base: base("oddlink") });
        _make("gone", { base: base("connected"), chosenFolder: _scratch + "/nowhere" });
        // Read again at once with another folder: the first read's answers are dropped
        const replaced = _make("replaced", { base: base("connected"), chosenFolder: _scratch + "/nowhere" });
        replaced.chosenFolder = "";
        replaced.git = _scratch + "/bin/git-tracked";
        replaced.read();
        _readSha.path = _scratch + "/sha256";
        _clock.start();
    }

    property FileView _readSha: FileView {
        // Given its path once the trees are written
        onLoaded: suite._sha256 = text().trim()
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        onTriggered: {
            suite._waited += interval;
            const waiting = Object.keys(suite._readers).filter(name => suite._readers[name].busy || suite._readers[name].revision === 0);
            if ((waiting.length > 0 || suite._sha256 === "") && suite._waited < 20000)
                return;
            stop();
            suite.assertEqual(waiting.join(","), "", "every reading answered");
            suite._check();
        }
    }

    function _check() {
        const reading = name => _readers[name].current();
        const facts = name => reading(name).facts.map(row => row.name + "=" + row.value).join("; ");

        let answer = reading("connected");
        assertEqual(answer.state, "connected", "the module's files and settings.json: connected");
        assertEqual(facts("connected"), "Configuration=" + _scratch + "/connected/etc/nixos; Type=Flake; Git=Yes; Host=testhost; The shell's file="
                    + _scratch + "/connected/etc/nixos/h2s-shell.json; File status=In force; Generations=3", "the facts read off the tree");
        assertEqual(answer.gitKnowsFile, "tracked", "git asked with the read-only words: it knows the file");
        assertEqual(answer.generations.current, 3, "the current generation from the system link");
        assertEqual(answer.file.sha256, _sha256, "the file's sha256");
        assertEqual(answer.owner + " " + answer.rootWrites + " " + answer.homeWarning, "yours false true", "a folder the user owns: yours, the warning due");
        assertEqual(answer.real, _scratch + "/connected/etc/nixos", "its real path");

        answer = reading("rootowned");
        assertEqual(answer.owner + " " + answer.rootWrites + " " + answer.homeWarning + " " + answer.gitAccess, "root true false root",
                    "a root-owned tree (a stand-in stat): root writes, no warning, root's repository");
        assertEqual(answer.gitKnowsFile, "tracked", "git asked with safe.directory for root's repository, the fsmonitor program off");

        answer = reading("oddlink");
        assertEqual(answer.configuration.found + " '" + answer.real + "' " + answer.owner, "true '' unknown",
                    "a link whose target holds a line break: its real path and owner unknown, no record made up from it");

        answer = reading("linked");
        assertEqual(answer.state + " " + answer.configuration.type + " " + answer.configuration.folder, "found classic " + _scratch + "/linked/etc/nixos",
                    "/etc/nixos a link to a classic configuration, nothing published: found");
        assertEqual(answer.real + " " + answer.owner + " " + answer.homeWarning, _scratch + "/home/nixos-config yours true",
                    "… its real path in the home folder: yours, the warning due");
        assertEqual(answer.fileStatus + " " + answer.git + " " + answer.gitKnowsFile, "notCreated absent ", "no shell's file, no git");
        assertEqual(answer.generations.count, -1, "no profiles folder: generations unknown");

        answer = reading("empty");
        assertEqual(answer.state + " " + answer.configuration.problem + " " + answer.module + " " + answer.facts.length, "notConnected none absent 0",
                    "an empty system: no configuration, not connected");

        answer = reading("locked");
        assertEqual(answer.state + " " + answer.fileStatus + " " + answer.published, "found unknown unknown",
                    "settings.json that cannot be read: found, the file's status unknown — never In force");
        assertEqual(answer.configuration.candidate + " " + answer.host + " " + answer.gitKnowsFile, "chosen laptop untracked",
                    "the chosen folder and host; git does not know the file");
        assertEqual(reading("lockedBrokenGit").gitKnowsFile, "unknown", "git failing: unknown");

        answer = reading("gone");
        assertEqual(answer.state + " " + answer.configuration.problem, "notConnected chosenMissing", "a chosen folder that is gone: not passed over");

        answer = reading("replaced");
        assertEqual(answer.configuration.candidate + " " + answer.state + " " + _readers.replaced.revision, "etc connected 1",
                    "a read replaced at once: only the second one's answer counts");

        const copy = reading("connected");
        copy.facts.push({ name: "x", value: "y" });
        assertEqual(reading("connected").facts.length, 7, "each caller gets a copy of its own");

        _sh("chmod -R u+rwx \"$1\" && rm -rf \"$1\"", [_scratch], code => {
            suite.assertEqual(code, 0, "the scratch trees removed");
            suite.finish();
        });
    }

    property Component _readerComponent: Component {
        NixosConfiguration {}
    }

    function _sh(script, args, done) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            property var done: null
            onExited: code => {
                _process.done?.(code);
                _process.destroy();
            }
        }
    }
}
