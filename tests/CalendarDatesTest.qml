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
    }
}
