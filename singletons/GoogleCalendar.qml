pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons

Singleton {
    id: root

    // ── Public state ────────────────────────────────────────────────────
    readonly property bool isAuthorized: Config.gcal.refreshToken !== ""
    property bool isBusy: false

    // ── Internal reactive maps (reassigned on update for QML binding) ───
    property var _cache: ({})       // "YYYY-MM-DD" → merged event array
    property var _loading: ({})     // "YYYY-MM-DD" → int (count of in-flight XHRs)
    property var _rawCache: ({})    // "YYYY-MM-DD" → { calId: [events] }
    property var _calendars: []     // [{id, name, color}] — fetched from calendarList API

    // Reactive array of enabled calendar IDs (parsed from Config)
    property var enabledCalendarIds: {
        try { return JSON.parse(Config.gcal.enabledCalendarIds); } catch (e) { return []; }
    }

    property string _authBuf: ""

    // ── colorId → background hex (populated from /colors API) ───────────
    property var _colorMap: ({})

    // ── OAuth process ───────────────────────────────────────────────────
    Process {
        id: _authProcess
        command: ["python3", Quickshell.shellDir + "/scripts/google_auth.py", Config.gcal.clientId, Config.gcal.clientSecret]
        stdout: SplitParser {
            splitMarker: ""
            onRead: function (data) {
                root._authBuf += data;
            }
        }
        onRunningChanged: {
            if (!running) {
                root.isBusy = false;
                root._handleAuthResult();
            }
        }
    }

    // Fetch colors and calendar list on startup (if already authorized)
    Component.onCompleted: {
        if (isAuthorized) {
            _ensureToken(function () {
                _fetchColors();
                _fetchCalendars();
            });
        }
    }

    // ── Public functions ────────────────────────────────────────────────

    function login() {
        if (isBusy)
            return;
        _authBuf = "";
        isBusy = true;
        _authProcess.running = true;
    }

    function logout() {
        Config.gcal.accessToken = "";
        Config.gcal.refreshToken = "";
        Config.gcal.tokenExpiry = 0;
        _cache = {};
        _loading = {};
        _rawCache = {};
        _calendars = [];
    }

    function eventsForDate(year, month, day) {
        return _cache[_dateKey(year, month, day)] || [];
    }

    function isLoadingDate(year, month, day) {
        return !!_loading[_dateKey(year, month, day)];
    }

    function fetchCalendars() {
        _ensureToken(function () {
            _fetchCalendars();
        });
    }

    function isCalendarEnabled(calId) {
        return _getEnabledIds().indexOf(calId) !== -1;
    }

    function setCalendarEnabled(calId, enabled) {
        var ids = _getEnabledIds();
        var idx = ids.indexOf(calId);
        if (enabled && idx === -1) {
            ids.push(calId);
        } else if (!enabled && idx !== -1) {
            ids.splice(idx, 1);
        } else {
            return;
        }
        _setEnabledIds(ids);
        _recomputeAllMerges();
    }

    function fetchEventsForDate(year, month, day) {
        if (!isAuthorized || day <= 0)
            return;
        var key = _dateKey(year, month, day);
        var ids = _getEnabledIds();
        if (ids.length === 0)
            return;

        // Find which calendars still need fetching for this date
        var toFetch = [];
        for (var i = 0; i < ids.length; i++) {
            var calId = ids[i];
            if (!_rawCache[key] || _rawCache[key][calId] === undefined)
                toFetch.push(calId);
        }

        if (toFetch.length === 0)
            return;

        // Increment loading count for each calendar to fetch
        var nl = Object.assign({}, _loading);
        nl[key] = (nl[key] || 0) + toFetch.length;
        _loading = nl;

        _ensureToken(function () {
            for (var j = 0; j < toFetch.length; j++) {
                _fetchCalendarEvents(key, year, month, day, toFetch[j], false);
            }
        });
    }

    function invalidateAndRefetch(year, month, day) {
        if (!isAuthorized)
            return;
        var key = _dateKey(year, month, day);

        // Clear rawCache for this key
        var nr = Object.assign({}, _rawCache);
        delete nr[key];
        _rawCache = nr;

        // Clear loading and cache
        var nl = Object.assign({}, _loading);
        delete nl[key];
        _loading = nl;
        var nc = Object.assign({}, _cache);
        delete nc[key];
        _cache = nc;

        // Refetch
        fetchEventsForDate(year, month, day);
    }

    // ── Internal helpers ────────────────────────────────────────────────

    function _dateKey(year, month, day) {
        // month is 0-indexed; returns "YYYY-MM-DD"
        var m = ("0" + (month + 1)).slice(-2);
        var d = ("0" + day).slice(-2);
        return year + "-" + m + "-" + d;
    }

    function _getEnabledIds() {
        try {
            return JSON.parse(Config.gcal.enabledCalendarIds) || [];
        } catch (e) {
            return [];
        }
    }

    function _setEnabledIds(arr) {
        Config.gcal.enabledCalendarIds = JSON.stringify(arr);
    }

    function _mergeCalendars(key) {
        var ids = _getEnabledIds();
        var merged = [];
        if (_rawCache[key]) {
            for (var i = 0; i < ids.length; i++) {
                var calEvents = _rawCache[key][ids[i]];
                if (calEvents)
                    merged = merged.concat(calEvents);
            }
        }
        // Sort: all-day first, then by start time string ascending
        merged.sort(function (a, b) {
            var aAllDay = a.time === "All day";
            var bAllDay = b.time === "All day";
            if (aAllDay && !bAllDay) return -1;
            if (!aAllDay && bAllDay) return 1;
            if (!aAllDay && !bAllDay) return a.time.localeCompare(b.time);
            return 0;
        });
        var nc = Object.assign({}, _cache);
        nc[key] = merged;
        _cache = nc;
    }

    function _recomputeAllMerges() {
        var keys = Object.keys(_rawCache);
        for (var i = 0; i < keys.length; i++) {
            _mergeCalendars(keys[i]);
        }
    }

    function _fetchColors() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://www.googleapis.com/calendar/v3/colors");
        xhr.setRequestHeader("Authorization", "Bearer " + Config.gcal.accessToken);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText);
                var eventColors = data.event || {};
                var map = {};
                for (var id in eventColors) {
                    map[id] = eventColors[id].background;
                }
                _colorMap = map;
            } else {
                console.warn("GoogleCalendar: failed to fetch colors:", xhr.status);
            }
        };
        xhr.send();
    }

    function _fetchCalendars() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://www.googleapis.com/calendar/v3/users/me/calendarList");
        xhr.setRequestHeader("Authorization", "Bearer " + Config.gcal.accessToken);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText);
                var items = data.items || [];
                var cals = items.map(function (item) {
                    return {
                        id: item.id,
                        name: item.summary || item.id,
                        color: item.backgroundColor || "#5b9bf5"
                    };
                });
                _calendars = cals;
                // Auto-enable all calendars on first login (when list is still empty)
                var currentEnabled = _getEnabledIds();
                if (currentEnabled.length === 0) {
                    var allIds = cals.map(function (c) { return c.id; });
                    _setEnabledIds(allIds);
                }
            } else {
                console.warn("GoogleCalendar: failed to fetch calendar list:", xhr.status);
            }
        };
        xhr.send();
    }

    function _ensureToken(callback) {
        var now = Date.now() / 1000;
        if (Config.gcal.tokenExpiry - now < 300) {
            _refreshToken(callback);
        } else {
            callback();
        }
    }

    function _refreshToken(callback) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "https://oauth2.googleapis.com/token");
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                var resp = JSON.parse(xhr.responseText);
                Config.gcal.accessToken = resp.access_token;
                Config.gcal.tokenExpiry = Math.floor(Date.now() / 1000) + (resp.expires_in || 3600);
                if (callback)
                    callback();
            } else {
                console.warn("GoogleCalendar: token refresh failed:", xhr.status, xhr.responseText);
            }
        };
        var body = "grant_type=refresh_token" + "&refresh_token=" + encodeURIComponent(Config.gcal.refreshToken) + "&client_id=" + encodeURIComponent(Config.gcal.clientId) + "&client_secret=" + encodeURIComponent(Config.gcal.clientSecret);
        xhr.send(body);
    }

    function _fetchCalendarEvents(key, year, month, day, calId, retried) {
        var timeMin = encodeURIComponent(key + "T00:00:00Z");
        var timeMax = encodeURIComponent(key + "T23:59:59Z");
        var url = "https://www.googleapis.com/calendar/v3/calendars/" + encodeURIComponent(calId) + "/events"
                + "?timeMin=" + timeMin + "&timeMax=" + timeMax + "&singleEvents=true" + "&orderBy=startTime";

        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Authorization", "Bearer " + Config.gcal.accessToken);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;

            if (xhr.status === 200) {
                var data = JSON.parse(xhr.responseText);
                var items = data.items || [];
                var events = items.map(function (item) {
                    var timeStr = "All day";
                    if (item.start && item.start.dateTime) {
                        var dt = new Date(item.start.dateTime);
                        timeStr = ("0" + dt.getHours()).slice(-2) + ":" + ("0" + dt.getMinutes()).slice(-2);
                        dt = new Date(item.end.dateTime);
                        timeStr += " - " + ("0" + dt.getHours()).slice(-2) + ":" + ("0" + dt.getMinutes()).slice(-2);
                    }
                    var color = root._colorMap[item.colorId] || "#5b9bf5";
                    return {
                        title: item.summary || "(No title)",
                        description: item.description,
                        eventType: item.eventType,
                        time: timeStr,
                        color: color
                    };
                });

                // Update rawCache
                var nr = Object.assign({}, _rawCache);
                if (!nr[key]) nr[key] = {};
                nr[key] = Object.assign({}, nr[key]);
                nr[key][calId] = events;
                _rawCache = nr;

                // Decrement loading count
                var nl = Object.assign({}, _loading);
                nl[key] = Math.max(0, (nl[key] || 0) - 1);
                if (nl[key] === 0) delete nl[key];
                _loading = nl;

                // Merge all enabled calendars for this date
                _mergeCalendars(key);

            } else if (xhr.status === 401 && !retried) {
                // Token expired — refresh once and retry (don't decrement loading yet)
                _refreshToken(function () {
                    _fetchCalendarEvents(key, year, month, day, calId, true);
                });
            } else {
                console.warn("GoogleCalendar: fetch failed for", calId, ":", xhr.status);

                // Store empty so we don't keep retrying
                var nr2 = Object.assign({}, _rawCache);
                if (!nr2[key]) nr2[key] = {};
                nr2[key] = Object.assign({}, nr2[key]);
                nr2[key][calId] = [];
                _rawCache = nr2;

                // Decrement loading count
                var nl2 = Object.assign({}, _loading);
                nl2[key] = Math.max(0, (nl2[key] || 0) - 1);
                if (nl2[key] === 0) delete nl2[key];
                _loading = nl2;

                // Merge
                _mergeCalendars(key);
            }
        };
        xhr.send();
    }

    function _handleAuthResult() {
        try {
            var result = JSON.parse(_authBuf.trim());
            Config.gcal.accessToken = result.access_token || "";
            Config.gcal.refreshToken = result.refresh_token || "";
            Config.gcal.tokenExpiry = result.expiry || 0;
            if (Config.gcal.accessToken) {
                _fetchColors();
                _fetchCalendars();
            }
        } catch (e) {
            console.warn("GoogleCalendar: failed to parse auth result:", e, _authBuf);
        }
    }
}
