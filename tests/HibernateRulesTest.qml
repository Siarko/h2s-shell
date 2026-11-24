import QtQuick
import qs.distributions.arch
import qs.distributions.generic
import qs.distributions.nixos
import qs.singletons

// Hibernation's reading and writing rules (singletons/HibernateRules.qml): the swap tables,
// memory, lockdown and resume reads, systemd time spans, sleep.conf's delay through its
// drop-ins, the reason shown when it is not possible, the drop-in's text, and what the
// Hibernate section offers by each shipped distribution's capability (Arch applies, NixOS
// names the option, generic says why not) and what is in force.
TestCase {
    id: suite
    suiteName: "HibernateRules"

    property Component _arch: Component {
        ArchIntegration {}
    }
    property Component _nixos: Component {
        NixosIntegration {}
    }
    property Component _generic: Component {
        GenericIntegration {}
    }

    // The offer under the times, from the integrations' own capabilities
    function _offers(rules, duration) {
        const kind = "sleep.hibernateDelay";
        const json = value => JSON.stringify(value);
        const made = [_arch.createObject(suite), _nixos.createObject(suite), _generic.createObject(suite)];
        const [arch, nixos, generic] = made.map(integration => integration.capability(kind));
        const hint = made[1].plan(kind, 10800).preview.hint;
        made.forEach(integration => integration.destroy());
        const ours = "/etc/systemd/sleep.conf.d/h2s-shell.conf";
        const absent = { state: "absent", text: null, sha256: "absent", ours: false };
        const shells = { state: "text", text: rules.dropInText(3600), sha256: "a".repeat(64), ours: true };
        const edited = { state: "text", text: "[Sleep]\nHibernateDelaySec=1h\n", sha256: "b".repeat(64), ours: false };
        const read = (file, extra) => Object.assign({ state: "set", value: 7200, from: "/etc/systemd/sleep.conf", elsewhere: "", file, afterOwn: false }, extra ?? {});
        const set = { state: "set", seconds: 7200 };
        const offer = (extra) => rules.delayOffer(Object.assign({ delay: set, picked: 10800, differs: true, capability: arch, hint: "",
                                                                    inForce: read(absent), busy: "", undoable: false }, extra ?? {}), duration);

        // Arch: Apply, its effect the request it shows
        let answer = offer();
        assertEqual(answer.line, "Picked 3 h; the system now hibernates after 2 h. Apply to change it.", "Arch: the picked time after Apply");
        assert(answer.shown && answer.apply.button === "plain" && answer.apply.label === "Apply" && answer.apply.available, "… Apply on the click");
        assertEqual(json(answer.apply.request), json({ seconds: 10800, current: absent, replace: false }),
                    "… its effect: the time picked, checked against the file as read, nothing replaced");
        assert(!answer.undo.shown, "… no Undo before a change");
        answer = offer({ inForce: read(shells, { from: ours }) });
        assert(answer.apply.button === "plain" && answer.apply.request.current === shells, "the shell's own file sets it: Apply over it, no question");
        assertEqual(offer({ delay: { state: "unset" }, inForce: read(absent, { state: "default", value: null, from: "" }) }).line,
                    "Picked 3 h; the system's delay is not set (systemd's default). Apply to change it.", "unset: said, Apply offered");
        // Set in a file read after the shell's: shown, Apply could not win
        answer = offer({ inForce: read(absent, { from: "/etc/systemd/sleep.conf.d/zz.conf", elsewhere: "/etc/systemd/sleep.conf.d/zz.conf", afterOwn: true }) });
        assertEqual(answer.line, "Picked 3 h. Set in /etc/systemd/sleep.conf.d/zz.conf: 2 h; it is read after the shell's file.",
                    "set in a file read after the shell's: named with its value");
        assert(answer.shown && answer.apply.button === "none" && answer.apply.request === null, "… no Apply (it could not win)");
        answer = offer({ inForce: read(absent, { state: "default", value: null, from: "/run/x.conf", elsewhere: "/run/x.conf", afterOwn: true }) });
        assertEqual(answer.line, "Picked 3 h. Set in /run/x.conf: systemd's default; it is read after the shell's file.", "… a file putting the default back: named too");
        assertEqual(answer.apply.button, "none", "… no Apply");
        answer = offer({ inForce: read(absent, { elsewhere: "/etc/systemd/sleep.conf", afterOwn: undefined }) });
        assertEqual(answer.apply.button, "none", "… not told whether it is read after: no Apply");
        // Set in a file read before it: warned, Apply asks first
        answer = offer({ inForce: read(absent, { elsewhere: "/etc/systemd/sleep.conf" }) });
        assertEqual(answer.line, "Picked 3 h. Set in /etc/systemd/sleep.conf: 2 h.", "set in the user's own sleep.conf: named with its value");
        assert(answer.apply.button === "ask" && answer.apply.question === "Use the shell's value instead?", "… Apply asks first");
        assertEqual(json(answer.apply.request), json({ seconds: 10800, current: absent, replace: false }), "… the shell's own file written, nothing else replaced");
        answer = offer({ inForce: read(edited, { elsewhere: "/etc/systemd/sleep.conf" }) });
        assertEqual(answer.line, "Picked 3 h. Set in /etc/systemd/sleep.conf: 2 h. " + ours + " was changed outside the shell: Apply replaces it.",
                    "… and the shell's file edited by hand: both said");
        assert(answer.apply.button === "ask" && answer.apply.request.replace === true, "… one question, the file replaced");
        answer = offer({ inForce: read({ state: "unknown", text: null, sha256: "", ours: false }, { elsewhere: "/etc/systemd/sleep.conf" }) });
        assertEqual(answer.line + "|" + answer.apply.button, "Picked 3 h. Set in /etc/systemd/sleep.conf: 2 h.|none", "… the shell's file not read: no Apply");
        // The shell's file changed outside it: the question first
        answer = offer({ inForce: read(edited, { from: ours }) });
        assertEqual(answer.line, "Picked 3 h; the system now hibernates after 2 h. " + ours + " was changed outside the shell: Apply replaces it.",
                    "the shell's file edited by hand: warned");
        assert(answer.apply.button === "ask" && answer.apply.question === "Replace?", "… Apply asks first");
        assertEqual(json(answer.apply.request), json({ seconds: 10800, current: edited, replace: true }), "… and replaces only that file as read");
        // What is in force not read: no Apply (another file may set it)
        for (const inForce of [null, read(absent, { state: "unknown", value: null, from: "" }), read(null), read({ state: "unknown", text: null, sha256: "", ours: false })]) {
            answer = offer({ inForce });
            assert(answer.shown && answer.apply.button === "none" && answer.apply.request === null, "not read: no Apply (" + json(inForce) + ")");
            assertEqual(answer.line, "Picked 3 h; the system now hibernates after 2 h.", "… nothing promised");
        }
        assertEqual(offer({ delay: { state: "unknown" }, inForce: null }).line, "Picked 3 h; the system's delay could not be read.", "unread: said");
        // Busy, Undo
        answer = offer({ busy: "apply" });
        assert(answer.apply.label === "Applying\u2026" && !answer.apply.available, "applying: said, not again");
        assert(!offer({ busy: "undo" }).apply.available && offer({ busy: "undo" }).apply.label === "Apply", "undoing: Apply not clickable, its label kept");
        answer = offer({ undoable: true });
        assert(answer.undo.shown && answer.undo.label === "Undo" && answer.undo.available, "after an Apply: Undo");
        answer = offer({ undoable: true, differs: false });
        assert(answer.shown && answer.undo.shown && answer.apply.button === "none", "… shown when the times agree now");
        assertEqual(answer.line, "Undo puts back " + ours + " as it was before the last Apply.", "… with a line saying what it undoes");
        assert(!offer({ undoable: true, busy: "undo" }).undo.available, "… not while one runs");
        answer = offer({ differs: false });
        assert(!answer.shown && answer.line === "", "the same time, nothing to undo: nothing shown");
        // NixOS: the integration's hint
        answer = offer({ capability: nixos, hint });
        assertEqual(answer.line, "Picked 3 h; the system now hibernates after 2 h. On NixOS it is the option programs.h2s-shell.idle.hibernateDelay.",
                    "NixOS: the option named, in the integration's words");
        assert(answer.apply.button === "none" && answer.apply.request === null && !offer({ capability: nixos, hint, undoable: true }).undo.shown,
               "… no Apply, no Undo");
        assertEqual(offer({ capability: nixos, hint: "" }).line, "Picked 3 h; the system now hibernates after 2 h.", "… no hint: nothing more said");
        assert(!offer({ capability: nixos, hint, inForce: read(absent, { elsewhere: "/etc/systemd/sleep.conf", afterOwn: true }) }).line.startsWith("Picked 3 h. Set in"),
               "… its generated sleep.conf is no setting of the user's to name");
        // Generic, and the distribution not known
        answer = offer({ capability: generic });
        assertEqual(answer.line, "Picked 3 h; the system now hibernates after 2 h. Not supported on this distribution.", "generic: why not");
        assert(answer.apply.button === "none" && !offer({ capability: generic, undoable: true }).undo.shown, "… no Apply, no Undo");
        answer = offer({ capability: IntegrationRules.unknownCapability() });
        assertEqual(answer.line, "Picked 3 h; the system now hibernates after 2 h.", "not known yet: nothing promised");
        assertEqual(answer.apply.button, "none", "… no Apply");

        // Which files systemd reads after the shell's drop-in
        for (const [path, after] of [["/etc/systemd/sleep.conf", false], ["/usr/lib/systemd/sleep.conf", false], ["/run/systemd/sleep.conf", false],
                                     ["/usr/local/lib/systemd/sleep.conf", false],
                                     ["/usr/lib/systemd/sleep.conf.d/10-vendor.conf", false], ["/etc/systemd/sleep.conf.d/aa.conf", false],
                                     ["/run/systemd/sleep.conf.d/50-x.conf", false], ["/run/systemd/sleep.conf.d/h2s-shell.conf", false],
                                     ["/etc/systemd/sleep.conf.d/zz-tlp.conf", true], ["/run/systemd/sleep.conf.d/i.conf", true],
                                     ["/usr/lib/systemd/sleep.conf.d/h2s-shell.confx.conf", true],
                                     ["/home/me/sleep.conf", true], ["", true], ["/etc/systemd/sleep.conf.d/x.txt", true], [null, true]])
            assertEqual(rules.readAfterDropIn(path), after, "read after the shell's drop-in: " + path + " → " + after);
    }

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
                    json({ state: "set", seconds: 10800, file: "/etc/systemd/sleep.conf.d/h2s-shell.conf" }), "a drop-in sets it, its file named");
        assertEqual(json(rules.hibernateDelay(main + "[Sleep]\nHibernateDelaySec = 2h\n# /usr/lib/systemd/sleep.conf.d/z.conf\n[Sleep]\nHibernateDelaySec=45min\n")),
                    json({ state: "set", seconds: 2700, file: "/usr/lib/systemd/sleep.conf.d/z.conf" }), "the last one read wins");
        assertEqual(json(rules.hibernateDelay("[Sleep]\nHibernateDelaySec=2h\n[Sleep]\nHibernateDelaySec=\n")), json({ state: "unset", file: "" }),
                    "an empty assignment puts it back to unset");
        assertEqual(json(rules.hibernateDelay("[Other]\nHibernateDelaySec=2h\n")), json({ state: "unset" }), "only in [Sleep]");
        assertEqual(json(rules.hibernateDelay("[Sleep]\nHibernateDelaySec=soon\n")), json({ state: "unknown" }), "a value not understood: unknown");
        assertEqual(json(rules.hibernateDelay("# /etc/systemd/sleep.conf\n[Sleep]\nHibernateDelaySec=2h\n# /etc/systemd/sleep.conf.d/x.conf\nHibernateDelaySec=5h\n")),
                    json({ state: "set", seconds: 7200, file: "/etc/systemd/sleep.conf" }),
                    "a file's assignment before any header of its own is outside [Sleep], as systemd reads it");
        assertEqual(rules.hibernateDelay("#  /run/systemd/sleep.conf.d/\u0007odd.conf\n[Sleep]\nHibernateDelaySec=1h\n").file,
                    "/run/systemd/sleep.conf.d/ odd.conf", "the file's path on one line");
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
        _offers(rules, duration);
        // What will happen: the system's delay with sleep on, until Apply
        const fromSleep = { on: true, from: "sleep", at: 1800, after: 10800 };
        assertEqual(JSON.stringify(rules.inEffect(fromSleep, { state: "set", seconds: 7200, file: "x" })),
                    JSON.stringify({ on: true, from: "sleep", at: 1800, after: 7200 }), "sleep on: the system's delay in effect");
        assertEqual(fromSleep.after, 10800, "… the profile's left as it was");
        assertEqual(rules.inEffect(fromSleep, { state: "unset" }), fromSleep, "the delay unset: the profile's (nothing better known)");
        assertEqual(rules.inEffect(fromSleep, { state: "unknown" }), fromSleep, "… unread: the same");
        const fromLock = { on: true, from: "lock", at: 1200, after: 7200 };
        assertEqual(rules.inEffect(fromLock, { state: "set", seconds: 60, file: "x" }), fromLock, "sleep off: the shell's own time, the delay does not apply");
        assertEqual(rules.inEffect(null, { state: "set", seconds: 60 }), null, "nothing given: nothing");

        // ---- the Apply's text ----
        assertEqual(rules.dropInText(10800), "# Written by h2s-shell: Settings, When away, Hibernate\n[Sleep]\nHibernateDelaySec=10800\n",
                    "the drop-in's text");
        assertEqual(json(rules.hibernateDelay(rules.dropInText(10800))), json({ state: "set", seconds: 10800, file: "" }), "… read back as written");
        assertEqual(json(rules.hibernateDelay("# /etc/systemd/sleep.conf.d/h2s-shell.conf\n" + rules.dropInText(10800))),
                    json({ state: "set", seconds: 10800, file: "/etc/systemd/sleep.conf.d/h2s-shell.conf" }),
                    "… under cat-config's path line: its own first line is no path");
    }
}
