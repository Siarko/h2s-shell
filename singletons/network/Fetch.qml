pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.components

Singleton {
    id: root

    property var _pendingRequests: ({})

    Logger {
        id: logger
        enabled: Config.general.fetch_debug
        prefix: "[FETCH]"
    }

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
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
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
                    reject(new Error("Unexpected HTTP response status " + xhr.status + ", data: " + xhr.responseText));
                }
            };
            xhr.send(data.body ?? null);
        });
        if (data.id) {
            result.finally(() => {
                logger.log("Request resolved, removing stamped request ", data.id);
                delete root._pendingRequests[data.id];
            });
            logger.log("Adding stamped request", data.id, result);
            root._pendingRequests[data.id] = result;
        }
        return result;
    }

    function _printf(format, args) {
        return format.replace(/{(\d+)}/g, (match, num) => {
            return typeof args[num] !== undefined ? args[num] : match;
        });
    }
}
