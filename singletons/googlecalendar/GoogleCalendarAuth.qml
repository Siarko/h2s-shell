pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.singletons.network
import qs.components

Singleton {
    id: root

    readonly property string _TOKEN_ENDPONT: "https://oauth2.googleapis.com/token"

    property bool isAuthorized: Config.gcal.refreshToken !== ""
    property bool isBusy: authProcess.running

    signal authorized(success: bool)
    signal loggedOut
    signal tokenRefreshFailed

    Logger {
        id: logger
        enabled: Config.gcal.debug
        prefix: "[GoogleCalendar: Auth]"
    }

    Process {
        id: authProcess

        property var outputBuffer: ""

        command: ["python3", Quickshell.shellDir + "/scripts/google_auth.py", Config.gcal.clientId, Config.gcal.clientSecret]
        stdout: SplitParser {
            splitMarker: ""
            onRead: function (data) {
                authProcess.outputBuffer += data;
            }
        }
        onRunningChanged: {
            if (!running) {
                root._handleAuthResult(authProcess.outputBuffer);
                authProcess.outputBuffer = "";
            }
        }
    }

    function login() {
        authProcess.running = true;
    }

    function logout() {
        Config.gcal.accessToken = "";
        Config.gcal.refreshToken = "";
        Config.gcal.tokenExpiry = 0;
        root.loggedOut();
    }

    function _handleAuthResult(result: string) {
        try {
            var result = JSON.parse(result.trim());
            Config.gcal.accessToken = result.access_token || "";
            Config.gcal.refreshToken = result.refresh_token || "";
            Config.gcal.tokenExpiry = result.expiry || 0;
            root.authorized(!!Config.gcal.accessToken);
        } catch (e) {
            logger.error("Failed to parse auth result:", e, _authBuf);
            root.authorized(false);
        }
    }

    function _refreshToken() {
        let body = "grant_type=" + encodeURIComponent("refresh_token");
        body += "&refresh_token=" + encodeURIComponent(Config.gcal.refreshToken);
        body += "&client_id=" + encodeURIComponent(Config.gcal.clientId);
        body += "&client_secret=" + encodeURIComponent(Config.gcal.clientSecret);

        return Promises.create((resolve, reject) => {
            return Fetch.request(root._TOKEN_ENDPONT, {
                method: "POST",
                headers: {
                    "Content-Type": "application/x-www-form-urlencoded"
                },
                body: body,
                id: root._TOKEN_ENDPOINT
            }).then(result => {
                logger.log("Refresh token result received");
                return result.json().then(json => {
                    logger.log("Refreshed token expiry: ", json.expires_in);
                    Config.gcal.accessToken = json.access_token;
                    Config.gcal.tokenExpiry = Math.floor(Date.now() / 1000) + (json.expires_in || 3600);
                    return resolve();
                }).catch(reject);
            }).catch(e => {
                logger.error("Error while refreshing token", e);
                return reject(e);
            });
        });
    }

    function ensureAuthorized(callback) {
        let wrapper = function (resolve, reject) {
            callback().then(resolve).catch(reason => {
                if (reason.status === 401) {
                    logger.warn("Looks like token is expired, refreshing");
                    return _refreshToken().then(() => {
                        return callback().then(resolve).catch(reject);
                    }).catch(reject);
                } else {
                    logger.error("Rejected request for reason: ", reason);
                    return reject(reason);
                }
            });
        };
        return Promises.create((resolve, reject) => {
            let now = Date.now() / 1000;
            let left = Config.gcal.tokenExpiry - now;
            if (left < 300) {
                logger.log("pre-check - Token expired");
                return _refreshToken().then(() => {
                    logger.log("Token refreshed, executing request");
                    return wrapper(resolve, reject);
                }).catch(reject);
            } else {
                logger.log("Token seems ok - ", left, "sec left, executing request");
                return wrapper(resolve, reject);
            }
        });
    }
}
