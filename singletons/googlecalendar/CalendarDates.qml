pragma Singleton

import Quickshell

// Date keys and event-to-day mapping for the Google Calendar store. Kept apart from
// GoogleCalendar because these are pure functions: loading GoogleCalendar connects to
// the account, which the test suite must not do.
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
}
