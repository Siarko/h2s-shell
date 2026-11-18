import QtQuick
import qs.api
import qs.tests

// Module test mode from a module written for API 1.9 (tests/run-modules.sh): its suites may
// still put a stand-in pkexec that lies anywhere into PrivilegedAction's `elevate` — the
// gate that slice Z removes, listed in its deprecations — but never the real pkexec, and its
// plain commands follow the strict rule. Run beside the good fixture, whose suite sees the
// strict rule at the same time.
TestCase {
    id: suite
    suiteName: "legacy-elevate: the test-mode gate"
    asynchronous: true

    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))
    // A stand-in pkexec outside any module and no module's <testPrograms>/pkexec, as the
    // released Tailscale module's is (module/../tools/stand-in/pkexec)
    readonly property string outsideStandIn: String(Qt.resolvedUrl("../../../legacy-tools/pkexec")).replace(/^file:\/\//, "")
    property var _results: ({})

    property PrivilegedAction outside: PrivilegedAction {
        notifyFailures: false
    }
    property PrivilegedAction system: PrivilegedAction {
        notifyFailures: false
        // The system's pkexec (Arch: there, the same file; NixOS: not there, so it cannot be
        // checked) — refused either way, never run
        elevate: ["/usr/bin/pkexec"]
    }
    property PrivilegedAction wrapper: PrivilegedAction {
        notifyFailures: false
        // NixOS's setuid wrapper (Arch: not there) — refused either way
        elevate: ["/run/wrappers/bin/pkexec"]
    }
    property PrivilegedAction byName: PrivilegedAction {
        notifyFailures: false
    }
    property CommandRunner runner: CommandRunner {}

    property Timer _wait: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (Object.keys(suite._results).length < 5 && waited < 15000)
                return;
            stop();
            suite._check();
            suite.finish();
        }
    }

    function runAsync() {
        assert(Api.testMode, "test mode is on");
        assert((ModuleTestKit.status("legacy-elevate")?.deprecations ?? []).some(line => line.includes("will be removed")),
               "the gate is in its deprecations, which say it will be removed: " + JSON.stringify(ModuleTestKit.status("legacy-elevate")?.deprecations));
        outside.elevate = [outsideStandIn];
        outside.run(["/bin/sh", "-c", "echo legacy"], "Outside stand-in", result => suite._results.outside = result);
        system.run(["/bin/sh", "-c", "echo never"], "System pkexec", result => suite._results.system = result);
        wrapper.run(["/bin/sh", "-c", "echo never"], "Setuid wrapper", result => suite._results.wrapper = result);
        byName.run(["/bin/sh", "-c", "echo never"], "By name", result => suite._results.byName = result);
        runner.start([outsideStandIn, "/bin/true"], { done: result => suite._results.plain = result });
        _wait.start();
    }

    function _check() {
        const outsideResult = _results.outside;
        assert(outsideResult?.ok === true && outsideResult.lines[0] === "legacy",
               "a stand-in outside the module in elevate: checked, not the real pkexec, run: " + JSON.stringify(outsideResult));
        for (const name of ["system", "wrapper"])
            assert(_results[name] && !_results[name].ok && String(_results[name].error).startsWith("test mode:") && _results[name].code === -1,
                   name + ": the system's pkexec (or one that cannot be checked) in elevate: refused, nothing run: " + JSON.stringify(_results[name]));
        assert(_results.byName && !_results.byName.ok && String(_results.byName.error).startsWith("test mode:"),
               "the default elevate, \"pkexec\" by name: refused: " + JSON.stringify(_results.byName));
        assert(_results.plain && !_results.plain.ok && String(_results.plain.error).startsWith("test mode:"),
               "its plain commands follow the strict rule: a pkexec that is not a <testPrograms>/pkexec refused: " + JSON.stringify(_results.plain));
    }
}
