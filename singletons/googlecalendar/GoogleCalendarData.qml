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
        let allDayDuration = 0;
        let allDayStartDate = null;
        let allDayEndDate = null;

        if (data.start && data.start.dateTime) {
            startTime = new Date(data.start.dateTime);
            startTimeText = _clock(startTime);
            endTimeText = _clock(new Date(data.end.dateTime));
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
            allDayDuration = (endExclusive.getTime() - allDayStartDate.getTime()) / 86400000;
        }

        return {
            id: data.id,
            title: data.summary || "(No title)",
            description: data.description,
            eventType: data.eventType,
            startTime: startTime,
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
            primary: item.primary
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

    // An event as Google takes it, from the event form's values — { year, month (0-based),
    // day, title, description, colorId, rrule, startTime and endTime ("HH:MM", none for all
    // day) } — in the time zone `offset` ("+02:00")
    function eventBody(data, offset) {
        const dateText = CalendarDates.dateKey(data.year, data.month, data.day);
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
        if (data.startTime) {
            body.start.dateTime = dateText + "T" + data.startTime + ":00" + offset;
            body.end.dateTime = dateText + "T" + (data.endTime || data.startTime) + ":00" + offset;
        } else {
            // Google's all-day end date is exclusive. Sending the start date again creates
            // a zero-length event that the phone still shows but eventDayKeys drops.
            const nextDay = new Date(data.year, data.month, data.day + 1);
            body.start.date = dateText;
            body.end.date = CalendarDates.dateKey(nextDay.getFullYear(), nextDay.getMonth(), nextDay.getDate());
        }
        return body;
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
