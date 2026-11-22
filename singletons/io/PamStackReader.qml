import QtQuick
import Quickshell
import qs.singletons

// Reads the PAM stacks the shell cares about — polkit-1 and sudo, the lock's configs — and
// pam_faillock's settings, read only; the shell's one instance is PamStacks. Decisions are
// PamStackRules'; this only runs the commands:
//
// - the methods script (scripts/lock-auth-methods.sh) for whether a fingerprint and a
//   security key are ready and which configs the lock uses, and its `--fallback-facts`
//   for whether this is NixOS (where libpam reads /etc/pam.d only);
// - scripts/pam-files.sh in rounds: first for the places (the PAM directories and
//   faillock.conf, its seams), then for the paths the stacks ask for, until none is
//   missing (PamStackRules.readingStep). It tells a file not there from one it cannot
//   read, which a FileView does not.
//
// Every command is a property, so a suite points it at stand-ins (tests/PamStacksReadingTest
// .qml). Each run has a time limit; one that fails or times out leaves what it was asked
// unknown. Nothing is read until refresh(); then the published `reading` stays as it was
// until the new one is complete, and an answer from before a newer refresh() is dropped.
QtObject {
    id: root

    property var filesCommand: [Quickshell.shellDir + "/scripts/pam-files.sh"]
    property var methodsCommand: [Quickshell.shellDir + "/scripts/lock-auth-methods.sh"]
    property var nixosCommand: [Quickshell.shellDir + "/scripts/lock-auth-methods.sh", "--fallback-facts"]
    // Added to every run's environment (a suite's seams)
    property var environment: ({})
    // The methods script finishes within about four seconds whatever fprintd does
    property int timeoutMs: 6000
    readonly property var services: ["polkit-1", "sudo"]

    // The last complete reading, or null before the first: { services: { name: stack },
    // lock: { method: stack }, faillock: { name: settings or null }, facts: { nixos (true /
    // false / null), fingerprint, securityKey ("ready" / "absent" / "unknown") },
    // directories }
    property var reading: null
    // A refresh is going on
    readonly property bool running: _generation !== _finished
    // How many readings were published (a suite waits on it)
    property int readings: 0

    // Reads everything again; the methods script only `withMethods` (it asks fprintd over
    // D-Bus, which can take seconds), else its last answer counts (none: "unknown")
    function refresh(withMethods) {
        const generation = ++_generation;
        for (const run of _runs)
            run.cancel();
        _runs = [];
        _state = {
            places: null, answers: {}, rounds: 0, nixos: undefined, reading: false,
            methods: withMethods === true ? null
                : _methods ?? { known: false, fingerprint: "unknown", securityKey: "unknown", lock: {} }
        };
        if (withMethods === true) {
            _start(methodsCommand, [], (lines, result) => {
                _methods = PamStackRules.methodsAnswer(lines, result);
                _state.methods = _methods;
                _advance(generation);
            }, generation);
        }
        _start(nixosCommand, [], (lines, result) => {
            _state.nixos = PamStackRules.nixosAnswer(lines, result);
            _advance(generation);
        }, generation);
        _read([], generation);
    }

    property int _generation: 0
    property int _finished: 0
    property var _runs: []
    property var _state: ({})
    // The methods script's last answer (PamStackRules.methodsAnswer), null before the first
    property var _methods: null

    function _start(command, extra, done, generation) {
        const lines = [];
        const run = _runner.start(Array.from(command).concat(extra), {
            timeoutMs: timeoutMs,
            killAfterMs: 1000,
            environment: environment,
            maxOutputBytes: 1048576,
            keepOutput: false,
            onLine: (line, stream) => {
                if (stream === "stdout" && line.trim() !== "")
                    lines.push(line);
            },
            done: result => {
                root._runs = root._runs.filter(item => item !== run);
                if (generation === root._generation)
                    done(lines, result);
            }
        });
        _runs = _runs.concat([run]);
    }

    function _read(paths, generation) {
        _state.reading = true;
        _state.rounds += 1;
        _start(filesCommand, paths, (lines, result) => {
            const answer = PamStackRules.filesAnswer(lines, result, paths);
            _state.reading = false;
            if (_state.places === null)
                _state.places = answer.places ?? { directories: [], faillockPath: "" };
            Object.assign(_state.answers, answer.answers);
            _advance(generation);
        }, generation);
    }

    function _request() {
        const places = _state.places;
        const nixos = _state.nixos === true;
        // NixOS has no vendor directory: only the first counts there
        const directories = places.directories.length === 0 ? []
            : nixos ? places.directories.slice(0, 1) : places.directories;
        return {
            services: services,
            lock: _state.methods?.lock ?? {},
            directories: directories,
            faillockPath: places.faillockPath
        };
    }

    function _advance(generation) {
        if (generation !== _generation || _state.reading || _state.places === null)
            return;
        const request = _request();
        // Without places (the first run failed) nothing is read: every stack unknown
        const unplaced = request.directories.length === 0;
        const step = PamStackRules.readingStep(request, unplaced ? {} : _state.answers,
                                               unplaced || _state.rounds >= PamStackRules.maxRounds);
        if (step.pending.length > 0) {
            _read(step.pending, generation);
            return;
        }
        if (_state.methods === null || _state.nixos === undefined)
            return;
        reading = {
            services: step.services,
            lock: step.lock,
            faillock: step.faillock,
            facts: { nixos: _state.nixos, fingerprint: _state.methods.fingerprint, securityKey: _state.methods.securityKey },
            directories: request.directories
        };
        _finished = generation;
        readings += 1;
    }

    property CommandRunner _runner: CommandRunner {}
}
