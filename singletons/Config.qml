pragma Singleton

import Quickshell
import Quickshell.Io
import QtCore
import QtQuick

Singleton {
    id: config

    property string datetimeFormat: "hh:mm:ss"
    property bool _loaded: false

    onDatetimeFormatChanged: if (_loaded) _saveTimer.restart()

    readonly property string _configPath: StandardPaths.writableLocation(
        StandardPaths.GenericConfigLocation) + "/h2s_shell/config.json"

    // ── Debounce: write to disk 1s after last change ──────────────────
    Timer {
        id: _saveTimer
        interval: 1000
        onTriggered: _writer.running = true
    }

    // ── Write: python3 receives path + value as argv to avoid escaping ─
    Process {
        id: _writer
        command: [
            "python3", "-c",
            "import json,pathlib,sys; p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True,exist_ok=True); d=(json.loads(p.read_text()) if p.exists() else {}); d.setdefault('calendar',{})['datetimeFormat']=sys.argv[2]; p.write_text(json.dumps(d)+'\\n')",
            config._configPath,
            config.datetimeFormat
        ]
    }

    // ── Read: python3 prints compact JSON to stdout on startup ─────────
    Process {
        id: _reader
        running: true
        command: [
            "python3", "-c",
            "import json,pathlib,sys; p=pathlib.Path(sys.argv[1]); print(json.dumps(json.loads(p.read_text())) if p.exists() else '{}',end='')",
            config._configPath
        ]

        property string _buf: ""

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => _reader._buf += data
        }

        onRunningChanged: {
            if (running) return
            Qt.callLater(() => {
                try {
                    const d = JSON.parse(_buf)
                    if (d?.calendar?.datetimeFormat)
                        config.datetimeFormat = d.calendar.datetimeFormat
                } catch (e) {}
                config._loaded = true
            })
        }
    }
}
