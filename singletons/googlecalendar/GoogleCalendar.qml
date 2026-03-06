pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.components
import qs.singletons
import qs.singletons.network
import qs.singletons.googlecalendar

Singleton {
    id: root

    readonly property string _ENDPOINT_COLORS: "https://www.googleapis.com/calendar/v3/colors"
    readonly property string _ENDPOINT_CALENDARS: "https://www.googleapis.com/calendar/v3/users/me/calendarList"
    readonly property string _ENDPOINT_EVENTS: "https://www.googleapis.com/calendar/v3/calendars/{0}/events"
    readonly property string _ENDPOINT_EVENT: "https://www.googleapis.com/calendar/v3/calendars/{0}/events/{1}"

    readonly property bool isAuthorized: Config.gcal.refreshToken !== ""

    property var events: ({})
    property var eventsByCalendar: ({})
    property var eventsLoading: ({})
    property var calendars: ({})

    property bool _initialized: false
    property var _initializatingPromise: null

    property var _colorMapEvents: ({})
    property var _colorMapCalendars: ({})
    property var _busyRequests: ({})

    property var enabledCalendarIds: Config.gcal.enabledCalendarIds

    property var calendarsArray: Object.values(calendars)

    Logger {
        id: logger
        enabled: Config.gcal.debug
        prefix: "[GoogleCalendar API]"
    }

    Component.onCompleted: {
        if (GoogleCalendarAuth.isAuthorized) {
            logger.log("Initialization start");
            initialize().then(() => {
                logger.log("✔ Initialization done");
            }).catch(e => {
                logger.error("❌ Initialization error: ", e);
                logger.error("CallStack: \n", e.stack);
            });
        } else {
            logger.warn("🔒 Initialization aborted: Unauthorized");
        }
    }

    function initialize() {
        if (root._initialized) {
            return Promises.resolved();
        }
        if (root._initializatingPromise) {
            return root._initializatingPromise;
        }
        root._initializatingPromise = Promises.allSettled(fetchColorMappings(), fetchAllCalendars()).then(() => {
            root._initialized = true;
            root._initializatingPromise = null;
            logger.log("Setting initialized to true");
        });
        return root._initializatingPromise;
    }

    function getEnabledCalendarIds() {
        return Promises.create((resolve, reject) => {
            try {
                if (Object.keys(calendars).length === 0) {
                    fetchAllCalendars().then(() => {
                        resolve(_getConfigEnabledCalendarIds());
                    });
                } else {
                    resolve(_getConfigEnabledCalendarIds());
                }
            } catch (e) {
                reject(e);
            }
        });
    }

    function _getConfigEnabledCalendarIds() {
        return Config.gcal.enabledCalendarIds;
    }

    function setEnabledCalendarIds(idArray) {
        Config.gcal.enabledCalendarIds = idArray;
    }

    function setCalendarEnabled(id, enabled) {
        let ids = enabledCalendarIds.slice();
        let idx = ids.indexOf(id);
        if (enabled && idx === -1) {
            ids.push(id);
        } else if (!enabled && idx !== -1) {
            ids.splice(idx, 1);
        }
        setEnabledCalendarIds(ids);
    }

    function fetchColorMappings(invalidateCache = false) {
        return Promises.create((resolve, reject) => {
            if (!invalidateCache && Object.keys(root._colorMapEvents).length > 0) {
                resolve();
                return;
            }
            GoogleCalendarAuth.ensureAuthorized(() => {
                return _requestColors().then(response => {
                    return response.json().then(json => {
                        let mapBackgroundColor = objects => {
                            return Object.keys(objects).reduce((result, key) => {
                                result[key] = objects[key].background;
                                return result;
                            }, {});
                        };
                        _colorMapEvents = mapBackgroundColor(json.event || {});
                        _colorMapCalendars = mapBackgroundColor(json.calendar || {});
                        resolve();
                    }).catch(reject);
                }).catch(reject);
            }).catch(reject);
        });
    }

    function fetchAllCalendars(invalidateCache = false) {
        return Promises.create((resolve, reject) => {
            if (!invalidateCache && Object.keys(root.calendars).length > 0) {
                return resolve();
            }
            return GoogleCalendarAuth.ensureAuthorized(() => {
                return _requestCalendars().then(result => {
                    return result.json().then(json => {
                        logger.log("Calendar json received");
                        let cals = {};
                        json.items.forEach((element, index) => {
                            let item = _prepareCalendarData(json.items[index]);
                            cals[item.id] = item;
                        });
                        root.calendars = cals;
                        if (_getConfigEnabledCalendarIds().length === 0) {
                            let allIds = Object.values(cals).map(c => c.id);
                            setEnabledCalendarIds(allIds);
                        }
                        return resolve();
                    }).catch(reject);
                }).catch(reject);
            }).catch(reject);
        });
    }

    function fetchDayEvents(year, month, day, invalidateCache = false) {
        if (month > 11 || month < 0 || day < 1) {
            logger.error("Requested incorrect day: ", year, month, day);
            return;
        }
        const dateKey = _dateKey(year, month, day);
        const cachedEvents = root.events[dateKey];

        if (!invalidateCache && cachedEvents !== undefined) {
            return;
        }
        root.setDayLoading(dateKey, true);
        logger.log("Events for ", dateKey, " len: ", cachedEvents?.length);

        let exec = function () {
            logger.log("Entered exec of event fetching");
            let fetches = [];
            let enabledCalendars = Promises.await(getEnabledCalendarIds()).resolved ?? [];
            for (const id of enabledCalendars) {
                logger.log("Fetching events for calendar", id, "Date: ", year, month, day);
                fetches.push(fetchCalendarEvents(id, year, month, day));
            }
            return Promises.allSettled(fetches).then(() => {
                logger.log("All calendars fetched, merging events");
                _mergeEvents(year, month, day);
                root.setDayLoading(dateKey, false);
            }).catch(e => {
                logger.error("Caught error while fetching events: ", e);
                logger.error("Stack: ", e.stack);
            });
        };

        if (root._initialized) {
            logger.log("Already initialized, fetching");
            exec();
            return;
        } else {
            logger.log("Not initialized, running initialize first");
            return initialize().then(() => {
                logger.log("Initialized, now fetching events");
                exec();
            });
        }
    }

    function fetchCalendarEvents(calendarId: string, year, month, day) {
        return Promises.create((resolve, reject) => {
            logger.log("Entry to fetching events of calendar ", calendarId);
            if (!GoogleCalendarAuth.isAuthorized || day <= 0 || Object.keys(root.calendars).length === 0) {
                return resolve(null);
            }
            let dateKey = _dateKey(year, month, day);
            let requestId = dateKey + "_" + calendarId;

            logger.log("Requesting events for calendar: ", calendarId, " Date: ", dateKey);
            let calendar = root.calendars[calendarId] ?? null;
            let tz = _tzOffset();
            return GoogleCalendarAuth.ensureAuthorized(() => {
                return _requestEvents({
                    calendarId: calendarId,
                    timeMin: dateKey + "T00:00:00" + tz,
                    timeMax: dateKey + "T23:59:59" + tz,
                    id: dateKey + calendarId
                });
            }).then(response => {
                return response.json().then(data => {
                    let events = (data.items || []).map(item => _prepareEventData(item, calendar));
                    if (!root.eventsByCalendar[dateKey]) {
                        root.eventsByCalendar[dateKey] = {};
                    }
                    root.eventsByCalendar[dateKey][calendarId] = events;
                    return resolve();
                }).catch(reject);
            }).catch(reject);
        });
    }

    function _prepareEventData(data, calendar) {
        let timeStr = "All day";
        let startTimeStr = "";
        let endTimeStr = "";
        let color = data.colorId ? (root._colorMapEvents[data.colorId] || Theme.cellAccent) : calendar.color;
        let calendarColor = calendar ? (calendar?.primary ? null : calendar.color) : null;

        let startTime = null;
        if (data.start && data.start.dateTime) {
            startTime = new Date(data.start.dateTime);
            startTimeStr = ("0" + startTime.getHours()).slice(-2) + ":" + ("0" + startTime.getMinutes()).slice(-2);
            let dt = new Date(data.end.dateTime);
            endTimeStr = ("0" + dt.getHours()).slice(-2) + ":" + ("0" + dt.getMinutes()).slice(-2);
            timeStr = startTimeStr + " - " + endTimeStr;
        }
        return {
            id: data.id,
            title: data.summary || "(No title)",
            description: data.description,
            eventType: data.eventType,
            startTime: startTime,
            startTimeStr: startTimeStr,
            endTimeStr: endTimeStr,
            time: timeStr,
            color: color,
            calendarColor: calendarColor ?? null,
            calendarId: calendar?.id ?? null,
            colorId: data.colorId ?? null,
            rrule: (data.recurrence && data.recurrence.length > 0) ? data.recurrence[0] : null,
            recurringEventId: data.recurringEventId ?? null
        };
    }

    function _prepareCalendarData(item) {
        return {
            id: item.id,
            name: item.summary || item.id,
            color: item.backgroundColor || "#5b9bf5",
            primary: item.primary
        };
    }

    // month is 0-indexed (same as fetchDayEvents)
    // event: { year, month, day, title, description, startTime, endTime, calendarId }
    function createEvent(event) {
        const calendarId = event.calendarId || "primary";
        const body = _buildEventBody(event);
        GoogleCalendarAuth.ensureAuthorized(() => {
            return _requestCreateEvent({
                calendarId: calendarId,
                body: body
            });
        }).then(() => {
            fetchDayEvents(event.year, event.month, event.day, true);
        }).catch(e => {
            logger.error("createEvent failed:", e);
        });
    }

    // event: { year, month, day, eventId, calendarId, title, description, startTime, endTime }
    function updateEvent(event) {
        const calendarId = event.calendarId || "primary";
        const body = _buildEventBody(event);
        GoogleCalendarAuth.ensureAuthorized(() => {
            return _requestUpdateEvent({
                calendarId: calendarId,
                eventId: event.eventId,
                body: body
            });
        }).then(() => {
            fetchDayEvents(event.year, event.month, event.day, true);
        }).catch(e => {
            logger.error("updateEvent failed:", e);
        });
    }

    // event: { year, month, day, recurringEventId, calendarId }
    // Truncates the recurring series so it ends the day before the selected instance.
    function deleteFromEvent(event) {
        const calendarId = event.calendarId || "primary";
        GoogleCalendarAuth.ensureAuthorized(() => {
            return _requestGetEvent({
                calendarId: calendarId,
                eventId: event.recurringEventId
            }).then(response => {
                console.log(response.text());
                return response.json();
            }).then(masterData => {
                const recurrence = masterData.recurrence || [];
                console.log(masterData._isPromiseResult);
                const rruleIdx = recurrence.findIndex(r => r.startsWith("RRULE:"));
                if (rruleIdx === -1)
                    return;

                // UNTIL = day before the selected instance, in iCal format YYYYMMDD
                const dayBefore = new Date(event.year, event.month, event.day);
                dayBefore.setDate(dayBefore.getDate() - 1);
                const until = dayBefore.getFullYear().toString() + ("0" + (dayBefore.getMonth() + 1)).slice(-2) + ("0" + dayBefore.getDate()).slice(-2);

                let rrule = recurrence[rruleIdx].replace(/;UNTIL=[^;]*/g, "").replace(/;COUNT=[^;]*/g, "");
                rrule += ";UNTIL=" + until;

                const newRecurrence = recurrence.slice();
                newRecurrence[rruleIdx] = rrule;
                logger.log("Changing event recurrence", newRecurrence);

                return _requestUpdateEvent({
                    calendarId: calendarId,
                    eventId: event.recurringEventId,
                    body: JSON.stringify({
                        recurrence: newRecurrence
                    })
                });
            });
        }).then(() => {
            fetchDayEvents(event.year, event.month, event.day, true);
        }).catch(e => {
            logger.error("deleteFromEvent failed:", e);
        });
    }

    // event: { year, month, day, eventId, calendarId }
    function deleteEvent(event) {
        const calendarId = event.calendarId || "primary";
        GoogleCalendarAuth.ensureAuthorized(() => {
            return _requestDeleteEvent({
                calendarId: calendarId,
                eventId: event.eventId
            });
        }).then(() => {
            fetchDayEvents(event.year, event.month, event.day, true);
        }).catch(e => {
            logger.error("deleteEvent failed:", e);
        });
    }

    function _buildEventBody(data) {
        const dateStr = _dateKey(data.year, data.month, data.day);
        let body = {
            summary: data.title
        };
        if (data.description) {
            body.description = data.description;
        }
        if (data.colorId) {
            body.colorId = data.colorId;
        }
        if (data.rrule) {
            body.recurrence = [data.rrule];
        }

        body.start = {
            date: null,
            dateTime: null
        };
        body.end = {
            date: null,
            dateTime: null
        };
        if (data.startTime) {
            const tz = _tzOffset();
            body.start.dateTime = dateStr + "T" + data.startTime + ":00" + tz;
            body.end.dateTime = dateStr + "T" + (data.endTime || data.startTime) + ":00" + tz;
        } else {
            body.start.date = dateStr;
            body.end.date = dateStr;
        }
        body = JSON.stringify(body);
        logger.log("Event data", body);
        return body;
    }

    function _tzOffset(): string {
        let off = -(new Date().getTimezoneOffset());
        let sign = off >= 0 ? "+" : "-";
        let h = ("0" + Math.floor(Math.abs(off) / 60)).slice(-2);
        let m = ("0" + (Math.abs(off) % 60)).slice(-2);
        return sign + h + ":" + m;
    }

    function _dateKey(year: int, month: int, day: int): string {
        // month is 0-indexed; returns "YYYY-MM-DD"
        var m = ("0" + (month + 1)).slice(-2);
        var d = ("0" + day).slice(-2);
        return year + "-" + m + "-" + d;
    }

    function _mergeEvents(year, month, day) {
        let dateKey = _dateKey(year, month, day);
        root.events[dateKey] = [];
        let result = [];
        for (const calendarId in root.eventsByCalendar[dateKey]) {
            const events = root.eventsByCalendar[dateKey][calendarId];
            for (const event of events) {
                result.push(event);
            }
        }
        result.sort(function (a, b) {
            if (a.startTime === b.startTime)
                return 0;
            if (a.startTime === null)
                return -1;
            if (b.startTime === null)
                return 1;
            return a.startTime > b.startTime ? -1 : 1;
        });
        root.events[dateKey] = result;
        root.eventsChanged();
        logger.log("Sorting done, found events:", result.length);
    }

    function _requestEvents(data) {
        return Fetch.request(root._ENDPOINT_EVENTS, {
            method: "GET",
            headers: {
                "Authorization": "Bearer " + Config.gcal.accessToken
            },
            params: [data.calendarId],
            query: {
                timeMin: data.timeMin,
                timeMax: data.timeMax,
                singleEvents: true,
                orderBy: 'startTime'
            },
            id: data.id
        });
    }

    function _requestCreateEvent(data) {
        return Fetch.request(root._ENDPOINT_EVENTS, {
            method: "POST",
            headers: {
                "Authorization": "Bearer " + Config.gcal.accessToken,
                "Content-Type": "application/json"
            },
            params: [data.calendarId],
            body: data.body
        });
    }

    function _requestUpdateEvent(data) {
        return Fetch.request(root._ENDPOINT_EVENT, {
            method: "PATCH",
            headers: {
                "Authorization": "Bearer " + Config.gcal.accessToken,
                "Content-Type": "application/json"
            },
            params: [data.calendarId, data.eventId],
            body: data.body
        });
    }

    function _requestGetEvent(data) {
        return Fetch.request(root._ENDPOINT_EVENT, {
            method: "GET",
            headers: {
                "Authorization": "Bearer " + Config.gcal.accessToken
            },
            params: [data.calendarId, data.eventId]
        });
    }

    function _requestDeleteEvent(data) {
        return Fetch.request(root._ENDPOINT_EVENT, {
            method: "DELETE",
            headers: {
                "Authorization": "Bearer " + Config.gcal.accessToken
            },
            params: [data.calendarId, data.eventId]
        });
    }

    function _requestColors() {
        return Fetch.request(root._ENDPOINT_COLORS, {
            method: "GET",
            headers: {
                "Authorization": "Bearer " + Config.gcal.accessToken
            }
        });
    }

    function _requestCalendars() {
        return Fetch.request(root._ENDPOINT_CALENDARS, {
            method: "GET",
            headers: {
                "Authorization": "Bearer " + Config.gcal.accessToken
            }
        });
    }

    function setDayLoading(day, state) {
        root.eventsLoading[day] = state;
        root.eventsLoadingChanged();
    }
}
