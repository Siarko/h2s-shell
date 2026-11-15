import qs.singletons.io as Io

// Commands that change something, one after another, each answered (module API 1.0):
// run(command, done, environment) calls done({ ok, code, lines, error }). The shell's own
// idiom (singletons/io/CommandAction.qml, which says more): a secret goes in `environment`,
// never on the command line; nothing is ever started by a declarative `running: true`.
Io.CommandAction {}
