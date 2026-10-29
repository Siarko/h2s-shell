pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.components

Singleton {
    id: root

    property var _pendingRequests: ({})

    // QML's XMLHttpRequest has no timeout property — setting one is silently ignored — so
    // each request gets its own timer that aborts it. Without one, a hung request never
    // settles and its id stays deduplicated onto a dead promise for the rest of the session.
    readonly property int defaultTimeout: 30000

    Component {
        id: _timeoutTimer
        Timer {}
    }

    Logger {
        id: logger
        enabled: Profiles.value("general.fetchDebug") ?? false
        prefix: "[FETCH]"
    }

    // data: { method, headers, params, query, body, id, timeout }
    // Rejects with an Error carrying `status` (0 when no response arrived) and, when the
    // request was aborted for taking longer than `timeout` ms, `timedOut: true`.
    function request(url, data) {
        if (root._pendingRequests[data.id]) {
            logger.log("Returning stamped promise", data.id, root._pendingRequests[data.id]);
            return root._pendingRequests[data.id];
        }
        const result = Promises.create((resolve, reject) => {
            let xhr = new XMLHttpRequest();

            if (data.params) {
                let params = data.params.map(param => encodeURIComponent(param));
                url = _printf(url, params);
            }

            if (data.query) {
                let queryParams = [];
                for (const [name, value] of Object.entries(data.query)) {
                    queryParams.push(name + "=" + encodeURIComponent(value));
                }
                url += "?" + queryParams.join("&");
            }
            logger.log(data.method ?? 'GET', "URL: ", url);

            xhr.open(data.method || "GET", url);
            if (data.headers) {
                for (const [name, value] of Object.entries(data.headers)) {
                    xhr.setRequestHeader(name, value);
                }
            }
            const timeout = data.timeout ?? root.defaultTimeout;
            let timedOut = false;
            const timer = _timeoutTimer.createObject(root, { interval: timeout });
            timer.triggered.connect(() => {
                logger.log("Request timed out after", timeout, "ms:", url);
                timedOut = true;
                // abort() completes the request synchronously with status 0, which lands
                // in onreadystatechange below
                xhr.abort();
            });

            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                timer.stop();
                timer.destroy();
                // Released before settling, not in finally(): finally runs after every
                // handler, so a handler retrying the same id was handed this settled promise
                if (data.id && root._pendingRequests[data.id] === result) {
                    logger.log("Request done, removing stamped request", data.id);
                    delete root._pendingRequests[data.id];
                }
                if (timedOut) {
                    let failure = new Error("Request timed out after " + timeout + " ms");
                    failure.status = 0;
                    failure.timedOut = true;
                    reject(failure);
                    return;
                }
                if (xhr.status >= 200 && xhr.status < 300) {
                    resolve({
                        responseObject: xhr,
                        text: function () {
                            return this.responseObject.responseText;
                        },
                        json: function () {
                            return Promises.create((jresolve, jreject) => {
                                try {
                                    jresolve(JSON.parse(this.responseObject.responseText));
                                } catch (e) {
                                    jreject(e);
                                }
                            });
                        }
                    });
                } else {
                    // The status has to travel as a field, not just inside the message:
                    // GoogleCalendarAuth checks `reason.status === 401` to decide whether
                    // to refresh the token, and a bare Error made that check dead.
                    // No body at all (status 0: offline, refused, aborted) adds no "data:"
                    let failure = new Error("Unexpected HTTP response status " + xhr.status
                        + (xhr.responseText ? ", data: " + _truncate(xhr.responseText) : ""));
                    failure.status = xhr.status;
                    failure.body = xhr.responseText;
                    reject(failure);
                }
            };
            xhr.send(data.body ?? null);
            timer.start();
        });
        if (data.id) {
            logger.log("Adding stamped request", data.id, result);
            root._pendingRequests[data.id] = result;
        }
        return result;
    }

    // Error messages reach the log, and an auth endpoint's body can carry tokens, so the
    // full text stays on the error object for callers that need it and never in the message.
    function _truncate(text) {
        const body = text ?? "";
        return body.length > 200 ? body.substring(0, 200) + "… (truncated)" : body;
    }

    function _printf(format, args) {
        return format.replace(/{(\d+)}/g, (match, num) => {
            // typeof yields a string; compared with the value undefined it was always unequal,
            // so a missing argument put the text "undefined" into the URL
            return typeof args[num] !== "undefined" ? args[num] : match;
        });
    }
}
