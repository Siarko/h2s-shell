import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.io

// The reading behind PamStacks (singletons/io/PamStackReader.qml), run for real: copies of
// scripts/pam-files.sh and scripts/lock-auth-methods.sh with the test bed's seams.sh beside
// them, pointed at stand-in directories — Arch-, NixOS- and Debian-shaped — and a stand-in
// methods script (the methods script's own seam). A file that cannot be read (mode 000) and
// an include that is not there leave the stack unknown; the methods script failing leaves
// the fingerprint unknown; a refresh overtaken by another publishes nothing. The hint Settings shows follows the stack read (on Arch through
// `include system-auth`). Never the real /etc/pam.d, /usr/lib/pam.d, faillock.conf or
// fprintd. Asynchronous.
TestCase {
    id: suite
    suiteName: "PamStacksReading"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-pam-stacks-test-" + Date.now()
    readonly property string _tree: _scratch + "/tree/scripts"

    property var _reader: null
    property bool _ready: false
    property int _readingsBefore: 0

    property Component _readerComponent: Component {
        PamStackReader {}
    }

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 15000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        _reader?.destroy();
        _sh("chmod -R u+rwx \"$1\" 2> /dev/null; rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    // The next reading, of the system named (a directory under the scratch one), with the
    // methods stand-in answering `methods` (lines) and exiting with `code`
    function _readAs(system, nixos, withMethods, methods, code) {
        _ready = false;
        _sh("printf '%s' \"$2\" > \"$1/methods-out\"; printf '%s' \"$3\" > \"$1/methods-code\"",
            [_scratch, methods.map(line => line + "\n").join(""), String(code)], () => {
            suite._reader.environment = suite._environment(system, nixos);
            suite._readingsBefore = suite._reader.readings;
            suite._reader.refresh(withMethods);
            suite._ready = true;
        });
    }

    // The seams for the system named (a directory under the scratch one)
    function _environment(system, nixos) {
        const base = _scratch + "/" + system;
        return {
            H2S_LOCK_SYSTEM_PAM_DIR: base + "/etc",
            H2S_LOCK_VENDOR_PAM_DIR: base + "/usr",
            H2S_LOCK_FAILLOCK_CONF: base + "/faillock.conf",
            H2S_LOCK_SYSTEM: nixos ? "nixos" : "other",
            H2S_LOCK_AUTH_METHODS: _scratch + "/methods"
        };
    }

    function _answered() {
        return _ready && _reader.readings > _readingsBefore && !_reader.running;
    }

    function _names(stack) {
        return stack.lines.map(line => line.moduleName).join(" ");
    }

    function _order(reading) {
        return PolkitRules.pamStackOrderOf(reading.services["polkit-1"]);
    }

    function runAsync() {
        const arch = _scratch + "/arch";
        _then("the stand-ins are in place", () => _ready, () => {
            _reader = _readerComponent.createObject(suite, {
                filesCommand: [_tree + "/pam-files.sh"],
                methodsCommand: [_tree + "/lock-auth-methods.sh"],
                nixosCommand: [_tree + "/lock-auth-methods.sh", "--fallback-facts"]
            });
            assertEqual(_reader.reading, null, "before a refresh: nothing read");
            _readAs("arch", false, true, ["password\t" + _scratch + "/tree/pam\tpassword", "fingerprint\t" + arch + "/etc\th2s-shell-fingerprint"], 0);
        });
        _then("Arch read", () => _answered(), () => {
            const reading = _reader.reading;
            const polkit = reading.services["polkit-1"];
            assertEqual(polkit.file, arch + "/usr/polkit-1", "Arch: polkit-1 from the vendor directory, /etc/pam.d having none");
            assertEqual(polkit.known + " " + _names(polkit),
                        "true pam_faillock.so pam_systemd_home.so pam_unix.so pam_faillock.so pam_permit.so pam_env.so pam_faillock.so",
                        "… `include system-auth` followed, to /etc/pam.d's system-auth (the vendor one shadowed)");
            assertEqual(_order(reading), "password", "… no reader in it: the password");
            assertEqual(reading.services.sudo.file + " " + reading.services.sudo.known, arch + "/etc/sudo true", "sudo from /etc/pam.d, known");
            assertEqual(reading.faillock["polkit-1"].deny + " " + reading.faillock["polkit-1"].unlockTime, "5 120",
                        "pam_faillock's settings from faillock.conf (the seam's)");
            assertEqual(JSON.stringify(reading.facts), JSON.stringify({ nixos: false, fingerprint: "ready", securityKey: "absent" }),
                        "facts: not NixOS (the methods script's seam), a fingerprint ready, no security key");
            assertEqual(reading.directories.length, 2, "… both directories read");
            assertEqual(reading.lock.fingerprint.known + " " + _names(reading.lock.fingerprint), "true pam_fprintd.so",
                        "the lock's fingerprint config, at the path the methods script gave");
            assertEqual(reading.lock.password.problems[0]?.reason, "missing", "the lock's password config not there: missing, unknown");
            assertEqual(PolkitRules.pamStackHint(_order(reading), reading.facts.nixos), "", "the hint: nothing to say without a reader");
            _ready = false;
            _sh("printf 'auth sufficient pam_fprintd.so\\n' | cat - \"$1/etc/system-auth\" > \"$1/sa\" && mv \"$1/sa\" \"$1/etc/system-auth\"", [arch], () => {
                suite._readingsBefore = suite._reader.readings;
                suite._reader.refresh(false);
                suite._ready = true;
            });
        });
        _then("Arch with a reader in system-auth read", () => _answered(), () => {
            const reading = _reader.reading;
            assertEqual(_order(reading), "fingerprint-first", "Arch, pam_fprintd first in system-auth: the reader first, through the include");
            const hint = PolkitRules.pamStackHint(_order(reading), reading.facts.nixos);
            assert(hint.startsWith("This computer asks the fingerprint reader first"), "… the Settings hint is no longer empty on Arch");
            assert(!hint.includes("NixOS"), "… and names no NixOS option there");
            assertEqual(reading.facts.fingerprint, "ready", "without the methods script: its last answer kept");
            _readAs("nixos", true, false, [], 0);
        });
        _then("NixOS read", () => _answered(), () => {
            const reading = _reader.reading;
            const polkit = reading.services["polkit-1"];
            assertEqual(reading.facts.nixos, true, "NixOS (the methods script's seam)");
            assertEqual(reading.directories.length, 1, "… /etc/pam.d only");
            assertEqual(polkit.known + " " + _names(polkit), "true pam_fprintd.so pam_unix.so pam_deny.so", "NixOS' generated polkit-1, store paths");
            assertEqual(_order(reading), "fingerprint-first", "… the reader first");
            assert(PolkitRules.pamStackHint(_order(reading), true).includes("programs.h2s-shell.polkit.passwordFirst"), "… the hint names the module's option");
            assertEqual(reading.services.sudo.known + " " + reading.services.sudo.problems[0]?.reason, "false missing",
                        "a sudo only in the vendor directory is not read on NixOS");
            _readAs("debian", false, false, [], 0);
        });
        _then("Debian read", () => _answered(), () => {
            const reading = _reader.reading;
            const polkit = reading.services["polkit-1"];
            assertEqual(polkit.known + " " + _names(polkit), "true pam_unix.so pam_deny.so pam_permit.so",
                        "Debian: `@include common-auth` followed (no vendor directory there: absent, not unknown)");
            assertEqual(_order(reading), "password", "… the password");
            assertEqual(reading.faillock["polkit-1"], null, "… no pam_faillock: no settings");
            _readAs("unreadable", false, true, ["password\t/x\tpassword", "fingerprint\t/x\tfingerprint"], 1);
        });
        _then("the unreadable system read", () => _answered(), () => {
            const reading = _reader.reading;
            const polkit = reading.services["polkit-1"];
            assertEqual(polkit.known + " " + polkit.problems[0]?.reason + " " + polkit.lines.length, "false unreadable 0",
                        "polkit-1 there but unreadable (mode 000): unknown — the vendor file behind it not taken");
            assertEqual(_order(reading), "", "… the order not known");
            const sudo = reading.services.sudo;
            assertEqual(sudo.known + " " + sudo.problems[0]?.reason + " " + sudo.problems[0]?.target, "false missing no-such-file",
                        "an include that is not there: unknown");
            assertEqual(reading.faillock.sudo, null, "… pam_faillock in it, its settings unreadable: not known");
            assertEqual(reading.facts.fingerprint + " " + reading.facts.securityKey, "unknown unknown", "the methods script failed: unknown");
            assertEqual(Object.keys(reading.lock).length, 0, "… no lock configs from a failed answer");
            // Late answers lose: a refresh with the methods script on Arch, held, overtaken at
            // once by one without it on Debian; then both are let go
            _ready = false;
            _sh("touch \"$1/hold\"; printf 'fingerprint\\t/x\\tfingerprint\\n' > \"$1/methods-out\"; printf 0 > \"$1/methods-code\"", [_scratch], () => {
                suite._reader.filesCommand = [suite._scratch + "/held-files"];
                suite._readingsBefore = suite._reader.readings;
                suite._reader.environment = suite._environment("arch", false);
                suite._reader.refresh(true);
                suite._reader.environment = suite._environment("debian", false);
                suite._reader.refresh(false);
                suite.assert(suite._reader.running, "two refreshes overlapping: reading");
                suite._sh("rm -f \"$1/hold\"", [suite._scratch], () => suite._ready = true);
            });
        });
        _then("the overtaken refresh settled", () => _answered(), () => {
            const reading = _reader.reading;
            assertEqual(_reader.readings, _readingsBefore + 1, "one reading published, not two");
            assertEqual(reading.services["polkit-1"].file, _scratch + "/debian/etc/polkit-1", "… the newer refresh's (Debian), never the overtaken Arch one");
            assertEqual(reading.facts.fingerprint, "unknown", "… the overtaken methods answer dropped: the earlier one kept");
            assert(!_reader.running, "… nothing reading any more");
        });
        _clock.start();
        _sh([
            "set -e; s=$1; repo=$2; mkdir -p \"$s/tree/scripts\"",
            "cp \"$repo/scripts/pam-files.sh\" \"$repo/scripts/lock-auth-methods.sh\" \"$s/tree/scripts/\"",
            "cp \"$repo/tests/lock/seams/seams.sh\" \"$s/tree/scripts/seams.sh\"",
            // The methods stand-in, and pam-files.sh behind a wait: both hold while "hold" exists
            "printf '#!/bin/sh\\nwhile [ -e \"$(dirname \"$0\")/hold\" ]; do sleep 0.05; done\\ncat \"$(dirname \"$0\")/methods-out\"\\nexit \"$(cat \"$(dirname \"$0\")/methods-code\")\"\\n' > \"$s/methods\"; chmod +x \"$s/methods\"",
            "printf '#!/bin/sh\\nwhile [ -e \"%s/hold\" ]; do sleep 0.05; done\\nexec \"%s/tree/scripts/pam-files.sh\" \"$@\"\\n' \"$s\" \"$s\" > \"$s/held-files\"; chmod +x \"$s/held-files\"",
            // Arch: polkit-1 only in the vendor directory, system-auth in both (/etc wins)
            "mkdir -p \"$s/arch/etc\" \"$s/arch/usr\"",
            "printf '#%%PAM-1.0\\nauth include system-auth\\naccount include system-auth\\npassword include system-auth\\nsession include system-auth\\n' > \"$s/arch/usr/polkit-1\"",
            "printf 'auth required pam_deny.so\\n' > \"$s/arch/usr/system-auth\"",
            "printf '#%%PAM-1.0\\nauth include system-auth\\naccount include system-auth\\nsession include system-auth\\n' > \"$s/arch/etc/sudo\"",
            "printf '%s\\n' '#%PAM-1.0' 'auth       required                    pam_faillock.so      preauth'"
            + " '-auth      [success=2 default=ignore]  pam_systemd_home.so' 'auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok'"
            + " 'auth       [default=die]               pam_faillock.so      authfail' 'auth       optional                    pam_permit.so'"
            + " 'auth       required                    pam_env.so' 'auth       required                    pam_faillock.so      authsucc'"
            + " 'account    required                    pam_unix.so' > \"$s/arch/etc/system-auth\"",
            "printf 'auth required pam_fprintd.so\\n' > \"$s/arch/etc/h2s-shell-fingerprint\"",
            "printf '# faillock.conf\\ndeny = 5\\nunlock_time = 120\\n' > \"$s/arch/faillock.conf\"",
            // NixOS: generated, store paths; a vendor file that must not be read
            "mkdir -p \"$s/nixos/etc\" \"$s/nixos/usr\"",
            "printf '# Account management.\\naccount required /nix/store/aaa-linux-pam/lib/security/pam_unix.so\\n\\n# Authentication management.\\n"
            + "auth sufficient /nix/store/bbb-fprintd/lib/security/pam_fprintd.so\\nauth sufficient /nix/store/aaa-linux-pam/lib/security/pam_unix.so likeauth try_first_pass\\n"
            + "auth required /nix/store/aaa-linux-pam/lib/security/pam_deny.so\\n' > \"$s/nixos/etc/polkit-1\"",
            "printf 'auth sufficient pam_permit.so\\n' > \"$s/nixos/usr/sudo\"",
            // Debian: @include, no vendor directory
            "mkdir -p \"$s/debian/etc\"",
            "printf '#%%PAM-1.0\\n@include common-auth\\n@include common-account\\n' > \"$s/debian/etc/polkit-1\"",
            "cp \"$s/debian/etc/polkit-1\" \"$s/debian/etc/sudo\"",
            "printf 'auth\\t[success=1 default=ignore]\\tpam_unix.so nullok\\nauth\\trequisite\\t\\t\\tpam_deny.so\\nauth\\trequired\\t\\t\\tpam_permit.so\\n' > \"$s/debian/etc/common-auth\"",
            "printf 'account\\trequired\\tpam_unix.so\\n' > \"$s/debian/etc/common-account\"",
            // Unreadable: polkit-1 mode 000 (a readable vendor one behind it), an include not there
            "mkdir -p \"$s/unreadable/etc\" \"$s/unreadable/usr\"",
            "printf 'auth sufficient pam_unix.so\\n' > \"$s/unreadable/etc/polkit-1\"; chmod 000 \"$s/unreadable/etc/polkit-1\"",
            "printf 'auth sufficient pam_unix.so\\n' > \"$s/unreadable/usr/polkit-1\"",
            "printf 'auth required pam_faillock.so preauth\\nauth include no-such-file\\n' > \"$s/unreadable/etc/sudo\"",
            "printf 'deny = 1\\n' > \"$s/unreadable/faillock.conf\"; chmod 000 \"$s/unreadable/faillock.conf\""
        ].join("\n"), [_scratch, Quickshell.shellDir], code => {
            suite.assertEqual(code, 0, "the stand-in directories and the scripts' copies are made");
            suite._ready = true;
        });
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
