import QtQuick
import qs.singletons

// The lock's recovery decisions (singletons/LockRecoveryRules.qml), one case per scenario of
// the lock test bed that recovers (tests/lock/tests/marker-stale.sh, restart-*.sh,
// reload-*.sh): what the shell decides there, from the start probe's lines, Hyprland's word
// and the lock's own steps — the bed then checks the same on a real compositor.
TestCase {
    suiteName: "LockRecoveryRules"

    readonly property string keyA: "1b2c:wayland-1:2049:123:1700000000"
    readonly property string keyB: "1b2c:wayland-1:2049:456:1700000999"
    readonly property string allowed: '{"option":"misc:allow_session_lock_restore","int":1,"set":true}\n{"locked":true}'
    readonly property string refused: '{"option":"misc:allow_session_lock_restore","int":0,"set":false}\n{"locked":true}'

    // ---- Helpers ----

    // A driver's view of the rules: the state, the last step's effects and all of them
    function machine(settings) {
        const machine = {
            state: LockRecoveryRules.initial(Object.assign({ markerUsable: true, hyprland: false, runtimeDirectory: "/run/user/1000" }, settings ?? {})),
            effects: [],
            all: []
        };
        machine.send = event => {
            const result = LockRecoveryRules.step(machine.state, event);
            machine.state = result.state;
            machine.effects = result.effects;
            machine.all = machine.all.concat(result.effects);
            return machine;
        };
        // What a reload hands the next generation, as Lockscreen's _carried holds it
        machine.carry = carried => {
            machine.state = LockRecoveryRules.withCarried(machine.state, carried);
            return machine;
        };
        return machine;
    }

    function probeLines(key, marker) {
        const lines = ["private yes"];
        if (key)
            lines.push("key " + key);
        if (marker)
            lines.push("marker " + marker);
        return lines;
    }

    // A shell started and its start probe answered (the driver's two steps)
    function startedWith(settings, lines, locked) {
        const started = machine(settings).send({ type: "started" });
        assertEqual(types(started.effects), "probeMarker", "(the start asks for the marker)");
        started.send({ type: "markerAnswered", lines: lines, locked: locked === true });
        const answered = started.effects;
        started.send({ type: "markerChecked" });
        started.effects = answered;
        return started;
    }

    function types(effects) {
        return effects.map(effect => effect.type).join(" ");
    }

    function of(effects, type) {
        return effects.filter(effect => effect.type === type);
    }

    function logs(effects, level) {
        return of(effects, "log").filter(effect => !level || effect.level === level).map(effect => effect.message);
    }

    function written(effects) {
        return of(effects, "writeMarker").map(effect => effect.text);
    }

    // The steps of a lock the driver asks for and Quickshell takes
    function lockTaken(machine) {
        machine.send({ type: "lockAsked" });
        const asked = machine.effects;
        machine.send({ type: "lockTaken" });
        machine.effects = asked;
        return machine;
    }

    function run() {
        _markerStale();
        _restartCompositorGone();
        _restartCrashFinger();
        _restartCrashLocked();
        _restartHyprctlHang();
        _restartKillLocked();
        _restartKillUnlocked();
        _restartLauncher();
        _restartLockedLimit();
        _restartLockedRetry();
        _restartNoRestoreGeneric();
        _restartNoRestore();
        _reloadExplicit();
        _reloadHard();
        _reloadWhileLocked();
        _reloadWindow();
        _total();
    }

    // ---- marker-stale: another compositor session's marker is ignored; this one's locks ----

    function _markerStale() {
        const stale = startedWith({}, probeLines(keyB, "locked " + keyA));
        assertEqual(types(stale.effects), "log stopTimer writeMarker log resetLockRestarts",
                    "marker-stale: another session's marker is said, and overwritten");
        assert(logs(stale.effects, "info")[0].includes("another compositor session (locked " + keyA + ")"), "marker-stale: … naming it");
        assertEqual(written(stale.effects).join(), "unlocked\n", "marker-stale: … with \"unlocked\"");
        assert(!stale.state.restoring && stale.state.checked && stale.state.key === keyB, "marker-stale: no lock taken back; the start checked; this session's key");

        const own = startedWith({}, probeLines(keyB, "locked " + keyB));
        assertEqual(types(own.effects), "log requestLock", "marker-stale: positive control — this session's marker locks at once");
        assertEqual(logs(own.effects, "warning")[0], "the shell was locked when it stopped (the lock marker says so): locking again", "marker-stale: … saying why");
        assert(own.state.restoring && of(own.effects, "requestLock")[0].source === "restore", "marker-stale: … a lock taken back");

        assertEqual(types(startedWith({}, probeLines("", "locked " + keyA)).effects), "log requestLock",
                    "marker-stale: no key of this session: fail closed, it locks");
        assertEqual(types(startedWith({}, probeLines(keyB, "locked")).effects), "log requestLock",
                    "marker-stale: a marker without a key: fail closed, it locks");

        const open = startedWith({}, ["private no", "key " + keyB, "marker locked " + keyB]);
        assertEqual(types(open.effects), "log", "marker-stale: a runtime dir others can write: said, nothing read");
        assert(logs(open.effects, "warning")[0].startsWith("XDG_RUNTIME_DIR (/run/user/1000) is not a private directory")
               && !open.state.restoring && open.state.checked && open.state.key === "?", "marker-stale: … no lock taken back, the start checked");

        const none = machine({ markerUsable: false }).send({ type: "started" });
        assert(types(none.effects) === "log" && none.state.checked, "marker-stale: no XDG_RUNTIME_DIR: said once, the start checked");
        none.send({ type: "lockAsked" });
        assertEqual(types(none.effects), "", "marker-stale: … and no marker written at a lock");
    }

    // ---- restart-compositor-gone: a marker names the compositor session it was written in ----

    function _restartCompositorGone() {
        const first = startedWith({}, probeLines(keyA, "unlocked"));
        assertEqual(types(first.effects), "", "restart-compositor-gone: an unlocked marker: nothing to do");
        first.send({ type: "lockWanted", source: "ipc", locked: false });
        assertEqual(JSON.stringify(first.effects), JSON.stringify([{ type: "requestLock", source: "ipc" }]), "restart-compositor-gone: a lock asked for");
        lockTaken(first);
        assertEqual(written(first.effects).join(), "locked " + keyA + "\n", "restart-compositor-gone: \"locked\" with this session's key, before the compositor is asked");
        assert(first.state.carried.held && first.state.marker === "locked", "restart-compositor-gone: the lock held");
        // The compositor is gone, a new one serves the same display under a new socket
        const next = startedWith({}, probeLines(keyB, "locked " + keyA));
        assert(!next.state.restoring && written(next.effects).join() === "unlocked\n",
               "restart-compositor-gone: a shell of the new session takes no lock of the old one's back");
    }

    // ---- restart-crash-finger: the shell restarted in place takes the lock back (Hyprland allows it) ----

    function _restartCrashFinger() {
        const shell = startedWith({ hyprland: true }, probeLines(keyA, "locked " + keyA));
        assertEqual(types(shell.effects), "log probeRestore", "restart-crash-finger: under Hyprland it is asked first");
        shell.send({ type: "restoreAnswered", output: allowed, locked: false });
        assertEqual(JSON.stringify(shell.effects), JSON.stringify([{ type: "requestLock", source: "restore" }]),
                    "restart-crash-finger: Hyprland allows restoring: the lock asked for");
        lockTaken(shell);
        shell.send({ type: "confirmed" });
        assertEqual(types(shell.effects), "log stopTimer", "restart-crash-finger: confirmed");
        assertEqual(logs(shell.effects)[0], "the lock is back: the compositor confirmed it", "restart-crash-finger: … said");
        assert(!shell.state.restoring && shell.state.carried.secure && shell.state.carried.held, "restart-crash-finger: an ordinary lock from now on");
    }

    // ---- restart-crash-locked: restoring counts as locked until the compositor confirms ----

    function _restartCrashLocked() {
        const shell = startedWith({ hyprland: true }, probeLines(keyA, "locked " + keyA));
        assert(shell.state.restoring && shell.state.checked, "restart-crash-locked: from the marker's answer the start is taking a lock back (the notices wait)");
        shell.send({ type: "restoreAnswered", output: allowed, locked: false });
        lockTaken(shell);
        assert(shell.state.restoring, "restart-crash-locked: … still, while the compositor has not confirmed");
        shell.send({ type: "ended", locked: true, lastEnd: "" });
        assertEqual(types(shell.effects), "", "restart-crash-locked: a step that leaves the lock in force changes nothing");
        shell.send({ type: "confirmed" });
        assert(!shell.state.restoring && !shell.state.restorePending, "restart-crash-locked: … and no more once it has");
        assert(of(shell.all, "exit").length === 0, "restart-crash-locked: never a quit");
    }

    // ---- restart-hyprctl-hang: no answer from Hyprland is no answer: the lock is asked for ----

    function _restartHyprctlHang() {
        const shell = startedWith({ hyprland: true }, probeLines(keyA, "locked " + keyA));
        shell.send({ type: "restoreAnswered", output: "\n", locked: false });
        assertEqual(types(shell.effects), "log requestLock", "restart-hyprctl-hang: said, then the lock asked for anyway");
        assertEqual(logs(shell.effects, "warning")[0], "Hyprland did not answer (hyprctl, 2 s each): asking for the lock back anyway",
                    "restart-hyprctl-hang: … the warning");
    }

    // ---- restart-kill-locked: locked again at once; the unlock writes "unlocked" a moment later ----

    function _restartKillLocked() {
        const shell = startedWith({}, probeLines(keyA, "locked " + keyA));
        assertEqual(types(shell.effects), "log requestLock", "restart-kill-locked: the new shell locks at once (no Hyprland: no question)");
        lockTaken(shell);
        shell.send({ type: "confirmed" });
        shell.send({ type: "ended", locked: false, lastEnd: "authenticated" });
        assertEqual(types(shell.effects), "startMarkerUnlockDelay", "restart-kill-locked: unlocked — the marker's \"unlocked\" waits a moment");
        assert(shell.state.marker === "locked" && shell.state.carried.markerUnlockPending && !shell.state.carried.held,
               "restart-kill-locked: … the marker says \"locked\" meanwhile");
        shell.send({ type: "markerUnlockDue", locked: false });
        assertEqual(types(shell.effects), "stopTimer writeMarker log resetLockRestarts", "restart-kill-locked: then written, and the launcher's record reset");
        assert(shell.state.marker === "unlocked" && !shell.state.carried.markerUnlockPending, "restart-kill-locked: … the marker says \"unlocked\"");
    }

    // ---- restart-kill-unlocked: an unlocked marker brings no lock out of nowhere ----

    function _restartKillUnlocked() {
        const shell = startedWith({}, probeLines(keyA, "unlocked"));
        assert(types(shell.effects) === "" && !shell.state.restoring && shell.state.checked, "restart-kill-unlocked: nothing done");
        shell.send({ type: "lockWanted", source: "", locked: false });
        assertEqual(JSON.stringify(shell.effects), JSON.stringify([{ type: "requestLock", source: "request" }]), "restart-kill-unlocked: it locks as usual");
        lockTaken(shell);
        shell.send({ type: "confirmed" });
        assertEqual(types(shell.effects), "stopTimer", "restart-kill-unlocked: an ordinary lock confirmed: nothing said");
    }

    // ---- restart-launcher: a marker written before the key was known still locks ----

    function _restartLauncher() {
        const shell = startedWith({}, probeLines(keyA, "locked ?"));
        assertEqual(types(shell.effects), "log requestLock", "restart-launcher: \"locked ?\" counts as this session's (fail closed)");
        shell.send({ type: "markerAnswered", lines: probeLines(keyA, "locked " + keyA), locked: true });
        assert(!of(shell.effects, "requestLock").length, "restart-launcher: a marker read while locked asks for no second lock");
    }

    // ---- restart-locked-limit: the question to Hyprland unanswered, the start counts as locked ----

    function _restartLockedLimit() {
        const shell = startedWith({ hyprland: true }, probeLines(keyA, "locked " + keyA));
        assert(shell.state.restoring && shell.state.checked && !shell.state.restorePending,
               "restart-locked-limit: while Hyprland does not answer, the start is restoring (not \"unlocked\")");
        shell.send({ type: "restoreRetry", locked: false });
        assertEqual(types(shell.effects), "probeRestore", "restart-locked-limit: (a second question while one runs: the driver starts none)");
        shell.send({ type: "restoreAnswered", output: allowed, locked: false });
        lockTaken(shell);
        shell.send({ type: "confirmed" });
        shell.send({ type: "ended", locked: false, lastEnd: "authenticated" });
        shell.send({ type: "markerUnlockDue", locked: false });
        assertEqual(of(shell.effects, "resetLockRestarts").length, 1, "restart-locked-limit: the unlock starts the launcher's count afresh");
    }

    // ---- restart-locked-retry: the shell that can start again comes up locked ----

    function _restartLockedRetry() {
        const shell = startedWith({ hyprland: true }, probeLines(keyA, "locked " + keyA));
        shell.send({ type: "restoreAnswered", output: allowed, locked: false });
        assertEqual(types(shell.effects), "requestLock", "restart-locked-retry: the lock asked for");
        // The lock is up before Hyprland's late word on an older question
        lockTaken(shell);
        shell.send({ type: "restoreAnswered", output: refused, locked: true });
        assertEqual(types(shell.effects), "", "restart-locked-retry: an answer that comes once locked is dropped");
        assert(!shell.state.restorePending, "restart-locked-retry: … and refuses nothing");
    }

    // ---- restart-no-restore-generic: no Hyprland to ask: asked, refused, asked again later ----

    function _restartNoRestoreGeneric() {
        const shell = startedWith({}, probeLines(keyA, "locked " + keyA));
        assertEqual(types(shell.effects), "log requestLock", "restart-no-restore-generic: the lock asked for at once");
        lockTaken(shell);
        shell.send({ type: "ended", locked: false, lastEnd: "denied" });
        assertEqual(types(shell.effects), "log log startTimer", "restart-no-restore-generic: the compositor refuses it: said, asked again later");
        assert(shell.state.restorePending && shell.state.restoring && shell.state.marker === "locked" && !shell.state.carried.held,
               "restart-no-restore-generic: … the session counts as locked, the marker stays");
        assertEqual(of(shell.effects, "startTimer")[0].ms, 5000, "restart-no-restore-generic: … in 5 s");
        shell.send({ type: "restoreRetry", locked: false });
        assertEqual(JSON.stringify(shell.effects), JSON.stringify([{ type: "requestLock", source: "restore" }]), "restart-no-restore-generic: then asked again");
        shell.send({ type: "lockAsked" });
        shell.send({ type: "lockRefused", session: 3 });
        assertEqual(types(shell.effects), "log stopTimer writeMarker log exit",
                    "restart-no-restore-generic: refused at once while taking a lock back: the marker stays \"locked\", the process quits");
    }

    // ---- restart-no-restore: Hyprland refuses: not asked, asked again with a growing pause ----

    function _restartNoRestore() {
        const shell = startedWith({ hyprland: true }, probeLines(keyA, "locked " + keyA));
        shell.send({ type: "restoreAnswered", output: refused, locked: false });
        assertEqual(types(shell.effects), "log log startTimer", "restart-no-restore: Hyprland would refuse: no lock asked for");
        assert(logs(shell.effects, "error")[0].includes("Hyprland is locked and does not allow restoring the lock")
               && logs(shell.effects, "warning")[0] === "taking the lock back again in 5 s", "restart-no-restore: said why, and when again");
        assert(shell.state.restorePending, "restart-no-restore: the status says compositor-locked");
        const pauses = [of(shell.effects, "startTimer")[0].ms];
        for (let i = 0; i < 5; i++) {
            shell.send({ type: "restoreRetry", locked: false });
            assertEqual(types(shell.effects), "probeRestore", "restart-no-restore: each pause ends in a question, not a lock (" + i + ")");
            shell.send({ type: "restoreAnswered", output: refused, locked: false });
            pauses.push(of(shell.effects, "startTimer")[0].ms);
        }
        assertEqual(pauses.join(), "5000,10000,20000,40000,60000,60000", "restart-no-restore: 5 s, doubling up to a minute");
        assertEqual(logs(shell.all, "error").length, 1, "restart-no-restore: the refusal is said once");
        shell.send({ type: "lockWanted", source: "ipc", locked: false });
        assertEqual(types(shell.effects), "probeRestore", "restart-no-restore: a lock asked for meanwhile asks for that lock back");
        // The setting switched on from a TTY
        shell.send({ type: "restoreAnswered", output: allowed, locked: false });
        assertEqual(types(shell.effects), "requestLock", "restart-no-restore: allowed now: the lock asked for");
        lockTaken(shell);
        shell.send({ type: "confirmed" });
        assert(!shell.state.restorePending && !shell.state.restoring && shell.state.restoreDelay === 0
               && types(shell.effects) === "log stopTimer", "restart-no-restore: confirmed: back to an ordinary lock, the retry stopped");
    }

    // ---- reload-explicit: the lock carried over, nothing taken back ----

    function _reloadExplicit() {
        const shell = machine({}).carry({ held: true, secure: true }).send({ type: "started" });
        shell.send({ type: "lockAdopted" });
        assertEqual(types(shell.effects), "stopTimer writeMarker log checkCarriedLater", "reload-explicit: held, \"locked\" written, checked once realized");
        assertEqual(written(shell.effects).join(), "locked ?\n", "reload-explicit: (the key not known yet)");
        shell.send({ type: "carriedChecked", locked: true, compositorLocked: true });
        assertEqual(types(shell.effects), "", "reload-explicit: the new lock holds it: nothing to do");
        shell.send({ type: "markerAnswered", lines: probeLines(keyA, "locked ?"), locked: true });
        assertEqual(written(shell.effects).join(), "locked " + keyA + "\n", "reload-explicit: the key known: the marker written again with it");
        assert(!shell.state.restoring && !of(shell.effects, "requestLock").length, "reload-explicit: no lock taken back over the carried one");
        shell.send({ type: "ended", locked: false, lastEnd: "authenticated" });
        assertEqual(types(shell.effects), "startMarkerUnlockDelay", "reload-explicit: the unlock as usual");
    }

    // ---- reload-hard: nothing carried; this process cannot lock again and quits ----

    function _reloadHard() {
        const shell = startedWith({ hyprland: true }, probeLines(keyA, "locked " + keyA));
        shell.send({ type: "restoreAnswered", output: allowed, locked: false });
        shell.send({ type: "lockAsked" });
        shell.send({ type: "lockRefused", session: 1 });
        assertEqual(types(shell.effects), "log stopTimer writeMarker log exit", "reload-hard: refused at once: said, \"locked\" kept, quit");
        assert(logs(shell.effects, "error")[0].startsWith("this process cannot take the session lock back"), "reload-hard: … why");
        assert(!of(shell.effects, "compositorFinished").length && !shell.state.carried.held, "reload-hard: … not a refusal the lock rules hear of");

        const ordinary = startedWith({}, probeLines(keyA, "unlocked"));
        ordinary.send({ type: "lockAsked" });
        ordinary.send({ type: "lockRefused", session: 4 });
        assertEqual(JSON.stringify(ordinary.effects), JSON.stringify([{ type: "compositorFinished", session: 4 }]),
                    "reload-hard: an ordinary lock refused at once: the lock rules hear of it");

        const lost = machine({}).carry({ held: true, secure: true }).send({ type: "lockAdopted" });
        lost.send({ type: "carriedChecked", locked: true, compositorLocked: false });
        assertEqual(types(lost.effects), "log stopTimer writeMarker log exit", "reload-hard: a reload that did not carry the lock over: quit, \"locked\" kept");
        assert(logs(lost.effects, "error")[0].startsWith("the lock was not carried over the reload"), "reload-hard: … why");
        lost.send({ type: "carriedChecked", locked: false, compositorLocked: false });
        assertEqual(types(lost.effects), "", "reload-hard: unlocked by then: nothing");
    }

    // ---- reload-while-locked: a reload between an unlock and its "unlocked" ----

    function _reloadWhileLocked() {
        const before = startedWith({}, probeLines(keyA, "unlocked"));
        before.send({ type: "lockWanted", source: "ipc", locked: false });
        lockTaken(before);
        before.send({ type: "confirmed" });
        before.send({ type: "ended", locked: false, lastEnd: "authenticated" });
        const carried = before.state.carried;
        assert(carried.markerUnlockPending && !carried.held, "reload-while-locked: unlocked, \"unlocked\" still to be written");
        // The new generation: what _carried kept, and the marker as the old one left it
        const after = machine({}).carry(carried).send({ type: "started" });
        after.send({ type: "markerAnswered", lines: probeLines(keyA, "locked " + keyA), locked: false });
        assertEqual(types(after.effects), "stopTimer writeMarker log resetLockRestarts", "reload-while-locked: the new generation writes \"unlocked\"");
        assert(!after.state.restoring && !after.state.carried.markerUnlockPending, "reload-while-locked: … and takes no lock back");
    }

    // ---- reload-window: a lock right after an unlock is never overwritten by its "unlocked" ----

    function _reloadWindow() {
        const shell = startedWith({}, probeLines(keyA, "unlocked"));
        shell.send({ type: "lockWanted", source: "ipc", locked: false });
        lockTaken(shell);
        shell.send({ type: "confirmed" });
        shell.send({ type: "ended", locked: false, lastEnd: "authenticated" });
        shell.send({ type: "lockWanted", source: "ipc", locked: false });
        assertEqual(types(shell.effects), "requestLock", "reload-window: a lock at once after the unlock is taken");
        lockTaken(shell);
        assertEqual(types(shell.effects), "stopTimer writeMarker log", "reload-window: \"locked\" written, the pending \"unlocked\" stopped");
        shell.send({ type: "markerUnlockDue", locked: true });
        assertEqual(types(shell.effects), "", "reload-window: a late pause end writes nothing over it");
        assert(shell.state.marker === "locked" && !shell.state.carried.markerUnlockPending, "reload-window: the marker says \"locked\"");
    }

    // ---- Every event total ----

    function _total() {
        const fresh = machine({});
        const before = JSON.stringify(fresh.state);
        for (const event of [null, undefined, {}, { type: "toString" }, { type: "__proto__" }, { type: 5 }])
            fresh.send(event);
        assert(JSON.stringify(fresh.state) === before && fresh.all.length === 0, "an unknown event changes nothing");
        const unlocked = startedWith({}, probeLines(keyA, "unlocked"));
        unlocked.send({ type: "ended", locked: false, lastEnd: "authenticated" });
        assertEqual(types(unlocked.effects), "", "an unlocked step with no lock of this shell's: nothing");
        assertEqual(JSON.stringify(LockRecoveryRules.withCarried(fresh.state, { held: 1, secure: true }).carried),
                    JSON.stringify({ held: false, secure: true, markerUnlockPending: false }), "withCarried: only true counts");
    }
}
