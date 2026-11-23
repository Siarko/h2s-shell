pragma Singleton

import Quickshell
import QtQuick

// What the sign-in rule list (panels/settings/PamRuleList.qml) shows and allows, from a
// service's rows (PamRuleRules' row model) and the machine's facts: the icons and chips of
// a row, which control words an opened row offers, the "No limit" details, the add list,
// where a dragged row drops and the list a drop or an add makes, the fixed row's removal
// question (tests/PamRuleListTest.qml). Pure: the element only draws these and emits the
// lists they return.
Singleton {
    id: root

    // One glyph per method, the add list's icon column and a row's method pill
    readonly property var icons: ({
        fingerprint: String.fromCodePoint(0xF0237),
        securityKey: String.fromCodePoint(0xF0306),
        password: String.fromCodePoint(0xF11C),
        raw: String.fromCodePoint(0xF121),
        system: String.fromCodePoint(0xF023)
    })

    function icon(method) {
        return icons[method] ?? "";
    }

    function label(method) {
        return PamRuleRules.methods[method]?.label ?? String(method ?? "");
    }

    // The control words an opened row offers for its method (the list shows none for a raw
    // line: its word is in its text)
    function controlsFor(method) {
        return PamRuleRules.controlsFor(method);
    }

    // ── Details that may be unlimited (PamRuleRules' `noLimit`: pam_fprintd's -1) ──

    function unlimited(value) {
        return typeof value === "number" && value < 0;
    }

    // { min, max, noLimit (undefined where the module has none), initial, unit, label } of an
    // int detail, or null
    function range(method, detail) {
        const spec = PamRuleRules.methods[method]?.details?.[detail];
        return spec && spec.kind === "int"
            ? { min: spec.min, max: spec.max, noLimit: spec.noLimit, initial: spec.initial, unit: spec.unit ?? "", label: spec.label } : null;
    }

    // The details change for a typed value: a whole number in the range, else null (the
    // field shows the problem, the row keeps its value)
    function typedChange(method, detail, text) {
        const spec = range(method, detail);
        const value = /^\s*\d+\s*$/.test(String(text ?? "")) ? parseInt(text, 10) : NaN;
        if (!spec || !Number.isInteger(value) || value < spec.min || value > spec.max)
            return null;
        return { [detail]: value };
    }

    // The details change for "No limit" turned on or off: off takes the field's text when it
    // is a value in the range, else the detail's initial value
    function limitChange(method, detail, on, text) {
        const spec = range(method, detail);
        if (!spec || spec.noLimit === undefined)
            return null;
        if (on)
            return { [detail]: spec.noLimit };
        return typedChange(method, detail, text) ?? { [detail]: spec.initial };
    }

    // ── A closed row's chips ──

    // `facts`: PamRuleRules.check's ({ system, faillockPresent, faillock, … })
    function chips(row, facts) {
        const details = row?.details ?? {};
        switch (row?.method) {
        case "fingerprint": {
            const timeout = details.timeout, tries = details.tries;
            return [unlimited(timeout) ? "no time limit" : timeout + " s",
                    unlimited(tries) ? "unlimited tries" : tries === 1 ? "1 try" : tries + " tries",
                    PamRuleRules.countsChip(row)];
        }
        case "securityKey":
            return [details.pin === true ? "PIN" : "Touch", PamRuleRules.countsChip(row)];
        case "password":
            return facts?.faillockPresent === true ? [PamRuleRules.countsChip(row)] : [];
        case "raw":
            return [PamRuleRules.countsChip(row)];
        case "system":
            if (facts?.faillockPresent === true)
                return [PamRuleRules.faillockSummary(facts.faillock)];
            return facts?.system === "nixos" ? ["NixOS's rules"] : [];
        }
        return [];
    }

    // What an opened row shows under its line: "rule" (the control words and the method's
    // details), "raw" (the line's field and how it reads), "fixed" (the system's own lines)
    function opened(row) {
        if (PamRuleRules.isFixed(row))
            return "fixed";
        return row?.method === "raw" ? "raw" : "rule";
    }

    // A raw line opened: { text, problem }
    function rawReading(text, facts) {
        const reading = PamRuleRules.rawLine(text, facts);
        if (reading.refusal)
            return { text: reading.refusal.text, problem: true };
        return { text: "Reads as: " + reading.reads + ". Written exactly as typed; the trial runs it.", problem: false };
    }

    // How a row's border says what the checks found: "refused", "warned" or ""
    function rowState(result, id) {
        const mine = list => (list ?? []).some(found => found.id !== "" && String(found.id) === String(id));
        if (mine(result?.refusals))
            return "refused";
        return mine(result?.warnings) ? "warned" : "";
    }

    // ── Adding ──

    // The add list: every method in PamRuleRules' order, each { method, label, note,
    // available }; a reader the machine lacks is listed off, with its reason
    function addOptions(facts) {
        const offered = PamRuleRules.offeredMethods(facts);
        const note = method => {
            const state = facts?.[method];
            if (method === "fingerprint")
                return state === "ready" ? "A finger is enrolled" : state === "absent" ? "No finger enrolled" : "Not known whether a finger is enrolled";
            if (method === "securityKey")
                return state === "ready" ? "A key is registered" : state === "absent" ? "No key registered" : "Not known whether a key is registered";
            if (method === "raw")
                return "Any PAM line, as written — not checked";
            return "Only the password, without the system's other rules";
        };
        return PamRuleRules.addOrder.map(method => ({ method, label: label(method), note: note(method), available: offered.includes(method) }));
    }

    // A row of `method` added above the fixed row: { rows, id } (the new row's id, which the
    // list opens), or null for a method the add list does not offer with these facts
    function added(rows, method, facts) {
        if (!PamRuleRules.offeredMethods(facts).includes(method))
            return null;
        const row = PamRuleRules.newRow(method, rows);
        if (!row)
            return null;
        const list = Array.isArray(rows) ? rows : [];
        return { rows: PamRuleRules.insertRow(list, row, list.length), id: row.id };
    }

    // ── Dragging ──

    // The slot a dragged row would drop into (the index it goes before), for a pointer at
    // `pointerY`, given the middle of each row's line (`middles`, in the same coordinates, in
    // order): before the first row whose middle the pointer is above, never below the fixed
    // row
    function dropSlot(rows, middles, pointerY) {
        const list = Array.isArray(rows) ? rows : [];
        const fixedAt = list.findIndex(row => PamRuleRules.isFixed(row));
        const limit = fixedAt < 0 ? list.length : fixedAt;
        let slot = list.length;
        for (let i = 0; i < (middles ?? []).length; i++) {
            if (pointerY < middles[i]) {
                slot = i;
                break;
            }
        }
        return Math.max(0, Math.min(slot, limit));
    }

    // Whether a drop line shows above the row at `index` (or, `index` = the count, below the
    // last): the slot is there and the drop would move the row
    function dropLineAt(dragIndex, slot, index) {
        return dragIndex >= 0 && slot === index && slot !== dragIndex && slot !== dragIndex + 1;
    }

    // The list after dropping the row at `from` into `slot`, or null when nothing moves (its
    // own place, the fixed row, beyond the list)
    function dropped(rows, from, slot) {
        const list = Array.isArray(rows) ? rows : [];
        if (from < 0 || from >= list.length || !PamRuleRules.canMove(list[from]) || slot < 0 || slot === from || slot === from + 1)
            return null;
        const next = PamRuleRules.moveRow(list, from, slot > from ? slot - 1 : slot);
        return next.every((row, i) => String(row?.id) === String(list[i]?.id)) ? null : next;
    }

    // ── Removing the fixed row ──

    // The Settings modal's question (SettingsModalHost.ask's spec) before the fixed row goes:
    // `title` names the list ("sudo and administrator prompts")
    function removeFixedQuestion(title, rows, facts) {
        const list = Array.isArray(rows) ? rows : [];
        const body = [String(title ?? "") + " will no longer ask the password the way the system does.",
                      "Without it, pam_faillock stops counting wrong passwords here, and systemd-homed accounts are not asked."];
        const passwordLeft = list.some(row => !PamRuleRules.isFixed(row)
                                       && (row?.method === "password"
                                           || (row?.method === "raw" && PamRuleRules.rawLine(row?.details?.text, facts).method === "password")));
        if (!passwordLeft)
            body.push("No other row asks for the password: if the reader breaks, this is closed until you repair it from a root console.");
        return { kind: "danger", title: "Remove the system's password?", body,
                 buttons: [{ id: "remove", label: "Remove", kind: "delete" }],
                 subject: { list: String(title ?? ""), id: PamRuleRules.systemId } };
    }
}
