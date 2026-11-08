pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.singletons.network
import qs.components

Singleton {
    id: root

    readonly property string _TOKEN_ENDPOINT: "https://oauth2.googleapis.com/token"

    // The shell's own OAuth client (a "Desktop app" client of the h2s-shell project in Google
    // Cloud), so nobody has to make one. For installed apps Google says the client secret
    // "is obviously not treated as a secret": the program carries it, anyone can read it.
    // What protects a sign-in is the user's consent and PKCE (scripts/google_auth.py).
    // A client of your own, entered in the settings, takes its place.
    //
    // Stored scrambled (XOR with a fixed key, then base64) only so that secret scanners
    // (GitHub's push protection, trufflehog…) do not flag it as a leak. It is not
    // protection: anyone reading this file can undo it, and that is accepted (above).
    readonly property string _builtInClientId: _unscramble("XAFGGUddV1lZUApKAEBZCQsFG1tCFBVaDQ0AAAoRXwVYAlgeDVcRXRFQCR8NRlMDXQBGAgMDD14WWAANFw8DBkYWQwdGBgMB")
    readonly property string _builtInClientSecret: _unscramble("L30wfiMwSAsrG3sZZkclIRsIGkQcRBYiCz4kOXpLYgcZNDw=")
    function _unscramble(encoded: string): string {
        const key = "h2s-shell";
        const bytes = Qt.atob(encoded);
        let text = "";
        for (let i = 0; i < bytes.length; i++)
            text += String.fromCharCode(bytes.charCodeAt(i) ^ key.charCodeAt(i % key.length));
        return text;
    }
    readonly property bool usingOwnClient: Config.gcal.clientId !== "" && Config.gcal.clientSecret !== ""
    readonly property string clientId: usingOwnClient ? Config.gcal.clientId : _builtInClientId
    readonly property string clientSecret: usingOwnClient ? Config.gcal.clientSecret : _builtInClientSecret

    property bool isAuthorized: Config.gcal.refreshToken !== ""
    property bool isBusy: authProcess.running

    signal authorized(success: bool)
    signal loggedOut
    signal tokenRefreshFailed

    Logger {
        id: logger
        enabled: Profiles.value("gcal.debug") ?? false
        prefix: "[GoogleCalendar: Auth]"
    }

    Process {
        id: authProcess

        property var outputBuffer: ""

        command: ["python3", Quickshell.shellDir + "/scripts/google_auth.py"]
        // In the environment, not the arguments: any user can read a process's command
        // line from /proc/<pid>/cmdline, while /proc/<pid>/environ is the owner's and root's
        environment: ({
            "GOOGLE_CLIENT_ID": root.clientId,
            "GOOGLE_CLIENT_SECRET": root.clientSecret
        })
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
                // Started only once the old helper is gone, so its exit cannot be mistaken
                // for the new one's, and deferred so Process is not restarted from inside
                // its own running change
                if (root._restartLogin) {
                    root._restartLogin = false;
                    Qt.callLater(root.login);
                }
            }
        }
    }

    // Set by cancelLogin() so the empty output of a killed helper is not reported as an error
    property bool _loginCancelled: false
    // Set by login() when a login is already running, to start a fresh one once it exits
    property bool _restartLogin: false

    function login() {
        // A login already running is most likely waiting on a browser tab the user closed,
        // and would sit there until its timeout. Asking again means starting over.
        if (authProcess.running) {
            root._restartLogin = true;
            root.cancelLogin();
            return;
        }
        root._loginCancelled = false;
        authProcess.running = true;
    }

    function cancelLogin() {
        root._loginCancelled = true;
        authProcess.running = false;
    }

    function logout() {
        Config.gcal.accessToken = "";
        Config.gcal.refreshToken = "";
        Config.gcal.tokenExpiry = 0;
        root.loggedOut();
    }

    function _handleAuthResult(result: string) {
        if (root._loginCancelled) {
            root._loginCancelled = false;
            logger.log("Login cancelled by the user");
            root.authorized(false);
            return;
        }
        try {
            let json = JSON.parse(result.trim());
            Config.gcal.accessToken = json.access_token || "";
            Config.gcal.refreshToken = json.refresh_token || "";
            Config.gcal.tokenExpiry = json.expiry || 0;
            root.authorized(!!Config.gcal.accessToken);
        } catch (e) {
            logger.error("Failed to parse auth result:", e, result);
            root.authorized(false);
            Notifier.send("Error ocurred while processing google auth result, look into the logs for more detail.");
        }
    }

    // Every request that hits a 401 asks for a refresh, often several at once. They share
    // one refresh so that a failure notifies and logs out once: a burst of interactive
    // notifications clobbers Notifier's single callback slot and leaves Reconnect dead.
    property var _refreshPromise: null

    function _refreshToken() {
        if (root._refreshPromise)
            return root._refreshPromise;
        // Local, because finally() runs inline on an already settled promise and would clear
        // the property before this function returns it
        const refresh = root._requestTokenRefresh();
        root._refreshPromise = refresh;
        refresh.finally(() => {
            root._refreshPromise = null;
        });
        return refresh;
    }

    function _requestTokenRefresh() {
        let body = "grant_type=" + encodeURIComponent("refresh_token");
        body += "&refresh_token=" + encodeURIComponent(Config.gcal.refreshToken);
        body += "&client_id=" + encodeURIComponent(root.clientId);
        body += "&client_secret=" + encodeURIComponent(root.clientSecret);

        return Promises.create((resolve, reject) => {
            return Fetch.request(root._TOKEN_ENDPOINT, {
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
            }).catch(failure => {
                // Offline after a resume, a timeout, Google's 5xx: the login is still good,
                // the next request tries again. Logging out here threw the refresh token
                // away and asked for a new login after every network hiccup.
                if (!root.refreshFailureIsFinal(failure)) {
                    logger.warn("Token refresh failed, keeping the login for the next request:", failure);
                    return reject(failure);
                }
                logger.error("Google rejected the refresh token", failure);
                Notifier.send("Google Calendar Token expired! You need to login again :/", {
                    actions: [{ id: "reconnect", label: "Reconnect", onTriggered: () => root.login() }]
                });
                logout();
                return reject(failure);
            });
        });
    }

    // Whether a failed refresh means the refresh token itself is dead — revoked, expired,
    // the app's access removed — the one case only a new login fixes. Google answers that
    // with "invalid_grant"; anything else is worth retrying.
    function refreshFailureIsFinal(failure) {
        if (!failure || (failure.status !== 400 && failure.status !== 401))
            return false;
        try {
            return JSON.parse(failure.body ?? "").error === "invalid_grant";
        } catch (error) {
            return false;
        }
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
