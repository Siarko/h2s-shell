pragma Singleton

import Quickshell
import QtQuick

// Writing a PAM file on Arch, and undoing it (tests/PamApplyRulesTest.qml): the one root
// step that follows a passed trial (PamTrialRules), and its reply. One service per run.
//
// The root step is `applyScript`, a fixed script in the shell's code run by the system's
// /bin/sh through the shell's runs as administrator (PrivilegedRuns.startShell): nothing is
// loaded from a file, every run asks the password. Its places (the PAM folder, the vendor
// folder, the backups) are written into the script text, never handed as arguments; its
// arguments are checked inside it — the service from a fixed list, hashes as 64 hex digits,
// included files as names (no path), a backup by its exact pattern. It refuses before
// changing anything when:
// - the bytes it would write are not the ones the trial passed (sha256 of the written temp
//   file against the candidate's, before the rename);
// - the service's file changed since the shell read it (its sha256, or that there was none);
// - a file the rules include changed since the trial (each name looked up as libpam would:
//   the PAM folder, then the vendor folder; its sha256 against the trial's copy);
// - for a removal, the vendor file is not the text the trial passed;
// - the service's file is a link, or a folder is.
// It writes the new file beside the old one in the PAM folder (mode 0644) and checks it,
// copies the current file to the backups (`<service>.<UTC time>`, `.absent` when there was
// none; every backup kept), renames the new file into place, and prints what is in force.
//
// What is left to the user: a file the rules include by absolute path outside the PAM
// folders cannot be looked up by name as root, so rules that include one are not written.
// Pure: texts and states are handed in, nothing is read or written.
Singleton {
    id: root

    // Where the files are on Arch; a suite's stand-in runs use folders of its own
    readonly property var livePaths: ({
        system: "/etc/pam.d",
        vendor: "/usr/lib/pam.d",
        backups: "/var/lib/h2s-shell/pam-backup"
    })

    // Why a run was not started, or what the root step refused, by code
    readonly property var texts: ({
        // Before the run
        service: "Unknown service.",
        built: "The new rules could not be made.",
        unchanged: "Nothing to change.",
        unread: "The file could not be read.",
        notTried: "The new rules were not tried: try them first.",
        places: "The trial read other folders than the ones written.",
        outside: "The new rules include a file outside the PAM folders: it cannot be checked before the write.",
        backupName: "Not a backup of this service.",
        paths: "Not a place the shell writes PAM files to.",
        busy: "A change is already being saved.",
        // By the root step
        arguments: "The request was not valid.",
        system: "The PAM folder is not there.",
        link: "The file is a link: not changed.",
        changed: "The file changed since it was read: read it again.",
        unreadable: "The file could not be read.",
        included: "A file the rules include changed since the trial: try again.",
        vendor: "polkit's own file changed since the trial: try again.",
        backup: "The backup could not be made: nothing changed.",
        nobackup: "That backup is not there.",
        write: "The new file could not be written: nothing changed.",
        hash: "The file written was not the one tried: nothing changed."
    })

    // A backup's name: the service, the UTC time, a counter for a second one in the same
    // second, `.absent` when the service had no file
    readonly property string _stampPattern: "[0-9]{8}T[0-9]{6}Z(-[1-9])?(\\.absent)?"

    function refusal(code) {
        return { code, text: texts[code] ?? texts.arguments };
    }

    function _refused(code) {
        return { argv: null, expected: null, refusal: refusal(code) };
    }

    function isHash(value) {
        return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
    }

    // Whether `name` is a backup of `service` as the root step names them
    function validBackup(service, name) {
        return PamRuleRules.services.includes(service) && typeof name === "string"
            && new RegExp("^" + service.replace(/[.-]/g, "\\$&") + "\\." + _stampPattern + "$").test(name);
    }

    // A backup's full path, for the page: a repair from a console is one `cp` (or an `rm`
    // for a backup of no file)
    function backupPath(paths, name) {
        return String(paths?.backups ?? "") + "/" + String(name ?? "");
    }

    function _plainPath(path) {
        return typeof path === "string" && /^(\/[A-Za-z0-9._-]+)+$/.test(path)
            && !path.split("/").some(part => part === "." || part === "..");
    }

    // Whether the places may be written: "" when they may, else a refusal code. `live`: the
    // run goes to the system's pkexec, so only livePaths; a stand-in's run never touches
    // /etc, /usr or /var.
    function pathsRefusal(paths, live) {
        const names = ["system", "vendor", "backups"];
        if (paths === null || typeof paths !== "object" || names.some(name => !_plainPath(paths[name])))
            return "paths";
        if (live === true)
            return names.every(name => paths[name] === livePaths[name]) ? "" : "paths";
        const system = ["/etc", "/usr", "/var"];
        return names.some(name => system.some(top => paths[name] === top || paths[name].startsWith(top + "/"))) ? "paths" : "";
    }

    function _quoted(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    // The root step's script for these places ("" for places that are not plain absolute
    // paths). Its arguments ($0 is "sh"):
    //   write  <service> <candidate sha256> <current sha256 | absent> <text> [<name> <sha256>]…
    //   remove polkit-1  <vendor sha256>    <current sha256>          [<name> <sha256>]…
    //   undo   <service> <backup name>      <current sha256 | absent>
    // Its last line on success: `written|removed|restored <service> <sha256 in force |
    // absent> <backup made>`; a refusal: `refused <code>` on stderr, exit 3.
    function applyScript(paths) {
        if (pathsRefusal(paths, false) !== "" && pathsRefusal(paths, true) !== "")
            return "";
        return "set -eu; umask 077; export LC_ALL=C\n"
            + "system=" + _quoted(paths.system) + "; vendor=" + _quoted(paths.vendor) + "; backups=" + _quoted(paths.backups) + "\n"
            + "pam_temporary=; backup_temporary=\n"
            + "trap 'for leftover in \"$pam_temporary\" \"$backup_temporary\"; do [ -z \"$leftover\" ] || rm -f -- \"$leftover\"; done' EXIT\n"
            + "refuse() { echo \"refused $1\" >&2; exit 3; }\n"
            + "hash_of() { sum=$(sha256sum < \"$1\") || return 1; printf '%s\\n' \"${sum%% *}\"; }\n"
            + "is_hash() { case \"$1\" in ''|*[!0-9a-f]*) return 1;; esac; [ ${#1} -eq 64 ]; }\n"
            + "is_name() { case \"$1\" in ''|[!A-Za-z0-9_]*|*[!A-Za-z0-9._@+-]*) return 1;; esac; [ ${#1} -le 255 ]; }\n"
            // The service's file as the shell read it: that hash, or none
            + "check_current() {\n"
            + "  if [ -L \"$target\" ]; then refuse link; fi\n"
            + "  if [ \"$1\" = absent ]; then\n"
            + "    if [ -e \"$target\" ]; then refuse changed; fi\n"
            + "    return 0\n"
            + "  fi\n"
            + "  [ -f \"$target\" ] || refuse changed\n"
            + "  got=$(hash_of \"$target\") || refuse unreadable\n"
            + "  [ \"$got\" = \"$1\" ] || refuse changed\n"
            + "}\n"
            // Each included name where libpam finds it, as the trial read it
            + "check_includes() {\n"
            + "  while [ $# -gt 0 ]; do\n"
            + "    [ $# -ge 2 ] || refuse arguments\n"
            + "    is_name \"$1\" && is_hash \"$2\" || refuse arguments\n"
            + "    if [ -e \"$system/$1\" ] || [ -L \"$system/$1\" ]; then file=\"$system/$1\"\n"
            + "    elif [ -e \"$vendor/$1\" ] || [ -L \"$vendor/$1\" ]; then file=\"$vendor/$1\"\n"
            + "    else refuse included; fi\n"
            + "    [ -f \"$file\" ] || refuse included\n"
            + "    got=$(hash_of \"$file\") || refuse included\n"
            + "    [ \"$got\" = \"$2\" ] || refuse included\n"
            + "    shift 2\n"
            + "  done\n"
            + "}\n"
            + "prepare_backups() {\n"
            + "  if [ -L \"${backups%/*}\" ] || [ -L \"$backups\" ]; then refuse backup; fi\n"
            + "  mkdir -p -- \"$backups\" || refuse backup\n"
            + "  if [ -L \"$backups\" ] || [ ! -d \"$backups\" ]; then refuse backup; fi\n"
            + "  chmod 0700 -- \"$backups\" || refuse backup\n"
            + "}\n"
            // The current file (checked) into the backups; a name never taken twice (ln
            // fails on a name that is there)
            + "make_backup() {\n"
            + "  prepare_backups\n"
            + "  stamp=$(date -u +%Y%m%dT%H%M%SZ)\n"
            + "  suffix=\n"
            + "  if [ \"$1\" = absent ]; then suffix=.absent; fi\n"
            + "  backup_temporary=$(mktemp -- \"$backups/.new.XXXXXX\") || refuse backup\n"
            + "  if [ \"$1\" != absent ]; then cat -- \"$target\" > \"$backup_temporary\" || refuse backup; fi\n"
            + "  chmod 0600 -- \"$backup_temporary\" || refuse backup\n"
            + "  count=0; extra=\n"
            + "  while :; do\n"
            + "    backup_name=\"$service.$stamp$extra$suffix\"\n"
            + "    if ln -- \"$backup_temporary\" \"$backups/$backup_name\" 2> /dev/null; then break; fi\n"
            + "    count=$((count + 1)); [ \"$count\" -le 9 ] || refuse backup\n"
            + "    extra=\"-$count\"\n"
            + "  done\n"
            + "  rm -f -- \"$backup_temporary\"; backup_temporary=\n"
            + "}\n"
            // A new file beside the target, checked, renamed into place (never half a file;
            // a rename replaces a link, never follows it)
            + "new_file() { pam_temporary=$(mktemp -- \"$system/.h2s-shell.XXXXXX\") || refuse write; }\n"
            + "seal() {\n"
            + "  chmod 0644 -- \"$pam_temporary\" || refuse write\n"
            + "  got=$(hash_of \"$pam_temporary\") || refuse write\n"
            + "  if [ -n \"$1\" ] && [ \"$got\" != \"$1\" ]; then refuse hash; fi\n"
            + "}\n"
            + "put_in_place() { mv -fT -- \"$pam_temporary\" \"$target\" || refuse write; pam_temporary=; }\n"
            + "[ $# -ge 2 ] || refuse arguments\n"
            + "mode=$1; service=$2; shift 2\n"
            + "case \"$service\" in sudo|polkit-1) ;; *) refuse arguments;; esac\n"
            + "if [ -L \"$system\" ] || [ ! -d \"$system\" ]; then refuse system; fi\n"
            + "target=$system/$service\n"
            + "case \"$mode\" in\n"
            + "write)\n"
            + "  [ $# -ge 3 ] || refuse arguments\n"
            + "  want=$1; current=$2; text=$3; shift 3\n"
            + "  is_hash \"$want\" || refuse arguments\n"
            + "  [ \"$current\" = absent ] || is_hash \"$current\" || refuse arguments\n"
            + "  check_current \"$current\"\n"
            + "  check_includes \"$@\"\n"
            + "  new_file\n"
            + "  printf '%s' \"$text\" > \"$pam_temporary\" || refuse write\n"
            + "  seal \"$want\"\n"
            + "  make_backup \"$current\"\n"
            + "  put_in_place\n"
            + "  echo \"written $service $got $backup_name\";;\n"
            + "remove)\n"
            + "  [ \"$service\" = polkit-1 ] && [ $# -ge 2 ] || refuse arguments\n"
            + "  want=$1; current=$2; shift 2\n"
            + "  is_hash \"$want\" && is_hash \"$current\" || refuse arguments\n"
            + "  source=$vendor/$service\n"
            + "  if [ -L \"$source\" ] || [ ! -f \"$source\" ]; then refuse vendor; fi\n"
            + "  got=$(hash_of \"$source\") || refuse vendor\n"
            + "  [ \"$got\" = \"$want\" ] || refuse vendor\n"
            + "  check_current \"$current\"\n"
            + "  check_includes \"$@\"\n"
            + "  make_backup \"$current\"\n"
            + "  rm -f -- \"$target\"\n"
            + "  echo \"removed $service $want $backup_name\";;\n"
            + "undo)\n"
            + "  [ $# -eq 2 ] || refuse arguments\n"
            + "  name=$1; current=$2\n"
            + "  stamp_pattern='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'\n"
            + "  case \"$name\" in \"$service\".*) ;; *) refuse arguments;; esac\n"
            + "  case \"${name#\"$service\".}\" in $stamp_pattern|$stamp_pattern-[1-9]|$stamp_pattern.absent|$stamp_pattern-[1-9].absent) ;; *) refuse arguments;; esac\n"
            + "  [ \"$current\" = absent ] || is_hash \"$current\" || refuse arguments\n"
            + "  prepare_backups\n"
            + "  source=$backups/$name\n"
            + "  if [ -L \"$source\" ] || [ ! -f \"$source\" ]; then refuse nobackup; fi\n"
            + "  check_current \"$current\"\n"
            + "  case \"$name\" in\n"
            + "  *.absent)\n"
            + "    make_backup \"$current\"\n"
            + "    rm -f -- \"$target\"\n"
            + "    echo \"restored $service absent $backup_name\";;\n"
            + "  *)\n"
            + "    new_file\n"
            + "    cat -- \"$source\" > \"$pam_temporary\" || refuse write\n"
            + "    seal ''\n"
            + "    make_backup \"$current\"\n"
            + "    put_in_place\n"
            + "    echo \"restored $service $got $backup_name\";;\n"
            + "  esac;;\n"
            + "*) refuse arguments;;\n"
            + "esac\n";
    }

    // What the trial must have passed for a build (PamEditRules.build's answer): its text,
    // or for a removal of our polkit-1 the vendor file that is then in force. → { text,
    // remove } or null when the build made nothing
    function candidate(built, vendorText) {
        if (built?.ok !== true)
            return null;
        if (built.remove === true)
            return typeof vendorText === "string" ? { text: vendorText, remove: true } : null;
        return typeof built.text === "string" ? { text: built.text, remove: false } : null;
    }

    // What the prompt says the run is for
    function what(mode, service) {
        const target = service === "sudo" ? "sudo" : "administrator prompts";
        return mode === "undo" ? "Undo the change to the sign-in rules for " + target
            : "Change the sign-in rules for " + target;
    }

    // The root step for Apply. `request`: { service, built (PamEditRules.build's answer),
    // currentText (the service's file the build was made from; polkit: null when there was
    // none), vendorText (polkit's vendor file), trial (PamTrialRules' state) }. The trial
    // must have passed for this exact candidate, or — one trial for a shared list — for the
    // other service's candidate whose auth lines are the same (PamTrialRules.sameAuthLines,
    // the files this one includes all among those the trial read). → { argv ([shell, "-c",
    // script, "sh", words…]), expected (for applyReply), refusal (null or { code, text }) }
    function applyArgv(shell, request, paths, live) {
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return _refused("arguments");
        const pathProblem = pathsRefusal(paths, live);
        if (pathProblem !== "")
            return _refused(pathProblem);
        const service = String(request?.service ?? "");
        if (!PamRuleRules.services.includes(service))
            return _refused("service");
        const chosen = candidate(request?.built, request?.vendorText);
        if (chosen === null)
            return _refused("built");
        if (chosen.remove && service !== "polkit-1")
            return _refused("built");
        const currentText = request?.currentText;
        let current;
        if (typeof currentText === "string")
            current = PamEditRules.sha256(currentText);
        else if (service === "polkit-1" && (currentText === null || currentText === undefined))
            current = "absent";
        else
            return _refused("unread");
        const want = PamEditRules.sha256(chosen.text);
        if (chosen.remove ? current === "absent" : current === want)
            return _refused("unchanged");
        // The trial
        const trial = request?.trial;
        if (trial?.phase !== "passed" || typeof trial.candidate !== "string")
            return _refused("notTried");
        const directories = Array.isArray(trial.directories) ? trial.directories.map(dir => String(dir).replace(/\/+$/, "")) : [];
        if (directories.length !== 2 || directories[0] !== paths.system || directories[1] !== paths.vendor)
            return _refused("places");
        const step = PamTrialRules.stagingStep(service, chosen.text, trial.answers ?? {}, directories, false);
        if (step.refusal !== null || step.pending.length > 0)
            return _refused("notTried");
        // The same service: this exact text. The other one: the same auth lines
        if (trial.service === service ? trial.candidate !== chosen.text : !PamTrialRules.sameAuthLines(trial.stack, step.stack))
            return _refused("notTried");
        // Every file the stack read must be one the root step can look up again: the
        // service's own (the candidate) or an included name
        const answers = trial.answers ?? {};
        const found = step.files.slice(1).map(file => PamStackRules.candidates(file.name, directories)
                                                   .find(path => typeof answers[path]?.text === "string"));
        const own = directories[0] + "/" + service;
        if (step.stack.files.some(path => path !== own && !found.includes(path)))
            return _refused("outside");
        const includes = [];
        for (const file of step.files.slice(1))
            includes.push(file.name, PamEditRules.sha256(file.text));
        const words = chosen.remove ? ["remove", service, want, current].concat(includes)
            : ["write", service, want, current, chosen.text].concat(includes);
        return {
            argv: [shell, "-c", applyScript(paths), "sh"].concat(words),
            expected: { mode: chosen.remove ? "remove" : "write", service, sha256: want },
            refusal: null
        };
    }

    // The root step for Undo: `request` { service, backup (the name the apply's reply gave),
    // currentSha256 (what that apply left in force: its reply's sha256, "absent" after a
    // removal) }. No trial: the backup is the state that was in force. → as applyArgv
    function undoArgv(shell, request, paths, live) {
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return _refused("arguments");
        const pathProblem = pathsRefusal(paths, live);
        if (pathProblem !== "")
            return _refused(pathProblem);
        const service = String(request?.service ?? "");
        if (!PamRuleRules.services.includes(service))
            return _refused("service");
        if (!validBackup(service, request?.backup))
            return _refused("backupName");
        const current = request?.currentSha256;
        if (current !== "absent" && !isHash(current))
            return _refused("unread");
        return {
            argv: [shell, "-c", applyScript(paths), "sh", "undo", service, request.backup, current],
            expected: { mode: "undo", service, sha256: "" },
            refusal: null
        };
    }

    // The root step's reply (PrivilegedRules' result: ok, code, stdout, stderr, dismissed,
    // refused, cancelled, blocked, error) for what applyArgv / undoArgv expected → { ok,
    // quiet (a prompt dismissed, a run refused or cancelled: said elsewhere, or the user's
    // choice), kind (written / removed / restored), service, sha256 (what is in force in the
    // PAM folder now; "absent" for no file there), backup (the backup made), refused (the
    // root step's code), error (for the log and the page) }. ok only when its last line
    // says it did what was asked, for that service, with the expected hash.
    function applyReply(result, expected) {
        const outcome = { ok: false, quiet: false, kind: "", service: String(expected?.service ?? ""), sha256: "", backup: "", refused: "", error: "" };
        const words = { write: "written", remove: "removed", undo: "restored" };
        const kind = words[expected?.mode] ?? "";
        const last = String(result?.stdout ?? "").trim().split("\n").pop().trim();
        const said = /^(written|removed|restored) (sudo|polkit-1) ([0-9a-f]{64}|absent) (\S+)$/.exec(last);
        if (result?.ok === true && said !== null && kind !== "" && said[1] === kind && said[2] === outcome.service
                && validBackup(said[2], said[4]) && (expected.sha256 === "" || said[3] === expected.sha256)
                && (kind !== "written" || said[3] !== "absent")) {
            return Object.assign(outcome, {
                ok: true, kind, sha256: kind === "removed" ? "absent" : said[3], backup: said[4]
            });
        }
        if (result?.dismissed === true || result?.refused === true || result?.cancelled === true || (result?.blocked ?? "") !== "")
            return Object.assign(outcome, { quiet: true });
        const stderr = String(result?.stderr ?? "").trim().split("\n").map(line => line.trim());
        const refusedLine = stderr.slice().reverse().find(line => /^refused [a-z]+$/.test(line));
        if (refusedLine !== undefined) {
            const code = refusedLine.slice("refused ".length);
            return Object.assign(outcome, { refused: code, error: texts[code] ?? texts.arguments });
        }
        const reason = String(result?.error || stderr.pop() || (result?.ok === true ? "an answer that is not the one asked for" : ""))
            .replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
        return Object.assign(outcome, { error: reason !== "" ? reason.slice(0, 200) : "exit code " + (result?.code ?? -1) });
    }

    // Whether the service's file in the PAM folder, read again (`text`: null / undefined
    // when there is none), is what the run left in force
    function inForce(text, outcome) {
        if (outcome?.ok !== true)
            return false;
        if (outcome.sha256 === "absent")
            return text === null || text === undefined;
        return typeof text === "string" && PamEditRules.sha256(text) === outcome.sha256;
    }
}
