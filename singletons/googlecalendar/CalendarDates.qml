pragma Singleton

import Quickshell

// Date keys, event-to-day mapping and recurrence rules for the Google Calendar store.
// Kept apart from GoogleCalendar because these are pure functions: loading
// GoogleCalendar connects to the account, which the test suite must not do.
Singleton {
    id: root

    function dateKey(year: int, month: int, day: int): string {
        // month is 0-indexed; returns "YYYY-MM-DD"
        var m = ("0" + (month + 1)).slice(-2);
        var d = ("0" + day).slice(-2);
        return year + "-" + m + "-" + d;
    }

    function monthKey(year: int, month: int): string {
        // month is 0-indexed; returns "YYYY-MM"
        return year + "-" + ("0" + (month + 1)).slice(-2);
    }

    function daysInMonth(year: int, month: int): int {
        return new Date(year, month + 1, 0).getDate();
    }

    // A "YYYY-MM-DD" key as a local date, or null when it is not one. Never new Date(key):
    // that reads it as UTC, a day early west of Greenwich.
    function parseDateKey(key) {
        const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key ?? "");
        if (!parts)
            return null;
        const year = parseInt(parts[1]), month = parseInt(parts[2]) - 1, day = parseInt(parts[3]);
        if (month > 11 || day < 1 || day > daysInMonth(year, month))
            return null;
        return new Date(year, month, day);
    }

    function keyOfDate(date) {
        return dateKey(date.getFullYear(), date.getMonth(), date.getDate());
    }

    function addDays(key, days) {
        const date = parseDateKey(key);
        return keyOfDate(new Date(date.getFullYear(), date.getMonth(), date.getDate() + days));
    }

    // Whole days from one key to another; rounded, so a DST change between them (a 23 or
    // 25 hour day) does not cut one off
    function daysBetween(fromKey, toKey) {
        return Math.round((parseDateKey(toKey) - parseDateKey(fromKey)) / 86400000);
    }

    // An event's span of days, { start, end } as keys, after its start moved: the end moves
    // with it, so the event keeps its length
    function spanWithStart(span, newStart) {
        return { start: newStart, end: addDays(newStart, daysBetween(span.start, span.end)) };
    }

    // After its end moved: an end before the start becomes the new start, the length kept
    function spanWithEnd(span, newEnd) {
        if (daysBetween(span.start, newEnd) < 0)
            return spanWithStart(span, newEnd);
        return { start: span.start, end: newEnd };
    }

    // The bars of events spanning days, for a grid of days from firstKey to lastKey: by day
    // key, the pieces of bar on that day — { id, color, lane, isStart, isEnd }. Each event
    // keeps one lane (a row of bars, 0 the lowest) over all its days, so its bar runs on
    // unbroken, across weeks too; lanes go to events by start, longer first, each in the
    // lowest lane free by then. isStart and isEnd mark the event's real first and last
    // day — not where the grid cuts it off — for the rounded ends. `events` are the
    // panels' events (GoogleCalendarData.event), each once; single days are left out.
    function dayBars(events, firstKey, lastKey) {
        const spanning = events.filter(event => event.startDate && event.lastDate && event.lastDate > event.startDate
                && event.lastDate >= firstKey && event.startDate <= lastKey)
            .sort((a, b) => a.startDate < b.startDate ? -1 : a.startDate > b.startDate ? 1
                : daysBetween(b.startDate, b.lastDate) - daysBetween(a.startDate, a.lastDate));
        // The last day taken in each lane so far
        const laneEnds = [];
        const bars = {};
        for (const event of spanning) {
            let lane = laneEnds.findIndex(end => end < event.startDate);
            if (lane === -1)
                lane = laneEnds.length;
            laneEnds[lane] = event.lastDate;
            let key = event.startDate < firstKey ? firstKey : event.startDate;
            const last = event.lastDate > lastKey ? lastKey : event.lastDate;
            while (key <= last) {
                (bars[key] = bars[key] ?? []).push({
                    id: event.id,
                    color: event.color,
                    lane: lane,
                    isStart: key === event.startDate,
                    isEnd: key === event.lastDate
                });
                key = addDays(key, 1);
            }
        }
        return bars;
    }

    // Returns all "YYYY-MM-DD" keys within [year, month] that rawItem covers.
    // Handles timed events, all-day events, and multi-day spans. Clamps to the
    // given month so callers don't receive keys outside the fetched range.
    function eventDayKeys(rawItem, year, month) {
        let startDate, endDate;

        if (rawItem.start && rawItem.start.dateTime) {
            let startDt = new Date(rawItem.start.dateTime);
            let endDt = new Date(rawItem.end.dateTime);
            startDate = new Date(startDt.getFullYear(), startDt.getMonth(), startDt.getDate());
            endDate   = new Date(endDt.getFullYear(),   endDt.getMonth(),   endDt.getDate());
            // End exactly at midnight means the event doesn't extend into that calendar day
            if (endDt.getHours() === 0 && endDt.getMinutes() === 0 && endDt.getSeconds() === 0)
                endDate.setDate(endDate.getDate() - 1);
        } else if (rawItem.start && rawItem.start.date) {
            // Parse as local date — new Date("YYYY-MM-DD") uses UTC and shifts the day
            // at negative UTC offsets (e.g. Polish summer time = UTC+2 is fine, but
            // to be safe we always split manually).
            let sp = rawItem.start.date.split('-').map(Number);
            let ep = rawItem.end.date.split('-').map(Number);
            startDate = new Date(sp[0], sp[1] - 1, sp[2]);
            endDate   = new Date(ep[0], ep[1] - 1, ep[2]);
            // Google Calendar all-day events use an exclusive end date. Events saved with
            // end == start (as this shell used to create them) still occupy their start day.
            endDate.setDate(endDate.getDate() - 1);
            if (endDate < startDate)
                endDate = new Date(startDate);
        } else {
            return [];
        }

        // Clamp to the requested month so we don't emit keys for adjacent months
        let monthStart = new Date(year, month, 1);
        let monthEnd   = new Date(year, month + 1, 0);
        if (startDate < monthStart) startDate = new Date(monthStart);
        if (endDate   > monthEnd)   endDate   = new Date(monthEnd);
        if (startDate > endDate) return [];

        let dayKeys = [];
        let current = new Date(startDate);
        while (current <= endDate) {
            dayKeys.push(root.dateKey(current.getFullYear(), current.getMonth(), current.getDate()));
            current.setDate(current.getDate() + 1);
        }
        return dayKeys;
    }

    // A recurrence as the event form edits it: how often, every how many, on which days
    // (weekly only), and how it ends — never, on a date, or after a count
    readonly property var defaultRecurrence: ({
        freq: "WEEKLY", interval: 1, days: [], endType: "never", endDate: "", count: 1
    })

    // The RRULE line for a recurrence, as Google takes it
    function recurrenceRule(recurrence) {
        let rule = "RRULE:FREQ=" + recurrence.freq + ";INTERVAL=" + recurrence.interval;
        if (recurrence.freq === "WEEKLY" && recurrence.days.length > 0)
            rule += ";BYDAY=" + recurrence.days.join(",");
        if (recurrence.endType === "count")
            rule += ";COUNT=" + recurrence.count;
        else if (recurrence.endType === "date" && recurrence.endDate.length === 10)
            rule += ";UNTIL=" + recurrence.endDate.replace(/-/g, "");
        return rule;
    }

    // The recurrence an RRULE line describes; null for none (an empty line)
    function parseRecurrence(ruleText) {
        if (!ruleText)
            return null;
        const params = {};
        ruleText.replace("RRULE:", "").split(";").forEach(part => {
            const equals = part.indexOf("=");
            params[part.slice(0, equals)] = part.slice(equals + 1);
        });
        const recurrence = Object.assign({}, defaultRecurrence, {
            freq: params.FREQ || "WEEKLY",
            interval: parseInt(params.INTERVAL) || 1,
            days: params.BYDAY ? params.BYDAY.split(",") : []
        });
        if (params.COUNT) {
            recurrence.endType = "count";
            recurrence.count = parseInt(params.COUNT);
        } else if (params.UNTIL) {
            const until = params.UNTIL;
            recurrence.endType = "date";
            recurrence.endDate = until.slice(0, 4) + "-" + until.slice(4, 6) + "-" + until.slice(6, 8);
        }
        return recurrence;
    }
}
