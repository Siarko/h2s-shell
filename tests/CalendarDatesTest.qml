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
        assertEqual(GoogleCalendarData.describeFailure({ status: 0 }), "no connection", "status 0: offline");
        assertEqual(GoogleCalendarData.describeFailure({ status: 0, timedOut: true }), "the request timed out", "a timeout says so");
        assert(GoogleCalendarData.describeFailure({ status: 401 }).includes("sign-in expired"), "401: the sign-in");
        assertEqual(GoogleCalendarData.describeFailure({ status: 500 }), "Google returned an error (HTTP 500)", "other statuses");
        assertEqual(GoogleCalendarData.describeFailure(new Error("boom")), "boom", "anything else: its message");

        // --- Google's JSON and the shell's shapes ---
        assertEqual(GoogleCalendarData.offsetText(120), "+02:00", "offset east of UTC");
        assertEqual(GoogleCalendarData.offsetText(-210), "-03:30", "offset west, with minutes");
        assertEqual(GoogleCalendarData.offsetText(0), "+00:00", "UTC");

        const calendar = GoogleCalendarData.calendar({ id: "work@x", summary: "Work", backgroundColor: "#123456" });
        assertEqual(JSON.stringify(calendar), JSON.stringify({ id: "work@x", name: "Work", color: "#123456" }), "a calendar: name and colour");
        assertEqual(GoogleCalendarData.calendar({ id: "a@x" }).name, "a@x", "a calendar without a name: its id");

        const timed = GoogleCalendarData.event({ id: "e1", summary: "Standup", start: { dateTime: "2026-03-05T09:30:00" }, end: { dateTime: "2026-03-05T10:00:00" } },
            calendar, {}, "#ffffff");
        assertEqual(timed.time, "09:30 - 10:00", "a timed event's hours");
        assertEqual(timed.color, "#123456", "no colour of its own: the calendar's");
        assertEqual(timed.calendarColor, "#123456", "the calendar's colour shown beside it, not being the primary one");
        const coloured = GoogleCalendarData.event({ id: "e2", colorId: "5", start: { dateTime: "2026-03-05T09:30:00" }, end: { dateTime: "2026-03-05T10:00:00" } },
            calendar, { "5": "#fbd75b" }, "#ffffff");
        assertEqual(coloured.color, "#fbd75b", "its own colour, from Google's palette");
        assertEqual(coloured.title, "(No title)", "no title");
        assertEqual(GoogleCalendarData.event({ id: "e3", colorId: "99", start: { date: "2026-03-05" }, end: { date: "2026-03-06" } },
            calendar, {}, "#ffffff").color, "#ffffff", "a colour id not in the palette: the fallback");
        const allDay = GoogleCalendarData.event({ id: "e4", start: { date: "2026-03-05" }, end: { date: "2026-03-08" } }, calendar, {}, "#ffffff");
        assertEqual(allDay.time, "All day", "all day");
        assertEqual(allDay.allDayDuration, 3, "end date exclusive: three days");
        assertEqual(allDay.allDayEndDate.getDate(), 7, "the last day shown is the day before the end date");
        assertEqual(GoogleCalendarData.event({ id: "e5", start: { date: "2026-03-05" }, end: { date: "2026-03-05" } }, calendar, {}, "#ffffff").allDayDuration,
            1, "zero-length all-day event: one day");

        const body = GoogleCalendarData.eventBody({ year: 2026, month: 2, day: 5, title: "Lunch", startTime: "12:00", endTime: "13:00", colorId: "2", rrule: "RRULE:FREQ=WEEKLY;INTERVAL=1" }, "+01:00");
        assertEqual(body.start.dateTime, "2026-03-05T12:00:00+01:00", "a timed event's start, with the offset");
        assertEqual(body.end.dateTime, "2026-03-05T13:00:00+01:00", "and its end");
        assertEqual(body.recurrence.join(), "RRULE:FREQ=WEEKLY;INTERVAL=1", "its recurrence");
        assertEqual(body.description, undefined, "no description: none sent");
        const allDayBody = GoogleCalendarData.eventBody({ year: 2026, month: 1, day: 28, title: "Trip" }, "+01:00");
        assertEqual(allDayBody.start.date + " " + allDayBody.end.date, "2026-02-28 2026-03-01", "all day: end date the next day, across a month");
        assertEqual(allDayBody.start.dateTime, null, "all day: no times");

        assertEqual(GoogleCalendarData.recurrenceEndingBefore(["RRULE:FREQ=WEEKLY;COUNT=10;BYDAY=MO"], 2026, 2, 1).join(),
            "RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20260228", "a series cut to end the day before: COUNT replaced, across a month");
        assertEqual(GoogleCalendarData.recurrenceEndingBefore(["EXDATE:20260101", "RRULE:FREQ=DAILY;UNTIL=20270101"], 2026, 0, 1).join("|"),
            "EXDATE:20260101|RRULE:FREQ=DAILY;UNTIL=20251231", "UNTIL replaced, other lines kept, across a year");
        assertEqual(GoogleCalendarData.recurrenceEndingBefore(["EXDATE:20260101"], 2026, 0, 1), null, "no RRULE: nothing to cut");

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
