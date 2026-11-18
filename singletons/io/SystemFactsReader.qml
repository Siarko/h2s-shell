import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Reads what the shell knows of the system (SystemFactsRules decides from what it read;
// the shell's one instance is SystemFacts, modules see it as Api.system). Every path it
// reads is a property, so a suite points it at made-up files (tests/SystemFactsTest.qml).
//
// - The environment is read once, when it is made (a process's own does not change).
// - /proc/self/status (the user id) and /proc/sys/kernel/hostname are read synchronously:
//   the kernel makes them in memory (KernelFile). So are the forwarding switches, at each
//   readIpForwarding().
// - The user name is `id -un` (the user database through NSS: a network account too), a
//   process with a time limit; user-dirs.dirs is read as text without blocking (a home on
//   a slow mount must not stall the shell) and never run.
// - `ready` once the name and user-dirs.dirs have answered, failed or not. refresh() reads
//   everything again; the facts stay as they were until the new readings come, and an
//   answer from before a newer refresh() is dropped.
QtObject {
    id: root

    // { HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_RUNTIME_DIR }: the process's own unless given
    property var environment: ({
        HOME: Quickshell.env("HOME"),
        XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME"),
        XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"),
        XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR")
    })
    property string statusPath: "/proc/self/status"
    property string hostNamePath: "/proc/sys/kernel/hostname"
    property string ipv4ForwardingPath: "/proc/sys/net/ipv4/ip_forward"
    property string ipv6ForwardingPath: "/proc/sys/net/ipv6/conf/all/forwarding"
    // "" — "<configHome>/user-dirs.dirs" (XDG_CONFIG_HOME, else ~/.config)
    property string userDirsPath: ""
    // What prints the user's name
    property var nameCommand: ["id", "-un"]
    property int nameTimeoutMs: 5000

    // SystemFactsRules.facts: { ready, userName, uid, hostName, home, configHome, dataHome,
    // runtimeDirectory, downloadDirectory }
    readonly property var facts: SystemFactsRules.facts(_readings)
    readonly property bool ready: facts.ready

    // Reads the two forwarding switches now → frozen { ipv4, ipv6 }: true, false, or null
    // for one that could not be read
    function readIpForwarding() {
        _forwardingFile.path = ipv4ForwardingPath;
        const ipv4 = _forwardingFile.read();
        _forwardingFile.path = ipv6ForwardingPath;
        const ipv6 = _forwardingFile.read();
        _forwardingFile.path = "";
        return SystemFactsRules.forwardingOf(_readable(ipv4), _readable(ipv6));
    }

    // Reads everything again
    function refresh() {
        const generation = ++_generation;
        const statusText = _readFile(statusPath);
        const hostNameText = _readFile(hostNamePath);
        _readings = Object.assign({}, _readings, { environment: environment, statusText: statusText, hostNameText: hostNameText });
        _nameRun?.cancel();
        _nameRun = _runner.start(Array.from(nameCommand), {
            timeoutMs: nameTimeoutMs,
            killAfterMs: 1000,
            maxOutputBytes: 4096,
            done: result => {
                if (generation !== root._generation)
                    return;
                root._nameRun = null;
                root._readings = Object.assign({}, root._readings, {
                    userName: { answered: true, ok: result.ok, text: result.ok ? result.stdout : "" }
                });
            }
        });
        const path = _userDirsFile();
        if (path === "") {
            _userDirsAnswered(generation, { answered: true, found: false, failed: false, text: "" });
        } else if (_userDirs.path !== path) {
            _userDirsGeneration = generation;
            _userDirs.path = path;
        } else {
            _userDirsGeneration = generation;
            _userDirs.reload();
        }
    }

    property var _readings: ({ environment: environment })
    property int _generation: 0
    property int _userDirsGeneration: 0
    property var _nameRun: null

    function _userDirsFile() {
        return userDirsPath !== "" ? userDirsPath
            : SystemFactsRules.userDirsPath(SystemFactsRules.baseDirectories(environment).configHome);
    }

    function _userDirsAnswered(generation, userDirs) {
        if (generation !== _generation)
            return;
        _readings = Object.assign({}, _readings, { userDirs: userDirs });
    }

    // A file KernelFile read: "" for one missing or unreadable (null: not read)
    function _readable(text) {
        return typeof text === "string" && text !== "" ? text : null;
    }

    function _readFile(path) {
        if (path === "")
            return "";
        _kernelFile.path = path;
        const text = _kernelFile.read();
        _kernelFile.path = "";
        return text;
    }

    property KernelFile _kernelFile: KernelFile {}
    property KernelFile _forwardingFile: KernelFile {}

    property FileView _userDirs: FileView {
        printErrors: false
        onLoaded: root._userDirsAnswered(root._userDirsGeneration, { answered: true, found: true, failed: false, text: text() })
        onLoadFailed: error => root._userDirsAnswered(root._userDirsGeneration, {
            answered: true, found: error !== FileViewError.FileNotFound,
            failed: error !== FileViewError.FileNotFound, text: ""
        })
    }

    property CommandRunner _runner: CommandRunner {}

    Component.onCompleted: refresh()
}
