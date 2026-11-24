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

    // ── The sign-in rules page (panels/settings/PamRulesSection.qml) ──

    readonly property var stepLabels: ({ fingerprint: "fingerprint", securityKey: "security key", password: "password" })
    readonly property var _stepModules: ({ "pam_fprintd.so": "fingerprint", "pam_u2f.so": "securityKey", "pam_unix.so": "password" })

    // What a stack in force asks, in order, as steps: the methods its auth lines (included
    // files' too) ask for, the same one twice in a row once; other modules are no step.
    // null when the stack is not known (a file not read or not understood)
    function stepsOf(stack) {
        if (!stack || stack.known !== true)
            return null;
        const steps = [];
        for (const line of stack.lines ?? []) {
            const method = _stepModules[line?.moduleName];
            if (method && steps[steps.length - 1] !== method)
                steps.push(method);
        }
        return steps;
    }

    // The summary's rows: [{ title, steps (null: not known) }] — one row for both services
    // when they ask the same, else one each
    function summaryRows(sudoStack, polkitStack) {
        const sudo = stepsOf(sudoStack), polkit = stepsOf(polkitStack);
        if (sudo !== null && polkit !== null && sudo.join(",") === polkit.join(","))
            return [{ title: "sudo and administrator prompts", steps: sudo }];
        return [{ title: "sudo", steps: sudo }, { title: "Administrator prompts", steps: polkit }];
    }

    // "This computer has: …"
    function computerHas(facts) {
        const finger = facts?.fingerprint === "ready" ? "a finger enrolled"
            : facts?.fingerprint === "absent" ? "no finger enrolled" : "fingerprint not known";
        const key = facts?.securityKey === "ready" ? "a security key registered"
            : facts?.securityKey === "absent" ? "no security key registered" : "security key not known";
        return finger + " · " + key;
    }

    // Where the rules go: { label, text }
    function writtenTo(nixos, directory) {
        if (nixos === true)
            return { label: "Set through", text: "the NixOS module" };
        const folder = String(directory ?? "") !== "" ? String(directory) : "/etc/pam.d";
        return { label: "Written to", text: folder + "/sudo and " + folder + "/polkit-1" };
    }

    // The texts a reading holds for the page (PamStacks' `files`, `directories`): sudo's file,
    // our polkit-1 (null: none there), polkit's own vendor file; undefined where not read.
    // On NixOS there is one folder: polkit-1 is NixOS's file and there is no vendor file.
    function filesOf(files, directories) {
        const answers = files ?? {};
        const folders = Array.isArray(directories) ? directories : [];
        const textAt = path => {
            const answer = answers[path];
            if (typeof answer?.text === "string")
                return answer.text;
            return answer?.absent === true ? null : undefined;
        };
        const system = folders[0] ?? "";
        const vendor = folders[1] ?? "";
        return {
            sudo: system !== "" ? textAt(system + "/sudo") : undefined,
            polkit: system !== "" ? textAt(system + "/polkit-1") : undefined,
            vendorPolkit: vendor !== "" ? textAt(vendor + "/polkit-1") : undefined
        };
    }

    // A service's file in force for the page: PamEditRules.state's answer, or not known when
    // the file (or polkit's own file) was not read — PamEditRules takes a missing text for
    // "no file". On NixOS the shell writes no file: the fixed row alone, nothing changed by hand.
    function inForceOf(text, service, vendorText, facts) {
        if (facts?.system === "nixos")
            return { known: true, changed: false, reasons: [], rows: [PamRuleRules.fixedRow()], adopted: null, vendorChanged: false };
        if (text === undefined || (service === "polkit-1" && typeof vendorText !== "string"))
            return { known: false, changed: false, reasons: [], rows: null, adopted: null, vendorChanged: false };
        return PamEditRules.state(text, service, Object.assign({}, facts ?? {}, { vendorText: vendorText ?? undefined }));
    }

    // A service's facts for PamRuleRules.check and PamEditRules.build: the machine's (`base`:
    // { nixos, moduleDirectories, fingerprint, securityKey, u2f }), its faillock (`faillock`: PamStacks' settings or
    // null; present: the stack counts), the other service's rows, polkit's vendor text
    function serviceFacts(base, service, stack, faillock, otherRows, vendorText, changedByHand) {
        return {
            system: base?.nixos === true ? "nixos" : "arch",
            moduleDirectories: Array.isArray(base?.moduleDirectories) ? base.moduleDirectories : [],
            service,
            fingerprint: base?.fingerprint ?? "unknown",
            securityKey: base?.securityKey ?? "unknown",
            u2f: base?.u2f ?? undefined,
            faillockPresent: stack?.faillock?.present === true,
            faillock: faillock ?? null,
            otherService: otherRows,
            vendorText: typeof vendorText === "string" ? vendorText : undefined,
            changedByHand: changedByHand === true
        };
    }

    // The editor's lists as the files in force give them: { split, shared, sudo, polkit }; a
    // service not known starts with the fixed row alone
    function editorFrom(sudoRows, polkitRows) {
        const sudo = Array.isArray(sudoRows) ? sudoRows : [PamRuleRules.fixedRow()];
        const polkit = Array.isArray(polkitRows) ? polkitRows : [PamRuleRules.fixedRow()];
        const split = !PamRuleRules.sameRows(sudo, polkit);
        return { split, shared: sudo, sudo, polkit };
    }

    // Whether the editor's lists differ from the rows in force
    function pending(editor, inForceSudo, inForcePolkit) {
        const lists = PamRuleRules.listsFor(editor);
        return !PamRuleRules.sameRows(lists["sudo"], inForceSudo ?? []) || !PamRuleRules.sameRows(lists["polkit-1"], inForcePolkit ?? []);
    }

    // The split switch clicked: { ask (the warning modal first), editor (as it would be) }
    function splitToggled(editor) {
        if (editor?.split === true) {
            const joined = PamRuleRules.joinLists(editor.sudo, editor.polkit);
            return { ask: joined.asks, editor: { split: false, shared: joined.shared, sudo: editor.sudo, polkit: editor.polkit } };
        }
        const split = PamRuleRules.splitLists(editor?.shared);
        return { ask: false, editor: { split: true, shared: editor?.shared ?? [], sudo: split.sudo, polkit: split.polkit } };
    }

    readonly property var joinSpec: ({
        kind: "warning", title: "Use sudo's rules for both?",
        body: ["Administrator prompts have rules of their own. One list means they are replaced by sudo's."],
        buttons: [{ id: "join", label: "Use sudo's", kind: "warning" }]
    })

    // What Apply writes: each service whose new file differs from the one in force, in order
    // (sudo, then polkit-1). `inputs`: { service: { rows, currentText, facts } }. → { items:
    // [{ service, built, currentText, vendorText, text (the candidate) }], refusals (a build
    // that refused, with its service) }
    function applyQueue(inputs) {
        const items = [], refusals = [];
        for (const service of PamRuleRules.services) {
            const input = inputs?.[service];
            if (!input)
                continue;
            const built = PamEditRules.build(input.currentText, input.rows, input.facts);
            if (!built.ok) {
                refusals.push(...built.refusals.map(item => Object.assign({ service }, item)));
                continue;
            }
            const chosen = PamApplyRules.candidate(built, input.facts?.vendorText);
            if (chosen === null)
                continue;
            const current = input.currentText;
            const same = chosen.remove ? (current === null || current === undefined) : chosen.text === current;
            if (!same)
                items.push({ service, built, currentText: current, vendorText: input.facts?.vendorText, text: chosen.text });
        }
        return { items, refusals };
    }

    // Whether a passed trial also stands for `text` as `service`'s file: its own candidate, or
    // the other service's with the same auth lines (one trial for a shared list)
    function trialCovers(trial, service, text) {
        if (trial?.phase !== "passed" || typeof trial.candidate !== "string")
            return false;
        if (trial.service === service)
            return trial.candidate === text;
        const step = PamTrialRules.stagingStep(service, text, trial.answers ?? {}, trial.directories ?? [], false);
        return step.refusal === null && step.pending.length === 0 && PamTrialRules.sameAuthLines(trial.stack, step.stack);
    }

    function serviceName(service) {
        return service === "sudo" ? "sudo" : "administrator prompts";
    }

    // "1 of 2: sudo", or the service alone when it is the only one
    function progress(index, total, service) {
        return total > 1 ? (index + 1) + " of " + total + ": " + serviceName(service) : serviceName(service);
    }

    // The trial's modal (its content: PAM's messages and the field)
    function trialSpec(index, total, service) {
        return { kind: "info", title: "Try the new rules", size: "m", cancelLabel: "Cancel",
                 body: ["Nothing is changed yet. Sign in as the new rules ask" + (total > 1 ? " (" + progress(index, total, service) + ")." : ".")] };
    }

    // A reason on one line (PAM's message, a run's error)
    function _oneLine(text) {
        return String(text ?? "").replace(/[\u0000-\u001f\u007f\s]+/g, " ").trim();
    }

    function notSavedSpec(reason) {
        const text = _oneLine(reason);
        return { kind: "warning", title: "Not saved",
                 body: [text !== "" ? text : "The new rules did not let you in.", "Nothing was changed."],
                 buttons: [{ id: "again", label: "Try again", kind: "normal" }] };
    }

    // What an Apply that stopped tells: `outcomes` the services written before it stopped,
    // `reason` why ("" for a password prompt dismissed), `failed` the service it stopped at
    // and `file` what PamApply found there after a failed run ("unchanged", "done", "other",
    // "unknown"; "" when no run started). → { spec (null: nothing to say — a prompt dismissed
    // and nothing changed), changed (something may differ from before: read again) }
    function stoppedSpec(outcomes, reason, failed, file, backupsFolder) {
        const written = (Array.isArray(outcomes) ? outcomes : []).filter(outcome => outcome?.ok === true);
        const fileNote = file === "done" ? serviceName(failed) + ": the file was written, but the run did not say so. Read it again."
            : file === "other" ? serviceName(failed) + ": the file changed in another way. Read it again."
            : file === "unknown" ? serviceName(failed) + ": the file could not be read again."
            : "";
        const text = _oneLine(reason);
        if (written.length === 0 && fileNote === "") {
            if (text === "")
                return { spec: null, changed: false };
            return { spec: notSavedSpec(text), changed: false };
        }
        const body = [text !== "" ? text : "The administrator password was not given."];
        if (written.length > 0) {
            const names = written.map(outcome => serviceName(outcome.service));
            body.push("Written: " + names.join(" and ") + ". Not written: " + serviceName(failed) + ".");
        }
        if (fileNote !== "")
            body.push(fileNote);
        if (written.length > 0)
            body.push("Undo puts back " + written.map(outcome => String(backupsFolder ?? "") + "/" + outcome.backup).join(", ") + ".");
        return { spec: { kind: "warning", title: "Saved in part", cancelLabel: "OK", body }, changed: true };
    }

    // An Undo that did not finish: what is left is undone again by "Try again"
    function undoFailedSpec(reason, left) {
        const text = _oneLine(reason);
        const names = (Array.isArray(left) ? left : []).map(outcome => serviceName(outcome.service));
        return { kind: "warning", title: "Not undone",
                 body: [text !== "" ? text : "The old file could not be put back.",
                        names.length > 0 ? "Still with the new rules: " + names.join(" and ") + "." : ""],
                 buttons: [{ id: "again", label: "Try again", kind: "normal" }] };
    }

    // After the writes: the backups named
    function savedSpec(outcomes, backupsFolder) {
        const list = Array.isArray(outcomes) ? outcomes : [];
        const services = list.map(outcome => serviceName(outcome.service));
        const target = services.length > 1 ? "sudo and administrator prompts use" : (services[0] === "sudo" ? "sudo uses" : "Administrator prompts use");
        return { kind: "success", title: "Saved", cancelLabel: "OK",
                 body: [target + " the new rules.",
                        (list.length > 1 ? "Backups: " : "Backup: ") + list.map(outcome => String(backupsFolder ?? "") + "/" + outcome.backup).join(", "),
                        "Undo puts the old file back."] };
    }

    function replaceSpec(service, backupsFolder, adopted) {
        const own = adopted?.own ?? 0, raw = adopted?.raw ?? 0;
        return { kind: "warning", title: "Replace " + (service === "sudo" ? "/etc/pam.d/sudo" : "/etc/pam.d/polkit-1") + "?",
                 body: ["The hand-made file goes to the backups: " + String(backupsFolder ?? "") + ".",
                        "Taken in as " + (own + raw) + (own + raw === 1 ? " row" : " rows")
                        + (raw > 0 ? "; " + raw + (raw === 1 ? " line the editor does not make itself stays a raw line" : " lines the editor does not make itself stay raw lines") + ", as written." : "."),
                        "Nothing is written before Apply and its trial."],
                 buttons: [{ id: "replace", label: "Replace", kind: "warning" }],
                 subject: { service, hash: String(adopted?.hash ?? "") } };
    }

    // A generated file's lines for the preview: [{ text, kind }] — "marker" (the shell's
    // marker lines), "ours" (its lines), "counted" (the counted password's lines), "system"
    // (the file's own lines, kept as they are)
    function previewLines(text) {
        const lines = String(text ?? "").replace(/\n$/, "").split("\n");
        let inside = false;
        return lines.map(line => {
            const trimmed = line.trim();
            if (trimmed.startsWith(PamEditRules.beginMarker)) {
                inside = true;
                return { text: line, kind: "marker" };
            }
            if (trimmed.startsWith(PamEditRules.endMarker)) {
                inside = false;
                return { text: line, kind: "marker" };
            }
            if (trimmed.startsWith(PamEditRules.writtenMarker) || trimmed.startsWith(PamEditRules.replacedMarker))
                return { text: line, kind: "marker" };
            if (!inside)
                return { text: line, kind: "system" };
            const counted = /pam_faillock\.so/.test(line) || /^\s*-?auth\s+\[[^\]]*\]\s+pam_unix\.so/.test(line);
            return { text: line, kind: counted ? "counted" : "ours" };
        });
    }

    // A file changed by hand, its lines with the ones a reason names marked: [{ text, marked,
    // reason }]
    function handLines(text, reasons) {
        const marks = {};
        for (const reason of reasons ?? []) {
            if (reason?.line > 0)
                marks[reason.line] = reason.text;
        }
        return String(text ?? "").replace(/\n$/, "").split("\n")
            .map((line, i) => ({ text: line, marked: marks[i + 1] !== undefined, reason: marks[i + 1] ?? "" }));
    }

    // Apply's button: { available, tooltip }
    function applyButton(changed, refused, busy, replacing) {
        if (busy)
            return { available: false, tooltip: "Saving…" };
        if (refused)
            return { available: false, tooltip: "A check refuses the rows" };
        if (!changed && !replacing)
            return { available: false, tooltip: "Nothing changed" };
        return { available: true, tooltip: "Tries the new rules first, then asks the administrator password" };
    }

    // The lock screen's ways to unlock: [{ key ("" for the password), method, label, hint,
    // warning, checked, available }]. `values`: { "lockscreen.offerFingerprint", … } as set.
    // `facts.u2f.lock`: what the system's pam_u2f settings let the lock's key check do
    // (PamStackRules.u2fOptions'). Its one line must pass, so `nouserok` (PAM_IGNORE for a
    // user without a key) leaves no result and the check fails: only alwaysok and a touch
    // turned off are said
    function unlockRows(facts, values) {
        const row = (key, method, label, state, readyHint, absentHint, warning) => ({
            key, method, label,
            hint: state === "ready" ? readyHint : state === "absent" ? absentHint : "Not known on this computer",
            warning: state === "ready" ? warning : "",
            checked: state === "ready" && values?.[key] !== false,
            available: state === "ready"
        });
        return [
            { key: "", method: "password", label: "Password", hint: "Always offered", checked: true, available: false },
            row("lockscreen.offerFingerprint", "fingerprint", "Fingerprint", facts?.fingerprint, "A finger is enrolled", "No finger enrolled", ""),
            row("lockscreen.offerSecurityKey", "securityKey", "Security key", facts?.securityKey, "A key is registered", "No key registered",
                keyUnlockWarning(facts?.u2f?.lock))
        ];
    }

    // The security key switch's warning for the lock's key check, every point that holds in
    // one text: "" when its settings ask for a key and a touch and nothing is left out, or are
    // not read yet
    function keyUnlockWarning(lock) {
        if (!lock)
            return "";
        if (lock.known !== true)
            return "The system's pam_u2f settings could not be read: it may unlock without a key or a touch.";
        const said = [];
        if (lock.interactive)
            said.push("The key will not work here: the system's pam_u2f settings have interactive, and the lock screen cannot answer its Enter prompt.");
        if (lock.alwaysok)
            said.push("Unlocks without a key: the system's pam_u2f settings have alwaysok.");
        if (lock.touchOff)
            said.push("May unlock without a touch while a key is plugged in: the system's pam_u2f settings have userpresence=0.");
        if (lock.interactiveDropped)
            said.push("interactive is off for the lock screen: it cannot answer the Enter prompt.");
        return said.join(" ");
    }
}
