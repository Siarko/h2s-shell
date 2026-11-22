import QtQuick
import qs.singletons

// What comes into the lock's rules as text (singletons/LockParseRules.qml): the methods
// script's lines, logind's monitor lines, its GetSession answer, its idle and sleep
// inhibitors, what it says of sleep and the sleep call's outcome.
TestCase {
    suiteName: "LockParseRules"

    function run() {
        const methods = LockParseRules.parseMethods([
            "password\t/etc/pam.d\th2s-shell-password",
            "fingerprint\t/home/u/src/h2s-shell/pam\tfingerprint\r",
            "",
            "garbage line without tabs",
            "u2f\t/etc/pam.d",
            "u2f\trelative/dir\tu2f",
            "u2f\t/etc/pam.d\tnested/config",
            "password\t/elsewhere\tsecond",
            "Weird Name\t/etc/pam.d\tx",
            "u2f\t/etc/pam.d\th2s-shell-u2f\textra",
            "u2f \t /etc/pam.d \t h2s-shell-u2f "
        ]);
        assertEqual(JSON.stringify(methods),
                    JSON.stringify({ password: { directory: "/etc/pam.d", config: "h2s-shell-password" },
                                     fingerprint: { directory: "/home/u/src/h2s-shell/pam", config: "fingerprint" },
                                     u2f: { directory: "/etc/pam.d", config: "h2s-shell-u2f" } }),
                    "parseMethods: the script's lines, junk skipped, first line per method wins");
        assertEqual(JSON.stringify(LockParseRules.parseMethods("password\t/etc/pam.d\tlogin\n")),
                    JSON.stringify({ password: { directory: "/etc/pam.d", config: "login" } }),
                    "parseMethods: the NixOS fallback line, as one string");
        assertEqual(JSON.stringify(LockParseRules.parseMethods(null)), "{}", "parseMethods: nothing");

        const session = "/org/freedesktop/login1/session/_34";
        const logind = line => JSON.stringify(LockParseRules.parseLogind(line, session));
        assertEqual(logind("/org/freedesktop/login1/session/_34: org.freedesktop.login1.Session.Lock ()"),
                    JSON.stringify({ type: "lockRequested", source: "logind" }), "parseLogind: Lock on our session");
        assertEqual(logind("/org/freedesktop/login1/session/_34: org.freedesktop.login1.Session.Unlock ()"),
                    JSON.stringify({ type: "unlockRequested", source: "logind" }), "parseLogind: Unlock on our session");
        assertEqual(logind("/org/freedesktop/login1/session/_35: org.freedesktop.login1.Session.Unlock ()"), "null",
                    "parseLogind: another session's Unlock is not ours");
        assertEqual(logind("/org/freedesktop/login1/session/_341: org.freedesktop.login1.Session.Lock ()"), "null",
                    "parseLogind: a session path that only starts like ours is not ours");
        assertEqual(JSON.stringify(LockParseRules.parseLogind("/org/freedesktop/login1/session/_34: org.freedesktop.login1.Session.Unlock ()", "")),
                    "null", "parseLogind: without a session of our own, no Lock or Unlock counts");
        assertEqual(logind("/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)"),
                    JSON.stringify({ type: "prepareForSleep" }), "parseLogind: PrepareForSleep (true,)");
        assertEqual(logind("/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)"),
                    JSON.stringify({ type: "resumed" }), "parseLogind: PrepareForSleep (false,)");
        assertEqual(logind("/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (true,)"), "null",
                    "parseLogind: other Manager signals");
        assertEqual(logind("/org/freedesktop/login1/session/_34: org.freedesktop.DBus.Properties.PropertiesChanged ('org.freedesktop.login1.Session', {'IdleHint': <true>}, @as [])"),
                    "null", "parseLogind: a property change on our session");
        assertEqual(logind("/org/freedesktop/login1: org.freedesktop.login1.Manager.SessionNew ('35', objectpath '/org/freedesktop/login1/session/_35')"),
                    "null", "parseLogind: another unrelated signal");
        assertEqual(logind("Monitoring signals on object /org/freedesktop/login1/session/_34 owned by org.freedesktop.login1"), "null",
                    "parseLogind: the header line");
        assertEqual(logind("The name org.freedesktop.login1 is owned by :1.7"), "null", "parseLogind: the owner line");
        assertEqual(logind(""), "null", "parseLogind: an empty line");

        assertEqual(LockParseRules.parseSessionPath("(objectpath '/org/freedesktop/login1/session/_34',)\n"),
                    "/org/freedesktop/login1/session/_34", "parseSessionPath: GetSession's answer");
        assertEqual(LockParseRules.parseSessionPath("Error: GDBus.Error:org.freedesktop.login1.NoSuchSession: No session '' known"), "",
                    "parseSessionPath: an error (no XDG_SESSION_ID)");
        assertEqual(LockParseRules.parseSessionPath(""), "", "parseSessionPath: nothing");
        assertEqual(LockParseRules.parseSessionPath("(objectpath '/org/freedesktop/login1/user/_1000',)"), "",
                    "parseSessionPath: a path that is no session");

        // logind's idle block (Idle reads it before a stage would start)
        const inhibitor = (what, who, why, mode, uid) => ({ what: what, who: who, why: why, mode: mode, uid: uid, pid: 1 });
        const block = (list, uid) => JSON.stringify(LockParseRules.idleBlock(list, uid === undefined ? 1000 : uid));
        assertEqual(block([inhibitor("idle", "mpv", "Playing", "block", 1000)]),
                    JSON.stringify({ held: true, holders: [{ who: "mpv", why: "Playing" }] }), "idleBlock: an idle block of this user's: held");
        assertEqual(block([inhibitor("sleep:idle:shutdown", "Totem", "", "block", 1000)]),
                    JSON.stringify({ held: true, holders: [{ who: "Totem", why: "" }] }), "idleBlock: idle among other kinds");
        assertEqual(block([inhibitor("idle", "gdm", "Greeter", "block", 60), inhibitor("idle", "x", "y", "delay", 1000),
                           inhibitor("sleep", "UPower", "z", "block", 1000), inhibitor("idlesomething", "w", "", "block", 1000),
                           inhibitor("idle", "h2s-shell", "own", "block", 1000)]),
                    JSON.stringify({ held: false, holders: [] }),
                    "idleBlock: another user's, a delay, other kinds and the shell's own do not count: free");
        assertEqual(block([]), JSON.stringify({ held: false, holders: [] }), "idleBlock: no inhibitors: free");
        assertEqual(block(null), JSON.stringify({ held: "unknown", holders: [] }), "idleBlock: no list (a failed read): unknown");
        assertEqual(block([], null), JSON.stringify({ held: "unknown", holders: [] }), "idleBlock: no uid: unknown");
        const odd = LockParseRules.idleBlock([inhibitor("idle", "<b>a</b>\n" + "b".repeat(60), "line\none " + "c".repeat(100), "block", 1000),
                                              inhibitor("idle", "", "", "block", 1000)], 1000).holders;
        assertEqual(odd[0].who.length, 40, "idleBlock: a long name capped");
        assert(odd[0].who.startsWith("<b>a</b> b") && odd[0].why.startsWith("line one c") && odd[0].why.length === 80,
                   "idleBlock: one line, capped, kept as plain text");
        assertEqual(odd[1].who, "an app", "idleBlock: no name: an app");
        assertEqual(LockParseRules.idleBlock(Array(8).fill(inhibitor("idle", "a", "", "block", 1000)), 1000).holders.length, 5,
                    "idleBlock: at most 5 holders");
        const listed = "([('sleep', 'UPower', 'Pause', 'delay', uint32 0, uint32 2), ('idle', 'mpv', 'Playing \\'a\\'', 'block', uint32 1000, uint32 3)],)";
        assertEqual(JSON.stringify(LockParseRules.idleBlockFromOutput("1000\n" + listed)),
                    JSON.stringify({ held: true, holders: [{ who: "mpv", why: "Playing 'a'" }] }), "idleBlockFromOutput: id -u, then the list");
        assertEqual(LockParseRules.idleBlockFromOutput("1000\n(@a(ssssuu) [],)\n").held, false, "idleBlockFromOutput: an empty list: free");
        assertEqual(LockParseRules.idleBlockFromOutput("1000\n").held, "unknown", "idleBlockFromOutput: gdbus said nothing (it failed): unknown");
        assertEqual(LockParseRules.idleBlockFromOutput("1000\n([('idle', 'mpv'").held, "unknown", "idleBlockFromOutput: malformed: unknown");
        assertEqual(LockParseRules.idleBlockFromOutput(listed).held, "unknown", "idleBlockFromOutput: no uid line: unknown");
        assertEqual(LockParseRules.idleBlockFromOutput(null).held, "unknown", "idleBlockFromOutput: nothing: unknown");

        // logind's sleep block (Idle reads it before it asks logind to suspend)
        const sleepBlock = list => JSON.stringify(LockParseRules.sleepBlock(list));
        assertEqual(sleepBlock([inhibitor("sleep", "borg", "Backup", "block", 0)]),
                    JSON.stringify({ held: true, holders: [{ who: "borg", why: "Backup" }] }), "sleepBlock: a sleep block, root's too: held");
        assertEqual(sleepBlock([inhibitor("sleep:idle", "mpv", "Playing", "block", 1000)]),
                    JSON.stringify({ held: true, holders: [{ who: "mpv", why: "Playing" }] }), "sleepBlock: sleep among other kinds");
        assertEqual(sleepBlock([inhibitor("sleep", "h2s-shell", "Lock first", "delay", 1000), inhibitor("sleep", "UPower", "", "delay", 0),
                                inhibitor("idle", "mpv", "", "block", 1000), inhibitor("sleepy", "x", "", "block", 1000)]),
                    JSON.stringify({ held: false, holders: [] }), "sleepBlock: delays (the shell's own), other kinds: free");
        assertEqual(sleepBlock(null), JSON.stringify({ held: "unknown", holders: [] }), "sleepBlock: no list: unknown");
        assertEqual(sleepBlock([inhibitor("sleep", "backup", "Copying", "block-weak", 1000)]),
                    JSON.stringify({ held: true, holders: [{ who: "backup", why: "Copying" }] }),
                    "sleepBlock: block-weak (its owner's own calls pass it, not the shell's): held");
        assertEqual(sleepBlock([inhibitor("sleep", "x", "", "weak", 1000)]), JSON.stringify({ held: false, holders: [] }),
                    "sleepBlock: a mode logind does not have: not counted");
        assertEqual(LockParseRules.sleepBlock([inhibitor("sleep", "", "a\nb", "block", 0)]).holders[0].who + "/"
                    + LockParseRules.sleepBlock([inhibitor("sleep", "", "a\nb", "block", 0)]).holders[0].why, "an app/a b",
                    "sleepBlock: no name: an app; one line");
        assertEqual(LockParseRules.sleepBlock([inhibitor("sleep", "w".repeat(40), "", "block", 0)]).holders[0].who, "w".repeat(40),
                    "sleepBlock: a name of exactly the cap kept whole");
        assertEqual(LockParseRules.sleepBlock(Array(8).fill(inhibitor("sleep", "a", "", "block", 0))).holders.length, 5,
                    "sleepBlock: at most 5");
        assertEqual(JSON.stringify(LockParseRules.sleepBlockFromOutput("1000\n([('sleep', 'borg', 'Backup', 'block', uint32 0, uint32 7)],)")),
                    JSON.stringify({ held: true, holders: [{ who: "borg", why: "Backup" }] }), "sleepBlockFromOutput: the idle reader's output");
        assertEqual(LockParseRules.sleepBlockFromOutput("1000\n").held, "unknown", "sleepBlockFromOutput: gdbus said nothing: unknown");
        assertEqual(LockParseRules.sleepBlockFromOutput("x\n(@a(ssssuu) [],)").held, false, "sleepBlockFromOutput: no uid needed");

        // What logind says of sleep
        for (const answer of ["yes", "no", "challenge", "na"])
            assertEqual(LockParseRules.canAnswer("('" + answer + "',)\n"), answer, "canAnswer: " + answer);
        for (const junk of ["", "('maybe',)", "('yes', 'no')", "Error: GDBus.Error", null, "yes"])
            assertEqual(LockParseRules.canAnswer(junk), "unknown", "canAnswer: " + JSON.stringify(junk) + ": unknown");
        assertEqual(JSON.stringify(LockParseRules.idleAction("(<'suspend'>,)", "(<uint64 1800000000>,)")),
                    JSON.stringify({ action: "suspend", after: 1800 }), "idleAction: the action and its time in seconds");
        assertEqual(JSON.stringify(LockParseRules.idleAction("(<'ignore'>,)\n", "(<uint64 1800000000>,)\n")),
                    JSON.stringify({ action: "ignore", after: 1800 }), "idleAction: ignore, logind's default");
        assertEqual(JSON.stringify(LockParseRules.idleAction("(<'suspend-then-hibernate'>,)", "(<1500000>,)")),
                    JSON.stringify({ action: "suspend-then-hibernate", after: 2 }), "idleAction: a dashed action; rounded seconds");
        assertEqual(LockParseRules.idleAction("", "(<uint64 1800000000>,)"), null, "idleAction: the action not read: null");
        assertEqual(LockParseRules.idleAction("(<'suspend'>,)", "Error"), null, "idleAction: the time not read: null");
        assertEqual(LockParseRules.idleAction("(<'Suspend!'>,)", "(<uint64 1>,)"), null, "idleAction: not a word logind uses: null");
        const pick = value => ({ canSuspend: value.canSuspend, idleAction: value.idleAction });
        const support = LockParseRules.sleepSupport("[CanSuspend]\n('yes',)\n[IdleAction]\n(<'suspend'>,)\n[IdleActionUSec]\n(<uint64 600000000>,)\n");
        assertEqual(JSON.stringify(pick(support)), JSON.stringify({ canSuspend: "yes", idleAction: { action: "suspend", after: 600 } }),
                    "sleepSupport: the three answers under their headers");
        assertEqual(JSON.stringify(pick(LockParseRules.sleepSupport("[CanSuspend]\n[IdleAction]\n(<'ignore'>,)\n[IdleActionUSec]\n(<uint64 1>,)\n"))),
                    JSON.stringify({ canSuspend: "unknown", idleAction: { action: "ignore", after: 0 } }), "sleepSupport: a failed CanSuspend: unknown");
        assertEqual(JSON.stringify(LockParseRules.sleepSupport("")), JSON.stringify({
            canSuspend: "unknown", canHibernate: "unknown", canSuspendThenHibernate: "unknown", idleAction: null,
            hibernation: { swaps: null, memoryInUse: -1, lockdown: "unknown", resume: "unknown", delay: { state: "unknown" }, nixos: null }
        }), "sleepSupport: nothing: unknown, not read");
        assertEqual(JSON.stringify(LockParseRules.sleepSupportUnread()), JSON.stringify(LockParseRules.sleepSupport("")), "… the same before a read");
        const whole = LockParseRules.sleepSupport("[CanSuspend]\n('yes',)\n[CanHibernate]\n('na',)\n[CanSuspendThenHibernate]\n('challenge',)\n"
            + "[IdleAction]\n[IdleActionUSec]\n"
            + "[Swaps]\nFilename Type Size Used Priority\n/dev/zram0 partition 4194300 0 100\n"
            + "[Meminfo]\nMemTotal: 1000 kB\nMemAvailable: 400 kB\n"
            + "[Lockdown]\nnone [integrity] confidentiality\n[Resume]\n0:0\n[Cmdline]\nroot=x resume=/dev/sda2\n[NixOS]\nno\n"
            + "[SleepConf]\n# /etc/systemd/sleep.conf\n[Swaps]\n[NixOS]\n[Sleep]\nHibernateDelaySec=3h\n");
        assertEqual(JSON.stringify(whole), JSON.stringify({
            canSuspend: "yes", canHibernate: "na", canSuspendThenHibernate: "challenge", idleAction: null,
            hibernation: { swaps: [{ name: "/dev/zram0", type: "partition", kib: 4194300, zram: true }], memoryInUse: 600, lockdown: "integrity",
                           resume: true, delay: { state: "set", seconds: 10800 }, nixos: false }
        }), "sleepSupport: every section; sleep.conf's own [Sleep] and look-alike headers stay in it, past its header");
        assertEqual(LockParseRules.sleepSupport("[NixOS]\nyes\n").hibernation.nixos, true, "sleepSupport: NixOS");
        assertEqual(LockParseRules.sleepSupport("[Bogus]\n[NixOS]\nyes\n[Other]\nno\n").hibernation.nixos, null,
                    "sleepSupport: an unknown header is a line of the section before (NixOS: not one word)");
        assertEqual(LockParseRules.sleepSupport("('yes',)\n").canSuspend, "unknown", "sleepSupport: an answer without its header: unknown");

        // The sleep call's outcome
        assertEqual(JSON.stringify(LockParseRules.suspendOutcome("()\n[exit 0]\n")), JSON.stringify({ ok: true, error: "" }),
                    "suspendOutcome: logind's empty answer, status 0: taken");
        assertEqual(JSON.stringify(LockParseRules.suspendOutcome("Error: GDBus.Error:org.freedesktop.login1.OperationInProgress: busy\n[exit 1]")),
                    JSON.stringify({ ok: false, error: "Error: GDBus.Error:org.freedesktop.login1.OperationInProgress: busy" }),
                    "suspendOutcome: refused, with gdbus's words");
        assertEqual(JSON.stringify(LockParseRules.suspendOutcome("\n[exit 127]")), JSON.stringify({ ok: false, error: "gdbus exited with 127" }),
                    "suspendOutcome: nothing said: the status");
        assertEqual(LockParseRules.suspendOutcome("odd\n[exit 0]").ok, false, "suspendOutcome: status 0 without logind's answer: not taken");
        assertEqual(LockParseRules.suspendOutcome("()").ok, false, "suspendOutcome: no status: not taken");
        assertEqual(LockParseRules.suspendOutcome("x".repeat(500) + "\n[exit 1]").error.length, 200, "suspendOutcome: the words capped");

        // LockRules forwards them: its callers read the same answers
        assertEqual(JSON.stringify(LockRules.parseMethods("password\t/etc/pam.d\tlogin")),
                    JSON.stringify(LockParseRules.parseMethods("password\t/etc/pam.d\tlogin")), "LockRules.parseMethods forwards");
        assertEqual(JSON.stringify(LockRules.parseLogind("/org/freedesktop/login1/session/_34: org.freedesktop.login1.Session.Lock ()", session)),
                    JSON.stringify({ type: "lockRequested", source: "logind" }), "LockRules.parseLogind forwards");
        assertEqual(LockRules.parseSessionPath("(objectpath '/org/freedesktop/login1/session/_34',)"),
                    "/org/freedesktop/login1/session/_34", "LockRules.parseSessionPath forwards");
    }
}
