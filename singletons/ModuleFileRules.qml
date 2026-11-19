pragma Singleton

import Quickshell
import QtQuick

// The module system's decisions about paths and files (ModuleRules.qml has the overview):
// canonical paths and a module's directories, the files a module names and the check
// they pass before anything is loaded, and the start guard. Pure, checked by
// tests/ModuleRulesTest.qml; the scripts here are run by ModuleHost.
Singleton {
    id: root

    // ---- Paths ----

    // A path made canonical without the file system: absolute, no "." or ".." segments, no
    // repeated or trailing "/". "" when it is not an absolute path. Two spellings of one
    // directory load its singletons twice (plan §2: "a//b" does, "a/./b" does not, a symlink
    // does): the launcher resolves symlinks (realpath), this takes care of the rest.
    function canonicalPath(path) {
        if (typeof path !== "string" || !path.startsWith("/") || path.includes("\0"))
            return "";
        const parts = [];
        for (const part of path.split("/")) {
            if (part === "" || part === ".")
                continue;
            if (part === "..")
                parts.pop();
            else
                parts.push(part);
        }
        return "/" + parts.join("/");
    }

    // H2S_SHELL_MODULES (colon-separated) or a list given to the host: the canonical module
    // directories, in order, each once; what was not an absolute path is reported
    function moduleDirectories(value) {
        const list = typeof value === "string" ? value.split(":") : Array.isArray(value) ? value : [];
        const directories = [];
        const ignored = [];
        for (const entry of list) {
            if (entry === "" || entry === undefined || entry === null)
                continue;
            const canonical = canonicalPath(entry);
            if (canonical === "" || canonical === "/") {
                ignored.push(String(entry));
                continue;
            }
            if (!directories.includes(canonical))
                directories.push(canonical);
        }
        return { directories: directories, ignored: ignored };
    }

    // A file of a module, as given in its manifest: "" when fine, else why not
    function pathProblem(path) {
        if (typeof path !== "string" || path === "")
            return "not a file name";
        if (path.length > 300)
            return "too long";
        if (path.startsWith("/"))
            return "an absolute path";
        if (!/^[A-Za-z0-9_][A-Za-z0-9_./-]*$/.test(path))
            return "has characters a module file name may not have";
        if (path.split("/").some(part => part === ".." || part === "." || part === ""))
            return "leaves the module's directory or is not a plain path";
        if (!path.endsWith(".qml"))
            return "not a .qml file";
        return "";
    }

    // A directory of a module, as given in its manifest (testPrograms): "" when fine, else
    // why not — as pathProblem, without the .qml, a trailing "/" allowed
    function directoryProblem(path) {
        if (typeof path !== "string" || path === "")
            return "not a directory name";
        if (path.length > 300)
            return "too long";
        if (path.startsWith("/"))
            return "an absolute path";
        if (!/^[A-Za-z0-9_][A-Za-z0-9_./-]*$/.test(path))
            return "has characters a module file name may not have";
        if (path.replace(/\/$/, "").split("/").some(part => part === ".." || part === "." || part === ""))
            return "leaves the module's directory or is not a plain path";
        return "";
    }

    // The file:// URL of a module's file. Only what a URL cannot hold as it is is escaped,
    // so that one file always gets one spelling
    function fileUrl(directory, relative) {
        const path = canonicalPath(directory + "/" + relative);
        return "file://" + path.replace(/%/g, "%25").replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    // The module's files the host should check imports of: main and every component its
    // entries name, each once
    function manifestFiles(manifest) {
        const files = [];
        const add = file => {
            if (typeof file === "string" && file !== "" && !files.includes(file))
                files.push(file);
        };
        add(manifest?.main);
        for (const widget of manifest?.widgets ?? []) {
            add(widget.widget);
            add(widget.popupPanel);
            add(widget.settings);
        }
        for (const page of manifest?.settingsPages ?? [])
            add(page.component);
        for (const slot of manifest?.slots ?? [])
            add(slot.component);
        return files;
    }

    // The QML files a qmldir names (its types and singletons), relative to its directory;
    // plugins, imports and other directives are skipped
    function qmldirFiles(text) {
        const files = [];
        if (typeof text !== "string")
            return files;
        for (const rawLine of text.slice(0, ModuleRules.maxHeaderBytes).split("\n")) {
            const words = rawLine.replace(/#.*$/, "").trim().split(/\s+/);
            if (words[0] === "singleton" || words[0] === "internal")
                words.shift();
            if (words.length < 2 || !/^[A-Z]/.test(words[0]))
                continue;
            const file = words[words.length - 1];
            if (pathProblem(file) === "" && !files.includes(file))
                files.push(file);
        }
        return files;
    }

    // ---- The file check (part of the format, enforced before anything is loaded) ----
    //
    // Every file a module names — main, each entry's components, its tests, what its qmldir
    // lists — must resolve, symlinks followed, to a regular file inside the module's canonical
    // directory, of at most maxFileBytes. The host asks a process (a FIFO opened by
    // Qt.createComponent would block the GUI thread for as long as it has no writer; a link
    // can lead anywhere) before it reads or loads any of them. An entry whose file fails is
    // dropped with an error; a failing main or qmldir file fails the module (every file of
    // the module imports its directory, so a broken qmldir breaks them all).

    readonly property int maxFileBytes: 1024 * 1024

    // The import scan (importWarnings, importDeprecations, codeDeprecations) reads every QML
    // and JavaScript file under the module's directory, not only the ones it names: a file in
    // a subdirectory, one a Loader builds, or a script a file imports, imports as much as main
    // does. At most this many files, at most this many directories deep; of each, its first
    // ModuleRules.maxHeaderBytes (all the import reader looks at; the old ways in its code are
    // looked for there too). What it leaves out (more files, deeper ones, names it cannot read
    // back) or cannot read is one warning in the module's status (scanWarning): never
    // "nothing found".
    readonly property int maxScannedFiles: 100
    readonly property int scanDepth: 8
    // The listing's lines at most (a line per file found, one level deeper than scanDepth
    // too, so that deeper files are seen and counted)
    readonly property int maxListedLines: 400
    // The key the listing's answer and text are filed under, among a check's files
    readonly property string listKey: "*.qml"

    // The listing's answer and text → { files, skipped, more, failed }: the QML and
    // JavaScript files it names, relative to the module's directory, the first
    // maxScannedFiles of them, each once; `skipped` the ones found and left out — past
    // maxScannedFiles, deeper than scanDepth, a name that is not plainly a path inside the
    // directory (a line break or another control character in it, a ".." part); `more` when more may have been left
    // out than counted (the listing cut at maxListedLines, or a file deeper than scanDepth:
    // the listing looks one level further only); `failed` when it was not read whole
    // (no answer, find failing on a directory it could not read, no status line).
    function listing(answer, text) {
        const result = { files: [], skipped: 0, more: false, failed: false };
        if (answer !== "ok" || typeof text !== "string") {
            result.failed = true;
            return result;
        }
        const lines = text.split("\n");
        const status = /^status ([0-9]+)$/.exec(lines[lines.length - 1]);
        if (status) {
            lines.pop();
            result.failed = status[1] !== "0";
        } else if (lines.length >= maxListedLines) {
            result.more = true;
        } else {
            result.failed = true;
        }
        for (const line of lines) {
            // find prints every name ending in .qml or .js: a line that does not is a piece of
            // a name with a line break in it (its last piece is counted)
            if (!line.endsWith(".qml") && !line.endsWith(".js"))
                continue;
            const file = line.startsWith("./") ? line.slice(2) : "";
            const parts = file.split("/");
            if (file === "" || /[\x00-\x1f\x7f\\]/.test(file) || parts.some(part => part === ".." || part === "" || part === ".")) {
                result.skipped++;
                continue;
            }
            // Deeper than scanDepth: seen one level down only, so there may be more below
            if (parts.length - 1 > scanDepth) {
                result.skipped++;
                result.more = true;
                continue;
            }
            if (result.files.includes(file))
                continue;
            if (result.files.length >= maxScannedFiles) {
                result.skipped++;
                continue;
            }
            result.files.push(file);
        }
        return result;
    }

    // The status warning for an incomplete import scan: "" when every listed file was read.
    // `unread`: how many of the listed files the check did not read (gone, not a regular file
    // any more, a name not valid UTF-8, out of time).
    function scanWarning(listed, unread) {
        if (!listed || listed.failed)
            return "imports not checked: the file list could not be read";
        const count = (listed.skipped ?? 0) + (unread ?? 0);
        if (count === 0 && !listed.more)
            return "";
        return "imports not checked in " + count + (listed.more ? " or more files" : count === 1 ? " file" : " files");
    }

    // Of the listed files, the ones the check does not read already (`checked`: filesToCheck's)
    function scanOnly(listed, checked) {
        const named = (checked ?? []).map(entry => entry.file);
        return (listed ?? []).filter(file => !named.includes(file));
    }

    // The order of a check's triples: `asked` (each with `optional`: true for the listing and
    // the import scan's reads) → the required ones first, every module's, then the optional
    // ones, each group in its order. One process under one deadline reads them all, so a
    // module's many scanned files must never push another's main past it: a timeout costs
    // only the scan (a warning), never a module.
    function checkOrder(asked) {
        const list = asked ?? [];
        return list.filter(entry => entry?.optional !== true).concat(list.filter(entry => entry?.optional === true));
    }

    // The files of a module the check looks at: { file, kind } — kind "main", "entry",
    // "test" or "qmldir"; each file once (the first kind wins)
    function filesToCheck(manifest, qmldirText) {
        const files = [];
        const add = (file, kind) => {
            if (typeof file === "string" && file !== "" && !files.some(entry => entry.file === file))
                files.push({ file: file, kind: kind });
        };
        add(manifest?.main, "main");
        for (const file of manifestFiles(manifest))
            add(file, "entry");
        for (const file of qmldirFiles(qmldirText))
            add(file, "qmldir");
        for (const file of manifest?.tests ?? [])
            add(file, "test");
        return files;
    }

    // The check's shell script: arguments in triples (cap, directory, file); prints, per
    // triple, the file's text — each line prefixed "<index>:" — then "<index>\tok", or only
    // "<index>\t<why not>". By index, so no path is echoed back and parsed. The texts come
    // out of this process because reading is what can block (a mount that answers stat and
    // then hangs on read): the host reads no module file on the GUI thread — manifest, qmldir
    // and the texts for the import and property checks all come from here, under the host's
    // checkTimeoutMs, and a triple without its "ok" line when the deadline kills the process
    // counts as failed. The "ok" comes after the text, so a text cut short is never whole.
    //
    // Two kinds of triple more: a cap "list" lists the module's QML and JavaScript files
    // instead (the file is ignored) — regular files only, links not followed, hidden
    // directories skipped, not into another file system (-xdev), one level deeper than
    // scanDepth, at most maxListedLines — each line "<index>:./<path relative to the directory>", then
    // "<index>:status <find's exit status>" (not 0: a directory it could not read), then
    // "<index>\tok"; a cap "h<n>" reads the first n bytes of a file of any size (the import
    // scan needs only its header; no size asked). The module's real directory is resolved
    // once for its run of triples.
    readonly property string fileCheckScript: "i=0; last_dir=; "
        + "while [ $# -ge 3 ]; do cap=$1; dir=$2; file=$3; shift 3; "
        + "if [ \"$cap\" = list ]; then "
        + "if [ -d \"$dir\" ]; then ( cd -- \"$dir\" && find -P . -xdev -mindepth 1 -maxdepth " + (scanDepth + 2)
        + " -name '.*' -prune -o -type f \\( -name '*.qml' -o -name '*.js' \\) -print; echo \"status $?\" ) 2>/dev/null "
        + "| head -n " + maxListedLines + " | sed \"s/^/$i:/\"; printf '%s\\tok\\n' $i; "
        + "else printf '%s\\tcannot be listed\\n' $i; fi; i=$((i+1)); continue; fi; "
        + "whole=1; case $cap in h*) cap=${cap#h}; whole=0 ;; esac; "
        + "if [ \"$dir\" != \"$last_dir\" ]; then real_dir=$(realpath -e -- \"$dir\" 2>/dev/null) || real_dir=$dir; last_dir=$dir; fi; "
        + "if [ ! -e \"$dir/$file\" ] && [ ! -L \"$dir/$file\" ]; then printf '%s\\tdoes not exist\\n' $i; "
        + "elif ! real=$(realpath -e -- \"$dir/$file\" 2>/dev/null); then printf '%s\\tis a broken or looping link\\n' $i; "
        + "else case \"$real\" in \"$real_dir\"/*) "
        + "if [ ! -f \"$real\" ]; then printf '%s\\tis not a regular file\\n' $i; "
        + "else if [ \"$whole\" = 0 ]; then size=0; else size=$(stat -c %s -- \"$real\" 2>/dev/null) || size=-1; fi; "
        + "if [ \"$size\" -ge 0 ] && { [ \"$whole\" = 0 ] || [ \"$size\" -le \"$cap\" ]; }; then "
        + "{ head -c \"$cap\" -- \"$real\"; echo; } | sed \"s/^/$i:/\"; printf '%s\\tok\\n' $i; "
        + "else printf '%s\\tis larger than %s bytes\\n' $i \"$cap\"; fi; fi ;; "
        + "*) printf '%s\\tleaves the module directory through a link\\n' $i ;; esac; fi; "
        + "i=$((i+1)); done"

    // The check's output lines → { index: "ok" | why not }
    function parseFileCheck(lines) {
        const result = {};
        for (const line of lines ?? []) {
            const match = /^([0-9]+)\t(.*)$/.exec(String(line));
            if (match)
                result[match[1]] = match[2].slice(0, 200);
        }
        return result;
    }

    // The texts in the check's output lines → { index: text }, only of the files it answered
    // "ok" for (a text without its "ok" may be cut short)
    function fileTexts(lines) {
        const answered = parseFileCheck(lines);
        const parts = {};
        for (const line of lines ?? []) {
            const match = /^([0-9]+):/.exec(String(line));
            if (!match)
                continue;
            (parts[match[1]] = parts[match[1]] ?? []).push(String(line).slice(match[0].length));
        }
        const texts = {};
        for (const index of Object.keys(answered)) {
            // The script adds one line break after the text, so that a last line without one
            // is still a line of its own: joining the lines drops it again
            if (answered[index] === "ok")
                texts[index] = (parts[index] ?? []).join("\n");
        }
        return texts;
    }

    // A manifest without the entries whose files failed the check. `bad`: { file: why }.
    // → { manifest (a copy), errors, fatal: "" or why the module fails }
    function withoutBadFiles(manifest, bad, qmldirText) {
        const errors = [];
        const failing = file => typeof file === "string" && file !== "" && ModuleRules.has(bad ?? {}, file);
        const why = file => file + " " + bad[file];
        let fatal = "";
        if (failing(manifest?.main))
            fatal = "main " + why(manifest.main);
        for (const file of qmldirFiles(qmldirText)) {
            if (fatal === "" && failing(file))
                fatal = "qmldir names " + why(file);
        }
        const copy = Object.assign({}, manifest ?? {});
        const keep = (list, files, what) => (list ?? []).filter(entry => {
            const broken = files(entry).find(failing);
            if (broken !== undefined)
                errors.push(what(entry) + ": " + why(broken) + " (dropped)");
            return broken === undefined;
        });
        copy.widgets = keep(manifest?.widgets, entry => [entry.widget, entry.popupPanel, entry.settings], entry => "widget " + entry.type);
        copy.settingsPages = keep(manifest?.settingsPages, entry => [entry.component], entry => "settings page " + entry.id);
        copy.slots = keep(manifest?.slots, entry => [entry.component], entry => "slot " + entry.slot);
        copy.tests = (manifest?.tests ?? []).filter(file => {
            if (failing(file))
                errors.push("test " + why(file) + " (dropped)");
            return !failing(file);
        });
        return { manifest: copy, errors: errors, fatal: fatal };
    }

    // ---- The start guard (crash loops the launcher cannot see) ----
    //
    // Quickshell restarts a crashed shell in place — the same process, exec'd again — unless
    // it crashed within 10 s of starting; the launcher sees only processes, so it misses a
    // module that crashes the shell later, and `launch.sh -d` has no supervisor at all. So the
    // shell counts those relaunches itself: before any module is loaded the host runs
    // startGuardScript on $XDG_RUNTIME_DIR/h2s-shell-module-starts, which holds
    // "<identity> <count>". The identity is "<pid>:<crash>" — the shell's pid, and the
    // coredump pid Quickshell's crash handler put in the environment it exec'd the relaunch
    // with (__QUICKSHELL_CRASH_DUMP_PID, still readable in /proc/<pid>/environ after
    // Quickshell unsets it), "" for a process not relaunched after a crash. So:
    //   no crash marker                  a fresh process (a launch, a --restart, a launcher
    //                                    restart — which the launcher counts): 0
    //   the same identity as stored      a reload of the same relaunched process: unchanged
    //   the same pid, another crash      one more relaunch after a crash: count + 1
    // A start that lives guardClearMs writes its count back to 0. An orderly quit needs
    // nothing (the next start is a fresh process) — and could not do anything: Quickshell
    // stops all JavaScript before it tears a generation down. guardLimit or more: safe mode.
    readonly property int guardLimit: 2
    // The same window as the launcher's quick deaths (scripts/launch.sh: 30 s), so the two
    // counters tell one story: a start that lived 30 s was not a crash loop
    readonly property int guardClearMs: 30000

    // The guard's shell script: arguments the file, an identity to use instead of the
    // process's own ("" — the suites give one) and the shell's pid (the script's parent is
    // not the shell where it is started inside `timeout`; not a number: the parent).
    // Refuses anything but a plain file (a link, a FIFO: "refused <identity>"), prints
    // "<count> <identity>", writes the same (atomically)
    readonly property string startGuardScript: "file=$1; identity=$2; shell=$3; "
        + "case \"$shell\" in ''|*[!0-9]*) shell=$PPID ;; esac; "
        + "if [ -z \"$identity\" ]; then "
        + "crash=$(tr '\\000' '\\n' < /proc/$shell/environ 2>/dev/null | sed -n 's/^__QUICKSHELL_CRASH_DUMP_PID=//p' | head -n 1 | tr -cd 0-9); "
        + "identity=\"$shell:$crash\"; fi; "
        + "if [ -L \"$file\" ] || { [ -e \"$file\" ] && [ ! -f \"$file\" ]; }; then echo \"refused $identity\"; exit 0; fi; "
        + "stored=; old=0; if [ -f \"$file\" ]; then line=$(head -c 80 -- \"$file\" | head -n 1); stored=${line%% *}; "
        + "old=$(printf '%s' \"${line#* }\" | tr -cd 0-9 | cut -c1-4); fi; old=${old:-0}; "
        + "case \"$identity\" in *:) count=0 ;; *) "
        + "if [ \"$stored\" = \"$identity\" ]; then count=$old; "
        + "elif [ \"${stored%%:*}\" = \"${identity%%:*}\" ]; then count=$((old + 1)); else count=1; fi ;; esac; "
        + "echo \"$count $identity\"; "
        + "printf '%s %s\\n' \"$identity\" \"$count\" > \"$file.$$\" && mv -f -- \"$file.$$\" \"$file\""

    // Writes a start's count back to 0 once it has lived guardClearMs: arguments the file and
    // the identity (only a plain file, or none, is written)
    readonly property string guardClearScript: "file=$1; "
        + "if [ -L \"$file\" ] || { [ -e \"$file\" ] && [ ! -f \"$file\" ]; }; then exit 0; fi; "
        + "printf '%s 0\\n' \"$2\" > \"$file.$$\" && mv -f -- \"$file.$$\" \"$file\""

    // What the guard's output means → { safeMode, count, identity, reason }. Garbage, nothing
    // (the script failed) or "refused": counts as 0 — the guard must never be what keeps
    // modules off for good.
    function startGuard(output) {
        const text = String(output ?? "").trim();
        const match = /^([0-9]{1,4}) ([0-9]*:[0-9]*)$/.exec(text);
        if (!match)
            return { safeMode: false, count: 0, identity: "", reason: text.startsWith("refused") ? "the start counter is not a plain file: not counted" : "" };
        const count = Number(match[1]);
        return {
            safeMode: count >= guardLimit, count: count, identity: match[2],
            reason: count >= guardLimit ? "Quickshell relaunched the shell after a crash " + count + " times in a row, none living "
                + guardClearMs / 1000 + " s (a module may crash it): safe mode" : ""
        };
    }

    // The module whose directory holds `url` (a file:// URL or a path): its index in
    // `directories` (canonical paths), or -1. The deepest directory wins (a module inside
    // another's tree is its own).
    function directoryIndexOf(directories, url) {
        if (typeof url !== "string" && !(url && typeof url.toString === "function"))
            return -1;
        let path = String(url);
        if (path.startsWith("file://"))
            path = path.slice(7);
        try {
            path = decodeURIComponent(path);
        } catch (error) {
            return -1;
        }
        path = canonicalPath(path);
        if (path === "")
            return -1;
        let best = -1;
        (directories ?? []).forEach((directory, index) => {
            if ((path === directory || path.startsWith(directory + "/"))
                    && (best < 0 || directory.length > directories[best].length))
                best = index;
        });
        return best;
    }
}
