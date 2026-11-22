import QtQuick
import qs.singletons
import qs.singletons.io as Io

// Runs commands, any number at once, each with a time limit, its output as it comes and one
// answer (module API 1.8; the reference is in api/Api.qml):
// start(argv, options) → handle { running, cancel() }, cancelAll(), `running` (how many are
// not answered yet), `environment` (added to every run's). It lives under the module's
// main object or one of its views: when that goes, its runs are ended and nothing is called.
QtObject {
    id: root

    property var environment: ({})
    readonly property int running: _running

    function start(argv, options) {
        return _runs.start(argv, options);
    }

    function cancelAll() {
        _runs.cancelAll();
    }

    onEnvironmentChanged: _runs.setEnvironment(environment)
    Component.onCompleted: _runs.setEnvironment(environment)

    // What `running` reads: bound to the runner's count (_runs)
    property int _running: 0

    // The runner itself is held by these closures alone, never by a property: a module must
    // not reach it (its `refuse`, its runs). Its parent is this object, which ends it when this
    // goes. In module test mode a pkexec that is not a module's stand-in is refused, answered
    // with `error` and nothing run (ModuleRules.testRunProblem)
    readonly property var _runs: {
        const component = Qt.createComponent(Qt.resolvedUrl("../singletons/io/CommandRunner.qml"), Component.PreferSynchronous);
        // The environment is handed over after (onEnvironmentChanged, Component.onCompleted):
        // read here, it would make this a binding on it, a new runner at each change
        const runner = component.createObject(root, {
            refuse: argv => ModuleRules.testRunProblem(argv, Modules.host.testMode, Modules.host.testStandIns)
        });
        if (runner === null) {
            console.warn("[Api] CommandRunner: " + component.errorString().trim());
            const refused = () => Object.freeze({ running: false, cancel: () => {} });
            return Object.freeze({ start: refused, cancelAll: () => {}, setEnvironment: () => {} });
        }
        // A binding over the closure: the count follows the runner's, the runner unreached
        root._running = Qt.binding(() => runner.running);
        return Object.freeze({
            start: (argv, options) => runner.start(argv, options),
            cancelAll: () => runner.cancelAll(),
            setEnvironment: environment => runner.environment = environment
        });
    }
}
