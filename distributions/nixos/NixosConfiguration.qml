import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// The system's NixOS configuration, read as the user (NixosConfigRules decides what the
// answers mean): one run of scripts/nixos-config.sh for every file, folder and link the
// reading needs, then — for a configuration in git that is root's or the user's own — git
// asked whether it knows the shell's file, read only, the repository's own programs off
// (NixosConfigRules.gitArgv). git is never asked to change anything.
//
// read() is called by the page that shows it, when it is shown and on "Look again"; a read
// started while one runs replaces it, and the older one's answers are dropped. The folder and
// host chosen with "Change…" and the home-folder acknowledgements are Config's (machine
// state, not preferences); a suite hands its own, with a scratch `base` for the system's
// places and stand-in programs.
QtObject {
    id: root

    // The folder the system's places are under: "" for the system's own (a suite: a scratch
    // folder)
    property string base: ""
    property string chosenFolder: Config.nixos.folder
    property string chosenHost: Config.nixos.host
    property var acknowledged: Array.from(Config.nixos.homeWarningAcknowledged)
    property string nixPath: Quickshell.env("NIX_PATH") ?? ""
    property var readCommand: [Quickshell.shellDir + "/scripts/nixos-config.sh"]
    property string git: "git"
    // Added to the reading's environment (a suite's stand-in programs on PATH)
    property var environment: ({})

    // A read is under way
    readonly property bool busy: _busy
    // Changes with every finished read: current() then has the new answer
    readonly property int revision: _revision
    // The last reading's state ("" before the first read): NixosConfigRules.state's
    readonly property string state: _state

    property bool _busy: false
    property int _revision: 0
    property string _state: ""
    property var _reading: null
    // Which read the answers belong to: an answer of an older one loses
    property int _generation: 0

    // The last reading (NixosConfigRules.reading's, git's answer in it), a copy of its own
    // per call; null before the first read
    function current() {
        return _reading === null ? null : ReadOnlyRules.copy(_reading);
    }

    function read() {
        const generation = ++_generation;
        _busy = true;
        const inputs = {
            base: base,
            chosenFolder: chosenFolder,
            chosenHost: chosenHost,
            nixPath: nixPath,
            acknowledged: Array.from(acknowledged ?? [])
        };
        const args = NixosConfigRules.readArgs(inputs);
        const lines = [];
        _runner.start(Array.from(readCommand).concat(args), {
            timeoutMs: 10000,
            killAfterMs: 1000,
            maxOutputBytes: 1048576,
            keepOutput: false,
            environment: Object.assign({}, environment ?? {}),
            onLine: (line, stream) => {
                if (stream === "stdout" && generation === root._generation)
                    lines.push(line);
            },
            done: result => {
                if (generation !== root._generation)
                    return;
                const reading = NixosConfigRules.reading(inputs, NixosConfigRules.records(lines, result, args));
                const argv = reading.git === "present" ? NixosConfigRules.gitArgv(root.git, reading.real, reading.gitAccess) : [];
                if (argv.length === 0) {
                    root._finish(reading);
                    return;
                }
                root._runner.start(argv, {
                    timeoutMs: 10000,
                    killAfterMs: 1000,
                    maxOutputBytes: 65536,
                    keepOutput: false,
                    environment: { GIT_TERMINAL_PROMPT: "0", GIT_OPTIONAL_LOCKS: "0" },
                    done: gitResult => {
                        if (generation === root._generation)
                            root._finish(NixosConfigRules.withGit(reading, gitResult));
                    }
                });
            }
        });
    }

    // The user chose a folder (and a flake's host, "" for /etc/hostname's) with "Change…";
    // "" goes back to the usual places
    function choose(folder, host) {
        Config.nixos.folder = typeof folder === "string" ? folder : "";
        Config.nixos.host = typeof host === "string" ? host : "";
    }

    // The user took the home-folder warning for the configuration at this real path
    function acknowledgeHome(realPath) {
        if (!NixosConfigRules.plainPath(realPath))
            return;
        const list = Array.from(Config.nixos.homeWarningAcknowledged);
        if (!list.includes(realPath))
            Config.nixos.homeWarningAcknowledged = list.concat([realPath]);
    }

    function _finish(reading) {
        _reading = reading;
        _state = reading.state;
        _busy = false;
        _revision += 1;
    }

    property CommandRunner _runner: CommandRunner {}
}
