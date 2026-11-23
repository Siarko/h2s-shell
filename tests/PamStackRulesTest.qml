import QtQuick
import qs.singletons

// PamStackRules on fixture texts only: the real /etc/pam.d is never read
TestCase {
    suiteName: "PamStackRules"

    function run() {
        // The directories are always handed in (the distribution's): these cases read as on
        // Arch where they name none
        const archDirectories = ["/etc/pam.d", "/usr/lib/pam.d"];
        const stackAsArch = (service, read, directoryList) => PamStackRules.stack(service, read, directoryList ?? archDirectories);
        const rules = new Proxy(PamStackRules, { get: (target, key) => key === "stack" ? stackAsArch : target[key] });
        const names = stack => stack.lines.map(line => line.moduleName).join(" ");
        const controls = stack => stack.lines.map(line => line.control).join(" | ");

        // --- one line ---
        let line = rules.parseLine("auth [success=1 default=bad] pam_unix.so try_first_pass nullok");
        assertEqual(line.controlKind + " " + line.control, "bracketed [success=1 default=bad]", "a bracketed control kept whole");
        assertEqual(JSON.stringify(line.actions), "{\"success\":\"1\",\"default\":\"bad\"}", "… its value=action pairs");
        assertEqual(line.module + " " + line.args.join(","), "pam_unix.so try_first_pass,nullok", "… module and arguments after it");
        line = rules.parseLine("-auth  sufficient  /usr/lib/security/pam_fprintd.so timeout=10");
        assertEqual([line.optional, line.type, line.control, line.controlKind, line.moduleName].join(" "),
                    "true auth sufficient simple pam_fprintd.so", "-auth: optional, the module's name from its path");
        line = rules.parseLine("AUTH Required pam_env.so");
        assertEqual(line.type + " " + line.control, "auth required", "type and control word without case, as libpam");
        line = rules.parseLine("auth [ success=done   default=ignore ] pam_fprintd.so");
        assertEqual(JSON.stringify(line.actions), "{\"success\":\"done\",\"default\":\"ignore\"}", "spaces inside the brackets");
        assertEqual(JSON.stringify(rules.logicalLines("auth required \\  \t\n  pam_unix.so\nauth required pam_env.so")),
                    JSON.stringify([{ number: 1, text: "auth required    pam_unix.so" }, { number: 3, text: "auth required pam_env.so" }]),
                    "a backslash with white space after it goes on");
        assertEqual(JSON.stringify(rules.logicalLines("auth required \\  \t\n\n  pam_unix.so\n")),
                    JSON.stringify([{ number: 1, text: "auth required" }, { number: 3, text: "pam_unix.so" }]),
                    "a blank line ends the line being continued, as in libpam");
        assertEqual(JSON.stringify(rules.logicalLines("auth required \\\n# a comment\n  pam_unix.so")),
                    JSON.stringify([{ number: 1, text: "auth required" }, { number: 3, text: "pam_unix.so" }]),
                    "… a comment line too");
        assertEqual(JSON.stringify(rules.logicalLines("auth required \\ # why\n pam_unix.so")),
                    JSON.stringify([{ number: 1, text: "auth required \\" }, { number: 2, text: "pam_unix.so" }]),
                    "a backslash before a comment is no continuation: two lines");
        assert(rules.parseLine(rules.logicalLines("auth required \\ # why\n pam_unix.so")[1].text).error !== undefined, "… the second a bad line");
        for (const ending of ["auth required \\", "auth required \\\n", "auth required pam_env.so\nauth required \\  \n"]) {
            const items = rules.logicalLines(ending);
            assertEqual(items[items.length - 1].unfinished, true, "a continuation open at the end of the file: unfinished (" + JSON.stringify(ending) + ")");
        }
        assertEqual(rules.logicalLines("auth required pam_env.so\n").length, 1, "a final newline is the end of the file, not a blank line");
        let unfinished = rules.stack("sudo", { "/etc/pam.d/sudo": "auth required pam_env.so\nauth required \\\n" });
        assertEqual(unfinished.known + " " + unfinished.problems[0].reason + " " + unfinished.problems[0].line, "false unparsable 2",
                    "… and makes the file unparsable: the stack not known");
        assertEqual(JSON.stringify(rules.parseLine("auth [success = ok default = ignore] pam_unix.so").actions),
                    "{\"success\":\"ok\",\"default\":\"ignore\"}", "spaces around = inside brackets, as libpam takes them");
        assertEqual(JSON.stringify(rules.controlActions("[default=done default=bad success=ok success=bad]")),
                    "{\"default\":\"done\",\"success\":\"bad\"}", "as libpam: the first default counts, a value named again takes its last action");
        line = rules.parseLine("auth required pam_exec.so [query=select x from y] quiet");
        assertEqual(JSON.stringify(line.args), "[\"query=select x from y\",\"quiet\"]", "a bracketed argument kept as one, without its brackets, as libpam hands it");
        assertEqual(rules.parseLine("auth required pam_exec.so [a\\]b]").args[0], "a]b", "… an escaped bracket inside it unescaped");
        for (const typo of ["[sucess=1 default=ignore]", "[success=1 Default=ignore]", "[success=OK]", "[success=skip]", "[success=0]", "[]"])
            assert(rules.parseLine("auth " + typo + " pam_unix.so").error !== undefined, "a bracketed control libpam refuses: " + typo);
        assertEqual(JSON.stringify(rules.parseLine("auth [new_authtok_reqd=done user_unknown=reset default=12] pam_unix.so").actions),
                    "{\"new_authtok_reqd\":\"done\",\"user_unknown\":\"reset\",\"default\":\"12\"}", "… return-code names, reset and a jump count taken");
        assertEqual(rules.parseLine("@include common-auth").target, "common-auth", "@include");
        assertEqual(rules.parseLine("auth substack system-auth").controlKind, "substack", "substack");
        assert(rules.parseLine("auth [success=1 pam_unix.so").error !== undefined, "an unclosed bracket: an error");
        assert(rules.parseLine("auth [success] pam_unix.so").error !== undefined, "a bracket without value=action: an error");
        assert(rules.parseLine("auth sometimes pam_unix.so").error !== undefined, "an unknown control word: an error");
        assert(rules.parseLine("login required pam_unix.so").error !== undefined, "an unknown type: an error");
        assert(rules.parseLine("auth required").error !== undefined, "no module: an error");
        assert(rules.parseLine("auth include").error !== undefined, "include without a file: an error");
        const logical = rules.logicalLines("auth required \\\n  pam_unix.so nullok # comment\n\n# only a comment\naccount required pam_unix.so");
        assertEqual(JSON.stringify(logical), JSON.stringify([{ number: 1, text: "auth required    pam_unix.so nullok" },
                                                             { number: 5, text: "account required pam_unix.so" }]),
                    "a backslash goes on in the next line; comments and empty lines go");

        // --- Arch: polkit-1 only in the vendor directory, include system-auth with faillock ---
        const archSystemAuth = "#%PAM-1.0\n\n"
            + "auth       required                    pam_faillock.so      preauth\n"
            + "# Optionally use requisite above if you do not want to prompt for the password\n"
            + "-auth      [success=2 default=ignore]  pam_systemd_home.so\n"
            + "auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok\n"
            + "auth       [default=die]               pam_faillock.so      authfail\n"
            + "auth       optional                    pam_permit.so\n"
            + "auth       required                    pam_env.so\n"
            + "auth       required                    pam_faillock.so      authsucc\n\n"
            + "-account   [success=1 default=ignore]  pam_systemd_home.so\n"
            + "account    required                    pam_unix.so\n"
            + "password   required                    pam_unix.so          try_first_pass nullok shadow\n"
            + "session    required                    pam_unix.so\n";
        const archPolkit = "#%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\n"
            + "password   include      system-auth\nsession    include      system-auth\n";
        const arch = {
            "/etc/pam.d/system-auth": archSystemAuth,
            "/usr/lib/pam.d/polkit-1": archPolkit
        };
        let stack = rules.stack("polkit-1", arch);
        assert(stack.known, "Arch polkit-1: known");
        assertEqual(stack.file, "/usr/lib/pam.d/polkit-1", "… found in the vendor directory");
        assertEqual(names(stack), "pam_faillock.so pam_systemd_home.so pam_unix.so pam_faillock.so pam_permit.so pam_env.so pam_faillock.so",
                    "… system-auth's auth lines, in order, no account/password/session");
        assertEqual(controls(stack), "required | [success=2 default=ignore] | [success=1 default=bad] | [default=die] | optional | required | required",
                    "… their control words");
        assertEqual(stack.lines[1].optional, true, "… -auth kept as optional");
        assertEqual(JSON.stringify(stack.lines[2].via), "[{\"file\":\"/usr/lib/pam.d/polkit-1\",\"line\":3}]", "… the include line that led there");
        assertEqual(stack.lines[2].file + ":" + stack.lines[2].line, "/etc/pam.d/system-auth:6", "… where each line is");
        assertEqual(JSON.stringify(stack.files), "[\"/usr/lib/pam.d/polkit-1\",\"/etc/pam.d/system-auth\"]", "… the files read");
        assertEqual(stack.faillock.present, true, "… pam_faillock present");
        assertEqual(stack.faillock.at.map(item => item.index + ":" + item.phase).join(" "), "0:preauth 3:authfail 6:authsucc", "… and where");
        assertEqual(stack.block, null, "… no block of ours");
        assertEqual(PolkitRules.pamStackOrderOf(stack), "password", "… PolkitRules: no reader, now that the include is followed");
        assertEqual(PolkitRules.pamStackOrder(archPolkit), "", "… the text alone still not known");

        // A file in /etc/pam.d shadows the vendor's of the same name
        stack = rules.stack("polkit-1", Object.assign({
            "/etc/pam.d/polkit-1": "# Written by h2s-shell abc123\nauth sufficient pam_fprintd.so\nauth include system-auth\n"
        }, arch));
        assertEqual(stack.file, "/etc/pam.d/polkit-1", "Arch with our polkit-1: /etc/pam.d wins");
        assertEqual(JSON.stringify(stack.writtenBy), "{\"hash\":\"abc123\"}", "… written by us, its hash");
        assertEqual(PolkitRules.pamStackOrderOf(stack), "fingerprint-first", "… the reader first");
        assertEqual(rules.stack("polkit-1", arch, ["/etc/pam.d"]).known, false, "with NixOS's directories only, the vendor file is not seen");

        // Our block in sudo
        const blockLines = "auth sufficient pam_fprintd.so timeout=10 max-tries=3\nauth sufficient pam_unix.so try_first_pass";
        stack = rules.stack("sudo", Object.assign({
            "/etc/pam.d/sudo": "#%PAM-1.0\n# BEGIN h2s-shell 5f2e\n" + blockLines + "\n# END h2s-shell\nauth include system-auth\naccount include system-auth\n"
        }, arch));
        assertEqual(stack.block.hash + " " + stack.block.beginLine + "-" + stack.block.endLine + " " + stack.block.complete,
                    "5f2e 2-5 true", "sudo with our block: its hash, lines, complete");
        assertEqual(stack.block.body, blockLines, "… its body as written, for the hash");
        assertEqual(JSON.stringify(stack.block.authIndices), "[0,1]", "… its lines' places in the stack");
        assertEqual(stack.lines.length, 9, "… followed by system-auth's seven");
        assertEqual(stack.writtenBy, null, "… not a file written whole by us");
        let block = rules.ownBlock("# BEGIN h2s-shell\nauth sufficient pam_fprintd.so\n");
        assertEqual(block.hash + "|" + block.endLine + "|" + block.complete, "|-1|false", "a block without hash or end: incomplete");
        block = rules.ownBlock("# BEGIN h2s-shell a\n# END h2s-shell\n# BEGIN h2s-shell b\n# END h2s-shell\n");
        assertEqual(block.complete, false, "two blocks: not complete");
        assertEqual(rules.ownBlock("# END h2s-shell\n").complete, false, "an end alone: not complete");
        assertEqual(rules.ownBlock("auth include system-auth\n"), null, "no markers: no block");
        assertEqual(rules.writtenBy("\n#%PAM-1.0\n# Written by h2s-shell x\n"), null, "Written by only as the first line");

        // --- NixOS: generated, absolute store paths, one directory ---
        const nixosPolkit = "# Account management.\n"
            + "account required /nix/store/aaa-linux-pam-1.6.1/lib/security/pam_unix.so # unix (order 10900)\n\n"
            + "# Authentication management.\n"
            + "auth sufficient /nix/store/bbb-fprintd-1.94.4/lib/security/pam_fprintd.so # fprintd (order 11400)\n"
            + "auth sufficient /nix/store/aaa-linux-pam-1.6.1/lib/security/pam_unix.so likeauth try_first_pass # unix (order 11700)\n"
            + "auth required /nix/store/aaa-linux-pam-1.6.1/lib/security/pam_deny.so # deny (order 12500)\n\n"
            + "# Password management.\npassword sufficient /nix/store/aaa-linux-pam-1.6.1/lib/security/pam_unix.so nullok yescrypt # unix (order 10200)\n";
        stack = rules.stack("polkit-1", { "/etc/pam.d/polkit-1": nixosPolkit }, rules.nixosDirectories);
        assert(stack.known, "NixOS polkit-1: known");
        assertEqual(names(stack), "pam_fprintd.so pam_unix.so pam_deny.so", "… the auth lines, names from store paths");
        assertEqual(stack.lines[0].module, "/nix/store/bbb-fprintd-1.94.4/lib/security/pam_fprintd.so", "… the module's full path kept");
        assertEqual(JSON.stringify(stack.lines[1].args), "[\"likeauth\",\"try_first_pass\"]", "… the order comment is not an argument");
        assertEqual(stack.faillock.present, false, "… no pam_faillock, known");
        assertEqual(PolkitRules.pamStackOrderOf(stack), "fingerprint-first", "… PolkitRules: the reader first");

        // --- Debian: @include common-auth ---
        const debian = {
            "/etc/pam.d/sudo": "#%PAM-1.0\n\n# Set up user limits from /etc/security/limits.conf.\nsession    required   pam_limits.so\n\n"
                + "session    required   pam_env.so readenv=1 user_readenv=0\n\n"
                + "@include common-auth\n@include common-account\n@include common-session-noninteractive\n",
            "/etc/pam.d/common-auth": "# here are the per-package modules (the \"Primary\" block)\n"
                + "auth\t[success=2 default=ignore]\tpam_fprintd.so max-tries=1 timeout=10 # debug\n"
                + "auth\t[success=1 default=ignore]\tpam_unix.so nullok try_first_pass\n"
                + "auth\trequisite\t\t\tpam_deny.so\nauth\trequired\t\t\tpam_permit.so\nauth\toptional\t\t\tpam_cap.so\n",
            "/etc/pam.d/common-account": "account\t[success=1 new_authtok_reqd=done default=ignore]\tpam_unix.so\naccount\trequisite\t\t\tpam_deny.so\n",
            "/etc/pam.d/common-session-noninteractive": "session\trequired\tpam_unix.so\n"
        };
        stack = rules.stack("sudo", debian);
        assert(stack.known, "Debian sudo: known");
        assertEqual(names(stack), "pam_fprintd.so pam_unix.so pam_deny.so pam_permit.so pam_cap.so", "… common-auth's auth lines through @include");
        assertEqual(JSON.stringify(stack.lines[0].args), "[\"max-tries=1\",\"timeout=10\"]", "… tabs separate, the comment goes");
        assertEqual(stack.files.length, 4, "… every @include read (only auth lines kept)");
        assertEqual(PolkitRules.pamStackOrderOf(stack), "fingerprint-first", "… the reader first");

        // --- Fedora: authselect's system-auth (a symlink: the reader sees through it) ---
        const fedora = {
            "/etc/pam.d/sudo": "#%PAM-1.0\nauth       include      system-auth\naccount    include      system-auth\n"
                + "password   include      system-auth\nsession    optional     pam_keyinit.so revoke\nsession    required     pam_limits.so\n"
                + "session    include      system-auth\n",
            "/etc/pam.d/system-auth": "# Generated by authselect\n# Do not modify this file manually, use authselect instead. Any user changes will be lost.\n\n"
                + "auth        required                                     pam_env.so\n"
                + "auth        required                                     pam_faildelay.so delay=2000000\n"
                + "auth        [success=done default=ignore]                pam_fprintd.so\n"
                + "auth        [default=1 ignore=ignore success=ok]         pam_usertype.so isregular\n"
                + "auth        [default=1 ignore=ignore success=ok]         pam_localuser.so\n"
                + "auth        sufficient                                   pam_unix.so nullok\n"
                + "auth        [default=1 ignore=ignore success=ok]         pam_usertype.so isregular\n"
                + "auth        sufficient                                   pam_sss.so forward_pass\n"
                + "auth        required                                     pam_deny.so\n\n"
                + "account     required                                     pam_unix.so\n"
        };
        stack = rules.stack("sudo", fedora);
        assert(stack.known, "Fedora sudo: known");
        assertEqual(names(stack), "pam_env.so pam_faildelay.so pam_fprintd.so pam_usertype.so pam_localuser.so pam_unix.so pam_usertype.so pam_sss.so pam_deny.so",
                    "… authselect's auth lines in order");
        assertEqual(JSON.stringify(stack.lines[3].actions), "{\"default\":\"1\",\"ignore\":\"ignore\",\"success\":\"ok\"}", "… a three-pair bracket");
        assertEqual(stack.faillock.present, false, "… without faillock: known absent");

        // --- substack and an absolute include ---
        stack = rules.stack("sudo", {
            "/etc/pam.d/sudo": "auth substack /etc/pam.d/inner\nauth required pam_env.so\n",
            "/etc/pam.d/inner": "auth sufficient pam_unix.so\n"
        });
        assertEqual(names(stack) + " " + stack.lines[0].substack + " " + stack.lines[1].substack, "pam_unix.so pam_env.so true false",
                    "a substack's lines marked, an absolute path taken as it is");
        assertEqual(stack.lines[0].depth, 1, "… their depth");

        // --- a reader function, and a reader that fails ---
        stack = rules.stack("sudo", path => path === "/usr/lib/pam.d/sudo" ? "auth required pam_unix.so\n" : undefined);
        assertEqual(stack.file + " " + names(stack), "/usr/lib/pam.d/sudo pam_unix.so", "a reader function: asked in the directories' order");
        stack = rules.stack("sudo", path => { throw new Error("denied"); });
        assertEqual(stack.known + " " + stack.problems[0].reason, "false unreadable", "a reader that throws: unreadable by us, not known");

        // --- unreadable by us is not absent: root-run libpam may read it, so the vendor file is not taken ---
        stack = rules.stack("sudo", { "/etc/pam.d/sudo": null, "/usr/lib/pam.d/sudo": "auth sufficient pam_permit.so\n" });
        assertEqual([stack.known, stack.problems[0].reason, stack.problems[0].target, stack.lines.length].join(" "),
                    "false unreadable /etc/pam.d/sudo 0", "an /etc/pam.d/sudo we cannot read: not known (libpam, as root, may run it), the vendor file not taken");
        stack = rules.stack("sudo", { "/etc/pam.d/sudo": undefined, "/usr/lib/pam.d/sudo": "auth required pam_unix.so\n" });
        assertEqual(stack.known + " " + stack.file, "true /usr/lib/pam.d/sudo", "undefined: no such file, the next directory");
        stack = rules.stack("polkit-1", { "/usr/lib/pam.d/polkit-1": archPolkit, "/etc/pam.d/system-auth": null, "/usr/lib/pam.d/system-auth": archSystemAuth });
        assertEqual([stack.known, stack.problems[0].reason, stack.problems[0].target, stack.lines.length].join(" "),
                    "false unreadable /etc/pam.d/system-auth 0", "… an include too");
        assertEqual(stack.faillock.present, null, "… pam_faillock not known");

        // --- a missing include: unknown, never "no such lines" ---
        stack = rules.stack("polkit-1", { "/usr/lib/pam.d/polkit-1": archPolkit });
        assertEqual(stack.known, false, "Arch without system-auth readable: not known");
        const gap = stack.problems[0];
        assertEqual([gap.reason, gap.file, gap.line, gap.target].join(" "), "missing /usr/lib/pam.d/polkit-1 3 system-auth",
                    "… the problem says which include, where");
        assertEqual(stack.faillock.present, null, "… pam_faillock not known, not absent");
        assertEqual(PolkitRules.pamStackOrderOf(stack), "", "… PolkitRules: not known");
        stack = rules.stack("sudo", { "/etc/pam.d/sudo": "auth sufficient pam_unix.so\nauth include gone\nauth sufficient pam_fprintd.so\n" });
        assertEqual(stack.unknownAt + " " + stack.lines.length, "1 2", "lines after a gap kept, unknownAt says where the gap is");
        assertEqual(PolkitRules.pamStackOrderOf(stack), "", "… a password alone before the gap: not known (a reader may follow in it)");
        stack = rules.stack("sudo", { "/etc/pam.d/sudo": "auth sufficient pam_unix.so\nauth sufficient pam_fprintd.so\nauth include gone\n" });
        assertEqual(PolkitRules.pamStackOrderOf(stack), "password-first", "… both before the gap, the password first: password-first");
        stack = rules.stack("sudo", { "/etc/pam.d/sudo": "auth sufficient pam_fprintd.so\nauth include gone\nauth sufficient pam_unix.so\n" });
        assertEqual(PolkitRules.pamStackOrderOf(stack), "fingerprint-first", "… the reader before the gap: fingerprint-first");
        stack = rules.stack("sudo", {});
        assertEqual(stack.known + " " + stack.problems[0].reason + " " + stack.file, "false missing ", "no service file: not known");
        assertEqual(rules.stack("sudo", { "/etc/pam.d/sudo": "auth include ../shadow\n" }).problems[0].reason, "missing",
                    "a relative name with a slash is never looked up");

        // --- a cycle and the depth limit ---
        stack = rules.stack("a", {
            "/etc/pam.d/a": "auth required pam_env.so\nauth include b\n",
            "/etc/pam.d/b": "auth include a\nauth sufficient pam_unix.so\n"
        });
        assertEqual(stack.known + " " + stack.problems[0].reason + " " + stack.problems[0].target, "false cycle /etc/pam.d/a",
                    "a cycle: not known, where it closes");
        assertEqual(names(stack), "pam_env.so pam_unix.so", "… the walk ends");
        const chain = count => {
            const files = {};
            for (let i = 0; i < count; i++)
                files["/etc/pam.d/s" + i] = "auth include s" + (i + 1) + "\n";
            files["/etc/pam.d/s" + count] = "auth sufficient pam_unix.so\n";
            return files;
        };
        stack = rules.stack("s0", chain(15));
        assertEqual(stack.known + " " + names(stack), "true pam_unix.so", "fifteen includes deep: libpam reads it");
        stack = rules.stack("s0", chain(16));
        assertEqual(stack.known + " " + stack.problems[0].reason, "false depth", "sixteen: deeper than libpam allows, not known");
        stack = rules.stack("self", { "/etc/pam.d/self": "@include self\n" });
        assertEqual(stack.problems[0].reason, "cycle", "a file including itself: a cycle");
        stack = rules.stack("wide", { "/etc/pam.d/wide": "auth required pam_env.so\n".repeat(rules.maxLines + 5) });
        assertEqual(stack.known + " " + stack.problems[0].reason + " " + stack.lines.length, "false too long " + rules.maxLines, "too many lines: not known");

        // --- a line libpam would not take: the stack is not known ---
        stack = rules.stack("sudo", { "/etc/pam.d/sudo": "auth sufficient pam_fprintd.so\nauth sometimes pam_unix.so\n" });
        assertEqual(stack.known + " " + stack.problems[0].reason + " " + stack.problems[0].line, "false unparsable 2", "an unparsable line: not known, its place");

        // --- faillock.conf ---
        const settings = config => config === null ? "null"
            : [config.deny, config.failInterval, config.unlockTime, config.rootUnlockTime, config.evenDenyRoot, config.silent].join(" ");
        assertEqual(settings(rules.faillockConfig("")), "3 900 600 600 false false", "no file: libpam's defaults");
        assertEqual(rules.faillockConfig(null), null, "not read: not known");
        assertEqual(settings(rules.faillockConfig("# deny = 9\ndeny = 5\nfail_interval=60 # one minute\nunlock_time  120\nsilent\neven_deny_root\n")),
                    "5 60 120 120 true true", "key = value, key=value, key value, flags; comments skipped");
        assertEqual(settings(rules.faillockConfig("unlock_time = never\nroot_unlock_time = 30\n")), "3 900 0 30 false false", "never: 0; root's own time");
        assertEqual(settings(rules.faillockConfig("deny = many\nfail_interval = 0\n")), "3 900 600 600 false false", "values libpam refuses: the defaults");
        assertEqual(rules.faillockConfig("deny = 0").deny, 0, "deny = 0 (never locks) kept");
        assertEqual(rules.faillockConfig("deny = 3 \\\nunlock_time = 5\n").unlockTime, 5, "faillock.conf has no continuation lines");
        assertEqual(settings(rules.faillockConfig("deny = 5\nunlock_time = 120\n", ["preauth", "deny=4", "unlock_time=60", "even_deny_root"])),
                    "4 900 60 60 true false", "the line's arguments override the file");
        assertEqual(rules.faillockConfig("deny = 5\n", ["preauth", "conf=/etc/security/other.conf"]), null, "conf= another file: this one not in force");
        assertEqual(rules.faillockConfPath(["authfail", "conf=/etc/security/other.conf"]), "/etc/security/other.conf", "… faillockConfPath names it");
        assertEqual(rules.faillockConfig("deny = 7\n", ["conf=/etc/security/other.conf"], "/etc/security/other.conf").deny, 7, "… and its text read with that path");
        assertEqual(rules.faillockConfPath(["preauth"]), "/etc/security/faillock.conf", "no conf=: the default file");
        stack = rules.stack("polkit-1", arch);
        assertEqual(settings(rules.faillockConfig("deny = 5\n", stack.lines[stack.faillock.at[0].index].args)), "5 900 600 600 false false",
                    "Arch's preauth line has no settings of its own: the file's");

        _reading(rules);
    }

    // The reading through scripts/pam-files.sh: its answer, the rounds, the methods script's
    // answers (PamStacksReadingTest runs the scripts themselves)
    function _reading(rules) {
        const names = stack => stack.lines.map(line => line.moduleName).join(" ");
        const ok = { ok: true, truncated: false };
        let answer = rules.filesAnswer(["directory\t/etc/pam.d", "directory\t/usr/lib/pam.d", "faillock\t/etc/security/faillock.conf",
                                        "file\t/etc/pam.d/sudo\ttext", "|auth include system-auth", "|", "end\t/etc/pam.d/sudo",
                                        "file\t/usr/lib/pam.d/sudo\tabsent", "file\t/etc/x\tunreadable",
                                        "file\t/etc/not-asked\ttext", "|auth required pam_deny.so", "end\t/etc/not-asked"],
                                       ok, ["/etc/pam.d/sudo", "/usr/lib/pam.d/sudo", "/etc/x", "/etc/never-answered"]);
        assertEqual(JSON.stringify(answer.places), JSON.stringify({ directories: ["/etc/pam.d", "/usr/lib/pam.d"], faillockPath: "/etc/security/faillock.conf" }),
                    "pam-files.sh's answer: the directories in order and faillock.conf");
        assertEqual(JSON.stringify(answer.answers["/etc/pam.d/sudo"]), JSON.stringify({ text: "auth include system-auth\n\n" }), "… a file's text, its blank line kept");
        assertEqual(JSON.stringify(answer.answers["/usr/lib/pam.d/sudo"]) + JSON.stringify(answer.answers["/etc/x"]),
                    "{\"absent\":true}{\"unreadable\":true}", "… absent and unreadable told apart");
        assertEqual(JSON.stringify(answer.answers["/etc/never-answered"]), "{\"unreadable\":true}", "… a path asked without a record: unreadable, never absent");
        assert(!("/etc/not-asked" in answer.answers), "… a record not asked for: ignored");
        answer = rules.filesAnswer(["file\t/etc/pam.d/sudo\ttext", "|auth required pam_unix.so"], ok, ["/etc/pam.d/sudo"]);
        assertEqual(JSON.stringify(answer.answers["/etc/pam.d/sudo"]), "{\"unreadable\":true}", "a text record without its end (cut off): unreadable");
        assertEqual(answer.places, null, "… no places in it: null");
        answer = rules.filesAnswer(["file\t/etc/pam.d/sudo\ttext", "|auth required pam_unix.so", "end\t/etc/pam.d/sudo"],
                                   { ok: false, code: 1 }, ["/etc/pam.d/sudo"]);
        assertEqual(JSON.stringify(answer.answers["/etc/pam.d/sudo"]), "{\"unreadable\":true}", "a run that failed: everything asked unreadable");
        answer = rules.filesAnswer(["directory\t/etc/pam.d"], { ok: true, truncated: true }, []);
        assertEqual(answer.places, null, "a run cut at its output limit: nothing taken");

        // The rounds: Arch's sudo needs system-auth, then faillock.conf
        const request = { services: ["sudo"], lock: {}, directories: ["/e", "/v"], faillockPath: "/f.conf" };
        const answers = {};
        let step = rules.readingStep(request, answers, false);
        assertEqual(step.pending.join(" "), "/e/sudo", "nothing read: the service's first place asked");
        answers["/e/sudo"] = { absent: true };
        step = rules.readingStep(request, answers, false);
        assertEqual(step.pending.join(" "), "/v/sudo", "absent there: the vendor directory next");
        answers["/v/sudo"] = { text: "auth include system-auth\n" };
        step = rules.readingStep(request, answers, false);
        assertEqual(step.pending.join(" "), "/e/system-auth", "then the include");
        answers["/e/system-auth"] = { text: "auth required pam_faillock.so preauth\nauth [success=1 default=bad] pam_unix.so\n" };
        step = rules.readingStep(request, answers, false);
        assertEqual(step.pending.join(" "), "/f.conf", "then faillock.conf, where pam-files.sh says it is");
        answers["/f.conf"] = { text: "deny = 4\n" };
        step = rules.readingStep(request, answers, false);
        assertEqual(step.pending.length, 0, "nothing more to read");
        assertEqual(step.services.sudo.known + " " + names(step.services.sudo), "true pam_faillock.so pam_unix.so", "… the stack known, from the vendor file");
        assertEqual(step.faillock.sudo.deny, 4, "… pam_faillock's settings read");
        answers["/f.conf"] = { absent: true };
        assertEqual(rules.readingStep(request, answers, false).faillock.sudo.deny, 3, "no faillock.conf: libpam's defaults");
        answers["/f.conf"] = { unreadable: true };
        assertEqual(rules.readingStep(request, answers, false).faillock.sudo, null, "an unreadable faillock.conf: not known");
        step = rules.readingStep(request, { "/e/sudo": { absent: true } }, true);
        assertEqual(step.pending.length + " " + step.services.sudo.known + " " + step.services.sudo.problems[0].reason, "0 false unreadable",
                    "rounds run out: what is not read is unreadable, the stack unknown");
        step = rules.readingStep({ services: ["sudo"], lock: {}, directories: [], faillockPath: "" }, {}, false);
        assertEqual(step.pending.length + " " + step.services.sudo.known + " " + step.services.sudo.file, "0 false ",
                    "no directories (the distribution not known): nothing asked, nothing found, the stack unknown — no default system's");
        assertEqual(PamStackRules.stack("sudo", { "/etc/pam.d/sudo": "auth required pam_unix.so\n" }).known, false,
                    "a stack read without directories: not found");
        assertEqual(PamStackRules.candidates("sudo").length, 0, "… no candidates either");
        step = rules.readingStep({ services: [], lock: { password: "/shell/pam/password", bad: "relative" }, directories: ["/e"] }, {}, false);
        assertEqual(step.pending.join(" ") + " " + Object.keys(step.lock).join(","), "/shell/pam/password password", "a lock config read at its own path; a relative one left out");

        // The methods script
        const exited = code => ({ ok: code === 0, code: code });
        let methods = rules.methodsAnswer(["password\t/etc/pam.d\tlogin", "fingerprint\t/etc/pam.d\th2s-shell-fingerprint"], exited(0));
        assertEqual([methods.known, methods.fingerprint, methods.securityKey].join(" "), "true ready absent", "a fingerprint line: ready; no u2f line: absent");
        assertEqual(JSON.stringify(methods.lock), JSON.stringify({ password: "/etc/pam.d/login", fingerprint: "/etc/pam.d/h2s-shell-fingerprint" }), "… the lock's configs");
        methods = rules.methodsAnswer(["password\t/s/pam\tpassword", "u2f\t/s/pam\tu2f"], exited(0));
        assertEqual(methods.securityKey + " " + methods.fingerprint, "ready absent", "a u2f line: the security key ready");
        methods = rules.methodsAnswer(["password\t/s/pam\tpassword", "fingerprint\t/s/pam\tfingerprint"], exited(1));
        assertEqual([methods.known, methods.fingerprint, methods.securityKey, Object.keys(methods.lock).length].join(" "), "false unknown unknown 0",
                    "the script failed (fprintd timed out): unknown, its lines not used");
        assertEqual(rules.methodsAnswer([], { failedToStart: true, code: -1 }).fingerprint, "unknown", "not started: unknown");
    }
}
