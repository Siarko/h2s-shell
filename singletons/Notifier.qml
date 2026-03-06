pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // send(summary, body?, urgency?)
    // urgency: "low" | "normal" | "critical"  (default "normal")
    function send(summary, body, urgency, appName) {
        _process.running = false;
        let cmd = ["notify-send", "--urgency=" + (urgency ?? "normal"), "--app-name=" + (appName ?? 'H2S Shell'), summary];
        if (body)
            cmd.push(body);
        _process.command = cmd;
        _process.running = true;
    }

    Process {
        id: _process
        running: false
    }
}
