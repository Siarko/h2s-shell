import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// logind's sleep "delay" inhibitor, held as a level: `wanted` says whether it should be
// held (the rules' holdInhibitor / releaseInhibitor), and this keeps it so. While it is
// held, logind waits (up to its InhibitDelayMaxSec, 5 s by default) before suspending, so
// the screen can lock first. Lives for the shell's lifetime.
//
// The lock is held for as long as `systemd-inhibit` runs; it ends when a line arrives on
// its input (the release), or a few seconds after the shell goes away and that input closes
// with it (`graceSeconds`, below) — so a crashed shell leaves no inhibitor behind for long,
// and a reload leaves logind waiting while the new generation locks. When it ends while
// still wanted (logind
// restarted, no system bus) it is taken again after a growing pause
// (LockIoRules.restartDelay), never in a tight loop; after a release this shell asked for,
// a new hold starts at once.
//
// `systemd-inhibit` is the one on PATH, or `toolDirectory`/systemd-inhibit when the driver
// names a directory (H2S_LOCK_TOOLS, the lock test bed's seam: its stand-in records holds
// and releases, the real system bus being cut off there).
Scope {
    id: root

    signal logLine(string level, string message)

    property bool wanted: false
    // Where `systemd-inhibit` is taken from: "" for PATH (see the header)
    property string toolDirectory: ""
    // Whether a systemd-inhibit process is running (held, or being released)
    readonly property bool running: _process.running

    readonly property var _restartTable: ({ minimum: 1000, maximum: 60000, healthyRun: 60000 })

    property double _startedAt: 0
    property int _delay: 0
    // A release was written and the process has not ended yet
    property bool _releasing: false

    onWantedChanged: _apply()

    function _apply() {
        if (wanted) {
            if (!_process.running && !_retry.running)
                _start();
        } else {
            _retry.stop();
            if (_process.running && !_releasing) {
                _releasing = true;
                _process.write("\n");
            }
        }
    }

    function _start() {
        _startedAt = Date.now();
        _releasing = false;
        _process.running = true;
    }

    // systemd-inhibit holds the lock while its command runs: `read -r release`, which ends at
    // once on the release line, and — when its input closes without one (this shell gone:
    // crashed, killed, or this generation torn down by a reload) — only after `graceSeconds`.
    // Those seconds bridge a reload: logind refuses a new inhibitor while a sleep is
    // already under way, and waits only for the ones held when it said PrepareForSleep, so
    // the old generation's inhibitor is what keeps the machine up while the new generation
    // locks (LogindMonitor asks logind about a sleep it did not hear). For that it must not
    // be the process Quickshell kills when the old generation's Process goes (SIGKILL to its
    // direct child): a small sh is, and systemd-inhibit runs beside it, reading the same input.
    //
    // How long: with s the signal, T this generation's teardown (s <= T <= s + b, b the new
    // generation's build) and d the time from T to the new generation's compositorLocked,
    // logind sleeps at min(T + grace, s + 5) and the lock comes at T + d, so it takes
    //     d < grace <= 5   and   b + d < 5   (InhibitDelayMaxSec, worst case: s at the
    // build's start; a grace past 5 - (T - s) is cut short by logind anyway). Measured in the
    // lock test bed (reload-window): d 0.05-0.07 s, s to T up to 1.01 s. 3 s leaves ~2.9 s of
    // margin, and costs a sleep right after a crash at most 3 s. notes/plans/lockscreen.md,
    // "The reload window".
    readonly property int graceSeconds: 3

    Process {
        id: _process
        stdinEnabled: true
        command: ["sh", "-c",
            "exec 3<&0\n"
            + "\"$0\" --what=sleep --mode=delay --who=h2s-shell '--why=Lock the screen before sleep' "
            + "sh -c \"read -r release || sleep $1\" <&3 3<&- &\n"
            + "wait $!",
            root.toolDirectory !== "" ? root.toolDirectory + "/systemd-inhibit" : "systemd-inhibit",
            String(root.graceSeconds)]

        onRunningChanged: {
            if (running) {
                root.logLine("info", "sleep inhibitor: systemd-inhibit started (delay lock wanted)");
                return;
            }
            const released = root._releasing;
            root._releasing = false;
            if (released)
                root.logLine("info", "sleep inhibitor released");
            if (!root.wanted)
                return;
            if (released) {
                // Released on request, and wanted again meanwhile: hold it again now
                root._start();
                return;
            }
            const ran = Date.now() - root._startedAt;
            root._delay = LockIoRules.restartDelay(root._delay, ran, root._restartTable);
            root.logLine("warning", "the sleep inhibitor ended after " + Math.round(ran / 1000)
                + " s while wanted: taken again in " + Math.round(root._delay / 1000) + " s");
            _retry.interval = root._delay;
            _retry.start();
        }
    }

    Timer {
        id: _retry
        repeat: false
        onTriggered: {
            if (root.wanted && !_process.running)
                root._start();
        }
    }
}
