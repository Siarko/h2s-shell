import QtQuick
import Quickshell.Io

// The last step of a restore that puts back side files (ConfigRestore), and the clean-up of
// one cut short (ConfigMigration, at start, before the config is read). A staging folder in
// config.json's folder (`.config-restore.*`, private) holds the restored config.json and the
// side files under new/; swap() takes the folder's lock (flock: a second shell's clean-up
// waits for it), checks every place (no link, nothing but a file where a file goes; a file it
// replaces or removes needs a backup to be kept in; no other restore cut short and not yet
// put back), writes its journal (`keep`, `entries`), copies the files it replaces or removes
// into the new backup's side folder with the list of those it creates (hash and path: a
// restore of that backup removes them only unchanged), keeps them in the staging folder
// (old/, old-config.json), renames config.json into place and then each side file (a crash
// between leaves the old config with newer side files, which the migrations run again on,
// never a migrated config with old side files, which they would not reach again), marks
// `done` and removes the staging folder. A step that fails, and recover() on a staging folder
// left by a crash, put back what the journal says was done, under the same lock. Each step is
// journalled before it is taken, with whether its file was there before; putting back copies
// from old/ and never removes it, so a putting back cut short anywhere is taken again from the
// start with the same result. When a step of it fails, the staging folder and the backup's
// copies stay where they are (the next start tries again) and it is said (`stuck`). A folder
// made for a side file whose folder was gone stays.
QtObject {
    id: root

    readonly property bool running: _swapper.running || _recoverer.running

    // Test seams: the swap, and a putting back, stop (as a crash would) after this many of
    // their steps; -1 never
    property int stopAfter: -1
    property int recoverStopAfter: -1

    // Shared by both scripts. `tick`: one step done (the test seam). `sidepath`: a journal's
    // path is one a restore may write (ConfigBackupRules.sidePathProblem's rules). `placeok`:
    // no link and nothing but a folder on the way to $dir/$1 (the problem on stdout).
    // `putback`: $1 copied (linked) to $2 by a rename, $1 left in place (nothing when $2 is $1
    // already: a step cut short before it was taken)
    readonly property string _commonFunctions: "tick() { ticks=$((ticks + 1)); if [ \"$stop\" = \"$ticks\" ]; then exit 3; fi; }; "
        + "sidepath() { case $1 in ''|/*|*/|.|..|./*|../*|*/.|*/..|*/./*|*/../*|*//*|config.json|.created-files|*[[:cntrl:]]*) return 1;; esac; "
        + "case ${1%%/*} in config.json.bak-*|backup-side-files|.config-restore.*) return 1;; esac; return 0; }; "
        + "placeok() { _path=$dir; _rest=$1; "
        + "while [ \"${_rest#*/}\" != \"$_rest\" ]; do _path=\"$_path/${_rest%%/*}\"; _rest=${_rest#*/}; "
        + "if [ -L \"$_path\" ]; then echo \"${_path#\"$dir\"/} is a link\"; return 1; fi; "
        + "if [ -e \"$_path\" ] && [ ! -d \"$_path\" ]; then echo \"${_path#\"$dir\"/} is not a folder\"; return 1; fi; done; "
        + "if [ -d \"$dir/$1\" ] && [ ! -L \"$dir/$1\" ]; then echo \"$1 is a folder\"; return 1; fi; return 0; }; "
        + "putback() { if [ \"$1\" -ef \"$2\" ]; then return 0; fi; rm -f -- \"$st/put\" && { ln -- \"$1\" \"$st/put\" 2>/dev/null || cp -p -- \"$1\" \"$st/put\"; } "
        + "&& mkdir -p -- \"$(dirname -- \"$2\")\" && mv -f -- \"$st/put\" \"$2\"; }; "
        + "keepok() { case $1 in '') return 0;; */*|*[[:cntrl:]]*) return 1;; config.json.bak-?*) return 0;; esac; return 1; }; "

    // The putting back, a shell function: $1 the staging folder, $dir the config's folder. The
    // journal: `keep` and `entries` (written whole before any change), `moved` (a line per step,
    // "<w|r><1|0>:<path>", 1 when the file was there before, written just before the step),
    // `config-moved` (1 or 0 the same, written before config.json is renamed). Undone newest
    // first, a step's line dropped once it is undone; the copies in old/ stay until the end,
    // so undoing a step again gives the same. The new backup's copies are removed last, only
    // when every file is back as old/ holds it
    readonly property string _recoverFunction: "recover() { st=$1; "
        + "if [ ! -f \"$st/entries\" ] || [ -f \"$st/done\" ]; then rm -rf -- \"$st\"; return 0; fi; "
        + "bad() { echo \"the journal in $st cannot be read ($1): kept\" >&2; return 1; }; "
        + "[ -f \"$st/keep\" ] || { bad keep; return 1; }; keep=$(cat -- \"$st/keep\") || { bad keep; return 1; }; "
        + "keepok \"$keep\" || { bad keep; return 1; }; "
        + "while [ -s \"$st/moved\" ]; do entry=$(tail -n 1 -- \"$st/moved\") || { bad moved; return 1; }; "
        + "kind=${entry%%:*}; file=${entry#*:}; "
        + "case $kind in w0|w1|r0|r1) ;; *) bad \"$entry\"; return 1;; esac; "
        + "{ sidepath \"$file\" && grep -Fxq -- \"${kind%?}:$file\" \"$st/entries\"; } || { bad \"$entry\"; return 1; }; "
        + "problem=$(placeok \"$file\") || { echo \"could not put back $file ($problem): kept in $st\" >&2; return 1; }; "
        + "case $kind in "
        + "?1) if [ -L \"$st/old/$file\" ] || [ ! -f \"$st/old/$file\" ]; then echo \"the copy of $file is missing: kept in $st\" >&2; return 1; fi; "
        + "putback \"$st/old/$file\" \"$dir/$file\";; "
        + "*) rm -f -- \"$dir/$file\";; esac "
        + "|| { echo \"could not put back $file: kept in $st\" >&2; return 1; }; tick; "
        + "sed -i '$d' -- \"$st/moved\" || return 1; tick; done; "
        + "if [ -f \"$st/config-moved\" ]; then "
        + "if [ -d \"$dir/config.json\" ] && [ ! -L \"$dir/config.json\" ]; then echo \"could not put back config.json (a folder): kept in $st\" >&2; return 1; fi; "
        + "case $(cat -- \"$st/config-moved\") in "
        + "1) if [ -L \"$st/old-config.json\" ] || [ ! -f \"$st/old-config.json\" ]; then echo \"the copy of config.json is missing: kept in $st\" >&2; return 1; fi; "
        + "putback \"$st/old-config.json\" \"$dir/config.json\";; "
        + "0) rm -f -- \"$dir/config.json\";; "
        + "*) bad config-moved; return 1;; esac "
        + "|| { echo \"could not put back config.json: kept in $st\" >&2; return 1; }; tick; "
        + "rm -f -- \"$st/config-moved\" || return 1; tick; fi; "
        + "copies=\"$dir/backup-side-files/$keep\"; "
        + "if [ -n \"$keep\" ] && [ ! -L \"$dir/backup-side-files\" ] && [ ! -L \"$copies\" ] && [ -d \"$copies\" ]; then same=1; "
        + "while IFS= read -r entry; do file=${entry#?:}; "
        + "if [ -f \"$st/old/$file\" ] && [ \"$(md5sum < \"$st/old/$file\")\" != \"$(md5sum < \"$dir/$file\" 2>/dev/null)\" ]; then same=0; fi; "
        + "done < \"$st/entries\"; "
        + "if [ \"$same\" = 1 ]; then rm -rf -- \"$copies\" || return 1; else echo \"$copies kept: a file put back differs from its copy\" >&2; fi; tick; fi; "
        + "rm -rf -- \"$st\"; return 0; }; "

    // $1 the folder, $2 the staging folder, $3 the backup just made ("" none), $4 stopAfter,
    // then an entry per side file: "w:<path>" put back from new/, "r:<path>" removed. Exit 4:
    // it failed and could not put back what it had done (the staging folder kept)
    readonly property string _swapScript: "dir=$1; stage=$2; keep=$3; stop=$4; shift 4; side=\"$dir/backup-side-files\"; config=\"$dir/config.json\"; umask 077; ticks=0; "
        + _commonFunctions + _recoverFunction
        + "fail() { echo \"$1: nothing restored\" >&2; stop=; recover \"$stage\" || exit 4; exit 1; }; "
        + "exec 9< \"$stage\" || { echo \"could not open the staging folder: nothing restored\" >&2; exit 1; }; "
        + "flock -w 30 9 || { echo \"could not lock the staging folder: nothing restored\" >&2; exit 1; }; "
        + "if [ ! -d \"$stage\" ]; then echo \"the staging folder is gone: nothing restored\" >&2; exit 1; fi; "
        + "for other in \"$dir\"/.config-restore.*; do "
        + "if [ \"$other\" != \"$stage\" ] && [ -f \"$other/entries\" ]; then fail \"a restore cut short is not put back yet\"; fi; done; "
        + "keepok \"$keep\" || fail \"$keep is no backup's name\"; "
        + "if [ -L \"$config\" ]; then fail \"config.json is a link\"; fi; "
        + "if [ -e \"$config\" ] && [ ! -f \"$config\" ]; then fail \"config.json is not a regular file\"; fi; "
        + "if [ -L \"$stage/config.json\" ] || [ ! -f \"$stage/config.json\" ]; then fail \"the restored config was not staged\"; fi; "
        + "for entry in \"$@\"; do file=${entry#?:}; "
        + "case $entry in w:*|r:*) ;; *) fail \"$entry is no side file entry\";; esac; "
        + "sidepath \"$file\" || fail \"$file is no side file's name\"; "
        + "problem=$(placeok \"$file\") || fail \"$problem\"; "
        + "if [ -L \"$dir/$file\" ]; then fail \"$file is a link\"; fi; "
        + "if [ -e \"$dir/$file\" ] && [ ! -f \"$dir/$file\" ]; then fail \"$file is not a regular file\"; fi; "
        + "if [ -e \"$dir/$file\" ] && [ -z \"$keep\" ]; then fail \"no config.json to back up with $file\"; fi; "
        + "case $entry in w:*) if [ -L \"$stage/new/$file\" ] || [ ! -f \"$stage/new/$file\" ]; then fail \"$file was not staged\"; fi;; esac; "
        + "done; "
        + "if [ -n \"$keep\" ]; then "
        + "if [ -L \"$side\" ]; then fail \"backup-side-files is a link\"; fi; "
        + "if [ -e \"$side/$keep\" ] || [ -L \"$side/$keep\" ]; then fail \"the side files of $keep are there already\"; fi; fi; "
        + "{ printf '%s\\n' \"$keep\" > \"$stage/keep.new\" && mv -f -- \"$stage/keep.new\" \"$stage/keep\" && : > \"$stage/created\" && "
        + "for entry in \"$@\"; do printf '%s\\n' \"$entry\"; done > \"$stage/entries.new\" && mv -f -- \"$stage/entries.new\" \"$stage/entries\"; } "
        + "|| fail \"could not write the journal\"; tick; "
        + "for entry in \"$@\"; do file=${entry#?:}; "
        + "if [ -f \"$dir/$file\" ]; then "
        + "{ mkdir -p -- \"$side/$keep/$(dirname -- \"$file\")\" && cp -- \"$dir/$file\" \"$side/$keep/$file\"; } || fail \"could not back up $file\"; "
        + "else case $entry in w:*) { hash=$(md5sum < \"$stage/new/$file\") && printf '%s %s\\n' \"${hash%% *}\" \"$file\" >> \"$stage/created\"; } "
        + "|| fail \"could not list the files created\";; esac; fi; done; "
        + "if [ -n \"$keep\" ] && [ -s \"$stage/created\" ]; then "
        + "{ mkdir -p -- \"$side/$keep\" && cp -- \"$stage/created\" \"$side/$keep/.created-files\"; } || fail \"could not list the files created\"; fi; tick; "
        + "for entry in \"$@\"; do file=${entry#?:}; if [ -f \"$dir/$file\" ]; then "
        + "{ mkdir -p -- \"$stage/old/$(dirname -- \"$file\")\" && { ln -- \"$dir/$file\" \"$stage/old/$file\" 2>/dev/null || cp -p -- \"$dir/$file\" \"$stage/old/$file\"; }; } "
        + "|| fail \"could not keep $file\"; "
        + "case $entry in w:*) chmod --reference=\"$dir/$file\" -- \"$stage/new/$file\" || fail \"could not keep the mode of $file\";; esac; fi; done; "
        + "existed=0; if [ -f \"$config\" ]; then existed=1; "
        + "{ { ln -- \"$config\" \"$stage/old-config.json\" 2>/dev/null || cp -p -- \"$config\" \"$stage/old-config.json\"; } "
        + "&& chmod --reference=\"$config\" -- \"$stage/config.json\"; } || fail \"could not keep config.json\"; "
        + "else chmod 600 -- \"$stage/config.json\" || fail \"could not restrict config.json\"; fi; tick; "
        + "{ : > \"$stage/moved\" && printf '%s\\n' \"$existed\" > \"$stage/config-moved.new\" && mv -f -- \"$stage/config-moved.new\" \"$stage/config-moved\"; } "
        + "|| fail \"could not write the journal\"; tick; "
        + "mv -f -- \"$stage/config.json\" \"$config\" || fail \"could not write config.json\"; tick; "
        + "for entry in \"$@\"; do file=${entry#?:}; existed=0; if [ -f \"$dir/$file\" ]; then existed=1; fi; "
        + "printf '%s\\n' \"${entry%%:*}$existed:$file\" >> \"$stage/moved\" || fail \"could not write the journal\"; tick; "
        + "case $entry in "
        + "w:*) mkdir -p -- \"$dir/$(dirname -- \"$file\")\" && mv -f -- \"$stage/new/$file\" \"$dir/$file\";; "
        + "r:*) rm -f -- \"$dir/$file\";; "
        + "esac || fail \"could not change $file\"; tick; done; "
        + ": > \"$stage/done\"; tick; rm -rf -- \"$stage\"; exit 0"

    // $1 the folder, $2 recoverStopAfter: each staging folder left there put back (or
    // finished: `done`), each under its lock; one another shell removed meanwhile is done
    readonly property string _recoverScript: "dir=$1; stop=$2; ticks=0; status=0; " + _commonFunctions + _recoverFunction
        + "for st0 in \"$dir\"/.config-restore.*; do "
        + "if [ -d \"$st0\" ] && [ ! -L \"$st0\" ]; then "
        + "( { exec 9< \"$st0\"; } 2>/dev/null || { if [ -e \"$st0\" ]; then echo \"could not open $st0: kept\" >&2; exit 1; fi; exit 0; }; "
        + "flock -w 30 9 || { echo \"could not lock $st0: kept\" >&2; exit 1; }; "
        + "if [ ! -d \"$st0\" ]; then exit 0; fi; recover \"$st0\" ); "
        + "code=$?; if [ \"$code\" = 3 ]; then exit 3; fi; if [ \"$code\" != 0 ]; then status=1; fi; fi; done; exit $status"

    property var _done: null

    // `entries`: "w:<path>" | "r:<path>". `done({ ok, problem, stuck })` (stuck: a staging
    // folder stays to be put back at the next start); false when one runs
    function swap(dir, stage, keep, entries, done) {
        if (running)
            return false;
        _done = done ?? null;
        _swapper.command = ["sh", "-c", _swapScript, "sh", dir, stage, keep ?? "", stopAfter >= 0 ? String(stopAfter) : ""]
            .concat(Array.from(entries ?? []));
        _swapper.running = true;
        return true;
    }

    // Puts back what a restore cut short left in `dir`. `done({ ok, problem, stuck })`; false
    // when one runs
    function recover(dir, done) {
        if (running)
            return false;
        _done = done ?? null;
        _recoverer.command = ["sh", "-c", _recoverScript, "sh", dir, recoverStopAfter >= 0 ? String(recoverStopAfter) : ""];
        _recoverer.running = true;
        return true;
    }

    // The scripts' own line comes last, after what a command they ran said
    function _problem(text, fallback) {
        const lines = String(text ?? "").trim().split("\n");
        const last = (lines[lines.length - 1] ?? "").slice(0, 200);
        return last !== "" ? last : fallback;
    }

    function _answer(code, stuck, errors, fallback) {
        const done = _done;
        _done = null;
        if (typeof done === "function")
            done({ ok: code === 0, problem: code === 0 ? "" : _problem(errors, fallback), stuck: stuck });
    }

    property Process _swapper: Process {
        stderr: StdioCollector { id: _swapErrors }
        onExited: code => root._answer(code, code === 3 || code === 4, _swapErrors.text, code === 3 ? "stopped (test seam)" : "could not restore the side files")
    }

    property Process _recoverer: Process {
        stderr: StdioCollector { id: _recoverErrors }
        onExited: code => root._answer(code, code !== 0, _recoverErrors.text, "could not put back a restore cut short")
    }
}
