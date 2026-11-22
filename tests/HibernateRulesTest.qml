import QtQuick
import qs.singletons

// Hibernation's reading and writing rules (singletons/HibernateRules.qml): the swap tables,
// memory, lockdown and resume reads, systemd time spans, sleep.conf's delay through its
// drop-ins, the reason shown when it is not possible, the page's delay line and the Apply's
// command and its answer.
TestCase {
    suiteName: "HibernateRules"

    function run() {
        const rules = HibernateRules;
        const json = value => JSON.stringify(value);

        // ---- /proc/swaps ----
        const header = "Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n";
        assertEqual(json(rules.swaps(header + "/dev/zram0                              partition\t4194300\t\t0\t\t100\n")),
                    json([{ name: "/dev/zram0", type: "partition", kib: 4194300, zram: true }]), "zram alone");
        assertEqual(json(rules.swaps(header + "/swap/swapfile file 16777212 0 -2\n/dev/nvme0n1p3 partition 8388604 512 -3\n")),
                    json([{ name: "/swap/swapfile", type: "file", kib: 16777212, zram: false },
                          { name: "/dev/nvme0n1p3", type: "partition", kib: 8388604, zram: false }]), "a file and a partition");
        assertEqual(json(rules.swaps(header + "/home/me/my\\040swap file 1024 0 -2\n")),
                    json([{ name: "/home/me/my swap", type: "file", kib: 1024, zram: false }]), "a name with a space, as the kernel escapes it");
        assertEqual(json(rules.swaps(header)), "[]", "no swap at all: an empty list");
        assertEqual(rules.swaps(""), null, "not read: null, never \"no swap\"");
        assertEqual(rules.swaps("junk\n/dev/sda2 partition 100 0 -2"), null, "no header: not understood");
        assertEqual(json(rules.swaps(header + "/dev/sda2 partition many 0 -2\n/dev/zram10 partition 5 0 1\n")),
                    json([{ name: "/dev/zram10", type: "partition", kib: 5, zram: true }]), "a line without a size skipped");
        assertEqual(rules.swaps(header + "/dev/zram0x partition 5 0 1\n")[0].zram, false, "only /dev/zram<n> is zram");
        assertEqual(json(rules.swaps(header + "/dev/sdb1 partition 100\n/dev/sdb2 200\n")), json([{ name: "/dev/sdb1", type: "partition", kib: 100, zram: false }]),
                    "three fields are enough; two are not a line");

        // ---- memory, lockdown, resume ----
        assertEqual(rules.memoryInUse("MemTotal:       32000000 kB\nMemFree:  100 kB\nMemAvailable:   20000000 kB\n"), 12000000,
                    "memory in use: total less available");
        assertEqual(rules.memoryInUse("MemTotal:       32000000 kB\n"), -1, "no MemAvailable: unread");
        assertEqual(rules.memoryInUse(""), -1, "not read");
        assertEqual(rules.memoryInUse("MemTotal: 0 kB\nMemAvailable: 0 kB\n"), 0, "nothing at all: 0, read");
        assertEqual(rules.memoryInUse("MemTotal: 100 kB\nMemAvailable: 0 kB\n"), 100, "nothing available: all in use");
        assertEqual(rules.memoryInUse("MemTotal: 100 kB\nMemAvailable: 100 kB\n"), 0, "all available: none in use");
        assertEqual(rules.lockdown("[none] integrity confidentiality\n"), "none", "lockdown none");
        assertEqual(rules.lockdown("none [integrity] confidentiality"), "integrity", "lockdown integrity");
        assertEqual(rules.lockdown("none integrity [confidentiality]"), "confidentiality", "lockdown confidentiality");
        assertEqual(rules.lockdown(""), "unknown", "not read");
        assertEqual(rules.resumeKnown("259:3\n", ""), true, "a resume device");
        assertEqual(rules.resumeKnown("8:0", ""), true, "… a major number alone");
        assertEqual(rules.resumeKnown("0:5", ""), true, "… a minor number alone");
        assertEqual(rules.resumeKnown("0:0\n", "BOOT_IMAGE=/vmlinuz root=UUID=x rw"), false, "none, none on the command line");
        assertEqual(rules.resumeKnown("0:0", "root=x resume=UUID=abc quiet"), true, "resume= on the command line");
        assertEqual(rules.resumeKnown("0:0", "root=x noresume=1"), false, "noresume= is not resume=");
        assertEqual(rules.resumeKnown("0:0", "resume= quiet"), false, "an empty resume=");
        assertEqual(rules.resumeKnown("", "resume=/dev/sda2"), "unknown", "the device not read: unknown");

        // ---- time spans ----
        const spans = { "7200": 7200, "2h": 7200, "1h 30min": 5400, "1h30min": 5400, "90 min": 5400, "1.5h": 5400, "45s": 45,
                        "1d": 86400, "2 hours": 7200, "500ms": 1, "1w": 604800, " 3h ": 10800,
                        "1500ms": 2, "1400msec": 1, "1500000us": 2, "1400000usec": 1, "30sec": 30, "1second": 1, "2 seconds": 2,
                        "2m": 120, "3min": 180, "1minute": 60, "4 minutes": 240, "1hr": 3600, "1hour": 3600, "2days": 172800,
                        "1day": 86400, "1week": 604800, "2weeks": 1209600 };
        for (const text of Object.keys(spans))
            assertEqual(rules.timeSpan(text), spans[text], "time span " + JSON.stringify(text));
        assertEqual(rules.timeSpan("0".repeat(99) + "7"), 7, "a hundred characters: still read");
        for (const text of ["", "infinity", "2M", "1y", "h2", "2 h junk", "2hh", "-5", null, "1".repeat(120), "0".repeat(100) + "7"])
            assertEqual(rules.timeSpan(text), null, "not a time span: " + JSON.stringify(text));

        // ---- sleep.conf with its drop-ins ----
        const main = "# /etc/systemd/sleep.conf\n[Sleep]\n#AllowSuspend=yes\n#HibernateDelaySec=\n";
        assertEqual(json(rules.hibernateDelay(main)), json({ state: "unset" }), "the main file's commented defaults: unset");
        assertEqual(json(rules.hibernateDelay(main + "\n# /etc/systemd/sleep.conf.d/h2s-shell.conf\n[Sleep]\nHibernateDelaySec=10800\n")),
                    json({ state: "set", seconds: 10800 }), "a drop-in sets it");
        assertEqual(json(rules.hibernateDelay(main + "[Sleep]\nHibernateDelaySec = 2h\n# /usr/lib/systemd/sleep.conf.d/z.conf\n[Sleep]\nHibernateDelaySec=45min\n")),
                    json({ state: "set", seconds: 2700 }), "the last one read wins");
        assertEqual(json(rules.hibernateDelay("[Sleep]\nHibernateDelaySec=2h\n[Sleep]\nHibernateDelaySec=\n")), json({ state: "unset" }),
                    "an empty assignment puts it back to unset");
        assertEqual(json(rules.hibernateDelay("[Other]\nHibernateDelaySec=2h\n")), json({ state: "unset" }), "only in [Sleep]");
        assertEqual(json(rules.hibernateDelay("[Sleep]\nHibernateDelaySec=soon\n")), json({ state: "unknown" }), "a value not understood: unknown");
        assertEqual(json(rules.hibernateDelay("")), json({ state: "unknown" }), "not read: unknown");
        assertEqual(json(rules.hibernateDelay("[Sleep]\n; HibernateDelaySec=1h\nHibernateDelaySecs=1h\n")), json({ state: "unset" }),
                    "a ; comment and another key: unset");

        // ---- why not ----
        const zram = rules.swaps(header + "/dev/zram0 partition 4194300 0 100\n");
        const disk = rules.swaps(header + "/swapfile file 16777212 0 -2\n/dev/zram0 partition 4194300 0 100\n");
        const facts = extra => Object.assign({ answer: "na", swaps: disk, memoryInUse: 8000000, lockdown: "none", resume: true }, extra);
        assertEqual(rules.unavailable(facts({ answer: "yes", swaps: zram })), "", "logind says yes: available, whatever was read");
        assertEqual(rules.unavailable(facts({ answer: "challenge" })), "Not available here: the system asks for a password to hibernate.",
                    "challenge: a password would be asked");
        assertEqual(rules.unavailable(facts({ answer: "no" })), "Not available here: the system does not allow it.", "no");
        for (const answer of ["unknown", undefined, "junk"])
            assertEqual(rules.unavailable(facts({ answer: answer })), "Not available here: the system did not say whether it can hibernate.",
                        "logind not read (" + answer + "): said so");
        assertEqual(rules.unavailable(facts({ swaps: zram })),
                    "Not available here: no swap space to save the session to (only zram, which is lost at power-off).",
                    "only zram");
        assertEqual(rules.unavailable(facts({ swaps: [] })), "Not available here: no swap space to save the session to.", "no swap");
        assertEqual(rules.unavailable(facts({ lockdown: "integrity", swaps: zram })), "Not available here: the kernel's lockdown (Secure Boot) forbids it.",
                    "lockdown first");
        assertEqual(rules.unavailable(facts({ lockdown: "confidentiality" })), "Not available here: the kernel's lockdown (Secure Boot) forbids it.",
                    "lockdown confidentiality");
        assertEqual(rules.unavailable(facts({ memoryInUse: 17000000 })), "Not available here: the swap space is smaller than the memory in use.",
                    "swap smaller than the memory in use (zram not counted)");
        assertEqual(rules.unavailable(facts({ memoryInUse: 16777212 })), "Not available here: this computer cannot hibernate.",
                    "swap as large as the memory in use: not that");
        assertEqual(rules.unavailable(facts({ memoryInUse: 16777213 })), "Not available here: the swap space is smaller than the memory in use.",
                    "… one KiB short: smaller");
        assertEqual(rules.unavailable(facts({ swaps: [{ name: "/odd", zram: false }], memoryInUse: 1 })),
                    "Not available here: the swap space is smaller than the memory in use.", "a swap without a size counts as none");
        assertEqual(rules.unavailable(facts({ resume: false })), "Not available here: the kernel has no resume device (resume=).", "no resume device");
        assertEqual(rules.unavailable(facts({ resume: "unknown", memoryInUse: -1 })), "Not available here: this computer cannot hibernate.",
                    "nothing read explains it");
        assertEqual(rules.unavailable(facts({ swaps: null, resume: false })), "Not available here: the kernel has no resume device (resume=).",
                    "swaps not read: not taken as no swap");

        // ---- the delay line ----
        const duration = seconds => seconds / 3600 + " h";
        assertEqual(rules.delayWords({ state: "set", seconds: 7200 }, duration), "2 h", "set");
        assertEqual(rules.delayWords({ state: "unset" }, duration), "not set: systemd's default", "unset");
        assertEqual(rules.delayWords({ state: "unknown" }, duration), "not read", "unread");
        assert(!rules.delayDiffers({ state: "set", seconds: 7200 }, 7200), "the same time: no Apply");
        assert(rules.delayDiffers({ state: "set", seconds: 7200 }, 10800), "another time: Apply");
        assert(rules.delayDiffers({ state: "unset" }, 7200), "unset: Apply");
        assert(rules.delayDiffers({ state: "unknown" }, 7200), "unread: Apply");
        assertEqual(rules.delayLine({ state: "set", seconds: 7200 }, false, duration),
                    "The time after sleeping is a system setting (now 2 h). Changing it asks for your password.", "Arch: Apply");
        assertEqual(rules.delayLine({ state: "set", seconds: 7200 }, true, duration),
                    "The time after sleeping is a system setting (now 2 h). On NixOS it is the option programs.h2s-shell.idle.hibernateDelay.",
                    "NixOS: the option");

        // ---- the Apply ----
        const argv = rules.applyArgv("/bin/sh", 10800, "/etc/systemd/sleep.conf.d");
        assertEqual(json(argv.slice(0, 2).concat(argv.slice(3))), json(["/bin/sh", "-c", "sh", "10800", "/etc/systemd/sleep.conf.d"]),
                    "the script's arguments: the delay and the directory");
        assertEqual(argv[2], rules.applyScript, "… the fixed script");
        assert(!/\$\(|`/.test(rules.applyScript.replace("$(mktemp", "")), "… no command substitution but mktemp's");
        assert(rules.applyArgv("/bin/sh", 60, "/etc") !== null && rules.applyArgv("/bin/sh", 86400, "/etc") !== null,
               "a minute and a day: the ends of the range, taken");
        for (const bad of [[ "sh", 10800, "/etc" ], [ "/bin/sh", 59, "/etc" ], [ "/bin/sh", 86401, "/etc" ], [ "/bin/sh", 7200.5, "/etc" ],
                           [ "/bin/sh", "7200", "/etc" ], [ "/bin/sh", 7200, "etc" ], [ "/bin/sh", 7200, "/etc/../root" ],
                           [ "/bin/sh", 7200, "/etc/x y" ], [ "/bin/sh", 7200, "/etc/$(id)" ], [ "/bin/sh", 7200, null ]])
            assertEqual(rules.applyArgv(bad[0], bad[1], bad[2]), null, "refused: " + JSON.stringify(bad));
        assertEqual(rules.dropInText(10800), "# Written by h2s-shell: Settings, When away, Hibernate\n[Sleep]\nHibernateDelaySec=10800\n",
                    "the drop-in's text");
        assertEqual(json(rules.hibernateDelay(rules.dropInText(10800))), json({ state: "set", seconds: 10800 }), "… read back as written");
        assertEqual(json(rules.applyOutcome({ ok: true, stdout: "written 10800\n" }, 10800)), json({ ok: true, quiet: false, error: "" }), "written");
        assertEqual(rules.applyOutcome({ ok: true, stdout: "written 7200\n" }, 10800).ok, false, "another delay said: not ok");
        assertEqual(rules.applyOutcome({ ok: true, stdout: "" }, 10800).ok, false, "nothing said: not ok");
        for (const quiet of [{ dismissed: true }, { refused: true }, { cancelled: true }, { blocked: "locked" }])
            assertEqual(json(rules.applyOutcome(Object.assign({ ok: false, code: 126 }, quiet), 10800)), json({ ok: false, quiet: true, error: "" }),
                        "quiet: " + json(quiet));
        assertEqual(rules.applyOutcome({ ok: false, code: 1, stderr: "mkdir: cannot create\nmv: read-only file system\n", error: "" }, 10800).error,
                    "mv: read-only file system", "a failure: its last line");
        assertEqual(json(rules.applyOutcome({ ok: false, code: 3, stderr: "", error: "" }, 10800)), json({ ok: false, quiet: false, error: "exit code 3" }),
                    "a failure without words: said, not quiet");
        assertEqual(rules.applyOutcome({}, 10800).error, "exit code -1", "no answer at all: no code");
        assertEqual(rules.applyOutcome({ ok: false, error: "pkexec could not be started" }, 10800).error, "pkexec could not be started", "the runner's error");
    }
}
