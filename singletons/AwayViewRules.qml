pragma Singleton

import QtQuick

// What the "When away" settings page shows, decided: the timeline's lanes, marks and where
// their labels go, the line under it, the apps keeping the screen on, a monitor's name, the
// Sleep and Hibernate sections' lines, the command entries' moments and lines.
// Pure functions; times in whole seconds, 0 = off. A lane's times are IdleRules.config's
// per monitor: { saverAfter, screenOffAfter }.
QtObject {
    id: root

    // The axis ends this far past the last mark, never before 10 min: a lone mark at 1 min
    // does not stand at the right edge
    readonly property real axisRoom: 1.18
    readonly property int axisMinimum: 600
    // Room between two labels on one side of the line, in pixels
    readonly property int labelGap: 8
    // An app's name and its reason, as shown (one line each, capped)
    readonly property int maxWho: 40
    readonly property int maxWhy: 80
    // The last of the sleep and the hibernation (the tail), this much later than everything
    // before it (and past an hour), sits on a compressed tail after a break, so the minutes
    // keep their room: the minutes get `mainShare` of the track, the stretch up to the tail
    // `tailShare`, the rest after it
    readonly property real breakRatio: 3
    readonly property int breakMinimum: 3600
    readonly property real mainShare: 0.7
    readonly property real tailShare: 0.15
    // The axis past the tail on the compressed tail
    readonly property real tailRoom: 1.1

    function _seconds(value) {
        return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : 0;
    }

    // When a monitor first goes dark (the screensaver or its screen-off, whichever comes
    // first), or -1 when it never does
    function firstDark(times) {
        const stages = [_seconds(times?.saverAfter), _seconds(times?.screenOffAfter)].filter(value => value > 0);
        return stages.length === 0 ? -1 : Math.min(...stages);
    }

    // When every monitor that goes dark has, or -1 when none does
    function allDarkAt(lanes) {
        const moments = (Array.isArray(lanes) ? lanes : []).map(firstDark).filter(value => value >= 0);
        return moments.length === 0 ? -1 : Math.max(...moments);
    }

    // A lane shows its screensaver: on, and at or before its screen-off (at the same time
    // the screen-off waits for its fade in) — or with no power control, where the screen-off
    // shows the screensaver too
    function showsSaver(times, canPowerOff) {
        const saver = _seconds(times?.saverAfter);
        const off = _seconds(times?.screenOffAfter);
        return saver > 0 && (off === 0 || saver <= off || canPowerOff !== true);
    }

    // Some monitor shows the screensaver at some point: its own stage (showsSaver), or its
    // screen-off where monitors cannot be turned off (the screensaver stands in for it)
    function anySaver(lanes, canPowerOff) {
        return (Array.isArray(lanes) ? lanes : []).some(times => showsSaver(times, canPowerOff)
            || canPowerOff !== true && _seconds(times?.screenOffAfter) > 0);
    }

    // A monitor's times as its card shows and writes them: its kept entry over the default's
    // (a field it lacks or holds wrongly is the default's), the four fields only, each time
    // a whole number within `range` ({ minimum, maximum }: IdleRules.monitorTimeRange). So a
    // hand-edited, partial entry still shows what idle uses and is written whole
    function cardTimes(own, defaults, range) {
        const low = Number(range?.minimum) || 1;
        const high = Number(range?.maximum) || 86400;
        const pick = (field, check, fallback) => {
            const value = own !== null && typeof own === "object" ? own[field] : undefined;
            return check(value) ? value : check(defaults?.[field]) ? defaults[field] : fallback;
        };
        const isFlag = value => typeof value === "boolean";
        const isTime = value => typeof value === "number" && Number.isFinite(value);
        const clamp = value => Math.min(high, Math.max(low, Math.round(value)));
        return {
            screensaverEnabled: pick("screensaverEnabled", isFlag, false),
            screensaverTimeout: clamp(pick("screensaverTimeout", isTime, 300)),
            screenOffEnabled: pick("screenOffEnabled", isFlag, false),
            screenOffTimeout: clamp(pick("screenOffTimeout", isTime, 600))
        };
    }

    // Something happens when you are away: a stage on some lane, the idle lock, the sleep or
    // the hibernation
    function anything(lanes, lockAfter, sleepAfter, hibernateAt) {
        return _seconds(lockAfter) > 0 || _seconds(sleepAfter) > 0 || _seconds(hibernateAt) > 0 || allDarkAt(lanes) >= 0;
    }

    // The command entries' marks as given ([{ t, number }], commandMarks), those with a time
    function _commands(commands) {
        return (Array.isArray(commands) ? commands : []).filter(mark => _seconds(mark?.t) > 0);
    }

    // Where the axis ends (seconds): past the last of the stages, the lock, the command
    // entries' moments (`commands`, commandMarks), the sleep and the hibernation
    function axisEnd(lanes, lockAfter, commands, sleepAfter, hibernateAt) {
        const moments = [axisMinimum / axisRoom, _seconds(lockAfter), _seconds(sleepAfter), _seconds(hibernateAt)]
            .concat(_commands(commands).map(mark => mark.t));
        for (const times of Array.isArray(lanes) ? lanes : [])
            moments.push(_seconds(times?.saverAfter), _seconds(times?.screenOffAfter));
        return Math.max(axisMinimum, Math.round(Math.max(...moments) * axisRoom));
    }

    // The timeline's axis: { end, breakAt, tailAt } in seconds. The tail — the hibernation
    // (`hibernateAt`, from the last input), else the sleep — past breakMinimum and more than
    // breakRatio times the axis of everything before it (the sleep too, when the tail is the
    // hibernation) — something being on before it — goes after a break at `breakAt` (that
    // axis's end), the axis then ending a little past it; else `breakAt` is -1 and the axis
    // linear to axisEnd
    function axis(lanes, lockAfter, commands, sleepAfter, hibernateAt) {
        const sleep = _seconds(sleepAfter);
        const hibernate = _seconds(hibernateAt);
        const tail = hibernate > 0 ? hibernate : sleep;
        const sleepBefore = hibernate > 0 ? sleep : 0;
        // A command entry at the tail (before sleep) goes with it, after the break
        const before = axisEnd(lanes, lockAfter, _commands(commands).filter(mark => !(tail > 0 && mark.t >= tail)), sleepBefore, 0);
        if (anything(lanes, lockAfter, sleepBefore, 0) && tail > breakMinimum && tail > breakRatio * before)
            return { end: Math.round(tail * tailRoom), breakAt: before, tailAt: tail };
        return { end: axisEnd(lanes, lockAfter, commands, sleep, hibernate), breakAt: -1, tailAt: tail };
    }

    // Where `t` (seconds) stands on an axis (axis()), from 0 to 1
    function place(t, given) {
        const end = Math.max(1, Number(given?.end) || 1);
        const at = Math.max(0, Math.min(Number(t) || 0, end));
        const breakAt = Number(given?.breakAt);
        if (!(breakAt > 0))
            return at / end;
        const tail = Number(given.tailAt);
        if (at <= breakAt)
            return mainShare * at / breakAt;
        if (at <= tail)
            return mainShare + tailShare * (at - breakAt) / (tail - breakAt);
        return mainShare + tailShare + (1 - mainShare - tailShare) * (at - tail) / Math.max(1, end - tail);
    }

    // One lane's stretches from 0 to `end`: [{ from, to, kind }], kind "on" (the desktop),
    // "saver", "off", "asleep" (from `sleepAfter`, the whole computer) or "hibernated" (from
    // `hibernateAt`). A screen-off before the screensaver hides it; without power control the
    // screen-off shows the screensaver. A stretch is cut at `breakAt` (> 0), so the break
    // shows as a gap
    function segments(times, end, canPowerOff, sleepAfter, breakAt, hibernateAt) {
        const last = _seconds(end);
        const saver = _seconds(times?.saverAfter);
        const off = _seconds(times?.screenOffAfter);
        const sleep = _seconds(sleepAfter);
        const hibernate = _seconds(hibernateAt);
        const cut = _seconds(breakAt);
        const kindAt = at => hibernate > 0 && at >= hibernate ? "hibernated"
            : sleep > 0 && at >= sleep ? "asleep"
            : off > 0 && at >= off ? (canPowerOff === true ? "off" : "saver")
            : saver > 0 && at >= saver ? "saver" : "on";
        const cuts = [0, saver, off, sleep, cut, hibernate].filter((value, index) => index === 0 || value > 0 && value < last)
            .sort((first, second) => first - second);
        const list = [];
        for (let i = 0; i < cuts.length; i++) {
            const to = i + 1 < cuts.length ? cuts[i + 1] : last;
            if (to <= cuts[i])
                continue;
            const kind = kindAt(cuts[i]);
            if (list.length > 0 && list[list.length - 1].kind === kind && cuts[i] !== cut)
                list[list.length - 1].to = to;
            else
                list.push({ from: cuts[i], to: to, kind: kind });
        }
        return list;
    }

    // The marks above and below the line: [{ t, text, kind }] — each lane's stage times
    // ("5 min"; equal times of two lanes once; a screensaver only where it shows,
    // showsSaver), "▸1 5 min" for each command entry with a time (`commands`, commandMarks),
    // "Lock 20 min", "Sleep 30 min", "Hibernate 2 h 20 min" (`hibernateAt`,
    // from the last input) — in time order, at one time the stages first, then the lock, the
    // sleep, the hibernation, then the command entries (whose moment those are)
    function marks(lanes, lockAfter, commands, durationOf, canPowerOff, sleepAfter, hibernateAt) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const list = [];
        const add = (t, text, kind) => {
            if (!list.some(mark => mark.t === t && mark.text === text))
                list.push({ t: t, text: text, kind: kind });
        };
        for (const times of Array.isArray(lanes) ? lanes : []) {
            const saver = showsSaver(times, canPowerOff !== false) ? _seconds(times?.saverAfter) : 0;
            for (const t of [saver, _seconds(times?.screenOffAfter)]) {
                if (t > 0)
                    add(t, label(t), "time");
            }
        }
        for (const mark of _commands(commands))
            add(mark.t, "\u25B8" + mark.number + " " + label(mark.t), "commands");
        if (_seconds(lockAfter) > 0)
            add(lockAfter, "Lock " + label(lockAfter), "lock");
        if (_seconds(sleepAfter) > 0)
            add(sleepAfter, "Sleep " + label(sleepAfter), "sleep");
        if (_seconds(hibernateAt) > 0)
            add(hibernateAt, "Hibernate " + label(hibernateAt), "hibernate");
        const order = { time: 0, lock: 1, sleep: 2, hibernate: 3, commands: 4 };
        // Equal ones keep the order they were added in (the entries' order): sort() need not be stable
        return list.map((mark, index) => ({ mark: mark, index: index }))
            .sort((first, second) => first.mark.t - second.mark.t || order[first.mark.kind] - order[second.mark.kind] || first.index - second.index)
            .map(item => item.mark);
    }

    // Where the labels go: `labels` [{ x, width }] in the marks' order, `x` the mark's place
    // on the line. Each is centred on its mark (inside the track) and goes above the line
    // (row 0) unless it would touch the one before it there; then below (row 1); with both
    // sides taken, the side that frees first, pushed right past the label there. → [{ left,
    // row }], in the same order
    function placeLabels(labels, trackWidth, gap) {
        const room = typeof gap === "number" ? gap : labelGap;
        const width = Math.max(0, Number(trackWidth) || 0);
        const ends = [-Infinity, -Infinity];
        const placed = [];
        for (const label of Array.isArray(labels) ? labels : []) {
            const labelWidth = Math.max(0, Number(label?.width) || 0);
            let left = Math.max(0, Math.min((Number(label?.x) || 0) - labelWidth / 2, width - labelWidth));
            const row = ends[0] + room <= left ? 0 : ends[1] + room <= left ? 1 : ends[0] <= ends[1] ? 0 : 1;
            left = Math.max(left, ends[row] + room);
            ends[row] = left + labelWidth;
            placed.push({ left: left, row: row });
        }
        return placed;
    }

    // Text from outside on one line, capped
    function _line(text, length) {
        return typeof text === "string" ? text.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim().slice(0, length) : "";
    }

    // The apps keeping the screen on, as listed: [{ who, why }] — the screensaver
    // interface's holders ({ app, reason }), logind's idle blocks as last read ({ who, why })
    // and, when a Wayland client holds idle off (`waylandHeld`), "an app (unnamed)": Wayland
    // tells no name
    function holders(busHolders, logindHolders, waylandHeld) {
        const list = [];
        for (const holder of Array.isArray(busHolders) ? busHolders : [])
            list.push({ who: _line(holder?.app, maxWho) || "an app", why: _line(holder?.reason, maxWhy) });
        for (const holder of Array.isArray(logindHolders) ? logindHolders : [])
            list.push({ who: _line(holder?.who, maxWho) || "an app", why: _line(holder?.why, maxWhy) });
        if (waylandHeld === true)
            list.push({ who: "an app (unnamed)", why: "" });
        return list;
    }

    // The line under the timeline, always one: who holds the stages, who blocks the sleep
    // (logind's sleep blocks, while the sleep or the hibernation is on), nothing at all, or
    // where the lock comes and then the sleep and the hibernation, or what the lock screen
    // does. `facts`: { holders, sleepBlockers, anything, lockAfter, sleepAfter, hibernate
    // (IdleRules.config's, or null: none), perMonitor, lockedScreenOffAfter, canPowerOff }
    function caption(facts, durationOf) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const held = Array.isArray(facts?.holders) ? facts.holders : [];
        if (held.length > 0) {
            const first = held[0];
            return "Paused: " + first.who + " keeps the screen on" + (first.why ? " (" + first.why + ")" : "")
                + (held.length > 1 ? ", and " + (held.length - 1) + " more" : "") + ".";
        }
        const sleepAfter = _seconds(facts?.sleepAfter);
        const hibernate = facts?.hibernate?.on === true ? facts.hibernate : null;
        const blockers = Array.isArray(facts?.sleepBlockers) ? facts.sleepBlockers : [];
        if ((sleepAfter > 0 || hibernate !== null) && blockers.length > 0) {
            const first = blockers[0];
            return "Paused: " + (_line(first?.who, maxWho) || "an app") + " blocks sleep"
                + (_line(first?.why, maxWhy) ? " (" + _line(first.why, maxWhy) + ")" : "")
                + (blockers.length > 1 ? ", and " + (blockers.length - 1) + " more" : "") + ".";
        }
        if (facts?.anything !== true)
            return "Nothing happens when you are away.";
        const lockAfter = _seconds(facts?.lockAfter);
        const lockedOff = _seconds(facts?.lockedScreenOffAfter);
        return (lockAfter > 0 ? "Locks at " + label(lockAfter) + (facts?.perMonitor === true ? " on every monitor. " : ". ") : "No lock when idle. ")
            + (sleepAfter > 0 ? "Sleeps at " + label(sleepAfter) + (hibernate !== null ? ", hibernates " + label(hibernate.after) + " later." : ".")
               : hibernate !== null ? "Hibernates " + label(hibernate.after) + " after " + hibernateBaseName(hibernate.from) + "."
               : lockedOff > 0 ? "Locked: screens " + (facts?.canPowerOff === true ? "off" : "black") + " after " + label(lockedOff) + " without input."
               : "Locked: screens stay on.");
    }

    // ---- The Hibernate section ----

    // When the hibernation comes, from the last input (seconds; 0 none): `hibernate` as
    // IdleRules.config gives it — from where it counts, its time later
    function hibernateAt(hibernate) {
        return hibernate?.on === true ? _seconds(hibernate.at) + _seconds(hibernate.after) : 0;
    }

    // Where it counts from, as words (IdleRules.hibernateBase's `from`)
    function hibernateBaseName(from) {
        return ({ sleep: "sleeping", lock: "the lock", saver: "the screensaver" })[from] ?? "your last input";
    }

    // The words before its times: "after sleeping for" with sleep on, else "after the lock",
    // "after the screensaver", "after your last input"
    function hibernatePillsLabel(from) {
        return from === "sleep" ? "after sleeping for" : "after " + hibernateBaseName(from);
    }

    // The line under the section's title: why it is not possible (`unavailable`, from
    // HibernateRules.unavailable), else what it does, from where it counts
    function hibernateCaption(unavailable, from) {
        if (typeof unavailable === "string" && unavailable !== "")
            return unavailable;
        if (from === "sleep")
            return "Saves the session to disk and powers off, after the computer has slept this long \u2014 it wakes briefly to do it.";
        return "Saves the session to disk and powers off, this long after " + hibernateBaseName(from) + ".";
    }

    // The line under its times: "Hibernates 2 h after the lock (2 h 20 min after your last
    // input)."; counted from the last input, the brackets would say it twice
    function hibernateLine(hibernate, durationOf) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const after = _seconds(hibernate?.after);
        const from = hibernate?.from;
        if (from !== "sleep" && from !== "lock" && from !== "saver")
            return "Hibernates " + label(after) + " after your last input.";
        return "Hibernates " + label(after) + " after " + hibernateBaseName(from) + " (" + label(_seconds(hibernate.at) + after)
            + " after your last input).";
    }

    // ---- The Sleep section ----

    // Why the shell cannot sleep the computer here, from logind's CanSuspend answer; "" where
    // it can ("yes")
    function sleepUnavailable(canSuspend) {
        switch (canSuspend) {
        case "yes":
            return "";
        case "challenge":
            return "Not available here: the system asks for a password to sleep";
        case "na":
            return "Not available here: this computer cannot sleep";
        case "no":
            return "Not available here: the system does not allow it";
        default:
            return "Not available here: the system did not say whether it can sleep";
        }
    }

    // Whether the sleep locks first, said under its time: "Lock before the computer sleeps"
    // on; else an idle lock at or before it; else it sleeps unlocked — said in advance.
    // `facts`: { lockOnSleep, lockAfter (0 = no idle lock), sleepAfter }
    function sleepLockLine(facts, durationOf) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const lockAfter = _seconds(facts?.lockAfter);
        if (facts?.lockOnSleep === true)
            return "Locks first (\"Lock before the computer sleeps\").";
        if (lockAfter > 0 && lockAfter <= _seconds(facts?.sleepAfter))
            return "Already locked by then (lock at " + label(lockAfter) + ").";
        return "Sleeps unlocked: \"Lock before the computer sleeps\" is off.";
    }

    // What logind does by itself after idle (its IdleAction, `{ action, after }` as read), as
    // a warning beside the shell's sleep — whichever comes first acts; "" when it does
    // nothing that ends the session's work (ignore, lock), or was not read
    function systemSleeps(idleAction, durationOf) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const action = typeof idleAction?.action === "string" ? idleAction.action : "";
        const words = {
            "suspend": "puts the computer to sleep",
            "hybrid-sleep": "puts the computer to sleep",
            "suspend-then-hibernate": "puts the computer to sleep",
            "sleep": "puts the computer to sleep",
            "hibernate": "hibernates the computer",
            "poweroff": "turns the computer off",
            "halt": "turns the computer off",
            "reboot": "restarts the computer",
            "kexec": "restarts the computer"
        };
        if (!Object.prototype.hasOwnProperty.call(words, action))
            return "";
        const what = words[action];
        const after = _seconds(idleAction.after);
        return "The system already " + what + (after > 0 ? " after " + label(after) : "") + " without input (logind's IdleAction). "
            + "With this on too, whichever comes first acts.";
    }

    // ---- Command entries ----

    // When an entry's moment comes, in seconds from the last input, or -1 when it does not
    // come by the clock: "dark" the last of the monitors it waits for (IdleRules.commandWaits)
    // to go dark, -1 with none; "lock" the idle lock, "sleep" the sleep (or the hibernation in
    // its place) — -1 while off: they come only by hand or another's. `facts`: { config
    // (IdleRules.config), lockAfter, sleepAt }
    function commandAt(entry, facts) {
        if (entry?.moment === "lock")
            return _seconds(facts?.lockAfter) > 0 ? facts.lockAfter : -1;
        if (entry?.moment === "sleep")
            return _seconds(facts?.sleepAt) > 0 ? facts.sleepAt : -1;
        const config = facts?.config ?? {};
        const moments = IdleRules.commandWaits(entry, config, false)
            .map(id => firstDark(config.times?.[id] ?? { saverAfter: config.saverAfter, screenOffAfter: config.screenOffAfter }));
        return moments.length === 0 ? -1 : Math.max(...moments);
    }

    // An entry's moment as its line says it, and whether it can still come: { text, greyed }.
    // `names`: monitor id → its name (monitorNames)
    function commandMoment(entry, facts, names, durationOf) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const at = commandAt(entry, facts);
        if (entry?.moment === "lock")
            return { text: at > 0 ? "Locked (" + label(at) + ", or by hand)" : "Locked (by hand)", greyed: false };
        if (entry?.moment === "sleep")
            return { text: at > 0 ? "Before sleep (" + label(at) + ", or any sleep)" : "Before any sleep", greyed: false };
        const waited = IdleRules.commandWaits(entry, facts?.config ?? {}, false);
        if (waited.length === 0)
            return { text: "No screen goes dark", greyed: true };
        const who = !Array.isArray(entry?.monitors) ? "Every screen"
            : waited.map(id => _line(names?.[id] ?? monitorName(id, ""), maxWho)).join(" and ");
        return { text: who + " dark (" + label(at) + ")", greyed: false };
    }

    // An entry's two commands on its line, each cut short; "No commands yet" for neither
    function commandLine(entry) {
        const go = _line(entry?.go, 200);
        const back = _line(entry?.back, 200);
        if (go === "" && back === "")
            return "No commands yet";
        const shorten = command => command === "" ? "\u2014" : command.length > maxCommand ? command.slice(0, maxCommand - 1) + "\u2026" : command;
        return shorten(go) + "   /   back: " + shorten(back);
    }
    readonly property int maxCommand: 40

    // The timeline's marks of the entries: [{ t, number }] — each entry with a command whose
    // moment comes by the clock (commandAt), numbered by its place in the list from 1
    function commandMarks(entries, facts) {
        const list = [];
        (Array.isArray(entries) ? entries : []).forEach((entry, index) => {
            const at = commandAt(entry, facts);
            if (at > 0 && (_line(entry?.go, 1) !== "" || _line(entry?.back, 1) !== ""))
                list.push({ t: at, number: index + 1 });
        });
        return list;
    }

    // The editor's chips: each connected monitor ({ id }) with whether the entry waits for it,
    // whether it goes dark and when — [{ id, ticked, dark, at }]; a monitor that never goes
    // dark is never ticked (not waited for)
    function commandChips(entry, facts, monitors) {
        const config = facts?.config ?? {};
        const waited = IdleRules.commandWaits(entry, config, false);
        return (Array.isArray(monitors) ? monitors : []).map(monitor => {
            const id = typeof monitor === "string" ? monitor : monitor?.id;
            const at = firstDark(config.times?.[id] ?? { saverAfter: config.saverAfter, screenOffAfter: config.screenOffAfter });
            return { id: id, ticked: waited.includes(id), dark: at > 0, at: at };
        });
    }

    // The monitors an entry names after a chip's click: `id` ticked (its own id added) or
    // unticked — the list starting from the ones it waits for now when it named none (every
    // one that goes dark). Unticking drops the monitor's own id, and a key that names it
    // and others too (a twin's plain make|model|serial) gives way to those others' own ids,
    // so the others stay waited for. The last monitor waited for is not unticked: an entry
    // that waits for nothing has no moment. → the new list, or null when nothing changes
    function commandMonitorsToggled(entry, facts, id) {
        const config = facts?.config ?? {};
        const waited = IdleRules.commandWaits(entry, config, false);
        if (!waited.includes(id))
            return (Array.isArray(entry?.monitors) ? entry.monitors : waited).concat([id]);
        if (waited.length <= 1)
            return null;
        const named = Array.isArray(entry?.monitors) ? entry.monitors : waited;
        const keysOf = monitor => config.keys?.[monitor] ?? [monitor];
        const result = [];
        for (const key of named) {
            if (!keysOf(id).includes(key)) {
                result.push(key);
                continue;
            }
            // A key of the clicked monitor: the other waited monitors it covered keep theirs
            for (const other of waited) {
                if (other !== id && keysOf(other).includes(key) && !result.includes(other))
                    result.push(other);
            }
        }
        return result;
    }

    // A monitor's name on its card and its lane, from its id (make|model|serial, a twin's
    // with its connector) and its connector ("" for one not connected): the built-in panel
    // by its kind, else the make's first word and the model, else the connector
    function monitorName(id, connector) {
        const fields = String(id ?? "").split("|");
        const port = typeof connector === "string" && connector !== "" ? connector : (fields[3] ?? "");
        if (port !== "" && MonitorRules.isBuiltIn(port))
            return "Built-in screen";
        const make = _line(fields[0] ?? "", 80).split(" ")[0].replace(/,$/, "");
        const model = _line(fields[1] ?? "", 80);
        const name = [make, model].filter(part => part !== "").join(" ");
        return name !== "" ? name : (port !== "" ? _line(port, 40) : "Monitor");
    }

    // The connected monitors' names ([{ id, connector }] → names in that order): each its
    // monitorName, with its connector added where two share one (twins), so lanes and cards
    // tell them apart
    function monitorNames(monitors) {
        const list = Array.isArray(monitors) ? monitors : [];
        const names = list.map(monitor => monitorName(monitor?.id, monitor?.connector ?? ""));
        return names.map((name, index) => names.indexOf(name) !== names.lastIndexOf(name) && (list[index]?.connector ?? "") !== ""
            ? name + " (" + _line(list[index].connector, 40) + ")" : name);
    }
}
