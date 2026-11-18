import QtQuick
import qs.singletons.io as Io

// Runs commands, any number at once, each with a time limit, its output as it comes and one
// answer (module API 1.8; the reference is in api/Api.qml):
// start(argv, options) → handle { running, cancel() }, cancelAll(), `running` (how many are
// not answered yet), `environment` (added to every run's). It lives under the module's
// main object or one of its views: when that goes, its runs are ended and nothing is called.
QtObject {
    id: root

    property var environment: ({})
    readonly property int running: _runner.running

    function start(argv, options) {
        return _runner.start(argv, options);
    }

    function cancelAll() {
        _runner.cancelAll();
    }

    property Io.CommandRunner _runner: Io.CommandRunner {
        environment: root.environment
    }
}
