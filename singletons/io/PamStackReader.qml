import QtQuick
import Quickshell
import qs.singletons

// Reads the PAM stacks the shell cares about — polkit-1 and sudo, the lock's configs — and
// pam_faillock's settings, read only; the shell's one instance is PamStacks. Decisions are
// PamStackRules'; this only runs the commands:
//
// - the methods script (scripts/lock-auth-methods.sh) for whether a fingerprint and a
//   security key are ready and which configs the lock uses;
// - Distribution for its facts — whether this is NixOS, how many PAM directories libpam
//   reads there (NixOS: /etc/pam.d only), where its modules are: a reading is published
//   only once it has answered;
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
    // The distribution's facts (DistributionRules.manifest: id, pamDirectories,
    // pamModuleDirectories), null when it cannot be told, or undefined until Distribution
    // has answered
    // (From the one answer object: its ready and facts change together)
    property var distribution: Distribution.detection.ready ? Distribution.detection.facts : undefined
    // Whether this is NixOS: true, false, null when the distribution cannot be told, or
    // undefined until Distribution has answered
    readonly property var nixos: distribution === undefined ? undefined : distribution === null ? null : distribution.id === "nixos"
    // Added to every run's environment (a suite's seams)
    property var environment: ({})
    // The methods script finishes within about four seconds whatever fprintd does
    property int timeoutMs: 6000
    readonly property var services: ["polkit-1", "sudo"]

    // The last complete reading, or null before the first: { services: { name: stack },
    // lock: { method: stack }, faillock: { name: settings or null }, facts: { nixos (true /
    // false / null), moduleDirectories (the distribution's PAM module directories; [] when
    // not known), fingerprint, securityKey ("ready" / "absent" / "unknown"), u2f (what the
    // machine's pam_u2f settings let the lock's and the editor's key lines do:
    // PamStackRules._u2fOf's { lock, rows, conf }) },
    // directories, files: { path: { text } | { absent: true } | { unreadable: true } } (every
    // file read: the editor builds from the texts) }
    property var reading: null
    // A refresh is going on
    readonly property bool running: _generation !== _finished
    // How many readings were published (a suite waits on it)
    property int readings: 0

    // Reads everything again; the methods script only `withMethods` (it asks fprintd over
    // D-Bus, which can take seconds), else its last answer counts (none: "unknown")
    function refresh(withMethods) {
        // A refresh without the methods script while one with it runs takes it over: its run
        // is cancelled below, so it runs again rather than leave the methods unanswered
        const methods = withMethods === true || (running && _state.methods === null);
        const generation = ++_generation;
        for (const run of _runs)
            run.cancel();
        _runs = [];
        _state = {
            places: null, answers: {}, rounds: 0, distribution: distribution, reading: false,
            methods: methods ? null
                : _methods ?? { known: false, fingerprint: "unknown", securityKey: "unknown", lock: {} }
        };
        if (methods) {
            _start(methodsCommand, [], (lines, result) => {
                _methods = PamStackRules.methodsAnswer(lines, result);
                _state.methods = _methods;
                _advance(generation);
            }, generation);
        }
        _read([], generation);
    }

    // A refresh made before Distribution answered takes its answer when it comes
    onDistributionChanged: {
        if (running && _state.distribution === undefined && distribution !== undefined) {
            _state.distribution = distribution;
            _advance(_generation);
        }
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
                _state.places = answer.places ?? { directories: [], faillockPath: "", u2fConfPath: null };
            Object.assign(_state.answers, answer.answers);
            _advance(generation);
        }, generation);
    }

    function _request() {
        const places = _state.places;
        // The places pam-files.sh names stand for the distribution's PAM directories, in
        // order: as many count as it has (NixOS has no vendor directory: only the first). Not
        // known: none, every stack unknown
        const count = Array.isArray(_state.distribution?.pamDirectories) ? _state.distribution.pamDirectories.length : 0;
        const directories = places.directories.slice(0, count);
        return {
            services: services,
            lock: _state.methods?.lock ?? {},
            directories: directories,
            faillockPath: places.faillockPath,
            // Not placed: not known (pam_u2f.conf may hold anything)
            u2fConfPath: typeof places.u2fConfPath === "string" ? places.u2fConfPath : null,
            // NixOS or not, from the distribution's facts: null while not known
            nixos: _state.distribution === undefined || _state.distribution === null ? null : _state.distribution.id === "nixos"
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
        if (_state.methods === null || _state.distribution === undefined)
            return;
        const distribution = _state.distribution;
        reading = {
            services: step.services,
            lock: step.lock,
            faillock: step.faillock,
            facts: { nixos: distribution === null ? null : distribution.id === "nixos",
                     moduleDirectories: Array.isArray(distribution?.pamModuleDirectories) ? distribution.pamModuleDirectories.slice() : [],
                     fingerprint: _state.methods.fingerprint, securityKey: _state.methods.securityKey, u2f: step.u2f },
            directories: request.directories,
            files: Object.assign({}, _state.answers)
        };
        _finished = generation;
        readings += 1;
    }

    property CommandRunner _runner: CommandRunner {}
}
