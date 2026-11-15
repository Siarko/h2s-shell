import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// One PAM conversation against the shell's shipped config (pam/password, or the config
// named by H2S_PAM_PROBE_CONFIG) — the real-machine check of docs/plans/lockscreen.md,
// section 8. NOT run by any suite: it authenticates against the real account. Start it
// only through pam-probe.sh (README.md here), which reads the password without echo and
// hands it over through a private FIFO: never an argument, never the environment, never
// a log. No window. At most one attempt: one start(), one answer; a second prompt is not
// answered (the conversation is aborted and reported as an Error).
ShellRoot {
    id: root

    readonly property string directory: Quickshell.env("H2S_PAM_PROBE_DIR") ?? ""
    readonly property string config: Quickshell.env("H2S_PAM_PROBE_CONFIG") || "password"
    readonly property string fifo: Quickshell.env("H2S_PAM_PROBE_FIFO") ?? ""

    property string _secret: ""
    property bool _answered: false
    property bool _done: false

    function finish(word) {
        if (_done)
            return;
        _done = true;
        _secret = "";
        console.info("pam-probe: " + word + " (config " + config + " in " + directory + ")");
        Qt.exit(word === "Success" ? 0 : 1);
    }

    // The password, read once from the FIFO pam-probe.sh writes it to
    Process {
        id: _reader
        command: ["sh", "-c", "IFS= read -r line < \"$1\" && printf '%s' \"$line\"", "sh", root.fifo]
        stdout: StdioCollector {
            onStreamFinished: {
                root._secret = text;
                if (root._secret === "")
                    root.finish("Error (no password read)");
                else if (!_pam.start())
                    root.finish("Error (PAM refused to start: is " + root.directory + "/" + root.config + " there?)");
            }
        }
    }

    PamContext {
        id: _pam
        configDirectory: root.directory
        config: root.config
        onPamMessage: {
            if (!responseRequired)
                return;
            if (root._answered) {
                abort();
                root.finish("Error (PAM asked a second time; not answered)");
                return;
            }
            root._answered = true;
            const secret = root._secret;
            root._secret = "";
            respond(secret);
        }
        onCompleted: result => root.finish(result === PamResult.Success ? "Success"
            : result === PamResult.Failed ? "Failed"
            : result === PamResult.MaxTries ? "Failed (MaxTries)" : "Error")
        onError: error => root.finish("Error (" + PamError.toString(error) + ")")
    }

    Component.onCompleted: {
        if (directory === "" || fifo === "")
            finish("Error (start it with pam-probe.sh)");
        else
            _reader.running = true;
    }
}
