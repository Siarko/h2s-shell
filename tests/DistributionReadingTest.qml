import QtQuick
import Quickshell
import Quickshell.Io
import qs.api
import qs.singletons
import qs.singletons.io

// The distribution's reading (singletons/io/DistributionReader.qml) on made-up system trees
// (its fileRoot): the fixture os-release files of tests/fixtures/distribution/ put where
// each system has them — Arch's /etc/os-release a link to /usr/lib/os-release, NixOS's an
// empty /etc/NIXOS beside it —, a tree with only /usr/lib/os-release, one whose os-release
// cannot be read, markers that exist but cannot be read, the override (also changed after the
// start), and made-up distributions directories (one with a broken
// distribution.json). Then the shell's own Distribution: it answers, takes the test seam, and
// Api.system.distribution hands modules a copy of its answer.
TestCase {
    id: suite
    suiteName: "DistributionReading"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-distribution-test-" + Date.now()
    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/distribution"
    property var _readers: ({})
    property int _waited: 0

    function runAsync() {
        const notYet = _readerComponent.createObject(suite, {});
        assert(!notYet.detection.ready && notYet.detection.id === "" && notYet.detection.facts === null,
               "just made, before any file answered: unknown, no facts");
        notYet.destroy();
        _sh([
            "set -e; d=$1; f=$2; shipped=$3",
            "mkdir -p \"$d/arch/etc\" \"$d/arch/usr/lib\" \"$d/nixos/etc\" \"$d/endeavouros/etc\" \"$d/usronly/usr/lib\" \"$d/unreadable/etc\" \"$d/none\" \"$d/lockedmark/etc\" \"$d/dirmark/etc/NIXOS\"",
            "cp \"$f/arch.os-release\" \"$d/arch/usr/lib/os-release\"; ln -s ../usr/lib/os-release \"$d/arch/etc/os-release\"",
            "cp \"$f/nixos.os-release\" \"$d/nixos/etc/os-release\"; : > \"$d/nixos/etc/NIXOS\"",
            "cp \"$f/endeavouros.os-release\" \"$d/endeavouros/etc/os-release\"",
            "cp \"$f/fedora.os-release\" \"$d/usronly/usr/lib/os-release\"",
            "cp \"$f/arch.os-release\" \"$d/unreadable/etc/os-release\"; chmod 000 \"$d/unreadable/etc/os-release\"",
            // /etc/NIXOS there but not readable: mode 000, and a directory
            "cp \"$f/arch.os-release\" \"$d/lockedmark/etc/os-release\"; : > \"$d/lockedmark/etc/NIXOS\"; chmod 000 \"$d/lockedmark/etc/NIXOS\"",
            "cp \"$f/arch.os-release\" \"$d/dirmark/etc/os-release\"",
            // A distributions directory whose arch/distribution.json is broken
            "mkdir -p \"$d/broken-distributions\"; cp -r \"$shipped\"/. \"$d/broken-distributions/\"",
            "printf '{\"id\": \"arch\"}\\n' > \"$d/broken-distributions/arch/distribution.json\""
        ].join("\n"), [_scratch, _fixtures, Quickshell.shellDir + "/distributions"], code => {
            suite.assertEqual(code, 0, "the made-up trees are written");
            suite._start();
        });
    }

    function _make(name, properties) {
        const reader = _readerComponent.createObject(suite, properties);
        _readers[name] = reader;
        return reader;
    }

    function _start() {
        const tree = name => ({ fileRoot: _scratch + "/" + name });
        _make("arch", tree("arch"));
        _make("nixos", tree("nixos"));
        _make("endeavouros", tree("endeavouros"));
        _make("usronly", tree("usronly"));
        _make("unreadable", tree("unreadable"));
        _make("none", tree("none"));
        _make("override", Object.assign(tree("nixos"), { override: "arch" }));
        _make("unknownOverride", Object.assign(tree("arch"), { override: "plan9" }));
        _make("broken", Object.assign(tree("arch"), { distributionsDirectory: _scratch + "/broken-distributions" }));
        _make("lockedmark", tree("lockedmark"));
        _make("dirmark", tree("dirmark"));
        // The override changed at once: the first reading's answers are dropped, the new one counts
        _make("switched", Object.assign(tree("nixos"), { override: "arch" })).override = "";
        _make("missing", Object.assign(tree("arch"), { distributionsDirectory: _scratch + "/nowhere" }));
        _clock.start();
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        onTriggered: {
            suite._waited += interval;
            const waiting = Object.keys(suite._readers).filter(name => !suite._readers[name].detection.ready);
            const shell = Distribution.ready;
            if ((waiting.length > 0 || !shell) && suite._waited < 10000)
                return;
            stop();
            suite.assertEqual(waiting.join(","), "", "every reading answered");
            suite._check();
        }
    }

    function _check() {
        const answer = name => _readers[name].detection;
        const expect = (name, id, how, message) => {
            const detection = answer(name);
            assertEqual(detection.id + "/" + detection.how, id + "/" + how, message);
            assert(detection.facts !== null && detection.facts.id === id && detection.problem === "", message + ": with its facts");
        };
        expect("arch", "arch", "id", "Arch, /etc/os-release a link to /usr/lib/os-release: arch");
        expect("nixos", "nixos", "marker", "NixOS, an empty /etc/NIXOS: nixos, by the marker");
        expect("endeavouros", "arch", "like", "EndeavourOS: arch, by ID_LIKE");
        expect("usronly", "generic", "fallback", "only /usr/lib/os-release, Fedora's: read, generic");
        expect("none", "generic", "fallback", "no os-release, no marker: generic");
        expect("override", "arch", "override", "the override on a NixOS tree: arch");
        expect("lockedmark", "nixos", "marker", "/etc/NIXOS of mode 000 beside Arch's os-release: nixos (it exists, as `test -e` has it)");
        expect("dirmark", "nixos", "marker", "/etc/NIXOS a directory: nixos (it exists)");
        expect("switched", "nixos", "marker", "the override taken away after the start: read again, nixos");
        assertEqual(answer("arch").facts.pamDirectories.join(","), "/etc/pam.d,/usr/lib/pam.d", "Arch's facts read from its distribution.json");
        assertEqual(answer("nixos").facts.setuidWrapperDirectory, "/run/wrappers/bin", "NixOS's facts read from its distribution.json");
        const unknown = (name, message) => {
            const detection = answer(name);
            assert(detection.ready && detection.id === "" && detection.facts === null && detection.problem !== "",
                   message + ": unknown, the problem said (" + detection.problem + ")");
        };
        unknown("unreadable", "os-release that cannot be read");
        unknown("unknownOverride", "an override naming no distribution");
        unknown("broken", "a broken distribution.json");
        unknown("missing", "no distributions directory");

        // The shell's own, on the machine the tests run on (NixOS or Arch, os-release readable): a distribution, and the seam handed on
        assert(Distribution.ready && Distribution.id !== "", "Distribution answers, with a distribution (" + Distribution.detection.problem + ")");
        assert(DistributionRules.ids.includes(Distribution.id) && Distribution.facts?.id === Distribution.id,
               "… one of the distributions, with its facts (" + Distribution.id + ")");
        assertEqual(Distribution._reader.override, TestSeams.distribution, "… the override is the test seam's");
        // (module API 1.40) What modules read of it, outside module test mode: a frozen copy
        const shown = Api.system.distribution;
        assert(!Api.testMode, "module test mode is off in the unit suites");
        assertEqual([shown.ready, shown.id, shown.label].join("|"), [true, Distribution.id, Distribution.facts?.label].join("|"),
                    "Api.system.distribution: the shell's own answer, its id and label");
        assertEqual(JSON.stringify(shown.facts), JSON.stringify(Distribution.facts), "… its facts, all of them");
        assert(shown.facts !== Distribution.facts && Object.isFrozen(shown.facts) && Object.isFrozen(shown.facts.programDirectories),
               "… a frozen copy, never the shell's own object");

        for (const name of Object.keys(_readers))
            _readers[name].destroy();
        _readers = {};
        _sh("chmod -R u+rwX \"$1\"; rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    property Component _readerComponent: Component {
        DistributionReader {}
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
