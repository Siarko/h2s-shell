pragma Singleton

import QtQuick

// What the "When away" settings page shows, decided: the timeline's lanes, marks and where
// their labels go, the line under it, the apps keeping the screen on, a monitor's name.
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

    function _seconds(value) {
        return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : 0;
    }

    // When a monitor first goes dark (the screensaver or its screen-off, whichever comes
    // first), or -1 when it never does
    function firstDark(times) {
        const stages = [_seconds(times?.saverAfter), _seconds(times?.screenOffAfter)].filter(value => value > 0);
        return stages.length === 0 ? -1 : Math.min(...stages);
    }

    // When every monitor that goes dark has (the commands' moment), or -1 when none does
    function allDarkAt(lanes) {
        const moments = (Array.isArray(lanes) ? lanes : []).map(firstDark).filter(value => value >= 0);
        return moments.length === 0 ? -1 : Math.max(...moments);
    }

    // A lane shows its screensaver: on, and before its screen-off — or with no power
    // control, where the screen-off shows the screensaver too
    function showsSaver(times, canPowerOff) {
        const saver = _seconds(times?.saverAfter);
        const off = _seconds(times?.screenOffAfter);
        return saver > 0 && (off === 0 || saver < off || canPowerOff !== true);
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

    // Something happens when you are away: a stage on some lane, or the idle lock
    function anything(lanes, lockAfter) {
        return _seconds(lockAfter) > 0 || allDarkAt(lanes) >= 0;
    }

    // Where the axis ends (seconds): past the last of the stages, the lock and the commands
    function axisEnd(lanes, lockAfter, commandsAt) {
        const moments = [axisMinimum / axisRoom, _seconds(lockAfter), _seconds(commandsAt)];
        for (const times of Array.isArray(lanes) ? lanes : [])
            moments.push(_seconds(times?.saverAfter), _seconds(times?.screenOffAfter));
        return Math.max(axisMinimum, Math.round(Math.max(...moments) * axisRoom));
    }

    // One lane's stretches from 0 to `end`: [{ from, to, kind }], kind "on" (the desktop),
    // "saver" or "off". A screen-off before the screensaver hides it; without power control
    // the screen-off shows the screensaver
    function segments(times, end, canPowerOff) {
        const last = _seconds(end);
        const saver = _seconds(times?.saverAfter);
        const off = _seconds(times?.screenOffAfter);
        const kindAt = at => off > 0 && at >= off ? (canPowerOff === true ? "off" : "saver")
            : saver > 0 && at >= saver ? "saver" : "on";
        const cuts = [0, saver, off].filter((value, index) => index === 0 || value > 0 && value < last)
            .sort((first, second) => first - second);
        const list = [];
        for (let i = 0; i < cuts.length; i++) {
            const to = i + 1 < cuts.length ? cuts[i + 1] : last;
            if (to <= cuts[i])
                continue;
            const kind = kindAt(cuts[i]);
            if (list.length > 0 && list[list.length - 1].kind === kind)
                list[list.length - 1].to = to;
            else
                list.push({ from: cuts[i], to: to, kind: kind });
        }
        return list;
    }

    // The marks above and below the line: [{ t, text, kind }] — each lane's stage times
    // ("5 min"; equal times of two lanes once; a screensaver only where it shows,
    // showsSaver), "Commands 5 min" while the commands run
    // (`commandsAt` ≥ 0), "Lock 20 min" — in time order, at one time the stages first, the
    // lock last
    function marks(lanes, lockAfter, commandsAt, durationOf, canPowerOff) {
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
        if (typeof commandsAt === "number" && commandsAt > 0)
            add(commandsAt, "Commands " + label(commandsAt), "commands");
        if (_seconds(lockAfter) > 0)
            add(lockAfter, "Lock " + label(lockAfter), "lock");
        const order = { time: 0, commands: 1, lock: 2 };
        return list.sort((first, second) => first.t - second.t || order[first.kind] - order[second.kind]);
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

    // The line under the timeline, always one: who holds the stages, nothing at all, or
    // where the lock comes and what the lock screen does. `facts`: { holders, anything,
    // lockAfter, perMonitor, lockedScreenOffAfter, canPowerOff }
    function caption(facts, durationOf) {
        const label = typeof durationOf === "function" ? durationOf : seconds => seconds + " s";
        const held = Array.isArray(facts?.holders) ? facts.holders : [];
        if (held.length > 0) {
            const first = held[0];
            return "Paused: " + first.who + " keeps the screen on" + (first.why ? " (" + first.why + ")" : "")
                + (held.length > 1 ? ", and " + (held.length - 1) + " more" : "") + ".";
        }
        if (facts?.anything !== true)
            return "Nothing happens when you are away.";
        const lockAfter = _seconds(facts?.lockAfter);
        const lockedOff = _seconds(facts?.lockedScreenOffAfter);
        return (lockAfter > 0 ? "Locks at " + label(lockAfter) + (facts?.perMonitor === true ? " on every monitor. " : ". ") : "No lock when idle. ")
            + (lockedOff > 0 ? "Locked: screens " + (facts?.canPowerOff === true ? "off" : "black") + " after " + label(lockedOff) + " without input."
                             : "Locked: screens stay on.");
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
