pragma Singleton

import Quickshell
import QtQuick

// What Settings → System → Authentication's section "Remember the password"
// (panels/settings/RememberAdminSection.qml) shows and offers, from what RememberedAdmin
// read (RememberRules.state's answer, the facts and texts read, what is kept) and the
// setting: the setting's hint, the rule's state, the system's length and where it comes
// from, where the files are, which buttons there are and what each does, what Undo puts
// back, what is kept now, a file changed by hand and the questions. Pure
// (tests/RememberAdminPageTest.qml).
Singleton {
    id: root

    readonly property string nixOption: "programs.h2s-shell.polkit.rememberAdmin"
    readonly property var _counts: ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]

    // A length in seconds: whole minutes as minutes, anything else in seconds
    function durationText(seconds) {
        return seconds >= 60 && seconds % 60 === 0 ? seconds / 60 + " min" : seconds + " s";
    }

    // The time left until untilMs at nowMs: whole minutes rounded up, under a minute in
    // seconds, at least 1 s
    function leftText(untilMs, nowMs) {
        const seconds = Math.max(1, Math.ceil((untilMs - nowMs) / 1000) || 0);
        return seconds >= 60 ? Math.ceil(seconds / 60) + " min" : seconds + " s";
    }

    // The rule's state (RememberRules.state's rule; null before the first reading)
    // → { text, tone: "muted" | "success" | "warning" | "error" }
    function ruleLine(installed) {
        switch (installed?.rule) {
        case "none":
            return { text: "Not installed: every root run asks for the password.", tone: "muted" };
        case "ours":
            return { text: "Installed", tone: "success" };
        case "outdated":
            return { text: "Outdated: it names another timeout program than the shell uses now.", tone: "warning" };
        case "changed":
            return { text: "Changed outside the shell. Not replaced unless you choose to.", tone: "error" };
        case "unknown":
            return { text: "Not known: the files could not be read.", tone: "warning" };
        default:
            return { text: "Reading…", tone: "muted" };
        }
    }

    // How long the system keeps a typed password, and where that comes from
    function systemLine(installed, system) {
        if (!installed)
            return "Not read yet";
        const source = installed.secondsSource ?? "";
        if (installed.secondsReason === "unreadable")
            return "Not known: " + source + " could not be read";
        if (installed.secondsReason === "invalid" || !(installed.seconds > 0))
            return "Not known: " + source + " has a value polkit does not take";
        let from;
        if (installed.secondsReason === "default")
            from = system === "nixos" ? "polkit's default" : "polkit's default (no polkitd.conf)";
        else if (source === RememberRules.confPath && system === "nixos")
            from = source + ", from the NixOS module";
        else if (source === RememberRules.confPath && installed.conf === "ours")
            from = source + ", written by the shell";
        else if (source === RememberRules.confPath && installed.conf === "changed")
            from = source + ", not written by the shell";
        else
            from = source;
        return durationText(installed.seconds) + " — " + from;
    }

    // The setting asks more than the system keeps (a known length only)
    function needsLonger(installed, minutes) {
        return installed?.seconds > 0 && Number.isInteger(minutes) && minutes * 60 > installed.seconds;
    }

    // The setting's hint → { text, warning }
    function settingHint(installed, minutes, system) {
        if (!installed || installed.rule === "none")
            return { text: "Used once the rule is installed.", warning: false };
        if (!(installed.seconds > 0))
            return { text: "The system's length is not known.", warning: true };
        const seconds = minutes * 60;
        const own = durationText(installed.seconds);
        if (seconds < installed.seconds)
            return { text: "Shorter than the system's " + own + ": the shell forgets after " + minutes
                           + " min. That also forgets other programs' passwords in this session.", warning: false };
        if (seconds > installed.seconds)
            return { text: "Longer than the system's " + own + ": the system's length changes for every program. "
                           + (system === "nixos" ? "Copy the new line and switch." : "Install again to use it."), warning: true };
        return { text: "As long as the system keeps it.", warning: false };
    }

    // Whether Install would write the conf the setting needs (or remove the shell's that is
    // no longer needed): a conf not written by the shell is left to Replace…
    function _confToChange(installed, files, minutes) {
        if (installed?.conf === "changed" || installed?.conf === "unknown" || !files || !Number.isInteger(minutes))
            return false;
        const confs = files.confs ?? {};
        const want = RememberInstallRules.confFor(minutes, confs);
        const current = confs[RememberRules.confPath];
        return want !== "" ? current !== want : current !== undefined;
    }

    // A conf not written by the shell stands where the setting needs the shell's
    function confInTheWay(installed, files, minutes) {
        return installed?.conf === "changed" && !!files && Number.isInteger(minutes)
            && RememberInstallRules.confFor(minutes, files.confs ?? {}) !== "";
    }

    // Arch's buttons, each label with its effect → { install: { shown, label }, remove: {
    // shown, asks (a file changed by hand: the Settings modal first) }, undo: { shown },
    // available (no run under way) }. NixOS: none shown (the configuration line instead).
    function actions(installed, system, files, minutes, busy, lastWrite) {
        const arch = system === "arch" && !!installed && !!files;
        const rule = installed?.rule ?? "";
        const install = arch && (rule === "none" || rule === "outdated" || (rule === "ours" && _confToChange(installed, files, minutes)));
        return {
            install: { shown: install, label: rule === "none" ? "Install" : "Install again" },
            remove: { shown: arch && (rule === "ours" || rule === "outdated" || rule === "changed"), asks: rule === "changed" },
            undo: { shown: system === "arch" && lastWrite !== null && typeof lastWrite === "object" && RememberInstallRules.validStamp(lastWrite.stamp) },
            available: busy !== true
        };
    }

    // The sha256 of a file as read, or "absent" (what a run's record and Undo compare)
    function currentOf(text) {
        return typeof text === "string" ? PamEditRules.sha256(text) : text === undefined ? "absent" : null;
    }

    // What the last run left for Undo, from its reply and the texts it was asked with:
    // { mode, stamp, before { rule, conf }, after { rule, conf } }; null when it did not succeed
    function lastWriteOf(mode, outcome, files) {
        if (outcome?.ok !== true || !RememberInstallRules.validStamp(outcome.stamp))
            return null;
        return {
            mode: mode, stamp: outcome.stamp,
            before: { rule: currentOf(files?.rule), conf: currentOf(files?.confs?.[RememberRules.confPath]) },
            after: { rule: outcome.rule, conf: outcome.conf }
        };
    }

    // The caption under the buttons: what Undo puts back (the backups of the files the last
    // run changed), else where backups go
    function backupCaption(lastWrite, paths) {
        if (!lastWrite)
            return "Backups go to " + String(paths?.backups ?? "");
        const changed = [];
        if (lastWrite.before.rule !== lastWrite.after.rule)
            changed.push(RememberInstallRules.backupPath(paths, RememberInstallRules.ruleName, lastWrite.stamp, lastWrite.before.rule === "absent"));
        if (lastWrite.before.conf !== lastWrite.after.conf)
            changed.push(RememberInstallRules.backupPath(paths, RememberInstallRules.confName, lastWrite.stamp, lastWrite.before.conf === "absent"));
        return (lastWrite.mode === "remove" ? "Removed. " : "") + "Undo puts back " + changed.join(", ");
    }

    // What a finished run says under the buttons ("" for nothing): its error unless quiet
    // (a prompt dismissed), and a conf polkitd was not told about
    function runNote(outcome) {
        if (outcome?.ok === true)
            return outcome.reload === "nohup" ? "polkit was not told to read its length again: it keeps the old one until it restarts." : "";
        return outcome?.quiet === true ? "" : String(outcome?.error ?? "");
    }

    // Where the files are → { label, text }
    function writtenTo(system, installed, files, minutes) {
        if (system === "nixos")
            return { label: "Set through", text: "the NixOS module (" + nixOption + ")" };
        const conf = installed?.conf === "ours" || (!!files && Number.isInteger(minutes) && RememberInstallRules.confFor(minutes, files.confs ?? {}) !== "");
        return { label: "Written to", text: RememberRules.rulePath + (conf ? ", " + RememberRules.confPath : "") };
    }

    // The NixOS line's caption
    function nixCaption(installed, minutes) {
        return installed?.rule === "ours" && needsLonger(installed, minutes) ? "The line changed: copy it, then nixos-rebuild switch."
                                                                             : "After nixos-rebuild switch this page shows the rule.";
    }

    // What is kept now. `remembered` RememberedAdmin.remembered, `list` its kept (parseKept's;
    // null before a list), `forget` { outcome, reason, atMs } (the last revoke), lastObtainedMs
    // (the latest obtained time seen), `time` the revoke's time of day as text.
    // → { text, kept, forgetShown, hint, problem } — a forget counts until something is
    // obtained after it; a lock's forget is said only once something was kept.
    function keptRow(remembered, list, forget, lastObtainedMs, nowMs, time) {
        const kept = remembered?.kept === true && remembered.untilMs > nowMs;
        const fresh = (forget?.atMs ?? 0) > 0 && forget.atMs >= (lastObtainedMs ?? 0);
        const problem = fresh && forget.outcome === "failed" ? "Could not forget." : "";
        let text = "", note = false;
        if (kept) {
            text = "Remembered, " + leftText(remembered.untilMs, nowMs) + " left";
        } else if (list?.known !== true) {
            text = "Not known what is remembered now.";
        } else if (fresh && forget.outcome === "forgotten" && forget.reason === "forget") {
            text = "Forgotten. The next root run asks again.";
            note = true;
        } else if (fresh && forget.outcome === "forgotten" && forget.reason === "lock" && lastObtainedMs > 0) {
            text = "Forgotten when the screen locked at " + time + ".";
            note = true;
        } else {
            text = "Nothing remembered now.";
        }
        return {
            text, kept, problem,
            forgetShown: kept || list?.known !== true,
            hint: kept ? "Forgets every remembered password in this session. Also done when the screen locks."
                : note ? "" : "Forgotten when the screen locks and when the shell restarts."
        };
    }

    // How much of a file changed by hand is shown: at most this many lines, each cut to
    // this many characters
    readonly property int handMaxLines: 40
    readonly property int handMaxCharacters: 200

    // A file's lines for the page, capped: [{ text, marked, more (the "… N more lines" line) }]
    function _capped(lines) {
        const shown = lines.slice(0, handMaxLines).map(line => ({
            text: line.text.length > handMaxCharacters ? line.text.slice(0, handMaxCharacters) + "…" : line.text,
            marked: line.marked, more: false
        }));
        const rest = lines.length - shown.length;
        if (rest > 0)
            shown.push({ text: "… " + rest + (rest === 1 ? " more line" : " more lines"), marked: false, more: true });
        return shown;
    }

    // A rules file changed by hand, its lines against the shell's rule for the facts: those
    // the shell's text has not are marked (its header line never) → { lines: [{ text,
    // marked, more }], caption } — every marked line counted, the shown ones capped
    function handRule(text, facts) {
        const own = RememberRules.ruleText(facts).split("\n");
        const lines = String(text ?? "").replace(/\n$/, "").split("\n").map(line => ({
            text: line,
            marked: !/^\s*\/\/\s*Written by h2s-shell/.test(line) && !own.includes(line)
        }));
        const count = lines.filter(line => line.marked).length;
        return {
            lines: _capped(lines),
            caption: count === 0 ? "Changed outside the shell."
                : (_counts[count] ?? String(count)) + (count === 1 ? " line was" : " lines were") + " added outside the shell."
        };
    }

    // A polkitd.conf not written by the shell, as it is
    function handConf(text) {
        return {
            lines: _capped(String(text ?? "").replace(/\n$/, "").split("\n").map(line => ({ text: line, marked: false }))),
            caption: "Not written by the shell."
        };
    }

    // What a question acts on: the sha256 of both files as the page shows them ("absent"
    // for none; null when not readable — never acted on), and the files it names
    function subjectOf(files, replace) {
        return {
            rule: currentOf(files?.rule), conf: currentOf(files?.confs?.[RememberRules.confPath]),
            replace: { rule: replace?.rule === true, conf: replace?.conf === true }
        };
    }

    // The answer still acts: both files are exactly what the question was asked about
    function subjectHolds(subject, files) {
        const now = subjectOf(files, null);
        return !!subject && typeof subject.rule === "string" && typeof subject.conf === "string"
            && subject.rule === now.rule && subject.conf === now.conf;
    }

    function _pathOf(name) {
        return name === "rule" ? RememberRules.rulePath : RememberRules.confPath;
    }

    // Every file a run will touch, and a hand-made one it leaves, in the question's words.
    // `named` { rule, conf }: the files changed by hand the question replaces or removes;
    // `plan` RememberInstall.plan's answer; `kept` { rule, conf }: hand-made files left as
    // they are
    function _touchLines(named, plan, kept, verb) {
        const lines = [];
        const others = ["rule", "conf"].filter(name => plan?.[name] === true && named?.[name] !== true).map(_pathOf);
        if (others.length > 0)
            lines.push("Also " + verb + ": " + others.join(", ") + ".");
        const left = ["rule", "conf"].filter(name => kept?.[name] === true && named?.[name] !== true).map(_pathOf);
        if (left.length > 0)
            lines.push("Kept as it is: " + left.join(", ") + ".");
        return lines;
    }

    // The question before Replace: `replace` { rule, conf } the files changed by hand it
    // replaces, `plan` what the Install would change, `handMade` { rule, conf } the files not
    // the shell's, `files` the texts shown (its subject)
    function replaceSpec(replace, plan, handMade, files, backups) {
        const names = ["rule", "conf"].filter(name => replace?.[name] === true).map(_pathOf);
        return {
            kind: "warning",
            title: "Replace " + names.join(" and ") + "?",
            body: ["The hand-made " + (names.length === 1 ? "file goes" : "files go") + " to the backups: " + String(backups ?? "") + "."]
                .concat(_touchLines(replace, plan, handMade, "changed"))
                .concat(["Then the shell writes its own in their place. Undo puts them back."]),
            buttons: [{ id: "replace", label: "Replace", kind: "warning" }],
            subject: subjectOf(files, replace)
        };
    }

    // The question before Remove of a rules file changed by hand
    function removeSpec(plan, handMade, files, backups) {
        const named = { rule: true, conf: false };
        return {
            kind: "warning",
            title: "Remove " + RememberRules.rulePath + "?",
            body: ["It was changed outside the shell. It goes to the backups: " + String(backups ?? "") + "."]
                .concat(_touchLines(named, plan, handMade, "removed"))
                .concat(["Undo puts it back."]),
            buttons: [{ id: "remove", label: "Remove", kind: "warning" }],
            subject: subjectOf(files, named)
        };
    }
}
