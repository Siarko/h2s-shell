pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.network

// The Google Calendar API's requests, each with the signed-in account's token. They only
// send: GoogleCalendar decides what to fetch and keeps the results, and calls these inside
// GoogleCalendarAuth.ensureAuthorized, which refreshes the token on a 401.
Singleton {
    id: root

    readonly property string _ENDPOINT_COLORS: "https://www.googleapis.com/calendar/v3/colors"
    readonly property string _ENDPOINT_CALENDARS: "https://www.googleapis.com/calendar/v3/users/me/calendarList"
    readonly property string _ENDPOINT_EVENTS: "https://www.googleapis.com/calendar/v3/calendars/{0}/events"
    readonly property string _ENDPOINT_EVENT: "https://www.googleapis.com/calendar/v3/calendars/{0}/events/{1}"

    function _headers(withBody) {
        const headers = { "Authorization": "Bearer " + Config.gcal.accessToken };
        if (withBody)
            headers["Content-Type"] = "application/json";
        return headers;
    }

    // A calendar's events between two times, recurring ones expanded into instances.
    // query: { calendarId, timeMin, timeMax, id } — `id` names the request in the log
    function events(query) {
        return Fetch.request(root._ENDPOINT_EVENTS, {
            method: "GET",
            headers: _headers(false),
            params: [query.calendarId],
            query: {
                timeMin: query.timeMin,
                timeMax: query.timeMax,
                singleEvents: true,
                orderBy: 'startTime',
                maxResults: 2500
            },
            id: query.id
        });
    }

    // body: the event as JSON text (GoogleCalendarData.eventBody)
    function createEvent(calendarId, body) {
        return Fetch.request(root._ENDPOINT_EVENTS, {
            method: "POST",
            headers: _headers(true),
            params: [calendarId],
            body: body
        });
    }

    // Changes only the fields `body` has
    function updateEvent(calendarId, eventId, body) {
        return Fetch.request(root._ENDPOINT_EVENT, {
            method: "PATCH",
            headers: _headers(true),
            params: [calendarId, eventId],
            body: body
        });
    }

    function getEvent(calendarId, eventId) {
        return Fetch.request(root._ENDPOINT_EVENT, {
            method: "GET",
            headers: _headers(false),
            params: [calendarId, eventId]
        });
    }

    function deleteEvent(calendarId, eventId) {
        return Fetch.request(root._ENDPOINT_EVENT, {
            method: "DELETE",
            headers: _headers(false),
            params: [calendarId, eventId]
        });
    }

    // Google's palette of event and calendar colours, by colour id
    function colors() {
        return Fetch.request(root._ENDPOINT_COLORS, {
            method: "GET",
            headers: _headers(false)
        });
    }

    // The calendars on the account's list
    function calendars() {
        return Fetch.request(root._ENDPOINT_CALENDARS, {
            method: "GET",
            headers: _headers(false)
        });
    }
}
