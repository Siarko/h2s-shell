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
    property var _cache:   ({})   // "YYYY-MM-DD" → event array
    property var _loading: ({})   // "YYYY-MM-DD" → bool

    property string _authBuf: ""

    // ── colorId → background hex (populated from /colors API) ───────────
    property var _colorMap: ({})

    // ── OAuth process ───────────────────────────────────────────────────
    Process {
        id: _authProcess
        command: [
            "python3",
            Quickshell.shellDir + "/scripts/google_auth.py",
            Config.gcal.clientId,
            Config.gcal.clientSecret
        ]
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root._authBuf += data; }
        }
        onRunningChanged: {
            if (!running) {
                root.isBusy = false;
                root._handleAuthResult();
            }
        }
    }

    // Fetch event colors from API on startup (if already authorized)
    Component.onCompleted: {
        if (isAuthorized) {
            _ensureToken(function() { _fetchColors(); });
        }
    }

    // ── Public functions ────────────────────────────────────────────────

    function login() {
        if (isBusy) return;
        _authBuf = "";
        isBusy = true;
        _authProcess.running = true;
    }

    function logout() {
        Config.gcal.accessToken  = "";
        Config.gcal.refreshToken = "";
        Config.gcal.tokenExpiry  = 0;
        _cache   = {};
        _loading = {};
    }

    function eventsForDate(year, month, day) {
        return _cache[_dateKey(year, month, day)] || [];
    }

    function isLoadingDate(year, month, day) {
        return !!_loading[_dateKey(year, month, day)];
    }

    function fetchEventsForDate(year, month, day) {
        if (!isAuthorized || day <= 0) return;
        var key = _dateKey(year, month, day);
        if (_cache[key] !== undefined || _loading[key]) return;
        _ensureToken(function() { _fetchFromApi(key, year, month, day, false); });
    }

    function invalidateAndRefetch(year, month, day) {
        if (!isAuthorized) return;
        var key = _dateKey(year, month, day);
        // Clear both loading and cache for this key
        var nl = Object.assign({}, _loading);
        delete nl[key];
        _loading = nl;
        var nc = Object.assign({}, _cache);
        delete nc[key];
        _cache = nc;
        // Refetch
        _ensureToken(function() { _fetchFromApi(key, year, month, day, false); });
    }

    // ── Internal helpers ────────────────────────────────────────────────

    function _dateKey(year, month, day) {
        // month is 0-indexed; returns "YYYY-MM-DD"
        var m = ("0" + (month + 1)).slice(-2);
        var d = ("0"  + day).slice(-2);
        return year + "-" + m + "-" + d;
    }

    function _fetchColors() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://www.googleapis.com/calendar/v3/colors");
        xhr.setRequestHeader("Authorization", "Bearer " + Config.gcal.accessToken);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
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
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                var resp = JSON.parse(xhr.responseText);
                Config.gcal.accessToken  = resp.access_token;
                Config.gcal.tokenExpiry  = Math.floor(Date.now() / 1000) + (resp.expires_in || 3600);
                if (callback) callback();
            } else {
                console.warn("GoogleCalendar: token refresh failed:", xhr.status, xhr.responseText);
            }
        };
        var body = "grant_type=refresh_token"
            + "&refresh_token=" + encodeURIComponent(Config.gcal.refreshToken)
            + "&client_id="     + encodeURIComponent(Config.gcal.clientId)
            + "&client_secret=" + encodeURIComponent(Config.gcal.clientSecret);
        xhr.send(body);
    }

    function _fetchFromApi(key, year, month, day, retried) {
        // Mark as loading
        var nl = Object.assign({}, _loading);
        nl[key] = true;
        _loading = nl;

        var timeMin = encodeURIComponent(key + "T00:00:00Z");
        var timeMax = encodeURIComponent(key + "T23:59:59Z");
        var url = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
            + "?timeMin=" + timeMin
            + "&timeMax=" + timeMax
            + "&singleEvents=true"
            + "&orderBy=startTime";

        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.setRequestHeader("Authorization", "Bearer " + Config.gcal.accessToken);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            // Clear loading flag
            var nl2 = Object.assign({}, _loading);
            delete nl2[key];
            _loading = nl2;

            if (xhr.status === 200) {
                var data  = JSON.parse(xhr.responseText);
                var items = data.items || [];
                var events = items.map(function(item) {
                    var timeStr = "All day";
                    if (item.start && item.start.dateTime) {
                        var dt = new Date(item.start.dateTime);
                        timeStr = ("0" + dt.getHours()).slice(-2) + ":"
                                + ("0" + dt.getMinutes()).slice(-2);
                    }
                    var color = root._colorMap[item.colorId] || "#5b9bf5";
                    return {
                        title: item.summary || "(No title)",
                        time:  timeStr,
                        color: color
                    };
                });
                var nc = Object.assign({}, _cache);
                nc[key] = events;
                _cache = nc;

            } else if (xhr.status === 401 && !retried) {
                // Token expired — refresh once and retry
                _refreshToken(function() {
                    _fetchFromApi(key, year, month, day, true);
                });
            } else {
                console.warn("GoogleCalendar: fetch failed:", xhr.status);
                // Store empty so we don't keep retrying
                var nc2 = Object.assign({}, _cache);
                nc2[key] = [];
                _cache = nc2;
            }
        };
        xhr.send();
    }

    function _handleAuthResult() {
        try {
            var result = JSON.parse(_authBuf.trim());
            Config.gcal.accessToken  = result.access_token  || "";
            Config.gcal.refreshToken = result.refresh_token || "";
            Config.gcal.tokenExpiry  = result.expiry        || 0;
            if (Config.gcal.accessToken) {
                _fetchColors();
            }
        } catch(e) {
            console.warn("GoogleCalendar: failed to parse auth result:", e, _authBuf);
        }
    }
}
