pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.components
import qs.singletons
import qs.singletons.googlecalendar

// The calendar store: the account's calendars, their colours and the events of the
// months asked for, fetched through GoogleCalendarApi and turned into the panels' shapes by
// GoogleCalendarData; adding, changing and deleting events, each followed by a refetch of
// its month. Signing in is GoogleCalendarAuth's.
Singleton {
    id: root

    readonly property bool isAuthorized: Config.gcal.refreshToken !== ""
    // The "gcal.enabled" profile setting — off, e.g. in Power save, the calendar fetches
    // nothing, so it refreshes no tokens either, and shows no events
    readonly property bool enabled: Profiles.value("gcal.enabled") ?? true
    // Signed in and switched on: whether to fetch, and whether the panel offers editing
    readonly property bool available: isAuthorized && enabled

    // What went wrong with the last load, for the panel to show with a retry; "" when the
    // last load worked. A failed load otherwise looked like a month without events.
    property string error: ""

    property var events: ({})
    property var eventsByCalendar: ({})
    property var eventsLoading: ({})
    property var calendars: ({})

    property bool _initialized: false
    property var _initializatingPromise: null

    // Google's event colours by colour id, for the event form's swatches
    property var eventColors: ({})
    property var _fetchedMonths: ({})

    property var enabledCalendarIds: Config.gcal.enabledCalendarIds

    property var calendarsArray: Object.values(calendars)

    Logger {
        id: logger
        enabled: Profiles.value("gcal.debug") ?? false
        prefix: "[GoogleCalendar API]"
    }

    // Switched off: drop what was fetched, so nothing stale shows. Back on: initialise
    // again; an open calendar panel fetches its month when it sees `available` change.
    onAvailableChanged: {
        if (available) {
            initialize();
        } else {
            events = {};
            eventsByCalendar = {};
            eventsLoading = {};
            _fetchedMonths = {};
            error = "";
        }
    }

    Component.onCompleted: {
        if (!root.enabled) {
            logger.log("Initialization skipped: switched off by the active profile");
        } else if (GoogleCalendarAuth.isAuthorized) {
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
        root._initializatingPromise = Promises.allSettled(fetchColorMappings(), fetchAllCalendars()).then(results => {
            // allSettled never rejects, so reaching here says nothing about whether the
            // fetches worked. The calendar list is what every later fetch depends on, so
            // that is the condition: without it, stay uninitialised and retry next time
            // rather than reporting a readiness that is not there.
            root._initialized = Object.keys(root.calendars).length > 0;
            root._initializatingPromise = null;
            if (root._initialized) {
                logger.log("Initialised with", Object.keys(root.calendars).length, "calendars");
            } else {
                logger.warn("Initialisation did not produce any calendars — will retry");
                const failure = results[1]?.status === false ? results[1].reason : results[0]?.reason;
                root.error = "Could not load your calendars: "
                    + (failure !== undefined ? GoogleCalendarData.describeFailure(failure) : "Google returned none");
            }
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
            if (!invalidateCache && Object.keys(root.eventColors).length > 0) {
                resolve();
                return;
            }
            // The callback must return the bare request: ensureAuthorized only sees a 401 if
            // the rejection reaches it, and a catch inside the callback would swallow it.
            GoogleCalendarAuth.ensureAuthorized(() => {
                return GoogleCalendarApi.colors();
            }).then(response => {
                return response.json();
            }).then(json => {
                const colors = json.event || {};
                root.eventColors = Object.keys(colors).reduce((result, key) => {
                    result[key] = colors[key].background;
                    return result;
                }, {});
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
                return GoogleCalendarApi.calendars();
            }).then(result => {
                return result.json();
            }).then(json => {
                logger.log("Calendar json received");
                let cals = {};
                json.items.forEach((element, index) => {
                    let item = GoogleCalendarData.calendar(json.items[index]);
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
            if (!root.available || Object.keys(root.calendars).length === 0)
                return resolve(null);

            let calendar = root.calendars[calendarId] ?? null;
            let tz = GoogleCalendarData.localOffset();
            let firstDay = CalendarDates.dateKey(year, month, 1);
            let lastDay  = CalendarDates.dateKey(year, month, new Date(year, month + 1, 0).getDate());

            // Pre-initialise per-day buckets so stale events are cleared on invalidate
            let daysInMonth = new Date(year, month + 1, 0).getDate();
            for (let d = 1; d <= daysInMonth; d++) {
                let dayKey = CalendarDates.dateKey(year, month, d);
                if (!root.eventsByCalendar[dayKey]) root.eventsByCalendar[dayKey] = {};
                root.eventsByCalendar[dayKey][calendarId] = [];
            }

            return GoogleCalendarAuth.ensureAuthorized(() => {
                return GoogleCalendarApi.events({
                    calendarId: calendarId,
                    timeMin: firstDay + "T00:00:00" + tz,
                    timeMax: lastDay  + "T23:59:59" + tz,
                    id: CalendarDates.monthKey(year, month) + "_" + calendarId
                });
            }).then(response => {
                return response.json().then(data => {
                    for (let item of (data.items || [])) {
                        let prepared = GoogleCalendarData.event(item, calendar, root.eventColors, Theme.accentDark);
                        let dayKeys  = CalendarDates.eventDayKeys(item, year, month);
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
        if (!root.available) return;
        if (month > 11 || month < 0) {
            logger.error("Requested incorrect month: ", year, month);
            return;
        }

        let monthKey = CalendarDates.monthKey(year, month);
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
            }).then(results => {
                // Calendars that loaded still show; the others are reported
                const failed = (results ?? []).filter(result => result.status === false);
                root.error = failed.length === 0 ? ""
                    : "Could not load events from " + failed.length + " of " + results.length
                      + " calendars: " + GoogleCalendarData.describeFailure(failed[0].reason);
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
                root.error = "Could not load events: " + GoogleCalendarData.describeFailure(e);
                logger.error("fetchMonthEvents failed: ", e);
                logger.error("Stack: ", e?.stack);
            });
        };

        if (root._initialized) {
            exec();
        } else {
            // A failed initialisation has set the error already; going on would fetch the
            // calendar list a second time, through getEnabledCalendarIds
            initialize().then(() => {
                if (root._initialized)
                    exec();
                else
                    setDayLoading(monthKey, false);
            });
        }
    }

    // month is 0-indexed (same as fetchMonthEvents)
    // event: { year, month, day, title, description, startTime, endTime, calendarId }
    function createEvent(event) {
        const calendarId = event.calendarId || "primary";
        const body = _eventBody(event);
        GoogleCalendarAuth.ensureAuthorized(() => {
            return GoogleCalendarApi.createEvent(calendarId, body);
        }).then(() => {
            fetchMonthEvents(event.year, event.month, true);
        }).catch(e => {
            logger.error("createEvent failed:", e);
        });
    }

    // event: { year, month, day, eventId, calendarId, title, description, startTime, endTime }
    function updateEvent(event) {
        const calendarId = event.calendarId || "primary";
        const body = _eventBody(event);
        GoogleCalendarAuth.ensureAuthorized(() => {
            return GoogleCalendarApi.updateEvent(calendarId, event.eventId, body);
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
            return GoogleCalendarApi.getEvent(calendarId, event.recurringEventId).then(response => response.json()).then(masterData => {
                const newRecurrence = GoogleCalendarData.recurrenceEndingBefore(masterData.recurrence || [], event.year, event.month, event.day);
                if (newRecurrence === null)
                    return;
                logger.log("Changing event recurrence", newRecurrence);
                return GoogleCalendarApi.updateEvent(calendarId, event.recurringEventId, JSON.stringify({
                    recurrence: newRecurrence
                }));
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
            return GoogleCalendarApi.deleteEvent(calendarId, event.eventId);
        }).then(() => {
            fetchMonthEvents(event.year, event.month, true);
        }).catch(e => {
            logger.error("deleteEvent failed:", e);
        });
    }

    // The event as JSON text for Google, in the local time zone
    function _eventBody(event) {
        const body = JSON.stringify(GoogleCalendarData.eventBody(event, GoogleCalendarData.localOffset()));
        logger.log("Event data", body);
        return body;
    }

    function _mergeEvents(year, month, day) {
        let dateKey = CalendarDates.dateKey(year, month, day);
        root.events[dateKey] = [];
        let result = [];
        for (const calendarId in root.eventsByCalendar[dateKey]) {
            const events = root.eventsByCalendar[dateKey][calendarId];
            for (const event of events) {
                result.push(event);
            }
        }
        result.sort(GoogleCalendarData.compareEvents);
        root.events[dateKey] = result;
        root.eventsChanged();
        logger.log("Sorting done, found events:", result.length);
    }

    function setDayLoading(day, state) {
        root.eventsLoading[day] = state;
        root.eventsLoadingChanged();
    }
}
