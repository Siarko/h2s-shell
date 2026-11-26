import QtQuick
import Quickshell.Io

// The last step of a restore that puts back side files (ConfigRestore), and the clean-up of
// one cut short (ConfigMigration, at start, before the config is read). A staging folder in
// config.json's folder (`.config-restore.*`, private) holds the restored config.json and the
// side files under new/; swap() checks every place (no link, nothing but a file where a file
// goes; a file it replaces or removes needs a backup to be kept in), writes its journal
// (`entries`, `keep`), copies the files it replaces or removes into the new backup's side
// folder with the list of those it creates (hash and path: a restore of that backup removes
// them only unchanged), keeps them in the staging folder (old/, old-config.json), renames
// config.json into place and then each side file (a crash between leaves
// the old config with newer side files, which the migrations run again on, never a migrated
// config with old side files, which they would not reach again), marks `done` and removes the
// staging folder. A step that fails, and recover() on a staging folder left by a crash, put
// back what the journal says was done; when a step of that fails, the staging folder and the
// backup's copies stay where they are (the next start tries again) and it is said. A folder
// made for a side file whose folder was gone stays.
QtObject {
    id: root

    readonly property bool running: _swapper.running || _recoverer.running

    // Test seam: the swap stops (as a crash would) after this many renames, config.json's
    // first; -1 never
    property int stopAfter: -1

    // The putting back, a shell function: $1 the staging folder, $dir the config's folder. The
    // journal: `entries` (all, written before any change), `moved` (each step, written just
    // before it is taken; the last one dropped again when it fails), `config-moved` (the same
    // for config.json). Undone newest first, each step's line dropped once it is undone, so a
    // putting back that stops at a failure goes on from there the next time
    readonly property string _recoverFunction: "recover() { st=$1; "
        + "if [ ! -f \"$st/entries\" ] || [ -f \"$st/done\" ]; then rm -rf -- \"$st\"; return 0; fi; "
        + "keep=$(cat -- \"$st/keep\" 2>/dev/null); "
        + "while [ -s \"$st/moved\" ]; do entry=$(tail -n 1 -- \"$st/moved\"); file=${entry#?:}; "
        + "if [ -e \"$st/old/$file\" ]; then mv -f -- \"$st/old/$file\" \"$dir/$file\"; "
        + "else case $entry in w:*) rm -f -- \"$dir/$file\";; *) true;; esac; fi "
        + "|| { echo \"could not put back $file: kept in $st\" >&2; return 1; }; "
        + "sed -i '$d' -- \"$st/moved\" || return 1; done; "
        + "if [ -f \"$st/config-moved\" ]; then "
        + "if [ -e \"$st/old-config.json\" ]; then mv -f -- \"$st/old-config.json\" \"$dir/config.json\"; else rm -f -- \"$dir/config.json\"; fi "
        + "|| { echo \"could not put back config.json: kept in $st\" >&2; return 1; }; "
        + "rm -f -- \"$st/config-moved\" || return 1; fi; "
        + "if [ -n \"$keep\" ]; then rm -rf -- \"$dir/backup-side-files/$keep\"; fi; "
        + "rm -rf -- \"$st\"; return 0; }; "

    // $1 the folder, $2 the staging folder, $3 the backup just made ("" none), $4 stopAfter,
    // then an entry per side file: "w:<path>" put back from new/, "r:<path>" removed
    readonly property string _swapScript: "dir=$1; stage=$2; keep=$3; stop=$4; shift 4; side=\"$dir/backup-side-files\"; config=\"$dir/config.json\"; umask 077; "
        + _recoverFunction
        + "fail() { echo \"$1: nothing restored\" >&2; recover \"$stage\"; exit 1; }; "
        + "if [ -L \"$config\" ]; then fail \"config.json is a link\"; fi; "
        + "if [ -e \"$config\" ] && [ ! -f \"$config\" ]; then fail \"config.json is not a regular file\"; fi; "
        + "if [ -L \"$stage/config.json\" ] || [ ! -f \"$stage/config.json\" ]; then fail \"the restored config was not staged\"; fi; "
        + "for entry in \"$@\"; do file=${entry#?:}; "
        + "path=$dir; rest=$file; "
        + "while [ \"${rest#*/}\" != \"$rest\" ]; do path=\"$path/${rest%%/*}\"; rest=${rest#*/}; "
        + "if [ -L \"$path\" ]; then fail \"${path#\"$dir\"/} is a link\"; fi; "
        + "if [ -e \"$path\" ] && [ ! -d \"$path\" ]; then fail \"${path#\"$dir\"/} is not a folder\"; fi; done; "
        + "if [ -L \"$dir/$file\" ]; then fail \"$file is a link\"; fi; "
        + "if [ -e \"$dir/$file\" ] && [ ! -f \"$dir/$file\" ]; then fail \"$file is not a regular file\"; fi; "
        + "if [ -e \"$dir/$file\" ] && [ -z \"$keep\" ]; then fail \"no config.json to back up with $file\"; fi; "
        + "case $entry in w:*) if [ -L \"$stage/new/$file\" ] || [ ! -f \"$stage/new/$file\" ]; then fail \"$file was not staged\"; fi;; "
        + "r:*) ;; *) fail \"$entry is no side file entry\";; esac; "
        + "done; "
        + "if [ -n \"$keep\" ]; then "
        + "if [ -L \"$side\" ]; then fail \"backup-side-files is a link\"; fi; "
        + "if [ -e \"$side/$keep\" ] || [ -L \"$side/$keep\" ]; then fail \"the side files of $keep are there already\"; fi; fi; "
        + "{ printf '%s\\n' \"$keep\" > \"$stage/keep\" && : > \"$stage/created\" && "
        + "for entry in \"$@\"; do printf '%s\\n' \"$entry\"; done > \"$stage/entries\"; } || fail \"could not write the journal\"; "
        + "for entry in \"$@\"; do file=${entry#?:}; "
        + "if [ -f \"$dir/$file\" ]; then "
        + "{ mkdir -p -- \"$side/$keep/$(dirname -- \"$file\")\" && cp -- \"$dir/$file\" \"$side/$keep/$file\"; } || fail \"could not back up $file\"; "
        + "else case $entry in w:*) { hash=$(md5sum < \"$stage/new/$file\") && printf '%s %s\\n' \"${hash%% *}\" \"$file\" >> \"$stage/created\"; } "
        + "|| fail \"could not list the files created\";; esac; fi; done; "
        + "if [ -n \"$keep\" ] && [ -s \"$stage/created\" ]; then "
        + "{ mkdir -p -- \"$side/$keep\" && cp -- \"$stage/created\" \"$side/$keep/.created-files\"; } || fail \"could not list the files created\"; fi; "
        + "for entry in \"$@\"; do file=${entry#?:}; if [ -f \"$dir/$file\" ]; then "
        + "{ mkdir -p -- \"$stage/old/$(dirname -- \"$file\")\" && { ln -- \"$dir/$file\" \"$stage/old/$file\" 2>/dev/null || cp -p -- \"$dir/$file\" \"$stage/old/$file\"; }; } "
        + "|| fail \"could not keep $file\"; "
        + "case $entry in w:*) chmod --reference=\"$dir/$file\" -- \"$stage/new/$file\" || fail \"could not keep the mode of $file\";; esac; fi; done; "
        + "if [ -f \"$config\" ]; then "
        + "{ { ln -- \"$config\" \"$stage/old-config.json\" 2>/dev/null || cp -p -- \"$config\" \"$stage/old-config.json\"; } "
        + "&& chmod --reference=\"$config\" -- \"$stage/config.json\"; } || fail \"could not keep config.json\"; "
        + "else chmod 600 -- \"$stage/config.json\" || fail \"could not restrict config.json\"; fi; "
        + ": > \"$stage/moved\" && : > \"$stage/config-moved\" || fail \"could not write the journal\"; "
        + "mv -f -- \"$stage/config.json\" \"$config\" || { rm -f -- \"$stage/config-moved\"; fail \"could not write config.json\"; }; "
        + "count=0; if [ \"$stop\" = 0 ]; then exit 3; fi; "
        + "for entry in \"$@\"; do file=${entry#?:}; "
        + "printf '%s\\n' \"$entry\" >> \"$stage/moved\" || fail \"could not write the journal\"; "
        + "case $entry in "
        + "w:*) mkdir -p -- \"$dir/$(dirname -- \"$file\")\" && mv -f -- \"$stage/new/$file\" \"$dir/$file\";; "
        + "r:*) rm -f -- \"$dir/$file\";; "
        + "esac || { sed -i '$d' -- \"$stage/moved\"; fail \"could not change $file\"; }; "
        + "count=$((count + 1)); if [ \"$stop\" = $count ]; then exit 3; fi; done; "
        + ": > \"$stage/done\"; rm -rf -- \"$stage\"; exit 0"

    // $1 the folder: each staging folder left there put back (or finished: `done`)
    readonly property string _recoverScript: "dir=$1; status=0; " + _recoverFunction
        + "for st in \"$dir\"/.config-restore.*; do "
        + "if [ -d \"$st\" ] && [ ! -L \"$st\" ]; then recover \"$st\" || status=1; fi; done; exit $status"

    property var _done: null

    // `entries`: "w:<path>" | "r:<path>". `done({ ok, problem })`; false when one runs
    function swap(dir, stage, keep, entries, done) {
        if (running)
            return false;
        _done = done ?? null;
        _swapper.command = ["sh", "-c", _swapScript, "sh", dir, stage, keep ?? "", stopAfter >= 0 ? String(stopAfter) : ""]
            .concat(Array.from(entries ?? []));
        _swapper.running = true;
        return true;
    }

    // Puts back what a restore cut short left in `dir`. `done({ ok, problem })`; false when one runs
    function recover(dir, done) {
        if (running)
            return false;
        _done = done ?? null;
        _recoverer.command = ["sh", "-c", _recoverScript, "sh", dir];
        _recoverer.running = true;
        return true;
    }

    // The scripts' own line comes last, after what a command they ran said
    function _problem(text, fallback) {
        const lines = String(text ?? "").trim().split("\n");
        const last = (lines[lines.length - 1] ?? "").slice(0, 200);
        return last !== "" ? last : fallback;
    }

    function _answer(code, errors, fallback) {
        const done = _done;
        _done = null;
        if (typeof done === "function")
            done({ ok: code === 0, problem: code === 0 ? "" : _problem(errors, fallback) });
    }

    property Process _swapper: Process {
        stderr: StdioCollector { id: _swapErrors }
        onExited: code => root._answer(code, _swapErrors.text, code === 3 ? "stopped (test seam)" : "could not restore the side files")
    }

    property Process _recoverer: Process {
        stderr: StdioCollector { id: _recoverErrors }
        onExited: code => root._answer(code, _recoverErrors.text, "could not put back a restore cut short")
    }
}
