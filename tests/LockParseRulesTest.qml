import QtQuick
import qs.singletons

// What comes into the lock's rules as text (singletons/LockParseRules.qml): the methods
// script's lines, logind's monitor lines and its GetSession answer.
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

        // LockRules forwards them: its callers read the same answers
        assertEqual(JSON.stringify(LockRules.parseMethods("password\t/etc/pam.d\tlogin")),
                    JSON.stringify(LockParseRules.parseMethods("password\t/etc/pam.d\tlogin")), "LockRules.parseMethods forwards");
        assertEqual(JSON.stringify(LockRules.parseLogind("/org/freedesktop/login1/session/_34: org.freedesktop.login1.Session.Lock ()", session)),
                    JSON.stringify({ type: "lockRequested", source: "logind" }), "LockRules.parseLogind forwards");
        assertEqual(LockRules.parseSessionPath("(objectpath '/org/freedesktop/login1/session/_34',)"),
                    "/org/freedesktop/login1/session/_34", "LockRules.parseSessionPath forwards");
    }
}
