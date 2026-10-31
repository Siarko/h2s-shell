import QtQuick
import qs.singletons.googlecalendar

TestCase {
    suiteName: "CalendarDates"

    // A timed event's start or end as the API sends it, built from local time so the
    // assertions do not depend on the machine's time zone
    function _at(year, month, day, hours, minutes) {
        return new Date(year, month, day, hours, minutes).toISOString();
    }

    function _timed(start, end) {
        return { start: { dateTime: start }, end: { dateTime: end } };
    }

    function _allDay(start, end) {
        return { start: { date: start }, end: { date: end } };
    }

    function _keys(item, year, month) {
        return JSON.stringify(CalendarDates.eventDayKeys(item, year, month));
    }

    function run() {
        // --- keys ---
        assertEqual(CalendarDates.dateKey(2026, 0, 5), "2026-01-05", "dateKey pads and is 0-indexed by month");
        assertEqual(CalendarDates.monthKey(2026, 11), "2026-12", "monthKey is 0-indexed by month");

        // --- timed events (October 2026 is month 9) ---
        assertEqual(_keys(_timed(_at(2026, 9, 5, 10, 0), _at(2026, 9, 5, 11, 0)), 2026, 9),
            JSON.stringify(["2026-10-05"]), "timed event within one day");
        assertEqual(_keys(_timed(_at(2026, 9, 5, 22, 0), _at(2026, 9, 6, 0, 0)), 2026, 9),
            JSON.stringify(["2026-10-05"]), "timed event ending at midnight stays on its day");
        assertEqual(_keys(_timed(_at(2026, 9, 5, 22, 0), _at(2026, 9, 6, 2, 0)), 2026, 9),
            JSON.stringify(["2026-10-05", "2026-10-06"]), "timed event past midnight covers both days");

        // --- all-day events: the end date is exclusive ---
        assertEqual(_keys(_allDay("2026-10-05", "2026-10-06"), 2026, 9),
            JSON.stringify(["2026-10-05"]), "all-day event, one day");
        assertEqual(_keys(_allDay("2026-10-05", "2026-10-08"), 2026, 9),
            JSON.stringify(["2026-10-05", "2026-10-06", "2026-10-07"]), "all-day event, three days");
        assertEqual(_keys(_allDay("2026-10-05", "2026-10-05"), 2026, 9),
            JSON.stringify(["2026-10-05"]), "zero-length all-day event still shows on its day");

        // --- clamping to the requested month ---
        assertEqual(_keys(_allDay("2026-09-29", "2026-10-03"), 2026, 9),
            JSON.stringify(["2026-10-01", "2026-10-02"]), "event starting last month is clamped");
        assertEqual(_keys(_allDay("2026-10-30", "2026-11-03"), 2026, 9),
            JSON.stringify(["2026-10-30", "2026-10-31"]), "event ending next month is clamped");
        assertEqual(_keys(_allDay("2026-11-05", "2026-11-06"), 2026, 9),
            JSON.stringify([]), "event in another month gives no keys");

        // --- malformed ---
        assertEqual(_keys({}, 2026, 9), JSON.stringify([]), "event without a start gives no keys");

        // --- failures as the calendar panel shows them ---
        assertEqual(GoogleCalendar._describe({ status: 0 }), "no connection", "status 0: offline");
        assertEqual(GoogleCalendar._describe({ status: 0, timedOut: true }), "the request timed out", "a timeout says so");
        assert(GoogleCalendar._describe({ status: 401 }).includes("sign-in expired"), "401: the sign-in");
        assertEqual(GoogleCalendar._describe({ status: 500 }), "Google returned an error (HTTP 500)", "other statuses");
        assertEqual(GoogleCalendar._describe(new Error("boom")), "boom", "anything else: its message");

        // --- recurrence rules ---
        const weekly = Object.assign({}, CalendarDates.defaultRecurrence, { days: ["MO", "WE"] });
        assertEqual(CalendarDates.recurrenceRule(weekly), "RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE", "weekly on days, never ending");
        assertEqual(CalendarDates.recurrenceRule(Object.assign({}, weekly, { freq: "MONTHLY", interval: 2, endType: "count", count: 5 })),
            "RRULE:FREQ=MONTHLY;INTERVAL=2;COUNT=5", "days only for weekly; ending after a count");
        assertEqual(CalendarDates.recurrenceRule(Object.assign({}, weekly, { days: [], endType: "date", endDate: "2026-12-31" })),
            "RRULE:FREQ=WEEKLY;INTERVAL=1;UNTIL=20261231", "ending on a date");
        assertEqual(CalendarDates.recurrenceRule(Object.assign({}, weekly, { days: [], endType: "date", endDate: "2026-12" })),
            "RRULE:FREQ=WEEKLY;INTERVAL=1", "an unfinished end date is left out");
        assertEqual(CalendarDates.parseRecurrence(""), null, "no rule: no recurrence");
        assertEqual(JSON.stringify(CalendarDates.parseRecurrence("RRULE:FREQ=DAILY;INTERVAL=3;UNTIL=20270115")),
            JSON.stringify({ freq: "DAILY", interval: 3, days: [], endType: "date", endDate: "2027-01-15", count: 1 }), "parses an end date");
        for (const rule of ["RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE", "RRULE:FREQ=YEARLY;INTERVAL=1;COUNT=10", "RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20261231"])
            assertEqual(CalendarDates.recurrenceRule(CalendarDates.parseRecurrence(rule)), rule, "round trip: " + rule);
    }
}
