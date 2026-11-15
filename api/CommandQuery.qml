import qs.singletons.io as Io

// A command whose output is read line by line, run on request (module API 1.0): set
// `command`, call request(), get done(lines). A request while it runs runs it once more
// after. The shell's own idiom (singletons/io/CommandQuery.qml).
Io.CommandQuery {}
