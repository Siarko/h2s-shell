pragma Singleton

import Quickshell

// Which distribution the shell runs on, and that distribution's static facts — pure, tested
// in tests/DistributionRulesTest.qml. The reading is singletons/io/DistributionReader.qml's
// (the shell's one reader is Distribution).
//
// Each distribution the shell knows has a directory distributions/<id>/ with a
// distribution.json: plain data, so that scripts can read the same facts without running
// any of the shell's code. Its keys, every one required, no other allowed:
//
//   id                        the directory's name
//   label                     the distribution's name, one line
//   matches                   os-release ID values that are this distribution ([] for none)
//   markers                   absolute paths whose presence says it is this one, whatever
//                             os-release says ([] for none)
//   etcManaged                whether /etc is generated from a configuration (a file written
//                             there is replaced at the next rebuild)
//   helper                    "package": the shell's package carries the helper program;
//                             "build": the launcher builds it from the tree
//   builtinModules            "package": the package carries the built-in modules;
//                             "dataHome": they are copied to the data home's h2s-shell/builtin
//   programDirectories        where the system's own programs are, root's (the trusted
//                             programs' directories, in order)
//   setuidWrapperDirectory    where setuid programs (pkexec, unix_chkpwd) are reached when
//                             not in programDirectories; "" for none
//   pamDirectories            where libpam looks for a service, in order
//   pamModuleDirectories      where libpam's modules are, each ending in "/"
//   networkManagerVpnDirectories   where NetworkManager's VPN plugins' .name files are
//   polkitRulesDirectory      where polkit's rules are read from, for the shell's own
//   polkitRulesInstallable    whether the shell may install a rule file there
//
// Detection, one reading at start: H2S_DISTRIBUTION (a test seam, TestSeams.distribution)
// names one and wins; else a distribution whose marker exists (one that cannot be read
// exists too, as `test -e` has it); else os-release's ID
// matched against each distribution's `matches`; else each word of ID_LIKE in its order;
// else the generic one. Until every reading has answered nothing is known — the id is ""
// and the facts null, never a default system's; a reading that failed (rather than found
// nothing) leaves it unknown. Nothing here throws on any input.
Singleton {
    id: root

    // The distributions the shell ships, in the order their markers and matches are tried;
    // the last is the fallback, which matches nothing
    readonly property var ids: ["nixos", "arch", "generic"]
    readonly property string fallbackId: "generic"
    // Where os-release is looked for: the first one there is read (os-release(5))
    readonly property var osReleasePaths: ["/etc/os-release", "/usr/lib/os-release"]
    // The longest distribution.json or os-release taken
    readonly property int maxFileLength: 65536

    readonly property var _keys: ["id", "label", "matches", "markers", "etcManaged", "helper", "builtinModules",
        "programDirectories", "setuidWrapperDirectory", "pamDirectories", "pamModuleDirectories",
        "networkManagerVpnDirectories", "polkitRulesDirectory", "polkitRulesInstallable"]
    readonly property var _directoryLists: ["programDirectories", "pamDirectories", "pamModuleDirectories", "networkManagerVpnDirectories"]

    function _hasControl(text) {
        return /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(text);
    }

    // An os-release identifier (ID, a word of ID_LIKE): lower case, digits, ".", "_", "-"
    function isIdentifier(text) {
        return typeof text === "string" && /^[a-z0-9._-]{1,64}$/.test(text);
    }

    // An absolute path as written: no control character, no "." or ".." part, not too long
    function _isPath(text) {
        return typeof text === "string" && text.startsWith("/") && text.length <= 4096 && !_hasControl(text)
            && !text.split("/").some(part => part === "." || part === "..");
    }

    function _isPathList(value) {
        return Array.isArray(value) && value.length <= 32 && value.every(path => _isPath(path));
    }

    // os-release's text → frozen { NAME: value } of its assignments (os-release(5): shell-like
    // KEY=value lines, white space before the name ignored as systemd does; a value in double
    // quotes with \" \\ \$ \` escapes, or in single quotes, or bare). Comments, blank lines
    // and lines that are no well-formed assignment (an unescaped quote inside the quotes, a
    // backslash escaping the closing quote, a bare value with a quote, a "$" or white space)
    // are left out; a later assignment of a name wins. Not a string, or too long: null
    function parseOsRelease(text) {
        if (typeof text !== "string" || text.length > maxFileLength)
            return null;
        const values = {};
        for (const line of text.split("\n")) {
            const match = /^\s*([A-Z][A-Z0-9_]*)=(.*)$/.exec(line.replace(/\r$/, ""));
            if (!match)
                continue;
            let value = match[2];
            if (value.startsWith("\"")) {
                const quoted = /^"((?:[^"\\]|\\.)*)"$/.exec(value);
                if (!quoted)
                    continue;
                value = quoted[1].replace(/\\([\\"$`])/g, "$1");
            } else if (value.startsWith("'")) {
                const quoted = /^'([^']*)'$/.exec(value);
                if (!quoted)
                    continue;
                value = quoted[1];
            } else if (/["'\\$`\s]/.test(value)) {
                continue;
            }
            values[match[1]] = value;
        }
        return Object.freeze(values);
    }

    // The os-release readings, one per osReleasePaths entry in order, each null (not
    // answered) or { state: "text" | "absent" | "failed", text } → { answered, known, values }:
    // the first file that is there is the one read; one that failed before it leaves the
    // answer unknown (it might have been the one), and so does one too long, or holding no
    // well-formed assignment at all. None there: known, without values ({}).
    function osReleaseOf(readings) {
        const list = Array.isArray(readings) ? readings : [];
        for (let i = 0; i < osReleasePaths.length; ++i) {
            const reading = list[i];
            if (reading === null || typeof reading !== "object")
                return { answered: false, known: false, values: Object.freeze({}) };
            if (reading.state === "absent")
                continue;
            if (reading.state !== "text")
                return { answered: true, known: false, values: Object.freeze({}) };
            const values = parseOsRelease(reading.text);
            if (values === null || Object.keys(values).length === 0)
                return { answered: true, known: false, values: Object.freeze({}) };
            return { answered: true, known: true, values: values };
        }
        return { answered: true, known: true, values: Object.freeze({}) };
    }

    // A distribution.json's text, from distributions/<id>/ → its facts, frozen (lists too), or
    // null when it is no JSON object, misses a key or has another, or a value is not of its
    // kind (see above), or `id` is not the directory's
    function manifest(text, id) {
        if (typeof text !== "string" || text.length > maxFileLength || !isIdentifier(id))
            return null;
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (error) {
            return null;
        }
        if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed))
            return null;
        const keys = Object.keys(parsed);
        if (keys.length !== _keys.length || !_keys.every(key => keys.includes(key)))
            return null;
        const valid = parsed.id === id
            && typeof parsed.label === "string" && parsed.label !== "" && parsed.label.length <= 64 && !_hasControl(parsed.label)
            && Array.isArray(parsed.matches) && parsed.matches.length <= 32 && parsed.matches.every(word => isIdentifier(word))
            && _isPathList(parsed.markers)
            && typeof parsed.etcManaged === "boolean"
            && (parsed.helper === "package" || parsed.helper === "build")
            && (parsed.builtinModules === "package" || parsed.builtinModules === "dataHome")
            && _directoryLists.every(key => _isPathList(parsed[key]))
            && parsed.pamModuleDirectories.every(path => path.endsWith("/"))
            && (parsed.setuidWrapperDirectory === "" || _isPath(parsed.setuidWrapperDirectory))
            && _isPath(parsed.polkitRulesDirectory)
            && typeof parsed.polkitRulesInstallable === "boolean";
        if (!valid)
            return null;
        const facts = {};
        for (const key of _keys)
            facts[key] = Array.isArray(parsed[key]) ? Object.freeze(parsed[key].slice()) : parsed[key];
        return Object.freeze(facts);
    }

    // What was read → frozen { ready, id, facts, how, problem, shipped }:
    //   ready     every reading the answer needs has answered (a failed one too)
    //   id        one of `ids`, or "" while unknown
    //   facts     that distribution's manifest() answer, or null while unknown
    //   how       "override" | "marker" | "id" | "like" | "fallback" | "" (unknown)
    //   problem   why it is unknown once ready: "" when known
    //   shipped   every shipped distribution's facts, frozen { <id>: facts }, once every
    //             manifest has answered and each can be used (whether or not this system
    //             can be told); null before, or when one cannot be used
    // `readings`: {
    //   override    TestSeams.distribution: "" for none
    //   manifests   { <id>: text | { failed: true } | undefined (not answered) } for each of `ids`
    //   markers     { <path>: "present" | "absent" | "failed" | undefined } for each marker
    //               the manifests name
    //   osRelease   osReleaseOf's input
    // }
    function detect(readings) {
        let shipped = null;
        const unknown = (ready, problem) => Object.freeze({ ready: ready, id: "", facts: null, how: "", problem: ready ? problem : "", shipped: shipped });
        const known = (id, facts, how) => Object.freeze({ ready: true, id: id, facts: facts, how: how, problem: "", shipped: shipped });
        const given = readings !== null && typeof readings === "object" ? readings : {};
        const texts = given.manifests !== null && typeof given.manifests === "object" ? given.manifests : {};
        if (ids.some(id => texts[id] === undefined))
            return unknown(false);
        const manifests = {};
        for (const id of ids) {
            manifests[id] = manifest(texts[id], id);
            if (manifests[id] === null)
                return unknown(true, "distributions/" + id + "/distribution.json cannot be used");
        }
        shipped = Object.freeze(manifests);
        const override = typeof given.override === "string" ? given.override : "";
        if (override !== "") {
            if (!ids.includes(override))
                return unknown(true, "H2S_DISTRIBUTION names no distribution: " + override);
            return known(override, manifests[override], "override");
        }
        const markers = given.markers !== null && typeof given.markers === "object" ? given.markers : {};
        for (const id of ids) {
            for (const path of manifests[id].markers) {
                if (markers[path] === undefined)
                    return unknown(false);
            }
        }
        const osRelease = osReleaseOf(given.osRelease);
        if (!osRelease.answered)
            return unknown(false);
        for (const id of ids) {
            if (manifests[id].markers.some(path => markers[path] === "present" || markers[path] === "failed"))
                return known(id, manifests[id], "marker");
        }
        if (!osRelease.known)
            return unknown(true, "os-release cannot be read");
        const matching = word => ids.find(id => isIdentifier(word) && manifests[id].matches.includes(word));
        const byId = matching(osRelease.values.ID);
        if (byId !== undefined)
            return known(byId, manifests[byId], "id");
        for (const word of String(osRelease.values.ID_LIKE ?? "").split(/\s+/)) {
            const byLike = matching(word);
            if (byLike !== undefined)
                return known(byLike, manifests[byLike], "like");
        }
        return known(fallbackId, manifests[fallbackId], "fallback");
    }

    // A directory list of every shipped distribution (detect's `shipped`) as one list: each
    // distribution's own order kept — their first entries (in `ids` order), then their
    // second ones, and so on —, each directory once. For a reading that looks in every
    // system's places whichever this one is. `shipped` null or not a list there: []
    function unionOf(shipped, key) {
        if (shipped === null || typeof shipped !== "object")
            return [];
        const lists = ids.map(id => shipped[id]?.[key]).filter(list => Array.isArray(list));
        const result = [];
        const longest = Math.max(0, ...lists.map(list => list.length));
        for (let i = 0; i < longest; ++i) {
            for (const list of lists) {
                if (i < list.length && typeof list[i] === "string" && !result.includes(list[i]))
                    result.push(list[i]);
            }
        }
        return result;
    }
}
