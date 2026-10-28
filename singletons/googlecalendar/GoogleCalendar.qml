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
    property var _fetchedMonths: ({})

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
            // allSettled never rejects, so reaching here says nothing about whether the
            // fetches worked. The calendar list is what every later fetch depends on, so
            // that is the condition: without it, stay uninitialised and retry next time
            // rather than reporting a readiness that is not there.
            root._initialized = Object.keys(root.calendars).length > 0;
            root._initializatingPromise = null;
            if (root._initialized)
                logger.log("Initialised with", Object.keys(root.calendars).length, "calendars");
            else
                logger.warn("Initialisation did not produce any calendars — will retry");
        });
        return root._initializatingPromise;
    }

    function getEnabledCalendarIds() {
        return Promises.create((resolve, reject) => {
            try {
                if (Object.keys(calendars).length === 0) {
                    // Without the catch a failed calendar fetch left this promise pending
                    // forever, which is what hung every caller waiting on it.
                    fetchAllCalendars().then(() => {
                        resolve(_getConfigEnabledCalendarIds());
                    }).catch(reject);
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
            // The callback must return the bare request: ensureAuthorized only sees a 401 if
            // the rejection reaches it, and a catch inside the callback would swallow it.
            GoogleCalendarAuth.ensureAuthorized(() => {
                return _requestColors();
            }).then(response => {
                return response.json();
            }).then(json => {
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
        });
    }

    function fetchAllCalendars(invalidateCache = false) {
        return Promises.create((resolve, reject) => {
            if (!invalidateCache && Object.keys(root.calendars).length > 0) {
                return resolve();
            }
            // Bare request in the callback, for the same reason as in fetchColorMappings
            return GoogleCalendarAuth.ensureAuthorized(() => {
                return _requestCalendars();
            }).then(result => {
                return result.json();
            }).then(json => {
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
        });
    }

    function _fetchCalendarEventsForMonth(calendarId, year, month) {
        return Promises.create((resolve, reject) => {
            if (!GoogleCalendarAuth.isAuthorized || Object.keys(root.calendars).length === 0)
                return resolve(null);

            let calendar = root.calendars[calendarId] ?? null;
            let tz = _tzOffset();
            let firstDay = _dateKey(year, month, 1);
            let lastDay  = _dateKey(year, month, new Date(year, month + 1, 0).getDate());

            // Pre-initialise per-day buckets so stale events are cleared on invalidate
            let daysInMonth = new Date(year, month + 1, 0).getDate();
            for (let d = 1; d <= daysInMonth; d++) {
                let dayKey = _dateKey(year, month, d);
                if (!root.eventsByCalendar[dayKey]) root.eventsByCalendar[dayKey] = {};
                root.eventsByCalendar[dayKey][calendarId] = [];
            }

            return GoogleCalendarAuth.ensureAuthorized(() => {
                return Fetch.request(root._ENDPOINT_EVENTS, {
                    method: "GET",
                    headers: { "Authorization": "Bearer " + Config.gcal.accessToken },
                    params: [calendarId],
                    query: {
                        timeMin: firstDay + "T00:00:00" + tz,
                        timeMax: lastDay  + "T23:59:59" + tz,
                        singleEvents: true,
                        orderBy: 'startTime',
                        maxResults: 2500
                    },
                    id: _monthKey(year, month) + "_" + calendarId
                });
            }).then(response => {
                return response.json().then(data => {
                    for (let item of (data.items || [])) {
                        let prepared = _prepareEventData(item, calendar);
                        let dayKeys  = _getEventDayKeys(item, year, month);
                        for (let dayKey of dayKeys) {
                            if (!root.eventsByCalendar[dayKey])
                                root.eventsByCalendar[dayKey] = {};
                            if (!root.eventsByCalendar[dayKey][calendarId])
                                root.eventsByCalendar[dayKey][calendarId] = [];
                            root.eventsByCalendar[dayKey][calendarId].push(prepared);
                        }
                    }
                    return resolve();
                }).catch(reject);
            }).catch(reject);
        });
    }

    function fetchMonthEvents(year, month, invalidateCache = false) {
        if (!GoogleCalendarAuth.isAuthorized) return;
        if (month > 11 || month < 0) {
            logger.error("Requested incorrect month: ", year, month);
            return;
        }

        let monthKey = _monthKey(year, month);
        if (!invalidateCache && root._fetchedMonths[monthKey]) return;

        delete root._fetchedMonths[monthKey];
        setDayLoading(monthKey, true);
        logger.log("Fetching month: ", monthKey);

        let exec = function () {
            // Chained rather than awaited: the enabled-calendar list may need a fetch of
            // its own, and blocking on it froze the whole shell, QML being single-threaded.
            return getEnabledCalendarIds().then(enabledCalendars => {
                let fetches = [];
                for (const id of (enabledCalendars ?? [])) {
                    fetches.push(_fetchCalendarEventsForMonth(id, year, month));
                }
                return Promises.allSettled(fetches);
            }).then(() => {
                let daysInMonth = new Date(year, month + 1, 0).getDate();
                for (let d = 1; d <= daysInMonth; d++)
                    _mergeEvents(year, month, d);
                root._fetchedMonths[monthKey] = true;
                setDayLoading(monthKey, false);
                logger.log("Month fetch complete: ", monthKey);
            }).catch(e => {
                // The chain can now reject for real, so the loading flag has to be cleared
                // here too — otherwise EventsPanel shows its spinner forever.
                setDayLoading(monthKey, false);
                logger.error("fetchMonthEvents failed: ", e);
                logger.error("Stack: ", e?.stack);
            });
        };

        if (root._initialized) {
            exec();
        } else {
            initialize().then(() => exec());
        }
    }

    function _prepareEventData(data, calendar) {
        let timeStr = "All day";
        let startTimeStr = "";
        let endTimeStr = "";
        let color = data.colorId ? (root._colorMapEvents[data.colorId] || Theme.cellAccent) : calendar.color;
        let calendarColor = calendar ? (calendar?.primary ? null : calendar.color) : null;

        let startTime = null;
        let allDayDuration = 0;
        let allDayStartDate = null;
        let allDayEndDate = null;

        if (data.start && data.start.dateTime) {
            startTime = new Date(data.start.dateTime);
            startTimeStr = ("0" + startTime.getHours()).slice(-2) + ":" + ("0" + startTime.getMinutes()).slice(-2);
            let dt = new Date(data.end.dateTime);
            endTimeStr = ("0" + dt.getHours()).slice(-2) + ":" + ("0" + dt.getMinutes()).slice(-2);
            timeStr = startTimeStr + " - " + endTimeStr;
        } else if (data.start && data.start.date) {
            let sp = data.start.date.split("-");
            let ep = data.end.date.split("-");
            allDayStartDate = new Date(parseInt(sp[0]), parseInt(sp[1]) - 1, parseInt(sp[2]));
            let endExclusive = new Date(parseInt(ep[0]), parseInt(ep[1]) - 1, parseInt(ep[2]));
            // Same zero-length case as in _getEventDayKeys: treat end == start as one day
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
            startTimeStr: startTimeStr,
            endTimeStr: endTimeStr,
            time: timeStr,
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

    function _prepareCalendarData(item) {
        return {
            id: item.id,
            name: item.summary || item.id,
            color: item.backgroundColor || "#5b9bf5",
            primary: item.primary
        };
    }

    // month is 0-indexed (same as fetchMonthEvents)
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
            fetchMonthEvents(event.year, event.month, true);
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
            fetchMonthEvents(event.year, event.month, true);
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
            }).then(response => response.json()).then(masterData => {
                const recurrence = masterData.recurrence || [];
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
            fetchMonthEvents(event.year, event.month, true);
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
            fetchMonthEvents(event.year, event.month, true);
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
            // Google's all-day end date is exclusive. Sending the start date again creates
            // a zero-length event that the phone still shows but _getEventDayKeys drops.
            const nextDay = new Date(data.year, data.month, data.day + 1);
            body.start.date = dateStr;
            body.end.date = _dateKey(nextDay.getFullYear(), nextDay.getMonth(), nextDay.getDate());
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

    function _monthKey(year: int, month: int): string {
        // month is 0-indexed; returns "YYYY-MM"
        return year + "-" + ("0" + (month + 1)).slice(-2);
    }

    // Returns all "YYYY-MM-DD" keys within [year, month] that rawItem covers.
    // Handles timed events, all-day events, and multi-day spans. Clamps to the
    // given month so callers don't receive keys outside the fetched range.
    function _getEventDayKeys(rawItem, year, month) {
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
            dayKeys.push(_dateKey(current.getFullYear(), current.getMonth(), current.getDate()));
            current.setDate(current.getDate() + 1);
        }
        return dayKeys;
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
