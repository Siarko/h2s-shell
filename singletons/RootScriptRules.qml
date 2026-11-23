pragma Singleton

import Quickshell
import QtQuick

// What the shell's fixed root scripts that replace system files share
// (PamApplyRules, RememberInstallRules, and their suites): the places a run may
// write, the shell functions every such script defines, the lock that keeps runs to one at a
// time, and how a run that did not say it was done is read. Pure.
Singleton {
    id: root

    // A value as one single-quoted shell word
    function quoted(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    // An absolute path of plain names: no space, no quote, no `.` or `..` part
    function plainPath(path) {
        return typeof path === "string" && /^(\/[A-Za-z0-9._-]+)+$/.test(path)
            && !path.split("/").some(part => part === "." || part === "..");
    }

    // Whether the places `names` of `paths` may be written: "" when they may, else "paths".
    // `paths.owner` is who must own the folders written in. `live`: the run goes to the
    // system's pkexec, so exactly `livePaths`; a stand-in's run never touches /etc, /usr or
    // /var.
    function placesRefusal(paths, names, livePaths, live) {
        if (paths === null || typeof paths !== "object" || names.some(name => !plainPath(paths[name])))
            return "paths";
        if (!Number.isInteger(paths.owner) || paths.owner < 0)
            return "paths";
        if (live === true)
            return names.every(name => paths[name] === livePaths?.[name]) && paths.owner === livePaths.owner ? "" : "paths";
        const system = ["/etc", "/usr", "/var"];
        return names.some(name => system.some(top => paths[name] === top || paths[name].startsWith(top + "/"))) ? "paths" : "";
    }

    // The first line of every such script: stop at the first failure, files made private
    // (pkexec keeps the caller's umask), messages and sorting in the C locale
    readonly property string header: "set -eu; umask 077; export LC_ALL=C\n"

    // The functions every such script defines; they expect $owner (who owns the folders
    // written in) and $backups (the backups' folder):
    // - refuse <code>: `refused <code>` on stderr, exit 3;
    // - say <line>: what was done, on stderr first — it reaches the shell even when stdout
    //   is gone — then on stdout;
    // - safe_dir <dir>: no link, the owner's, nobody else may write in it;
    // - hash_of <file>, is_hash <word>;
    // - check_current <file> <sha256 | absent>: the file as the shell read it, never a link;
    // - prepare_backups: the backups' folder made, it and its parent safe, 0700.
    readonly property string functions: "refuse() { echo \"refused $1\" >&2; exit 3; }\n"
        + "say() { printf '%s\\n' \"$1\" >&2; printf '%s\\n' \"$1\" || :; }\n"
        + "safe_dir() {\n"
        + "  if [ -L \"$1\" ] || [ ! -d \"$1\" ]; then refuse owner; fi\n"
        + "  facts=$(stat -c '%u %a' -- \"$1\") || refuse owner\n"
        + "  [ \"${facts%% *}\" = \"$owner\" ] || refuse owner\n"
        + "  [ $((0${facts#* } & 022)) -eq 0 ] || refuse owner\n"
        + "}\n"
        + "hash_of() { sum=$(sha256sum < \"$1\") || return 1; printf '%s\\n' \"${sum%% *}\"; }\n"
        + "is_hash() { case \"$1\" in ''|*[!0-9a-f]*) return 1;; esac; [ ${#1} -eq 64 ]; }\n"
        + "check_current() {\n"
        + "  if [ -L \"$1\" ]; then refuse link; fi\n"
        + "  if [ \"$2\" = absent ]; then\n"
        + "    if [ -e \"$1\" ]; then refuse changed; fi\n"
        + "    return 0\n"
        + "  fi\n"
        + "  [ -f \"$1\" ] || refuse changed\n"
        + "  got=$(hash_of \"$1\") || refuse unreadable\n"
        + "  [ \"$got\" = \"$2\" ] || refuse changed\n"
        + "}\n"
        + "prepare_backups() {\n"
        + "  if [ -L \"${backups%/*}\" ] || [ -L \"$backups\" ]; then refuse backup; fi\n"
        + "  mkdir -p -- \"$backups\" || refuse backup\n"
        + "  safe_dir \"${backups%/*}\"\n"
        + "  safe_dir \"$backups\"\n"
        + "  chmod 0700 -- \"$backups\" || refuse backup\n"
        + "}\n"

    // One run at a time, from the first check to the last write, on the backups' lock file;
    // a second run is refused, never waited for. flock says 1 for a lock held; anything else
    // (no flock) is not "busy".
    readonly property string lock: "exec 9>> \"$backups/.lock\" || refuse backup\n"
        + "flock -n 9 || { held=$?; [ \"$held\" -ne 1 ] || refuse busy; refuse lock; }\n"

    // A run that did not say it was done (PrivilegedRules' result) → { quiet } for a prompt
    // dismissed, a run refused, cancelled or blocked (said elsewhere, or the user's choice);
    // else { refused (the script's code), error (its text in `texts`, else texts.arguments) }
    // for its refusal line; else { error } — the reason for the log and the page, on one line
    function failure(result, texts) {
        if (result?.dismissed === true || result?.refused === true || result?.cancelled === true || (result?.blocked ?? "") !== "")
            return { quiet: true };
        const stderr = String(result?.stderr ?? "").trim().split("\n").map(line => line.trim());
        const refusedLine = stderr.slice().reverse().find(line => /^refused [a-z]+$/.test(line));
        if (refusedLine !== undefined) {
            const code = refusedLine.slice("refused ".length);
            return { refused: code, error: texts?.[code] ?? texts?.arguments ?? "" };
        }
        const reason = String(result?.error || stderr.pop() || (result?.ok === true ? "an answer that is not the one asked for" : ""))
            .replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
        return { error: reason !== "" ? reason.slice(0, 200) : "exit code " + (result?.code ?? -1) };
    }
}
