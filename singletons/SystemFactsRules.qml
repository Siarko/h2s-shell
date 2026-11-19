pragma Singleton

import Quickshell

// What the shell knows of the system it runs on, decided from what was read — pure, tested
// in tests/SystemFactsTest.qml. The reading is singletons/io/SystemFactsReader.qml's (the
// shell's one reader is SystemFacts); modules see the result as Api.system (module API 1.13).
//
// Every fact comes from a reading that is the same on NixOS and on Arch: the process's
// environment (HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_RUNTIME_DIR), /proc/self/status
// (the user id), `id -un` (the user name, through NSS), /proc/sys/kernel/hostname, the
// user's user-dirs.dirs (xdg-user-dirs' file on Arch; home-manager's, often a link into the
// store, on NixOS — or none) and /proc's two forwarding switches. A reading that failed or
// says something unexpected gives "unknown" — "" for a text, null for a number or a switch —
// never a guess. Nothing here throws on any input.
Singleton {
    id: root

    // Where the modules' data directories are, below the data home
    readonly property string dataDirectoryName: "h2s-shell/module-data"
    // The longest path or name taken from a reading
    readonly property int maxPathLength: 4096
    readonly property int maxNameLength: 255

    // A text that holds a control character (a line break, an escape): never a path or a name
    function _hasControl(text) {
        return /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(text);
    }

    // An absolute path, its trailing "/" dropped ("/" stays) — or "" when the text is no
    // absolute path: relative, empty, with a control character or a "." or ".." part, too long
    function absolutePath(text) {
        if (typeof text !== "string" || text.length === 0 || text.length > maxPathLength || !text.startsWith("/") || _hasControl(text))
            return "";
        const trimmed = text.length > 1 ? text.replace(/\/+$/, "") : text;
        const path = trimmed === "" ? "/" : trimmed;
        if (path.split("/").some(part => part === "." || part === ".."))
            return "";
        return path;
    }

    // The base directories, from the environment ({ HOME, XDG_CONFIG_HOME, XDG_DATA_HOME,
    // XDG_RUNTIME_DIR }, texts or undefined). As the XDG base directory specification has
    // it: a relative XDG_* value is ignored, and the default below the home taken. HOME
    // not absolute → the home and everything below it unknown (""); XDG_RUNTIME_DIR has no
    // default.
    function baseDirectories(environment) {
        const home = absolutePath(environment?.HOME);
        const below = suffix => home === "" ? "" : (home === "/" ? "" : home) + suffix;
        const configHome = absolutePath(environment?.XDG_CONFIG_HOME);
        const dataHome = absolutePath(environment?.XDG_DATA_HOME);
        return {
            home: home,
            configHome: configHome !== "" ? configHome : below("/.config"),
            dataHome: dataHome !== "" ? dataHome : below("/.local/share"),
            runtimeDirectory: absolutePath(environment?.XDG_RUNTIME_DIR)
        };
    }

    // The real user id from /proc/self/status's text ("Uid:\t<real>\t<effective>…") → a
    // number, or null
    function uid(statusText) {
        const match = /^Uid:\s+(\d{1,10})\s/m.exec(typeof statusText === "string" ? statusText + "\n" : "");
        if (!match)
            return null;
        const value = Number(match[1]);
        return Number.isSafeInteger(value) && value <= 4294967294 ? value : null;
    }

    // One name on one line (`id -un`'s output, the host name file's text) → the name, or ""
    // when there is not exactly one non-empty line, or it holds a control character or white
    // space, or is too long
    function oneName(text) {
        if (typeof text !== "string")
            return "";
        const name = text.replace(/\n$/, "");
        if (name === "" || name.length > maxNameLength || _hasControl(name) || /\s/.test(name))
            return "";
        return name;
    }

    // XDG_DOWNLOAD_DIR from user-dirs.dirs' text — read, never run as a shell would — else
    // <home>/Downloads. `userDirs`: { text, found (false: there is no such file), failed
    // (true: it is there and could not be read) }. A value is "$HOME/<path>" or an absolute
    // path, in double quotes (xdg-user-dirs writes no other), a "# comment" after it allowed;
    // anything else (a command substitution, another variable, a relative path) is no folder
    // and the default is taken. Inside the quotes a backslash is read as sh reads it: it
    // drops before ", \, $ and ` and stays before anything else. "$HOME" or "$HOME/" alone
    // means "no download folder" there: the default too. A file that could not be read, or
    // no home: "" (unknown), unless the file names an absolute folder.
    function downloadDirectory(userDirs, home) {
        const homePath = absolutePath(home);
        const fallback = homePath !== "" && homePath !== "/" ? homePath + "/Downloads" : "";
        if (userDirs?.failed === true)
            return "";
        if (userDirs?.found !== true)
            return fallback;
        const noFolder = { fromHome: false, rest: "" };
        let value = null;
        // The last assignment counts, as when the file is sourced
        for (const line of String(userDirs?.text ?? "").split("\n")) {
            const match = /^\s*XDG_DOWNLOAD_DIR\s*=\s*"((?:[^"\\]|\\.)*)"(?:\s+#.*|\s*)$/.exec(line);
            if (match)
                value = _quotedValue(match[1]) ?? noFolder;
            else if (/^\s*XDG_DOWNLOAD_DIR\s*=/.test(line))
                value = noFolder;
        }
        if (value === null || (!value.fromHome && value.rest === ""))
            return fallback;
        if (value.fromHome && homePath === "")
            return "";
        const path = (value.fromHome ? (homePath === "/" ? "" : homePath) : "") + value.rest;
        const folder = absolutePath(path);
        if (folder === "" || folder === homePath || folder === "/")
            return fallback;
        return folder;
    }

    // The text between the double quotes as sh would make it → { fromHome (it starts with
    // $HOME), rest (the text after it) }, or null for what is no folder: an expansion other
    // than a leading $HOME ($, `), a backslash at the end
    function _quotedValue(quoted) {
        const fromHome = /^\$HOME(?![A-Za-z0-9_])/.test(quoted);
        let rest = "";
        for (let i = fromHome ? 5 : 0; i < quoted.length; i++) {
            const character = quoted[i];
            if (character === "\\") {
                const next = quoted[i + 1];
                if (next === undefined)
                    return null;
                rest += "\"\\$`".includes(next) ? next : character + next;
                i++;
            } else if (character === "$" || character === "`") {
                return null;
            } else {
                rest += character;
            }
        }
        return { fromHome: fromHome, rest: rest };
    }

    // A forwarding switch's text ("0\n", "1\n") → true, false, or null when it could not be
    // read or is no number
    function forwarding(text) {
        if (typeof text !== "string")
            return null;
        const match = /^\s*(\d{1,10})\s*$/.exec(text);
        return match ? Number(match[1]) !== 0 : null;
    }

    // Both switches → frozen { ipv4, ipv6 }
    function forwardingOf(ipv4Text, ipv6Text) {
        return Object.freeze({ ipv4: forwarding(ipv4Text), ipv6: forwarding(ipv6Text) });
    }

    // Every fact from its readings:
    //   environment     { HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_RUNTIME_DIR }
    //   statusText      /proc/self/status ("" when not read)
    //   userName        { answered (the command ended), ok (it exited 0), text (its output) }
    //   hostNameText    /proc/sys/kernel/hostname
    //   userDirs        { answered, found, failed, text }: user-dirs.dirs
    // → { ready (the name and user-dirs.dirs answered), userName, uid, hostName, home,
    //     configHome, dataHome, runtimeDirectory, downloadDirectory } — unknown: "" or null
    function facts(readings) {
        const base = baseDirectories(readings?.environment);
        const name = readings?.userName;
        const userDirs = readings?.userDirs;
        return {
            ready: name?.answered === true && userDirs?.answered === true,
            userName: name?.answered === true && name?.ok === true ? oneName(name?.text) : "",
            uid: uid(readings?.statusText),
            hostName: oneName(readings?.hostNameText),
            home: base.home,
            configHome: base.configHome,
            dataHome: base.dataHome,
            runtimeDirectory: base.runtimeDirectory,
            downloadDirectory: userDirs?.answered === true ? downloadDirectory(userDirs, base.home) : ""
        };
    }

    // Where user-dirs.dirs is: "<configHome>/user-dirs.dirs", or "" with no config home
    function userDirsPath(configHome) {
        const config = absolutePath(configHome);
        return config === "" ? "" : (config === "/" ? "" : config) + "/user-dirs.dirs";
    }

    // ---- Test mode (ModuleTestKit.setSystem) ----

    // The facts a module sees in module test mode before a suite sets any: made up, the same
    // on every machine; the directories below `home` (the host's private temporary one)
    function testDefaults(home) {
        const base = absolutePath(home);
        const below = suffix => base === "" ? "" : base + suffix;
        return {
            ready: true, userName: "tester", uid: 1000, hostName: "test-host",
            home: base, configHome: below("/.config"), dataHome: below("/.local/share"),
            runtimeDirectory: below("/run"), downloadDirectory: below("/Downloads"),
            ipForwarding: { ipv4: false, ipv6: false }
        };
    }

    // The fields setSystem takes, and the kind each must be: a field given with another kind
    // is left as it was (the problem named)
    readonly property var _testFieldKinds: ({
        ready: "boolean", userName: "text", uid: "uid", hostName: "text", home: "path",
        configHome: "path", dataHome: "path", runtimeDirectory: "path", downloadDirectory: "path",
        ipForwarding: "forwarding"
    })

    function _fieldProblem(kind, value) {
        if (kind === "boolean")
            return typeof value === "boolean" ? "" : "true or false";
        if (kind === "text")
            return typeof value === "string" && (value === "" || oneName(value) === value) ? "" : "a name on one line, or \"\"";
        if (kind === "uid")
            return value === null || (Number.isSafeInteger(value) && value >= 0 && value <= 4294967294) ? "" : "a user id, or null";
        if (kind === "path")
            return typeof value === "string" && (value === "" || absolutePath(value) === value) ? "" : "an absolute path, or \"\"";
        const switchOk = state => state === true || state === false || state === null;
        return value !== null && typeof value === "object" && switchOk(value.ipv4 ?? null) && switchOk(value.ipv6 ?? null)
            ? "" : "{ ipv4, ipv6 }, each true, false or null";
    }

    // setSystem's facts over the defaults → { facts, problems: [text] }. `given` null or
    // undefined: the defaults. Fields setSystem does not know are named among the problems
    function testFacts(given, defaults) {
        const facts = Object.assign({}, defaults ?? {});
        facts.ipForwarding = Object.assign({ ipv4: null, ipv6: null }, defaults?.ipForwarding ?? {});
        const problems = [];
        if (given === null || given === undefined)
            return { facts: facts, problems: problems };
        if (typeof given !== "object" || Array.isArray(given))
            return { facts: facts, problems: ["the facts are not an object"] };
        for (const key of Object.keys(given)) {
            const kind = _testFieldKinds[key];
            if (kind === undefined || !Object.prototype.hasOwnProperty.call(_testFieldKinds, key)) {
                problems.push(key + ": no such fact");
                continue;
            }
            const value = given[key];
            const problem = _fieldProblem(kind, value);
            if (problem !== "") {
                problems.push(key + ": " + problem);
                continue;
            }
            facts[key] = kind === "forwarding" ? { ipv4: value.ipv4 ?? null, ipv6: value.ipv6 ?? null } : value;
        }
        return { facts: facts, problems: problems };
    }

    // ---- The data directory (module.dataDirectory) ----

    // "<dataHome>/h2s-shell/module-data" — or "" with no data home
    function dataRoot(dataHome) {
        const base = absolutePath(dataHome);
        return base === "" ? "" : (base === "/" ? "" : base) + "/" + dataDirectoryName;
    }

    // A module's: "<root>/<id>" — or "" with no root or an id that is no module id
    function dataDirectory(root, id) {
        const base = absolutePath(root);
        return base === "" || !/^[a-z][a-z0-9_-]{0,31}$/.test(String(id ?? "")) ? "" : base + "/" + id;
    }

    // The script that makes the data directories, run as the user: $1 the root, or "" — then
    // a private temporary home is made first (mktemp -d, below $2, or /tmp when $2 is not an
    // absolute directory: module test mode) and named on a line "home <path>" — then the
    // ids. Under umask 077, so a directory it makes is 700. From the data home down (the
    // root less "/h2s-shell/module-data") it goes into each part with `cd -P`, then checks
    // the directory it is in: owned by the user or root, and not writable by group or others
    // unless it is root's with the sticky bit (/tmp) — so no other user can swap a part
    // below it. Below the data home no part may be a link. The root and each module's
    // directory must be the user's own besides, and are then made 700 (`chmod 700 .`: the
    // directory checked, not whatever a name leads to by then); one that others could write
    // before is refused, not closed, since what they put there would stay. One line per id:
    // "made <id>" or "failed <id>"; "root-failed" when the root cannot be used.
    readonly property string makeScript: [
        "umask 077",
        "root=$1; base=$2; shift 2",
        "if [ -z \"$root\" ]; then",
        "  case $base in /*) [ -d \"$base\" ] || base=/tmp ;; *) base=/tmp ;; esac",
        "  home=$(mktemp -d \"$base/h2s-module-data.XXXXXX\") || { echo root-failed; exit 3; }",
        "  printf 'home %s\\n' \"$home\"",
        "  root=$home/.local/share/" + "h2s-shell/module-data",
        "fi",
        "fail() { echo root-failed; exit 3; }",
        "case $root in /h2s-shell/module-data) data=/ ;; /*/h2s-shell/module-data) data=${root%/h2s-shell/module-data} ;; *) fail ;; esac",
        "uid=$(id -u) || fail",
        // The directory it is in: the user's or root's, not writable by group or others
        // unless root's and sticky
        "safe() {",
        "  set -- $(stat -c '%u %a' . 2> /dev/null)",
        "  [ $# -eq 2 ] || return 1",
        "  [ \"$1\" = \"$uid\" ] || [ \"$1\" = 0 ] || return 1",
        "  [ $((0$2 & 022)) -eq 0 ] || { [ \"$1\" = 0 ] && [ $((0$2 & 01000)) -ne 0 ]; }",
        "}",
        // Into a part below, made when missing; never a link
        "step() { mkdir -- \"$1\" 2> /dev/null; [ ! -L \"$1\" ] && cd -P -- \"$1\" 2> /dev/null; }",
        // The user's own, safe, then 700
        "own() { safe && [ -O . ] && chmod 700 . 2> /dev/null; }",
        "mkdir -p -- \"$data\" 2> /dev/null",
        "cd -P -- \"$data\" 2> /dev/null && safe || fail",
        "step h2s-shell && safe || fail",
        "step module-data && own || fail",
        "for id; do",
        "  case $id in ''|*[!a-z0-9_-]*) echo \"failed $id\"; continue ;; esac",
        "  if ( step \"$id\" && own ); then echo \"made $id\"; else echo \"failed $id\"; fi",
        "done"
    ].join("\n")

    // The script's lines for the ids asked → { home (the temporary home it made, or ""),
    // made: { <id>: true | false } } — an id it did not answer for is false
    function makeAnswers(lines, ids) {
        const made = {};
        let home = "";
        const told = {};
        for (const line of Array.isArray(lines) ? lines : []) {
            const text = String(line);
            if (text.startsWith("home ") && home === "")
                home = absolutePath(text.slice(5));
            const match = /^(made|failed) ([a-z][a-z0-9_-]{0,31})$/.exec(text);
            if (match)
                told[match[2]] = match[1] === "made";
        }
        for (const id of Array.isArray(ids) ? ids : [])
            made[id] = told[id] === true;
        return { home: home, made: made };
    }
}
