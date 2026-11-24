import QtQuick
import Quickshell
import Quickshell.Io

// scripts/nm-config-files.sh on scratch trees, its whole output checked: NetworkManager's
// files in its order (the packages' conf.d, /run's, the main file, /etc's), a name in a later
// folder hiding the same name in an earlier one, hidden names and every kind of entry ending
// in ".conf" listed (as nm-config.c does), names in byte order (A.conf before a.conf), a link
// read through, one leading nowhere and a folder unreadable, other names left out; the legacy
// main file nm-system-settings.conf in NetworkManager.conf's place; NixOS's packages' conf.d
// where there is no /usr/lib one; a conf.d folder that cannot be listed said first.
// Asynchronous.
TestCase {
    id: suite
    suiteName: "NmConfigFiles"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-nm-config-files-test-" + Date.now()
    readonly property string _script: Quickshell.shellDir + "/scripts/nm-config-files.sh"

    // The tree: each file's text is its own short name, one line
    readonly property string _setup: "set -e; umask 022; t=$1;"
        + " mkdir -p \"$t/a/usr/lib/NetworkManager/conf.d\" \"$t/a/run/NetworkManager/conf.d\" \"$t/a/etc/NetworkManager/conf.d/dir.conf\";"
        + " w() { printf '%s\\n' \"$2\" > \"$t/a/$1\"; };"
        + " w usr/lib/NetworkManager/conf.d/10-lib.conf lib10; w usr/lib/NetworkManager/conf.d/20-etc.conf lib20;"
        + " w usr/lib/NetworkManager/conf.d/30-run.conf lib30; w usr/lib/NetworkManager/conf.d/.h.conf hidden; w usr/lib/NetworkManager/conf.d/notes.txt no;"
        + " w run/NetworkManager/conf.d/30-run.conf run30; w run/NetworkManager/conf.d/40-both.conf run40;"
        + " w etc/NetworkManager/NetworkManager.conf main;"
        + " w etc/NetworkManager/conf.d/20-etc.conf etc20; w etc/NetworkManager/conf.d/40-both.conf etc40;"
        + " w etc/NetworkManager/conf.d/A.conf upper; w etc/NetworkManager/conf.d/a.conf lower;"
        + " printf 'linked\\n' > \"$t/target\"; ln -s \"$t/target\" \"$t/a/etc/NetworkManager/conf.d/link.conf\";"
        + " ln -s \"$t/nowhere\" \"$t/a/etc/NetworkManager/conf.d/dangling.conf\";"
        // b: the legacy main file, NixOS's packages' folder, a conf.d that cannot be listed
        + " mkdir -p \"$t/b/run/current-system/sw/lib/NetworkManager/conf.d\" \"$t/b/etc/NetworkManager/conf.d\";"
        + " printf 'nix\\n' > \"$t/b/run/current-system/sw/lib/NetworkManager/conf.d/20-nix.conf\";"
        + " printf 'legacy\\n' > \"$t/b/etc/NetworkManager/nm-system-settings.conf\"; printf 'main\\n' > \"$t/b/etc/NetworkManager/NetworkManager.conf\";"
        + " printf 'x\\n' > \"$t/b/etc/NetworkManager/conf.d/x.conf\"; chmod 000 \"$t/b/etc/NetworkManager/conf.d\""

    function _file(path, text) {
        return "file\t" + path + "\ttext\n|" + text + "\nend\t" + path + "\n";
    }

    property var _outputs: ({})

    function runAsync() {
        _exec(["sh", "-c", _setup, "sh", _scratch], code => {
            suite.assertEqual(code, 0, "the scratch trees made");
            suite._exec([suite._script, suite._scratch + "/a"], (code, stdout) => suite._outputs = Object.assign({}, suite._outputs, { a: stdout }));
            suite._exec([suite._script, suite._scratch + "/b"], (code, stdout) => suite._outputs = Object.assign({}, suite._outputs, { b: stdout }));
        });
        _clock.start();
    }

    function _check() {
        const lib = "/usr/lib/NetworkManager/conf.d/", run = "/run/NetworkManager/conf.d/", etc = "/etc/NetworkManager/conf.d/";
        assertEqual(_outputs.a,
                    _file(lib + ".h.conf", "hidden") + _file(lib + "10-lib.conf", "lib10")
                    + _file(run + "30-run.conf", "run30")
                    + _file("/etc/NetworkManager/NetworkManager.conf", "main")
                    + _file(etc + "20-etc.conf", "etc20") + _file(etc + "40-both.conf", "etc40") + _file(etc + "A.conf", "upper") + _file(etc + "a.conf", "lower")
                    + "file\t" + etc + "dangling.conf\tunreadable\n" + "file\t" + etc + "dir.conf\tunreadable\n" + _file(etc + "link.conf", "linked")
                    + "done\n",
                    "the packages', /run's, the main file, /etc's: same names hidden by later folders, hidden names listed, byte order, links read, other names left out");
        assertEqual(_outputs.b,
                    "unknown\t/etc/NetworkManager/conf.d cannot be listed\n"
                    + _file("/run/current-system/sw/lib/NetworkManager/conf.d/20-nix.conf", "nix")
                    + _file("/etc/NetworkManager/nm-system-settings.conf", "legacy")
                    + "done\n",
                    "a conf.d that cannot be listed said first; NixOS's packages' folder; the legacy main file in NetworkManager.conf's place");
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            const ready = suite._outputs.a !== undefined && suite._outputs.b !== undefined;
            if (!ready && waited < 10000)
                return;
            stop();
            if (!ready)
                suite.fail("timed out waiting for the script");
            else
                suite._check();
            suite._exec(["sh", "-c", "chmod -R u+rwx \"$1\" 2> /dev/null; rm -rf -- \"$1\"", "sh", suite._scratch], () => suite.finish());
        }
    }

    function _exec(command, done) {
        const process = _shell.createObject(suite, { command: command });
        process.finished.connect((code, stdout) => done?.(code, stdout));
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            signal finished(int code, string stdout)
            property bool _exited: false
            property bool _read: false
            property int _code: -1
            property string _stdout: ""
            function _over() {
                if (!(_exited && _read))
                    return;
                _process.finished(_code, _stdout);
                _process.destroy();
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    _process._stdout = text;
                    _process._read = true;
                    _process._over();
                }
            }
            onExited: code => {
                _process._code = code;
                _process._exited = true;
                _process._over();
            }
        }
    }
}
