pragma Singleton

import Quickshell

// Google Calendar's JSON and the shell's shapes, both ways: an event or a calendar as the
// panels show it, an event as Google takes it, a series cut short, and failures put into
// words. Pure functions, kept apart from GoogleCalendar for the same reason as
// CalendarDates: the test suite can load these without connecting to the account.
Singleton {
    id: root

    // A failure as the user would put it
    function describeFailure(reason) {
        if (reason?.timedOut)
            return "the request timed out";
        if (reason?.status === 0)
            return "no connection";
        if (reason?.status === 401)
            return "the sign-in expired — reconnect in Settings → Calendar";
        if (reason?.status === 403)
            return "access was denied";
        if (reason?.status)
            return "Google returned an error (HTTP " + reason.status + ")";
        return reason?.message ?? String(reason);
    }

    // A time zone offset, in minutes east of UTC, as ISO 8601 writes it: "+02:00"
    function offsetText(minutesEast) {
        const sign = minutesEast >= 0 ? "+" : "-";
        const hours = ("0" + Math.floor(Math.abs(minutesEast) / 60)).slice(-2);
        const minutes = ("0" + (Math.abs(minutesEast) % 60)).slice(-2);
        return sign + hours + ":" + minutes;
    }

    // The local time zone's offset now
    function localOffset() {
        return offsetText(-(new Date().getTimezoneOffset()));
    }

    function _clock(date) {
        return ("0" + date.getHours()).slice(-2) + ":" + ("0" + date.getMinutes()).slice(-2);
    }

    // An event as the panels show it. `calendar` is the one it came from (calendar() below),
    // `eventColors` Google's event colours by id, and `fallbackColor` what an event shows
    // whose colour id is not among them.
    function event(data, calendar, eventColors, fallbackColor) {
        let timeText = "All day";
        let startTimeText = "";
        let endTimeText = "";
        const color = data.colorId ? (eventColors[data.colorId] || fallbackColor) : calendar.color;
        const calendarColor = calendar ? (calendar?.primary ? null : calendar.color) : null;

        let startTime = null;
        let endTime = null;
        // The first and last day as keys, for the event form: a timed event's end date is
        // the day it ends on, an all-day event's its last day (Google's end date is the
        // day after)
        let startDate = "";
        let endDate = "";
        // The last day it takes up in the calendar
        let lastDate = "";
        let allDayDuration = 0;
        let allDayStartDate = null;
        let allDayEndDate = null;

        if (data.start && data.start.dateTime) {
            startTime = new Date(data.start.dateTime);
            endTime = new Date(data.end?.dateTime ?? data.start.dateTime);
            startTimeText = _clock(startTime);
            endTimeText = _clock(endTime);
            startDate = CalendarDates.keyOfDate(startTime);
            endDate = CalendarDates.keyOfDate(endTime);
            // Ending at midnight, it does not reach into that day (as in eventDayKeys)
            const endsAtMidnight = endTime.getHours() === 0 && endTime.getMinutes() === 0 && endTime.getSeconds() === 0;
            lastDate = endsAtMidnight && endTime > startTime ? CalendarDates.addDays(endDate, -1) : endDate;
            timeText = startTimeText + " - " + endTimeText;
        } else if (data.start && data.start.date) {
            const startParts = data.start.date.split("-");
            const endParts = data.end.date.split("-");
            allDayStartDate = new Date(parseInt(startParts[0]), parseInt(startParts[1]) - 1, parseInt(startParts[2]));
            let endExclusive = new Date(parseInt(endParts[0]), parseInt(endParts[1]) - 1, parseInt(endParts[2]));
            // Same zero-length case as in CalendarDates.eventDayKeys: end == start is one day
            if (endExclusive <= allDayStartDate)
                endExclusive = new Date(allDayStartDate.getFullYear(), allDayStartDate.getMonth(), allDayStartDate.getDate() + 1);
            allDayEndDate = new Date(endExclusive.getTime() - 86400000);
            allDayDuration = Math.round((endExclusive.getTime() - allDayStartDate.getTime()) / 86400000);
            startDate = CalendarDates.keyOfDate(allDayStartDate);
            endDate = CalendarDates.keyOfDate(allDayEndDate);
            lastDate = endDate;
        }

        return {
            id: data.id,
            title: data.summary || "(No title)",
            description: data.description,
            eventType: data.eventType,
            startTime: startTime,
            endTime: endTime,
            startDate: startDate,
            endDate: endDate,
            lastDate: lastDate,
            startTimeStr: startTimeText,
            endTimeStr: endTimeText,
            time: timeText,
            allDayDuration: allDayDuration,
            allDayStartDate: allDayStartDate,
            allDayEndDate: allDayEndDate,
            color: color,
            calendarColor: calendarColor ?? null,
            calendarId: calendar?.id ?? null,
            colorId: data.colorId ?? null,
            rrule: (data.recurrence && data.recurrence.length > 0) ? data.recurrence[0] : null,
            recurringEventId: data.recurringEventId ?? null
        };
    }

    // A calendar from the account's list, as the panels show it
    function calendar(item) {
        return {
            id: item.id,
            name: item.summary || item.id,
            color: item.backgroundColor || "#5b9bf5",
            primary: item.primary,
            // Events can be added, changed and deleted only with the owner's or a writer's
            // access; holiday and other subscribed calendars are read-only ("reader"). A
            // calendar without a role (never so from Google) counts as writable, as before.
            writable: !item.accessRole || item.accessRole === "owner" || item.accessRole === "writer"
        };
    }

    // The order of a day's events, as GoogleCalendar has always sorted them
    function compareEvents(first, second) {
        if (first.startTime === second.startTime)
            return 0;
        if (first.startTime === null)
            return -1;
        if (second.startTime === null)
            return 1;
        return first.startTime > second.startTime ? -1 : 1;
    }

    // The body sent to Google for an event the form made: `data` has startDate and endDate
    // ("YYYY-MM-DD"; for all day the last day, included), startTime and endTime ("HH:MM",
    // empty for all day), title, description, colorId, rrule. `offsetFor(dateKey, time)`
    // gives the UTC offset text at that moment — per moment, since a summer event made in
    // winter has another offset than today's.
    function eventBody(data, offsetFor) {
        const body = {
            summary: data.title
        };
        if (data.description)
            body.description = data.description;
        if (data.colorId)
            body.colorId = data.colorId;
        if (data.rrule)
            body.recurrence = [data.rrule];

        body.start = {
            date: null,
            dateTime: null
        };
        body.end = {
            date: null,
            dateTime: null
        };
        const endDate = data.endDate || data.startDate;
        if (data.startTime) {
            const endTime = data.endTime || data.startTime;
            body.start.dateTime = data.startDate + "T" + data.startTime + ":00" + offsetFor(data.startDate, data.startTime);
            body.end.dateTime = endDate + "T" + endTime + ":00" + offsetFor(endDate, endTime);
        } else {
            // Google's all-day end date is exclusive: the day after the last. Sending the
            // last day itself creates a zero-length event that the phone still shows but
            // eventDayKeys drops.
            body.start.date = data.startDate;
            body.end.date = CalendarDates.addDays(endDate, 1);
        }
        return body;
    }

    // The local UTC offset text at a moment: dateKey "YYYY-MM-DD", time "HH:MM"
    function localOffsetAt(dateKey, time) {
        const date = CalendarDates.parseDateKey(dateKey);
        const parts = (time || "00:00").split(":");
        date.setHours(parseInt(parts[0]), parseInt(parts[1]));
        return offsetText(-date.getTimezoneOffset());
    }

    // A series' recurrence lines cut to end the day before the given one (month 0-based):
    // its RRULE's COUNT or UNTIL replaced by that UNTIL. Null when it has no RRULE.
    function recurrenceEndingBefore(recurrence, year, month, day) {
        const ruleIndex = recurrence.findIndex(line => line.startsWith("RRULE:"));
        if (ruleIndex === -1)
            return null;
        const dayBefore = new Date(year, month, day - 1);
        const until = dayBefore.getFullYear().toString() + ("0" + (dayBefore.getMonth() + 1)).slice(-2) + ("0" + dayBefore.getDate()).slice(-2);
        const rule = recurrence[ruleIndex].replace(/;UNTIL=[^;]*/g, "").replace(/;COUNT=[^;]*/g, "") + ";UNTIL=" + until;
        const result = recurrence.slice();
        result[ruleIndex] = rule;
        return result;
    }
}
