import QtQuick
import qs.singletons

// PamStackRules on fixture texts only: the real /etc/pam.d is never read
TestCase {
    suiteName: "PamStackRules"

    function run() {
        const rules = PamStackRules;
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
        line = rules.parseLine("auth required pam_exec.so [query=select x from y] quiet");
        assertEqual(JSON.stringify(line.args), "[\"[query=select x from y]\",\"quiet\"]", "a bracketed argument kept as one");
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
        stack = rules.stack("sudo", path => path === "/usr/lib/pam.d/sudo" ? "auth required pam_unix.so\n" : null);
        assertEqual(stack.file + " " + names(stack), "/usr/lib/pam.d/sudo pam_unix.so", "a reader function: asked in the directories' order");
        stack = rules.stack("sudo", path => { throw new Error("denied"); });
        assertEqual(stack.known + " " + stack.problems[0].reason, "false missing", "a reader that throws: not there, not known");

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
        assertEqual(PolkitRules.pamStackOrderOf(stack), "password-first", "… only the lines before it decide: the password came first");
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
        const deep = {};
        for (let i = 0; i < 30; i++)
            deep["/etc/pam.d/s" + i] = "auth include s" + (i + 1) + "\n";
        deep["/etc/pam.d/s30"] = "auth sufficient pam_unix.so\n";
        stack = rules.stack("s0", deep);
        assertEqual(stack.known + " " + stack.problems[0].reason, "false depth", "includes deeper than libpam allows: not known");
        stack = rules.stack("self", { "/etc/pam.d/self": "@include self\n" });
        assertEqual(stack.problems[0].reason, "cycle", "a file including itself: a cycle");
        stack = rules.stack("wide", { "/etc/pam.d/wide": "auth required pam_env.so\n".repeat(rules.maxLines + 5) });
        assertEqual(stack.known + " " + stack.problems[0].reason + " " + stack.lines.length, "false too long " + rules.maxLines, "too many lines: not known");

        // --- a line libpam would not take: the stack is not known ---
        stack = rules.stack("sudo", { "/etc/pam.d/sudo": "auth sufficient pam_fprintd.so\nauth sometimes pam_unix.so\n" });
        assertEqual(stack.known + " " + stack.problems[0].reason + " " + stack.problems[0].line, "false unparsable 2", "an unparsable line: not known, its place");

        // --- faillock.conf ---
        assertEqual(JSON.stringify(rules.faillockConfig("")), "{\"deny\":3,\"failInterval\":900,\"unlockTime\":600}", "no file: libpam's defaults");
        assertEqual(rules.faillockConfig(null), null, "not read: not known");
        assertEqual(JSON.stringify(rules.faillockConfig("# deny = 9\ndeny = 5\nfail_interval=60 # one minute\nunlock_time = 120\nsilent\n")),
                    "{\"deny\":5,\"failInterval\":60,\"unlockTime\":120}", "set values read, comments and flags skipped");
        assertEqual(rules.faillockConfig("unlock_time = never").unlockTime, 0, "unlock_time = never: 0");
        assertEqual(JSON.stringify(rules.faillockConfig("deny = many\nfail_interval = 0\n")), "{\"deny\":3,\"failInterval\":900,\"unlockTime\":600}",
                    "values libpam refuses: the defaults");
        assertEqual(rules.faillockConfig("deny = 0").deny, 0, "deny = 0 (never locks) kept");
    }
}
