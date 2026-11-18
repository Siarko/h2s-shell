pragma Singleton

import Quickshell
import QtQuick

// What the test seams say (TestSeams reads them; notes/plans/architecture-cleanup.md §3):
// the environment variables by which the test beds change the shell's timings, tools,
// directories and stand-ins. Pure — given the variables as { NAME: value }, it decides
// which count and what each is. A seam that is not set, or set to something it cannot use,
// is not in force and the shell does what it does without it.
//
// Nothing here grants anything: whoever sets the shell's environment can already run
// anything as the user. What the seams change is the test beds' business; each user of one
// names it in its own comment.
Singleton {
    id: root

    // Every seam, with what it is for
    readonly property var seams: [
        { name: "H2S_LOCK_TOOLS", what: "a directory whose gdbus and systemd-inhibit stand in for the real ones (Lockscreen)" },
        { name: "H2S_LOCK_SYSTEM_PAM_DIR", what: "where the system-wide h2s-shell-* PAM configs are looked for instead of /etc/pam.d (Lockscreen)" },
        { name: "H2S_LOCK_SYSTEM", what: "the system the password fallback assumes, nixos or other, with H2S_LOCK_SYSTEM_PAM_DIR (Lockscreen)" },
        { name: "H2S_LOCK_LEDS_DIR", what: "the keyboard LEDs' directory instead of /sys/class/leds (CapsLockLed)" },
        { name: "H2S_LOCK_TEST_TIMINGS", what: "a JSON object of LockRules.timings overrides (Lockscreen)" },
        { name: "H2S_LOCK_TEST_RELOAD", what: "1: the IPC target locktest, which reloads the shell (Lockscreen)" },
        { name: "H2S_SHELL_TEST_MODULE_GUARD_MS", what: "the module start guard's window in ms (Modules)" },
        { name: "H2S_SHELL_TEST_MODULE_CHECK_PATH", what: "a directory put first on the module file check's PATH (Modules)" },
        { name: "H2S_SHELL_TEST_MODULE_CHECK_MS", what: "the module host's checks' deadline in ms (Modules)" },
        { name: "H2S_FAKE_VPN_PROVIDER", what: "1: the stand-in VPN provider of tests/FakeVpnProvider.qml (VpnManager)" }
    ]
    readonly property var names: seams.map(seam => seam.name)

    function _text(environment, name) {
        const value = environment?.[name];
        return typeof value === "string" ? value : "";
    }

    function _positive(text) {
        const number = Number(text);
        return text !== "" && isFinite(number) && number > 0 ? number : 0;
    }

    // { NAME: value } (undefined or "" for a variable not set) → frozen {
    //   lockTools, systemPamDirectory, ledsDirectory   "" when not given
    //   lockSystem       "nixos" | "other" | "" (only with systemPamDirectory)
    //   timings          the overrides given ({} for none), timingsProblem ("" or why not)
    //   reloadIpc, fakeVpnProvider   booleans
    //   moduleGuardMs, moduleCheckMs   > 0, or 0 for none
    //   moduleCheckPath  an absolute directory, or ""
    //   inForce          the names that change something, in `names`' order
    //   ignored          the names set to something unusable
    // }
    function read(environment) {
        const text = name => _text(environment, name);
        const systemPamDirectory = text("H2S_LOCK_SYSTEM_PAM_DIR");
        const system = text("H2S_LOCK_SYSTEM");
        let timings = {};
        let timingsProblem = "";
        if (text("H2S_LOCK_TEST_TIMINGS") !== "") {
            try {
                const parsed = JSON.parse(text("H2S_LOCK_TEST_TIMINGS"));
                if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed))
                    timings = parsed;
                else
                    timingsProblem = "not a JSON object";
            } catch (error) {
                timingsProblem = "not JSON";
            }
        }
        const checkPath = text("H2S_SHELL_TEST_MODULE_CHECK_PATH");
        const values = {
            lockTools: text("H2S_LOCK_TOOLS"),
            systemPamDirectory: systemPamDirectory,
            lockSystem: systemPamDirectory !== "" && (system === "nixos" || system === "other") ? system : "",
            ledsDirectory: text("H2S_LOCK_LEDS_DIR"),
            timings: Object.freeze(timings),
            timingsProblem: timingsProblem,
            reloadIpc: text("H2S_LOCK_TEST_RELOAD") === "1",
            moduleGuardMs: _positive(text("H2S_SHELL_TEST_MODULE_GUARD_MS")),
            moduleCheckPath: checkPath.startsWith("/") ? checkPath : "",
            moduleCheckMs: _positive(text("H2S_SHELL_TEST_MODULE_CHECK_MS")),
            fakeVpnProvider: text("H2S_FAKE_VPN_PROVIDER") === "1"
        };
        const taken = {
            H2S_LOCK_TOOLS: values.lockTools !== "",
            H2S_LOCK_SYSTEM_PAM_DIR: values.systemPamDirectory !== "",
            H2S_LOCK_SYSTEM: values.lockSystem !== "",
            H2S_LOCK_LEDS_DIR: values.ledsDirectory !== "",
            H2S_LOCK_TEST_TIMINGS: text("H2S_LOCK_TEST_TIMINGS") !== "" && timingsProblem === "",
            H2S_LOCK_TEST_RELOAD: values.reloadIpc,
            H2S_SHELL_TEST_MODULE_GUARD_MS: values.moduleGuardMs > 0,
            H2S_SHELL_TEST_MODULE_CHECK_PATH: values.moduleCheckPath !== "",
            H2S_SHELL_TEST_MODULE_CHECK_MS: values.moduleCheckMs > 0,
            H2S_FAKE_VPN_PROVIDER: values.fakeVpnProvider
        };
        values.inForce = Object.freeze(names.filter(name => taken[name]));
        values.ignored = Object.freeze(names.filter(name => !taken[name] && text(name) !== ""));
        return Object.freeze(values);
    }
}
