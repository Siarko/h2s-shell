import qs.singletons
import qs.singletons.io as Io

// A command whose output is read line by line, run on request (module API 1.0): set
// `command`, call request(), get done(lines). A request while it runs runs it once more
// after. The shell's own idiom (singletons/io/CommandQuery.qml).
// In module test mode a pkexec that is not a module's stand-in is refused (ModuleRules.testRunProblem).
Io.CommandQuery {
    refuse: function (argv) {
        return ModuleRules.testRunProblem(argv, Modules.host.testMode, Modules.host.testStandIns);
    }
}
