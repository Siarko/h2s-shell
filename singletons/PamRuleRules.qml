pragma Singleton

import Quickshell
import QtQuick

// The rule editor's rules for sudo's and polkit's `auth` lines (tests/PamRuleRulesTest.qml):
// a service's rules are an ordered list of rows, tried from the top as PAM runs a stack —
// each row a method with PAM's control word and the method's details, the list closed by
// the fixed row "Password (as the system)" (the service's own auth lines, kept as they
// are). Here: the row model and its edits (the fixed row stays last and goes only when
// asked for explicitly), the control words with their explanations, the methods' details
// and ranges, one shared list or one per service, and `check(rows, facts)`: every refusal
// (Apply off) and warning the list gets, raw lines judged as far as a line alone can be.
// Pure: no text is generated here (PamEditRules) and nothing is read.
Singleton {
    id: root

    readonly property var services: ["sudo", "polkit-1"]

    // ── Control words ──

    // The four words the editor's own rows carry, in the order the editor offers them; a
    // raw line keeps whatever it says
    readonly property string defaultControl: "sufficient"
    readonly property var controls: [
        { word: "sufficient", explanation: "If it passes and no row above has failed, you are in; if not, the next row is tried." },
        { word: "required", explanation: "Must pass. The next rows still run; a failure is told at the end." },
        { word: "requisite", explanation: "Must pass. A failure ends it at once." },
        { word: "optional", explanation: "Counts only when no other row decides." }
    ]

    function explanation(word) {
        const found = controls.find(control => control.word === word);
        return found ? found.explanation : "";
    }

    function isControl(word) {
        return controls.some(control => control.word === word);
    }

    // ── Methods and their details ──

    // `kind`: "int" (whole number in min–max), "bool", "fixed" (only `value`), "text" (one
    // line, at most maxLength characters). `counts`: the chip saying whether pam_faillock
    // counts the row's failures ("" where it depends on the row).
    readonly property string systemId: "system"
    readonly property int maxRawLength: 512
    readonly property var methods: ({
        fingerprint: {
            label: "Fingerprint", module: "pam_fprintd.so", counts: "Not counted",
            details: {
                timeout: { kind: "int", min: 5, max: 120, initial: 10, label: "Timeout", unit: "s" },
                tries: { kind: "int", min: 1, max: 10, initial: 3, label: "Tries", unit: "" }
            }
        },
        securityKey: {
            label: "Security key", module: "pam_u2f.so", counts: "Not counted",
            details: {
                pin: { kind: "bool", initial: false, label: "Ask for the key's PIN" },
                cue: { kind: "fixed", value: true, initial: true, label: "Say when to touch the key" }
            }
        },
        password: {
            label: "Password", module: "pam_unix.so", counts: "",
            details: {
                counted: { kind: "bool", initial: false, label: "Failures count" }
            }
        },
        raw: {
            label: "Raw line", module: "", counts: "Not checked",
            details: {
                text: { kind: "text", initial: "", maxLength: 512, label: "Line" }
            }
        },
        system: { label: "Password (as the system)", module: "", counts: "", details: {} }
    })
    // What "+ Add a row" lists, in its order: the raw line last
    readonly property var addOrder: ["fingerprint", "securityKey", "password", "raw"]
    readonly property var _readers: ["fingerprint", "securityKey"]

    // The methods "+ Add a row" offers with these facts: a reader or key only when it is
    // "ready" (an unknown fact counts as absent); the password and a raw line always
    function offeredMethods(facts) {
        return addOrder.filter(method => !_readers.includes(method) || facts?.[method] === "ready");
    }

    // Whether a detail is offered: "Failures count" only where the system's rules count
    // with pam_faillock
    function detailOffered(method, detail, facts) {
        if (method === "password" && detail === "counted")
            return facts?.faillockPresent === true;
        return Object.prototype.hasOwnProperty.call(methods[method]?.details ?? {}, detail);
    }

    // The row's chip for counting: "Counted" / "Not counted" / "Not checked" / "" (the
    // fixed row's chip is faillockSummary's)
    function countsChip(row) {
        if (row?.method === "password")
            return row.details?.counted === true ? "Counted" : "Not counted";
        return methods[row?.method]?.counts ?? "";
    }

    // ── faillock's numbers in words ──

    function duration(seconds) {
        const value = Number(seconds);
        if (value >= 3600 && value % 3600 === 0)
            return (value / 3600) + " h";
        if (value >= 60 && value % 60 === 0)
            return (value / 60) + " min";
        return value + " s";
    }

    function _lockWords(faillock) {
        return faillock.unlockTime === 0 ? "until reset" : duration(faillock.unlockTime);
    }

    // The fixed row's chip: "Counts: 3 wrong in 15 min lock 10 min"
    function faillockSummary(faillock) {
        if (!faillock)
            return "Counts: not known";
        if (faillock.deny === 0)
            return "Counts: off";
        return "Counts: " + faillock.deny + " wrong in " + duration(faillock.failInterval) + " lock "
            + _lockWords(faillock);
    }

    // An own Password row's hint: the trade-off of counting
    function countedHint(faillock) {
        const numbers = faillock && faillock.deny > 0
            ? " (" + faillock.deny + " wrong in " + duration(faillock.failInterval) + " lock " + _lockWords(faillock) + ")" : "";
        return "Off: an empty Enter to reach the reader is not a wrong password, but guesses here are not stopped by the lockout. "
            + "On: they count" + numbers + ". A success here does not clear the count.";
    }

    // ── Rows ──

    function isFixed(row) {
        return row?.method === "system";
    }

    function fixedRow() {
        return { id: systemId, method: "system", control: "", details: {} };
    }

    function hasFixedRow(rows) {
        return (Array.isArray(rows) ? rows : []).some(row => isFixed(row));
    }

    // An id not used in the list: "r1", "r2", …
    function nextId(rows) {
        const used = (Array.isArray(rows) ? rows : []).map(row => String(row?.id ?? ""));
        let number = 1;
        while (used.includes("r" + number))
            number++;
        return "r" + number;
    }

    // A new row of a method with its details' initial values and the default word; null for
    // the fixed row or an unknown method
    function newRow(method, rows) {
        if (!addOrder.includes(method))
            return null;
        const details = {};
        const spec = methods[method].details;
        for (const name of Object.keys(spec))
            details[name] = spec[name].initial;
        return { id: nextId(rows), method, control: method === "raw" ? "" : defaultControl, details };
    }

    function _copy(rows) {
        return JSON.parse(JSON.stringify(Array.isArray(rows) ? rows : []));
    }

    // Where rows may go: above the fixed row, or anywhere in a list without it
    function _limit(list) {
        const fixed = list.findIndex(row => isFixed(row));
        return fixed < 0 ? list.length : fixed;
    }

    // The list with `row` put at `index`, never below the fixed row; a fixed row is not put
    // in this way (restoreFixedRow)
    function insertRow(rows, row, index) {
        const list = _copy(rows);
        if (!row || isFixed(row))
            return list;
        const at = Math.max(0, Math.min(Number.isInteger(index) ? index : list.length, _limit(list)));
        list.splice(at, 0, JSON.parse(JSON.stringify(row)));
        return list;
    }

    // The fixed row moves nowhere; nothing moves below it
    function canMove(row) {
        return !isFixed(row);
    }

    function canEdit(row) {
        return !isFixed(row);
    }

    function moveRow(rows, from, to) {
        const list = _copy(rows);
        if (from < 0 || from >= list.length || isFixed(list[from]))
            return list;
        const [row] = list.splice(from, 1);
        const at = Math.max(0, Math.min(to, _limit(list)));
        list.splice(at, 0, row);
        return list;
    }

    // A row removed by id; the fixed row only with `explicit` true (the danger modal's answer)
    function removeRow(rows, id, explicit) {
        const list = _copy(rows);
        const index = list.findIndex(row => String(row?.id) === String(id));
        if (index < 0 || (isFixed(list[index]) && explicit !== true))
            return list;
        list.splice(index, 1);
        return list;
    }

    // The fixed row put back, last
    function restoreFixedRow(rows) {
        const list = _copy(rows);
        if (!hasFixedRow(list))
            list.push(fixedRow());
        return list;
    }

    // A row's word and details changed (`change`: { control?, details? }, details merged);
    // the fixed row is not edited
    function changeRow(rows, id, change) {
        const list = _copy(rows);
        const row = list.find(item => String(item?.id) === String(id));
        if (!row || isFixed(row))
            return list;
        if (change?.control !== undefined && row.method !== "raw")
            row.control = change.control;
        if (change?.details)
            row.details = Object.assign({}, row.details, change.details);
        return list;
    }

    // ── One list or two ──

    // What two rows do, without their ids, details at their initial values where unset
    function _rowKey(row) {
        const spec = methods[row?.method]?.details ?? {};
        const details = {};
        for (const name of Object.keys(spec))
            details[name] = row?.details?.[name] ?? spec[name].initial;
        return JSON.stringify([row?.method, isFixed(row) || row?.method === "raw" ? "" : row?.control, details]);
    }

    function sameRows(first, second) {
        const a = Array.isArray(first) ? first : [], b = Array.isArray(second) ? second : [];
        return a.length === b.length && a.every((row, i) => _rowKey(row) === _rowKey(b[i]));
    }

    // Each service's rows: `state` { split, shared, sudo, polkit }
    function listsFor(state) {
        if (state?.split === true)
            return { "sudo": _copy(state.sudo), "polkit-1": _copy(state.polkit) };
        return { "sudo": _copy(state?.shared), "polkit-1": _copy(state?.shared) };
    }

    function otherService(service) {
        return service === "sudo" ? "polkit-1" : "sudo";
    }

    // "Separate rules for administrator prompts" on: both lists start as the shared one
    function splitLists(shared) {
        return { split: true, sudo: _copy(shared), polkit: _copy(shared) };
    }

    // … off: sudo's list serves both; `asks` when the lists differ (the warning modal)
    readonly property string joinQuestion: "Use sudo's rules for both?"
    function joinLists(sudo, polkit) {
        return { split: false, shared: _copy(sudo), asks: !sameRows(sudo, polkit) };
    }

    // ── Raw lines ──

    // The places root loads modules from: a module named by an absolute path elsewhere is
    // refused (R7). NixOS's store and its system profile are read-only; elsewhere the
    // distribution's module directories.
    readonly property var moduleDirectories: ["/usr/lib/security/", "/lib/security/", "/usr/lib64/security/",
        "/lib64/security/", "/usr/lib/x86_64-linux-gnu/security/", "/lib/x86_64-linux-gnu/security/",
        "/usr/lib/aarch64-linux-gnu/security/", "/lib/aarch64-linux-gnu/security/"]
    // On NixOS only the system profile: any user can add a module to the store, so a store
    // path's file name says nothing about what the module does
    readonly property var nixosModuleDirectories: ["/run/current-system/sw/lib/security/"]
    // libpam's own modules: NixOS's libpam finds these, and only these, by bare name
    readonly property var libpamModules: ["pam_access", "pam_canonicalize_user", "pam_debug", "pam_deny", "pam_echo",
        "pam_env", "pam_exec", "pam_faildelay", "pam_faillock", "pam_filter", "pam_ftp", "pam_group",
        "pam_issue", "pam_keyinit", "pam_lastlog", "pam_limits", "pam_listfile", "pam_localuser",
        "pam_loginuid", "pam_mail", "pam_mkhomedir", "pam_motd", "pam_namespace", "pam_nologin",
        "pam_permit", "pam_pwhistory", "pam_rhosts", "pam_rootok", "pam_securetty", "pam_selinux",
        "pam_sepermit", "pam_setquota", "pam_shells", "pam_stress", "pam_succeed_if", "pam_time",
        "pam_timestamp", "pam_tty_audit", "pam_umask", "pam_unix", "pam_userdb", "pam_usertype",
        "pam_warn", "pam_wheel", "pam_xauth"].map(name => name + ".so")
    // The modules that ask for a credential: the only ones a raw line that can let the user
    // in may name (any other of libpam's lets in by a rule about the user, not a proof)
    readonly property var credentialModules: ["pam_unix.so", "pam_fprintd.so", "pam_u2f.so", "pam_userdb.so"]
    readonly property var _rawMethods: ({ "pam_unix.so": "password", "pam_fprintd.so": "fingerprint", "pam_u2f.so": "securityKey" })

    // Whether a module line asks for a credential: "yes" (pam_unix, pam_fprintd; pam_u2f
    // without the arguments that let it pass with no key or no touch; pam_userdb with its
    // database under /etc), "no" (another of libpam's modules, or one of those made to pass
    // by its arguments), "unknown" (a module the shell does not know)
    function credentialOf(line) {
        const name = line.moduleName, args = line.args ?? [];
        if (name === "pam_u2f.so")
            return args.includes("nouserok") || args.includes("userpresence=0") ? "no" : "yes";
        if (name === "pam_userdb.so") {
            const db = args.filter(word => word.startsWith("db=")).map(word => word.slice(3));
            return db.length > 0 && db.every(path => path.startsWith("/etc/") && !path.split("/").includes("..")) ? "yes" : "no";
        }
        if (credentialModules.includes(name))
            return "yes";
        return libpamModules.includes(name) ? "no" : "unknown";
    }

    // One raw line judged alone: { line (PamStackRules.parseLine's, or null), reads ("auth ·
    // sufficient · pam_ldap.so", or why it does not parse), method ("password" / "fingerprint"
    // / "securityKey" for those modules, else "unknown"), credential (credentialOf's, "unknown"
    // for a line that does not parse), refusal ({ code, text } or null) }. The list-wide
    // checks (R1, R9) are check()'s.
    function rawLine(text, facts) {
        const result = (line, reads, method, code, refusalText) => ({
            line, reads, method, credential: line ? credentialOf(line) : "unknown",
            refusal: code ? { code, text: refusalText } : null
        });
        if (typeof text !== "string")
            return result(null, "Not a line", "unknown", "R8", texts.R8);
        if (/[\n\r]/.test(text))
            return result(null, "More than one line", "unknown", "R8", "One line only: it holds a line break.");
        if (text.length > maxRawLength)
            return result(null, "Too long", "unknown", "R8", "The line is too long.");
        // A backslash outside a bracketed word would join the next line of the file to this
        // one (a line ending in one) or is not something a line of ours needs
        const stripped = text.replace(/#.*$/, "").replace(/\s+$/, "");
        const parts = PamStackRules.words(stripped);
        if (parts !== null && parts.some(word => !word.startsWith("[") && word.includes("\\")))
            return result(null, "Holds a backslash", "unknown", "R8", "No backslash outside brackets: it would join the next line.");
        const line = PamStackRules.parseLine(stripped);
        if (line.error !== undefined)
            return result(null, line.error, "unknown", "R8", texts.R8 + " " + line.error + ".");
        if (line.directive !== undefined || line.target !== undefined)
            return result(null, "Not a module line", "unknown", "R8", "Only a module line: no include.");
        if (line.type !== "auth")
            return result(null, "Not an auth line", "unknown", "R8", "Only an auth line.");
        // A jump or a reset makes the rows below this one not run as they stand
        if (line.actions && Object.keys(line.actions).some(name => line.actions[name] === "reset" || /^\d+$/.test(line.actions[name])))
            return result(null, "Jumps or resets", "unknown", "R8", "No jumps or reset in a raw line.");
        const reads = [line.optional ? "-auth" : "auth", line.control, line.moduleName].join(" · ");
        const method = _rawMethods[line.moduleName] ?? "unknown";
        const nixos = facts?.system === "nixos";
        const module = line.module;
        if (module.includes("/")) {
            const places = nixos ? nixosModuleDirectories : moduleDirectories;
            const segments = module.split("/");
            const inPlace = module.startsWith("/") && !segments.includes("..") && !segments.includes(".")
                && places.some(place => module.startsWith(place));
            if (!inPlace)
                return result(line, reads, method, "R7", texts.R7);
        } else if (nixos && !libpamModules.includes(module)) {
            return result(line, reads, method, "R8", "Needs the module's full path on NixOS.");
        }
        return result(line, reads, method, null, "");
    }

    // ── Checks ──

    readonly property var texts: ({
        R1: "No row can let you in now: keep a password row or a ready reader.",
        R2: "This row must pass, but the method is not ready: nobody would get in.",
        R3: "No rows.",
        R4method: "Unknown kind of row.",
        R4control: "Unknown control word.",
        R4fixed: "The system's password row can only be last, and only once.",
        R4counted: "Failures cannot count here: the system's rules do not count them.",
        R5: "Keep a password in sudo or in administrator prompts: one is the way to repair the other.",
        R6: "Changed outside the shell. Replace it to edit here.",
        R7: "The module is not in the system's module folders.",
        R8: "Not a PAM line.",
        R9: "This line lets anyone in.",
        R1deny: "This line refuses everyone: nobody would get in.",
        W1: "Only the reader lets you in. If it breaks, use the other service, su or a root console.",
        W2: "Both needed: without the reader nobody gets in.",
        W3: "An empty Enter to reach the reader counts as a wrong password.",
        W4: "The shell does not know this line: the trial runs it, the checks do not.",
        W5: "Does nothing here: another row decides.",
        W9: "nullok: an account with an empty password gets in.",
        W10: "Nothing above asks for the password, so this line never lets you in.",
        W6: "Asked twice: the same method is in another row.",
        W7: "A wrong password is asked again by the last row.",
        W8: "Not saved for both: Apply again to make the lists the same."
    })

    function _detailProblem(method, name, value) {
        const spec = methods[method].details[name];
        if (value === undefined)
            return "";
        if (spec.kind === "int" && (!Number.isInteger(value) || value < spec.min || value > spec.max))
            return spec.label + " must be " + spec.min + "–" + spec.max + (spec.unit ? " " + spec.unit : "") + ".";
        if (spec.kind === "bool" && typeof value !== "boolean")
            return spec.label + " must be on or off.";
        if (spec.kind === "fixed" && value !== spec.value)
            return spec.label + " cannot be changed.";
        return "";
    }

    // What a row is to the checks: { method ("password" / "fingerprint" / "securityKey" /
    // "system" / "unknown"), raw, atOnce (passing lets the user in at once: sufficient, a
    // bracketed done on success), okOnSuccess (a bracketed ok on success: in only when the
    // closing line keeps the result), fails (failing fails the stack: required, requisite, a
    // bracketed bad/die), optional, credential (raw: credentialOf's), denies (a raw pam_deny
    // that fails), firstPass (a raw pam_unix use_first_pass: only checks a password asked
    // above), nullok, refusals }
    function _role(row, service, facts) {
        const role = { method: "unknown", raw: false, atOnce: false, okOnSuccess: false, fails: false, optional: false,
                       credential: "unknown", denies: false, firstPass: false, nullok: false, refusals: [] };
        const method = row?.method;
        if (method === "system") {
            role.method = "system";
            role.fails = true;
            return role;
        }
        if (method === "raw") {
            role.raw = true;
            const judged = rawLine(row?.details?.text, facts);
            // A refused line counts as no method: a module from another place may be anything
            role.method = judged.refusal ? "unknown" : judged.method;
            if (judged.refusal)
                role.refusals.push(judged.refusal);
            const line = judged.line;
            if (line !== null) {
                const actions = line.actions ?? {};
                const onSuccess = actions.success ?? actions.default;
                role.atOnce = line.control === "sufficient" || onSuccess === "done";
                role.okOnSuccess = !role.atOnce && onSuccess === "ok";
                role.fails = line.control === "required" || line.control === "requisite"
                    || Object.keys(actions).some(key => key !== "success" && (actions[key] === "bad" || actions[key] === "die"));
                role.optional = line.control === "optional";
                role.credential = judged.credential;
                role.denies = line.moduleName === "pam_deny.so" && role.fails;
                role.firstPass = line.moduleName === "pam_unix.so" && line.args.includes("use_first_pass");
                role.nullok = line.moduleName === "pam_unix.so" && line.args.includes("nullok");
            }
            return role;
        }
        if (!addOrder.includes(method)) {
            role.refusals.push({ code: "R4", text: texts.R4method });
            return role;
        }
        role.method = method;
        if (!isControl(row.control))
            role.refusals.push({ code: "R4", text: texts.R4control });
        for (const name of Object.keys(methods[method].details)) {
            const problem = _detailProblem(method, name, row.details?.[name]);
            if (problem !== "")
                role.refusals.push({ code: "R4", text: problem });
        }
        if (method === "password" && row.details?.counted === true && facts?.faillockPresent !== true)
            role.refusals.push({ code: "R4", text: texts.R4counted });
        role.atOnce = row.control === "sufficient";
        role.fails = row.control === "required" || row.control === "requisite";
        role.optional = row.control === "optional";
        return role;
    }

    // How the shell's block ends: "system" (the fixed row), "permit" (`[default=done]
    // pam_permit.so`, keeping the result: a row that fails the stack on failure — required,
    // requisite, a raw bracketed bad/die — is in the list), "deny" (`requisite pam_deny.so`:
    // only a row that lets in at once lets in)
    function _closing(roles) {
        if (roles.some(role => role.method === "system"))
            return "system";
        return roles.some(role => role.fails) ? "permit" : "deny";
    }

    function closingOf(rows, facts) {
        const list = Array.isArray(rows) ? rows : [];
        return _closing(list.map(row => _role(row, String(facts?.service ?? ""), facts)));
    }

    // The rows' roles, each with `decides`: whether it can decide that the user is in — the
    // fixed row always; a row that lets in at once or fails the stack; a bracketed ok on
    // success unless the closing line is the deny; an own optional row only beside the fixed
    // row; a raw pam_unix use_first_pass only below a row that asks for the password
    function _analyse(list, service, facts) {
        const roles = list.map(row => _role(row, service, facts));
        const closing = _closing(roles);
        roles.forEach((role, i) => {
            if (role.method === "system")
                role.decides = true;
            else if (role.atOnce || role.fails)
                role.decides = true;
            else if (role.okOnSuccess)
                role.decides = closing !== "deny";
            else
                role.decides = !role.raw && role.optional && closing === "system";
            role.unasked = role.firstPass
                && !roles.slice(0, i).some(above => above.method === "password" && !above.firstPass);
            if (role.unasked)
                role.decides = false;
        });
        return { roles, closing };
    }

    function _hasPassword(rows, service, facts) {
        const list = Array.isArray(rows) ? rows : [];
        return _analyse(list, service, facts).roles.some(role => (role.method === "password" || role.method === "system") && role.decides);
    }

    // Every refusal and warning for one service's rows. `facts`: { system ("nixos" / …),
    // service ("sudo" / "polkit-1"), fingerprint, securityKey ("ready" / "absent" /
    // "unknown"), faillockPresent (the system's rules count with pam_faillock), faillock
    // (PamStackRules.faillockConfig's numbers, or null), otherService (the other service's
    // rows, in force or pending: the same rows for a shared list; not a list = not known),
    // changedByHand, sharedApplyStopped (a shared Apply stopped between the two
    // services) }. → { refusals, warnings }, each item { code, row (index, −1 for the list),
    // id ("" for the list), text }.
    function check(rows, facts) {
        const list = Array.isArray(rows) ? rows : [];
        const known = facts ?? {};
        const service = String(known.service ?? "");
        const refusals = [], warnings = [];
        const item = (code, index, text) => ({ code, row: index, id: index >= 0 ? String(list[index]?.id ?? "") : "", text });
        const refuse = (code, index, text) => refusals.push(item(code, index, text));
        const warn = (code, index, text) => warnings.push(item(code, index, text));

        if (known.changedByHand === true)
            refuse("R6", -1, texts.R6);
        if (list.length === 0) {
            refuse("R3", -1, texts.R3);
            return { refusals, warnings };
        }

        const analysed = _analyse(list, service, known);
        const roles = analysed.roles;
        const ready = method => known[method] === "ready";
        const isReader = role => _readers.includes(role.method);
        const fixedIndex = list.findIndex(row => isFixed(row));

        // Each row alone: its own refusals (R4, R7, R8), the fixed row's place (R4)
        roles.forEach((role, i) => {
            for (const refusal of role.refusals)
                refuse(refusal.code, i, refusal.text);
            if (role.method === "system" && (i !== list.length - 1 || i !== fixedIndex))
                refuse("R4", i, texts.R4fixed);
        });

        // R9: a raw line that can let the user in (sufficient, a bracketed done or ok on
        // success; required or requisite without the fixed row, where the closing line can
        // keep its result) with a module that asks for no credential, or made by its
        // arguments to pass without one. Jumps are refused (R8), so no row is skipped between.
        const fixedPresent = fixedIndex >= 0;
        roles.forEach((role, i) => {
            if (!role.raw || role.credential !== "no" || role.refusals.length > 0 || role.denies)
                return;
            if (role.atOnce || role.okOnSuccess || (role.fails && !fixedPresent))
                refuse("R9", i, texts.R9);
        });

        // R1: a raw pam_deny that fails refuses everyone
        roles.forEach((role, i) => {
            if (role.denies && role.refusals.length === 0)
                refuse("R1", i, texts.R1deny);
        });

        // R1: some row can let the user in with what the machine has now
        const hasPassword = roles.some(role => (role.method === "password" || role.method === "system") && role.decides);
        const wayIn = hasPassword || roles.some(role => isReader(role) && ready(role.method) && role.decides);
        if (!wayIn)
            refuse("R1", -1, texts.R1);

        // R2 / W2: a reader or key that must pass
        roles.forEach((role, i) => {
            if (isReader(role) && role.fails) {
                if (ready(role.method))
                    warn("W2", i, texts.W2);
                else
                    refuse("R2", i, texts.R2);
            }
        });

        // R5: one of the two services keeps a password
        if (!hasPassword && !(Array.isArray(known.otherService) && _hasPassword(known.otherService, otherService(service), known)))
            refuse("R5", -1, texts.R5);

        // W1: the way in is a reader only
        if (wayIn && !hasPassword)
            warn("W1", -1, texts.W1);

        // W3: a counted password row above a reader
        roles.forEach((role, i) => {
            if (role.method === "password" && !role.raw && list[i].details?.counted === true
                    && roles.slice(i + 1).some(later => isReader(later))) {
                const faillock = known.faillock;
                const numbers = faillock && faillock.deny > 0
                    ? " (" + faillock.deny + " lock you out " + (faillock.unlockTime === 0 ? "until reset" : "for " + duration(faillock.unlockTime)) + ")"
                    : "";
                warn("W3", i, texts.W3.replace(/\.$/, numbers + "."));
            }
        });

        // W4: a raw line the checks cannot judge
        roles.forEach((role, i) => {
            if (role.raw && role.method === "unknown" && role.refusals.length === 0)
                warn("W4", i, texts.W4);
        });

        // W9: a raw pam_unix line that lets an empty password in
        roles.forEach((role, i) => {
            if (role.nullok && role.refusals.length === 0)
                warn("W9", i, texts.W9);
        });

        // W10: a raw pam_unix use_first_pass with no password asked above it
        roles.forEach((role, i) => {
            if (role.unasked && role.refusals.length === 0)
                warn("W10", i, texts.W10);
        });

        // W5: an own optional row: another row decides, or the closing line does
        roles.forEach((role, i) => {
            if (role.raw || !role.optional)
                return;
            const decides = fixedIndex < 0 || roles.some((other, j) => j !== i && !other.optional);
            if (decides)
                warn("W5", i, texts.W5);
        });

        // W6: the same method in two rows (the fixed row is not counted)
        const seen = {};
        roles.forEach((role, i) => {
            if (role.method === "unknown" || role.method === "system")
                return;
            if (seen[role.method] === true)
                warn("W6", i, texts.W6);
            seen[role.method] = true;
        });

        // W7: an own sufficient password row above the fixed row
        roles.forEach((role, i) => {
            if (role.method === "password" && !role.raw && list[i].control === "sufficient" && fixedIndex > i)
                warn("W7", i, texts.W7);
        });

        // W8: split lists left different by a shared Apply that stopped
        if (known.sharedApplyStopped === true && Array.isArray(known.otherService) && !sameRows(list, known.otherService))
            warn("W8", -1, texts.W8);

        return { refusals, warnings };
    }

    // The codes only, sorted: for a view's state and the tests
    function codes(result) {
        return result.refusals.concat(result.warnings).map(found => found.code)
            .filter((code, i, all) => all.indexOf(code) === i).sort();
    }
}
