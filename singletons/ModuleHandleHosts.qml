pragma Singleton

import Quickshell
import QtQuick

// Which module host each module handle belongs to, by the handle's key (api/ModuleHandle.qml's
// `_hostKey`). The handle reads its host through here, inline, so that nothing of it — no
// property, no function — hands the host to a module (module API 1.36: `module.host` is gone).
Singleton {
    id: root

    property var _hosts: ({})
    property int _issued: 0

    // A new key for `host`'s handles
    function register(host) {
        _issued++;
        const key = "host-" + _issued + "-" + Math.random().toString(36).slice(2, 10);
        const hosts = Object.assign({}, _hosts);
        hosts[key] = host;
        _hosts = hosts;
        return key;
    }

    // The host is going: its key finds nothing once the current turn is over — its mains,
    // destroyed after it, still read their handles meanwhile
    function forgetLater(key) {
        _forgetting.push(key);
        _forgetTimer.restart();
    }

    property var _forgetting: []
    property Timer _forgetTimer: Timer {
        interval: 0
        onTriggered: {
            const keys = root._forgetting;
            root._forgetting = [];
            for (const key of keys)
                root.forget(key);
        }
    }

    function forget(key) {
        if (!Object.prototype.hasOwnProperty.call(_hosts, key))
            return;
        const hosts = Object.assign({}, _hosts);
        delete hosts[key];
        _hosts = hosts;
    }

    function hostOf(key) {
        return typeof key === "string" && Object.prototype.hasOwnProperty.call(_hosts, key) ? _hosts[key] : null;
    }
}
