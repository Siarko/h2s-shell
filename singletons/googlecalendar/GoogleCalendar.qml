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

    property var _enabledCalendarIds: {
        try {
            return JSON.parse(Config.gcal.enabledCalendarIds);
        } catch (e) {
            return [];
        }
    }

    function init() {
        logger.log("Init");
    }

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
                if (calendars.length == 0) {
                    fetchAllCalendars();
                } else {
                    resolve();
                }
                return _getConfigEnabledCalendarIds();
            } catch (e) {
                reject(e);
            }
        });
    }

    function _getConfigEnabledCalendarIds() {
        return JSON.parse(Config.gcal.enabledCalendarIds) || [];
    }

    function setEnabledCalendarIds(idArray) {
        Config.gcal.enabledCalendarIds = JSON.stringify(idArray);
    }

    function fetchColorMappings(invalidateCache = false) {
        return Promises.create((resolve, reject) => {
            if (!invalidateCache && root._colorMapEvents.length === 0) {
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
            if (!invalidateCache && root.calendars.length === 0) {
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
                        console.log(root.calendars.length);
                        root.calendars = cals;
                        if (_getConfigEnabledCalendarIds().length === 0) {
                            let allIds = cals.map(c => c.id);
                            setEnabledCalendarIds(allIds);
                        }
                        return resolve();
                    }).catch(reject);
                }).catch(reject);
            }).catch(reject);
        });
    }

    function fetchDayEvents(year, month, day, invalidateCache = false) {
        if (month > 12 || month < 1 || day < 1) {
            logger.error("Requested incorrect day: ", year, month, day);
            return;
        }
        const dateKey = _dateKey(year, month, day);
        const cachedEvents = root.events[dateKey];

        if (!invalidateCache && cachedEvents !== undefined) {
            return;
        }
        logger.log("Events for ", dateKey, " len: ", cachedEvents?.length);

        let exec = function () {
            logger.log("Entered exec of event fetching");
            let fetches = [];
            for (const [key, data] of Object.entries(root.calendars)) {
                logger.log("Fetching events for calendar", data.id, "Date: ", year, month, day);
                fetches.push(fetchCalendarEvents(data.id, year, month, day));
            }
            return Promises.allSettled(fetches).then(() => {
                logger.log("All calendars fetched, merging events");
                _mergeEvents(year, month, day);
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
            if (!GoogleCalendarAuth.isAuthorized || day <= 0 || root.calendars.length === 0) {
                return resolve(null);
            }
            let dateKey = _dateKey(year, month, day);
            let requestId = dateKey + "_" + calendarId;

            logger.log("Requesting events for calendar: ", calendarId, " Date: ", dateKey);
            let calendar = root.calendars[calendarId] ?? null;
            return GoogleCalendarAuth.ensureAuthorized(() => {
                return _requestEvents({
                    calendarId: calendarId,
                    timeMin: dateKey + "T00:00:00Z",
                    timeMax: dateKey + "T23:59:59Z",
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
        let color = data.colorId ? (root._colorMapEvents[data.colorId] || Theme.cellAccent) : calendar.color;
        let calendarColor = calendar ? (calendar?.primary ? null : calendar.color) : null;

        let startTime = null;
        if (data.start && data.start.dateTime) {
            startTime = new Date(data.start.dateTime);
            timeStr = ("0" + startTime.getHours()).slice(-2) + ":" + ("0" + startTime.getMinutes()).slice(-2);
            let dt = new Date(data.end.dateTime);
            timeStr += " - " + ("0" + dt.getHours()).slice(-2) + ":" + ("0" + dt.getMinutes()).slice(-2);
        }
        return {
            title: data.summary || "(No title)",
            description: data.description,
            eventType: data.eventType,
            startTime: startTime,
            time: timeStr,
            color: color,
            calendarColor: calendarColor ?? null
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
            return (a.startTime === null || a.startTime > b.startTime) ? 1 : -1;
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
}
