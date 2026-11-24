pragma Singleton

import Quickshell
import QtQuick

// What a distribution integration answers for each change kind (tests/IntegrationRulesTest.qml,
// tests/DistributionContractTest.qml): how the system makes the change, what the change
// would be, and what is in force. An integration (distributions/Integration.qml and each
// distribution's) holds its table of kinds; these functions read it, so every integration
// answers the same way. Pure.
//
//   capability(kind) → { mode, trial, undo, inForce, anyway, reason, known }
//     mode     "apply"        the shell writes the change (distributions/EtcFiles.qml)
//              "declare"      the shell sets it in the system's configuration and rebuilds
//              "copy"         the system's configuration sets it: the shell gives the text
//              "unavailable"  not on this system: `reason` says so
//     trial    the change is tried before it is applied
//     undo     the applied change can be put back
//     inForce  readInForce reads what is in force
//     anyway   "copy" or "declare": the shell can still write its file where the system's
//              configuration makes /etc, when the user asks (apply's `handlers.anyway`;
//              warned, the user's choice), with no Undo
//     known    false only while the distribution is not known (Distribution's answer)
//   plan(kind, value) → { preview, refusal }
//     preview  "apply": { files: [{ path, text ("" removes the file) }] }; "copy", "declare": { option, snippet,
//              hint (the integration's words naming where the setting is made) }
//   apply / undo → { started, refusal }
//   readInForce → what the system uses, read as the system merges it (inForceCommand), and
//     the shell's own file: { state, value, from, elsewhere, file, afterOwn }
//     state      "set" (a file sets it), "default" (none does: the system's own default),
//                "unknown" (not read, or not understood)
//     value      the value in force ("set"), else null
//     from       the file whose setting is in force ("" for none or not known)
//     elsewhere  `from` when it is not the shell's own file: the user's or the system's own
//                setting, which the shell shows ("Set in <file>") and never overrides unasked
//     afterOwn   `elsewhere` is read after the shell's own file: a change of the shell's
//                cannot take effect over it (false when `elsewhere` is "", or the shell's
//                file would be read after it: then the shell may override it, asked)
//     file       the shell's own file (EtcFilesRules.inForce's answer: its text, sha256 and
//                whether it is exactly the shell's), the `current` to hand apply; null where
//                the shell writes nothing
Singleton {
    id: root

    // The change kinds the shell defines, each with how its value is checked
    readonly property var kinds: ["sleep.hibernateDelay", "network.connectivityUri"]
    readonly property var modes: ["apply", "declare", "copy", "unavailable"]

    // The reason of a kind the integration does not offer
    readonly property string unsupported: "Not supported on this distribution."
    // The reason while the distribution is not known
    readonly property string unknown: "The distribution is not known."

    readonly property var texts: ({
        unknown: root.unknown,
        unavailable: root.unsupported,
        mode: "This system does not let the shell make this change.",
        value: "Not a value for this setting.",
        noUndo: "There is no change of the shell's to undo."
    })

    function refusal(code, text) {
        return { code, text: text ?? texts[code] ?? texts.value };
    }

    function _unavailable(reason, known) {
        return { mode: "unavailable", trial: false, undo: false, inForce: false, anyway: false, reason, known };
    }

    // The answer while the distribution is not known: nothing offered
    function unknownCapability() {
        return _unavailable(unknown, false);
    }

    // An integration's `table` ({ <kind>: { mode, trial, undo, inForce, anyway, reason, option } })
    // for `kind` → the capability; a kind the shell does not define, or the table does not
    // name or names wrongly, is unavailable with a reason
    function capability(table, kind) {
        if (!kinds.includes(kind))
            return _unavailable(unsupported, true);
        const entry = table !== null && typeof table === "object" && Object.prototype.hasOwnProperty.call(table, kind) ? table[kind] : null;
        if (entry === null || typeof entry !== "object" || !modes.includes(entry.mode) || entry.mode === "unavailable")
            return _unavailable(typeof entry?.reason === "string" && entry.reason !== "" ? entry.reason : unsupported, true);
        // Only an applied change is tried or undone by the shell
        const applied = entry.mode === "apply";
        return { mode: entry.mode, trial: applied && entry.trial === true, undo: applied && entry.undo === true,
                 inForce: entry.inForce === true, anyway: !applied && entry.anyway === true, reason: "", known: true };
    }

    // Whether an answer is a capability as the contract has it
    function valid(answer) {
        if (answer === null || typeof answer !== "object" || !modes.includes(answer.mode))
            return false;
        if (["trial", "undo", "inForce", "anyway", "known"].some(key => typeof answer[key] !== "boolean") || typeof answer.reason !== "string")
            return false;
        if (answer.mode === "unavailable")
            return answer.reason !== "" && !answer.trial && !answer.undo && !answer.inForce && !answer.anyway;
        return answer.known && answer.reason === "" && (answer.mode === "apply" ? !answer.anyway : !answer.trial && !answer.undo);
    }

    // Whether `value` is one for the kind
    function validValue(kind, value) {
        if (kind === "sleep.hibernateDelay")
            return Number.isInteger(value) && value >= HibernateRules.delayRange.minimum && value <= HibernateRules.delayRange.maximum;
        // "": the shell's file removed, the system's own address in force again
        if (kind === "network.connectivityUri")
            return value === "" || (typeof value === "string" && ConnectivityRules.isUri(value));
        return false;
    }

    // The file's text the shell writes for an applied kind ("" for none: the file removed)
    function textOf(kind, value) {
        if (kind === "sleep.hibernateDelay")
            return HibernateRules.dropInText(value);
        if (kind === "network.connectivityUri" && value !== "")
            return ConnectivityRules.text(value);
        return "";
    }

    // The line to copy for a kind set by an option: `option` its name
    function snippetOf(kind, option, value) {
        if (kind === "sleep.hibernateDelay")
            return option + " = " + value + ";";
        if (kind === "network.connectivityUri" && value !== "")
            return option + " = \"" + value + "\";";
        return "";
    }

    // What the change would be: `table` the integration's, `kind`, `value` → { preview, refusal }
    function plan(table, kind, value) {
        const answer = capability(table, kind);
        if (answer.mode === "unavailable")
            return { preview: null, refusal: refusal("unavailable", answer.reason) };
        if (!validValue(kind, value))
            return { preview: null, refusal: refusal("value") };
        if (answer.mode === "apply")
            return { preview: { files: [{ path: EtcFilesRules.files[kind] ?? "", text: textOf(kind, value) }] }, refusal: null };
        const option = String(table[kind].option ?? "");
        return { preview: { option, snippet: snippetOf(kind, option, value), hint: String(table[kind].hint ?? "") }, refusal: null };
    }

    // Why apply may not start for the capability (before the value): null when it may.
    // `anyway`: the user asked to write the file where the system's configuration makes /etc
    function applyRefusal(answer, anyway) {
        if (answer.mode === "unavailable")
            return refusal(answer.known === false ? "unknown" : "unavailable", answer.reason);
        return answer.mode === "apply" || (anyway === true && answer.anyway === true) ? null : refusal("mode");
    }

    // Why undo may not start: null when it may
    function undoRefusal(answer) {
        const notApplied = applyRefusal(answer);
        if (notApplied !== null)
            return notApplied;
        return answer.undo ? null : refusal("noUndo");
    }

    // The command that prints the kind's setting as the system merges it (every file it
    // reads, in its order), or null for a kind without one; `shellDir` the shell's tree
    function inForceCommand(kind, shellDir) {
        if (kind === "sleep.hibernateDelay")
            return ["systemd-analyze", "--no-pager", "cat-config", "systemd/sleep.conf"];
        if (kind === "network.connectivityUri")
            return [String(shellDir ?? "") + "/scripts/nm-config-files.sh"];
        return null;
    }

    // What is in force: `merged` inForceCommand's output (null: not read), `own` the shell's
    // own file as read (EtcFilesRules.inForce's answer; null where it writes none) →
    // { state, value, from, elsewhere, file, afterOwn }
    function inForceOf(kind, merged, own) {
        const file = own !== null && typeof own === "object" ? own : null;
        if (kind === "network.connectivityUri" && typeof merged === "string")
            return _connectivityInForce(merged, file);
        if (kind !== "sleep.hibernateDelay" || typeof merged !== "string")
            return Object.assign(inForceUnknown(), { file });
        const delay = HibernateRules.hibernateDelay(merged);
        if (delay.state !== "set" && delay.state !== "unset")
            return Object.assign(inForceUnknown(), { file });
        // A file that put systemd's default back (an empty assignment) is a setting too
        const from = typeof delay.file === "string" ? delay.file : "";
        const elsewhere = from !== "" && from !== EtcFilesRules.files[kind] ? from : "";
        return {
            state: delay.state === "set" ? "set" : "default",
            value: delay.state === "set" ? delay.seconds : null,
            from,
            elsewhere,
            file,
            afterOwn: elsewhere !== "" && HibernateRules.readAfterDropIn(elsewhere)
        };
    }

    // The connectivity check's address in force (ConnectivityRules.setting); one from the
    // distribution's packages is its default, not set elsewhere
    function _connectivityInForce(merged, file) {
        const setting = ConnectivityRules.setting(merged);
        if (setting.state === "unknown")
            return Object.assign(inForceUnknown(), { file });
        const own = EtcFilesRules.files["network.connectivityUri"];
        const elsewhere = setting.state === "set" && setting.from !== own ? setting.from : "";
        return { state: setting.state, value: setting.value, from: setting.from, elsewhere, file,
                 afterOwn: elsewhere !== "" && ConnectivityRules.readAfterOwn(elsewhere) };
    }

    // Nothing in force can be told
    function inForceUnknown() {
        return { state: "unknown", value: null, from: "", elsewhere: "", file: null, afterOwn: false };
    }

    // Whether an answer is readInForce's as the contract has it
    function validInForce(answer) {
        if (answer === null || typeof answer !== "object" || !["set", "default", "unknown"].includes(answer.state))
            return false;
        if (typeof answer.from !== "string" || typeof answer.elsewhere !== "string" || (answer.elsewhere !== "" && answer.elsewhere !== answer.from))
            return false;
        if (answer.file !== null && (typeof answer.file !== "object" || !["text", "absent", "unknown"].includes(answer.file.state)))
            return false;
        if (typeof answer.afterOwn !== "boolean" || (answer.afterOwn && answer.elsewhere === ""))
            return false;
        return answer.state === "set" ? answer.value !== null && answer.value !== undefined : answer.value === null;
    }
}
