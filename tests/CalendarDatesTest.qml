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

        // --- the built-in client: unscrambled into the shape Google gives ---
        assert(GoogleCalendarAuth._builtInClientId.endsWith(".apps.googleusercontent.com"), "the built-in client id unscrambles");
        assert(GoogleCalendarAuth._builtInClientSecret.startsWith("GOCSPX-"), "the built-in client secret unscrambles");
        assertEqual(GoogleCalendarAuth._unscramble(Qt.btoa("")), "", "nothing unscrambles to nothing");

        // --- a failed token refresh: only a dead refresh token logs out ---
        const refreshFailure = (status, body) => ({ status: status, body: body });
        assert(GoogleCalendarAuth.refreshFailureIsFinal(refreshFailure(400, '{"error":"invalid_grant","error_description":"Token has been expired or revoked."}')),
            "invalid_grant: the refresh token is dead, log in again");
        assert(!GoogleCalendarAuth.refreshFailureIsFinal({ status: 0 }), "offline (after a resume): keep the login");
        assert(!GoogleCalendarAuth.refreshFailureIsFinal({ status: 0, timedOut: true }), "a timeout: keep the login");
        assert(!GoogleCalendarAuth.refreshFailureIsFinal(refreshFailure(503, "")), "Google's 5xx: keep the login");
        assert(!GoogleCalendarAuth.refreshFailureIsFinal(refreshFailure(401, '{"error":"invalid_client"}')),
            "another 4xx error: not the refresh token's fault");
        assert(!GoogleCalendarAuth.refreshFailureIsFinal(refreshFailure(400, "<html>")), "a body that is not JSON: keep the login");
        assert(!GoogleCalendarAuth.refreshFailureIsFinal(new SyntaxError("bad JSON")), "a garbled success: keep the login");

        // --- Google's JSON and the shell's shapes ---
        assertEqual(GoogleCalendarData.offsetText(120), "+02:00", "offset east of UTC");
        assertEqual(GoogleCalendarData.offsetText(-210), "-03:30", "offset west, with minutes");
        assertEqual(GoogleCalendarData.offsetText(0), "+00:00", "UTC");

        const calendar = GoogleCalendarData.calendar({ id: "work@x", summary: "Work", backgroundColor: "#123456" });
        assertEqual(GoogleCalendarData.calendar({ id: "h", accessRole: "reader" }).writable, false, "a holiday calendar is read-only");
        assertEqual(GoogleCalendarData.calendar({ id: "o", accessRole: "owner" }).writable, true, "one's own is writable");
        assertEqual(JSON.stringify(calendar), JSON.stringify({ id: "work@x", name: "Work", color: "#123456", writable: true }), "a calendar: name and colour; no role, writable");
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

        const plusOne = () => "+01:00";
        const body = GoogleCalendarData.eventBody({ startDate: "2026-03-05", endDate: "2026-03-05", title: "Lunch", startTime: "12:00", endTime: "13:00", colorId: "2", rrule: "RRULE:FREQ=WEEKLY;INTERVAL=1" }, plusOne);
        assertEqual(body.start.dateTime, "2026-03-05T12:00:00+01:00", "a timed event's start, with the offset");
        assertEqual(body.end.dateTime, "2026-03-05T13:00:00+01:00", "and its end");
        assertEqual(body.recurrence.join(), "RRULE:FREQ=WEEKLY;INTERVAL=1", "its recurrence");
        assertEqual(body.description, undefined, "no description: none sent");
        const allDayBody = GoogleCalendarData.eventBody({ startDate: "2026-02-28", endDate: "2026-02-28", title: "Trip" }, plusOne);
        assertEqual(allDayBody.start.date + " " + allDayBody.end.date, "2026-02-28 2026-03-01", "all day: end date the next day, across a month");
        assertEqual(allDayBody.start.dateTime, null, "all day: no times");
        const longTrip = GoogleCalendarData.eventBody({ startDate: "2026-10-30", endDate: "2026-11-02", title: "Trip" }, plusOne);
        assertEqual(longTrip.start.date + " " + longTrip.end.date, "2026-10-30 2026-11-03", "several days: Google's end the day after the last");
        const overnight = GoogleCalendarData.eventBody({ startDate: "2026-10-31", endDate: "2026-11-01", title: "Party", startTime: "22:00", endTime: "02:00" },
            (dateKey, time) => dateKey === "2026-10-31" ? "+01:00" : "+00:00");
        assertEqual(overnight.start.dateTime + " " + overnight.end.dateTime, "2026-10-31T22:00:00+01:00 2026-11-01T02:00:00+00:00",
            "a timed event over days: each end its own date and offset");
        assertEqual(GoogleCalendarData.localOffsetAt("2026-07-01", "12:00"),
            GoogleCalendarData.offsetText(-new Date(2026, 6, 1, 12, 0).getTimezoneOffset()), "the local offset at a moment, not today's");

        // --- dates for the event form ---
        assertEqual(CalendarDates.parseDateKey("2026-02-29"), null, "no 29 February in 2026");
        assertEqual(CalendarDates.parseDateKey("2028-02-29").getDate(), 29, "but in 2028");
        assertEqual(CalendarDates.parseDateKey("31.10.2026"), null, "only YYYY-MM-DD");
        assertEqual(CalendarDates.addDays("2026-12-30", 3), "2027-01-02", "days added across a year");
        assertEqual(CalendarDates.daysBetween("2026-10-24", "2026-10-26"), 2, "days between, across the end of summer time");
        const span = { start: "2026-10-30", end: "2026-11-01" };
        assertEqual(JSON.stringify(CalendarDates.spanWithStart(span, "2026-11-05")), JSON.stringify({ start: "2026-11-05", end: "2026-11-07" }),
            "a moved start takes the end along");
        assertEqual(JSON.stringify(CalendarDates.spanWithEnd(span, "2026-11-04")), JSON.stringify({ start: "2026-10-30", end: "2026-11-04" }),
            "a later end: only the end");
        assertEqual(JSON.stringify(CalendarDates.spanWithEnd(span, "2026-10-28")), JSON.stringify({ start: "2026-10-28", end: "2026-10-30" }),
            "an end before the start becomes the start, the length kept");

        // --- bars of events spanning days ---
        const spanEvent = (id, start, last) => ({ id: id, color: "#" + id, startDate: start, lastDate: last });
        const bars = CalendarDates.dayBars([
            spanEvent("a", "2026-10-29", "2026-11-03"),   // Thursday to Tuesday: across a week
            spanEvent("b", "2026-10-30", "2026-10-31"),
            spanEvent("c", "2026-11-02", "2026-11-02"),   // one day: no bar
            spanEvent("d", "2026-11-01", "2026-11-02"),   // after b ends: b's lane again
            spanEvent("e", "2026-09-20", "2026-09-30")    // before the grid starts
        ], "2026-09-28", "2026-11-08");
        assertEqual(bars["2026-10-29"].map(bar => bar.id + bar.lane).join(), "a0", "the first bar in the lowest lane");
        assertEqual(bars["2026-10-30"].map(bar => bar.id + bar.lane).join(), "a0,b1", "a second one above it");
        assertEqual(bars["2026-11-02"].map(bar => bar.id + bar.lane).join(), "a0,d1", "a lane free again is taken; single days have no bar");
        assertEqual(bars["2026-11-03"][0].isEnd && !bars["2026-11-02"][0].isEnd, true, "the end marked on the last day only");
        assertEqual(bars["2026-11-02"][0].isStart, false, "continuing on a new week: no rounded start");
        assertEqual(bars["2026-09-28"][0].isStart, false, "cut off by the grid's start: not its start");
        assertEqual(bars["2026-09-30"][0].isEnd, true, "but its real end is");
        assertEqual(bars["2026-11-04"], undefined, "nothing after the last bar");

        const timedOverDays = GoogleCalendarData.event({ id: "e6", start: { dateTime: _at(2026, 9, 31, 22, 0) }, end: { dateTime: _at(2026, 10, 1, 2, 0) } }, calendar, {}, "#ffffff");
        assertEqual(timedOverDays.startDate + " " + timedOverDays.endDate, "2026-10-31 2026-11-01", "a timed event's dates: the day it ends on");
        const untilMidnight = GoogleCalendarData.event({ id: "e7", start: { dateTime: _at(2026, 9, 31, 20, 0) }, end: { dateTime: _at(2026, 10, 1, 0, 0) } }, calendar, {}, "#ffffff");
        assertEqual(untilMidnight.endDate + " " + untilMidnight.lastDate, "2026-11-01 2026-10-31", "ending at midnight: its last day is the one before");
        assertEqual(allDay.startDate + " " + allDay.endDate, "2026-03-05 2026-03-07", "an all-day event's dates: its last day, not Google's end");

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
