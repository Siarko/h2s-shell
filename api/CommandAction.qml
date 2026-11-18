import qs.singletons
import qs.singletons.io as Io

// Commands that change something, one after another, each answered (module API 1.0):
// run(command, done, environment) calls done({ ok, code, lines, error }). The shell's own
// idiom (singletons/io/CommandAction.qml, which says more): a secret goes in `environment`,
// never on the command line; nothing is ever started by a declarative `running: true`.
// In module test mode a pkexec that is not a module's stand-in is refused (ModuleRules.testRunProblem).
Io.CommandAction {
    refuse: function (argv) {
        return ModuleRules.testRunProblem(argv, Modules.host.testMode, Modules.host.testStandIns);
    }
}
