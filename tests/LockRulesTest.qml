import QtQuick
import qs.singletons

// The lock's rules (singletons/LockRules.qml), by the behaviours of the plan's Stage 1
// (docs/plans/lockscreen.md, sections 4 and 7). Each numbered part below is one of them;
// the seeded sweep at the end checks the invariants over thousands of generated sequences,
// and a liveness oracle checks from sampled states that the owner can still get in.
TestCase {
    suiteName: "LockRules"

    readonly property var fallback: ({ directory: "/shell/pam", config: "password" })
    readonly property var allLines: [
        "password\t/etc/pam.d\th2s-shell-password",
        "fingerprint\t/etc/pam.d\th2s-shell-fingerprint",
        "u2f\t/etc/pam.d\th2s-shell-u2f"
    ]
    readonly property var passwordOnly: ["password\t/etc/pam.d\th2s-shell-password"]
    readonly property var passwordAndFingerprint: ["password\t/etc/pam.d\th2s-shell-password", "fingerprint\t/etc/pam.d\th2s-shell-fingerprint"]
    readonly property var passwordAndKey: ["password\t/etc/pam.d\th2s-shell-password", "u2f\t/etc/pam.d\th2s-shell-u2f"]

    // ---- Helpers ----

    // A machine: the state, the clock, and the last step's result. `send` takes an event,
    // a function of the state returning one (for the ids only the state knows), or an
    // array of those.
    function machine(settings, startTime) {
        const rules = LockRules;
        const self = {
            state: rules.initial(settings ?? { lockOnSleep: true, passwordFallback: fallback }),
            now: startTime ?? 100000,
            effects: [],
            ignored: "",
            error: false,
            all: []
        };
        self.send = (event, advance) => {
            if (Array.isArray(event))
                return self.sendAll(event, advance);
            self.now += advance ?? 10;
            const resolved = typeof event === "function" ? event(self.state) : event;
            const result = rules.step(self.state, resolved, self.now);
            self.state = result.state;
            self.effects = result.effects;
            self.ignored = result.ignored;
            self.error = result.error === true;
            self.all = self.all.concat(result.effects);
            return self;
        };
        self.sendAll = (events, advance) => {
            for (const event of events)
                self.send(event, advance);
            return self;
        };
        return self;
    }

    function started(settings) {
        return machine(settings).send({ type: "started" });
    }

    function added(surface, screen) {
        return { type: "surfaceAdded", surface: surface, screen: screen ?? "DP-1" };
    }

    function removed(surface) {
        return { type: "surfaceRemoved", surface: surface };
    }

    function activity(surface) {
        return { type: "activity", surface: surface ?? "s1" };
    }

    function press(surface) {
        return { type: "press", surface: surface ?? "s1" };
    }

    function key(surface, name, text) {
        return { type: "key", surface: surface ?? "s1", key: name ?? "", text: text ?? "" };
    }

    // From the surface that shows the prompt (the field is only there)
    function submit(text) {
        return state => ({ type: "submit", surface: state.prompt.owner, text: text });
    }

    // Somebody at the first screen types and presses Enter
    function enter(text) {
        return [activity("s1"), submit(text)];
    }

    function confirmed() {
        return state => ({ type: "compositorLocked", session: state.phase.session });
    }

    function finished() {
        return state => ({ type: "compositorFinished", session: state.phase.session });
    }

    // Lock requested, one surface ("s1" on DP-1), the compositor not yet confirming
    function locking(settings) {
        return started(settings).sendAll([{ type: "lockRequested", source: "ipc" }, added("s1")]);
    }

    // Locked, compositor confirmed, one surface, the methods known (all three by default):
    // the passive methods running, the password idle, the prompt asleep
    function locked(lines, settings) {
        return locking(settings).sendAll([confirmed(), detected(lines ?? allLines)]);
    }

    function conversationOf(state, method) {
        const conversation = method === "password" ? state.password.conversation : state.passive[method].conversation;
        return conversation === null ? -1 : conversation.id;
    }

    function detected(lines) {
        return state => ({ type: "methodsDetected", generation: state.methods.generation, lines: lines });
    }

    function pamMessage(method, fields) {
        return state => Object.assign({ type: "pamMessage", method: method, conversation: conversationOf(state, method),
                                        message: "", messageIsError: false, responseRequired: false, responseVisible: false }, fields);
    }

    function passwordPrompt(message) {
        return pamMessage("password", { message: message ?? "Password: ", responseRequired: true });
    }

    function pamCompleted(method, result) {
        return state => ({ type: "pamCompleted", method: method, conversation: conversationOf(state, method), result: result });
    }

    function timer(name) {
        return state => ({ type: "timer", name: name, token: state.timers[name] ? state.timers[name].token : -1 });
    }

    function of(effects, type, match) {
        return effects.filter(effect => effect.type === type
                              && Object.keys(match ?? {}).every(key => effect[key] === match[key]));
    }

    function has(effects, type, match) {
        return of(effects, type, match).length > 0;
    }

    function types(effects) {
        return effects.filter(effect => effect.type !== "log").map(effect => effect.type);
    }

    // Nothing of the lock left: no conversation, no lock timer, no secret
    function nothingRunning(state) {
        const running = LockRules.running(state);
        return running.conversations.length === 0 && running.lockTimers.length === 0 && state.secret === null;
    }

    function run() {
        _behaviour1OnlyTheseUnlock();
        _behaviour2StaleIgnored();
        _behaviour3LeavingCleansUp();
        _behaviour3SecondLockEqualsFirst();
        _behaviour4InputBeforeMethods();
        _behaviour5PamFacts();
        _behaviour6Prompt();
        _behaviour6Surfaces();
        _behaviour7Sleep();
        _behaviour8RepeatedAndDeniedLocks();
        _behaviour8Unconfirmed();
        _behaviour9Retry();
        _behaviour10Settings();
        _behaviour11Hangs();
        _behaviour12Redetection();
        _parsers();
        _secrets();
        _totality();
        _livenessCases();
        _sweep(1600, 24, 20261114);
    }

    // ---- 1. Only these unlock ----

    function _behaviour1OnlyTheseUnlock() {
        const unlocks = (label, from, event, reason) => {
            const lock = from.send(event);
            assert(has(lock.effects, "unlockCompositor", { reason: reason }) && lock.state.phase.status === "unlocked"
                   && lock.state.phase.lastEnd === reason,
                   "1: " + label + " unlocks (" + reason + ")");
        };
        unlocks("logind's Unlock", locked(), { type: "unlockRequested", source: "logind" }, "logind");
        unlocks("the Escape key at an awake prompt", locked().send(activity()), key("s1", "Escape"), "escape");
        unlocks("the compositor ending the lock", locked(), finished(), "compositor");
        unlocks("the compositor refusing the lock", locking(), finished(), "denied");
        unlocks("a fingerprint accepted", locked(), pamCompleted("fingerprint", "success"), "authenticated");
        unlocks("a security key accepted", locked(), pamCompleted("u2f", "success"), "authenticated");
        const unconfirmed = locking();
        for (let attempt = 0; attempt < LockRules.limits.confirmAttempts - 1; attempt++)
            unconfirmed.send(timer("confirm"), 5000);
        unlocks("the compositor never confirming (given up, from locking only)", unconfirmed, timer("confirm"), "unconfirmed");

        const password = locked().sendAll([enter("hunter2"), passwordPrompt(), pamCompleted("password", "success")]);
        assert(has(password.effects, "unlockCompositor", { reason: "authenticated", method: "password" }),
               "1: a password accepted unlocks, naming the method");

        for (const source of ["ipc", "", "escape", "Escape", "sleep", "view", undefined]) {
            const lock = locked();
            const before = lock.state;
            lock.send({ type: "unlockRequested", source: source });
            assert(lock.state === before && lock.ignored.startsWith("unlock source not allowed") && lock.effects.length === 0,
                   "1: unlockRequested from " + JSON.stringify(source) + " is refused, reported, state untouched");
        }
        assertEqual(JSON.stringify(LockRules.unlockSources), "[\"logind\"]",
                    "1: the only unlock by request is logind's; Escape is not a request source");
        assertEqual(LockRules.escapeUnlocks, true,
                    "1: Escape unlocks for now — the one marked case in _key (removing it is deleting that block)");

        const sleepingEscape = locked().send(key("s1", "Escape"));
        assert(sleepingEscape.state.phase.status === "locked" && sleepingEscape.state.prompt.owner === "s1"
               && !has(sleepingEscape.effects, "forwardKey"),
               "1: Escape on a sleeping prompt only wakes it, and is not passed on");
        const ghostEscape = locked().send(activity()).send(key("s9", "Escape"));
        assert(ghostEscape.state.phase.status === "locked" && ghostEscape.ignored === "unknown surface",
               "1: Escape from a surface not known does nothing");
        const otherKeys = locked().send(activity()).sendAll([key("s1", "Enter"), key("s1", "", "x"), press(), activity()]);
        assertEqual(otherKeys.state.phase.status, "locked", "1: no other key, press or activity unlocks");

        const failed = locked().sendAll([pamCompleted("fingerprint", "failed"), pamCompleted("u2f", "maxTries")]);
        assert(failed.state.phase.status === "locked" && !has(failed.all, "unlockCompositor"),
               "1: failed and MaxTries results do not unlock");
        const errored = locked().send(pamCompleted("fingerprint", "bogus"));
        assert(errored.state.phase.status === "locked" && errored.state.passive.fingerprint.lastResult === "error",
               "1: an unknown PAM result counts as an error, never as success");

        // Plain lockRequested: the lock and its announcement come first, in that order
        const plain = started().send({ type: "lockRequested", source: "ipc" });
        assert(plain.effects[0].type === "lockCompositor" && plain.effects[0].session === 1
               && plain.effects[1].type === "announceLocked" && plain.effects[1].locked === true,
               "1: lockRequested: lockCompositor (session 1), then announceLocked(true), first: " + JSON.stringify(types(plain.effects)));
        assert(has(plain.effects, "detectMethods") && has(plain.effects, "startTimer", { name: "confirm", ms: 5000 }),
               "1: … and asks for the methods, and waits for the compositor's word a bounded time");
    }

    // ---- 2. Stale events are ignored ----

    function _behaviour2StaleIgnored() {
        // A round that failed and started again: the first conversation's success is stale
        const lock = locked();
        const first = conversationOf(lock.state, "fingerprint");
        lock.sendAll([pamCompleted("fingerprint", "failed"), timer("retry:fingerprint")]);
        assert(conversationOf(lock.state, "fingerprint") !== first && conversationOf(lock.state, "fingerprint") !== -1,
               "2: the retry is a new conversation");
        const before = lock.state;
        lock.send({ type: "pamCompleted", method: "fingerprint", conversation: first, result: "success" });
        assert(lock.state === before && lock.ignored === "stale conversation", "2: a success from an older conversation is ignored");
        lock.send({ type: "pamMessage", method: "fingerprint", conversation: first, message: "Swipe", messageIsError: false });
        assertEqual(lock.ignored, "stale conversation", "2: a message from an older conversation is ignored");

        // Ids compared strictly: nothing that only looks like the current id passes
        const current = conversationOf(lock.state, "fingerprint");
        for (const forged of [String(current), [current], { valueOf: () => current, toString: () => String(current) }, current + 0.5, null, undefined]) {
            const forgedBefore = lock.state;
            lock.send({ type: "pamCompleted", method: "fingerprint", conversation: forged, result: "success" });
            assert(lock.state === forgedBefore && lock.state.phase.status === "locked" && lock.ignored === "stale conversation",
                   "2: a conversation id " + (Array.isArray(forged) ? "array" : typeof forged) + " " + JSON.stringify(forged)
                   + " is not the current id " + current);
        }

        // A success that arrives after the abort that a prompt time-out made
        const asked = locked(passwordOnly).sendAll([enter("pw"), passwordPrompt(), passwordPrompt("Verification code: ")]);
        const askedId = conversationOf(asked.state, "password");
        asked.send(timer("prompt"), 10000);
        assert(has(asked.effects, "abortPam", { method: "password", conversation: askedId }), "2: (the time-out aborted the question)");
        asked.send({ type: "pamCompleted", method: "password", conversation: askedId, result: "success" });
        assert(asked.state.phase.status === "locked" && asked.ignored === "method not running",
               "2: a success after an abort is ignored");

        // A success from the previous lock, after unlock and lock again
        const relock = locked();
        const old = conversationOf(relock.state, "fingerprint");
        relock.sendAll([{ type: "unlockRequested", source: "logind" }, { type: "lockRequested", source: "ipc" },
                        added("s2"), confirmed(), detected(allLines)]);
        relock.send({ type: "pamCompleted", method: "fingerprint", conversation: old, result: "success" });
        assert(relock.state.phase.status === "locked" && relock.ignored === "stale conversation",
               "2: a success from the previous lock's conversation is ignored after a relock");

        const idle = locked();
        idle.send({ type: "pamCompleted", method: "password", conversation: 1, result: "success" });
        assertEqual(idle.ignored, "method not running", "2: a completion for a method not running is ignored");
        idle.send({ type: "pamCompleted", method: "smartcard", conversation: 1, result: "success" });
        assertEqual(idle.ignored, "unknown method", "2: a completion for a method there is not is ignored");

        // The session check stands even should an id ever match across sessions
        const crafted = locked();
        const forgedState = Object.assign({}, crafted.state, { phase: Object.assign({}, crafted.state.phase, { session: 99 }) });
        const result = LockRules.step(forgedState, { type: "pamCompleted", method: "fingerprint",
                                                     conversation: conversationOf(forgedState, "fingerprint"), result: "success" }, 1);
        assertEqual(result.ignored, "stale session", "2: a conversation of another session is ignored by its session number");

        // The compositor's word about an earlier session (Quickshell emits secureStateChanged
        // synchronously inside the unlock) does not touch the next lock
        const next = locked().sendAll([{ type: "unlockRequested", source: "logind" }, { type: "lockRequested", source: "idle" }]);
        assert(next.effects[0].type === "lockCompositor" && next.effects[0].session === 2,
               "2: (the next lock is session 2)");
        next.send({ type: "compositorFinished", session: 1 });
        assert(next.state.phase.status === "locking" && next.ignored === "stale session",
               "2: a compositorFinished of the previous session does not end the next lock");
        next.send({ type: "compositorLocked", session: 1 });
        assert(next.state.phase.status === "locking" && next.ignored === "stale session",
               "2: nor does its compositorLocked confirm it");
        next.send({ type: "compositorFinished" });
        assertEqual(next.ignored, "stale session", "2: a compositor event without a session counts for none");
        next.send({ type: "compositorLocked", session: 2 });
        assertEqual(next.state.phase.status, "locked", "2: the current session's word counts");
    }

    // ---- 3. Leaving the lock leaves nothing behind ----

    // A lock with everything going: passive methods running and backing off, a password
    // typed and held, the prompt awake, timers
    function _busyLock() {
        return locked().sendAll([
            activity(),
            pamCompleted("u2f", "failed"),
            key("s1", "", "x"),
            submit("secret-typed")
        ]);
    }

    function _behaviour3LeavingCleansUp() {
        const routes = [
            ["logind", { type: "unlockRequested", source: "logind" }],
            ["Escape", key("s1", "Escape")],
            ["the compositor", finished()],
            ["a fingerprint", pamCompleted("fingerprint", "success")],
            ["the password", pamCompleted("password", "success")]
        ];
        for (const [label, event] of routes) {
            const lock = _busyLock();
            assert(lock.state.secret !== null && LockRules.running(lock.state).lockTimers.length >= 2
                   && LockRules.running(lock.state).conversations.length >= 2,
                   "3: (the busy lock holds a secret, runs conversations and timers) — " + label);
            const conversations = LockRules.running(lock.state).conversations;
            const timers = LockRules.running(lock.state).lockTimers;
            lock.send(event);
            assert(conversations.every(c => has(lock.effects, "abortPam", { method: c.method, conversation: c.conversation })
                                       || (label === "a fingerprint" && c.method === "fingerprint")
                                       || (label === "the password" && c.method === "password")),
                   "3: leaving by " + label + " aborts every other conversation");
            assert(timers.every(name => has(lock.effects, "stopTimer", { name: name })),
                   "3: leaving by " + label + " stops every timer of the lock");
            assert(nothingRunning(lock.state) && lock.state.password.status === "idle"
                   && lock.state.prompt.owner === null && lock.state.methods.status === "unknown",
                   "3: leaving by " + label + " leaves nothing running, no secret, fresh regions");
            const order = types(lock.effects);
            const unlockAt = order.indexOf("unlockCompositor");
            assert(order.lastIndexOf("abortPam") < unlockAt && order.lastIndexOf("stopTimer") < unlockAt
                   && order.indexOf("announceLocked") > unlockAt,
                   "3: by " + label + ": aborts and stops first, then unlockCompositor, then announceLocked");
            assertEqual(of(lock.effects, "unlockCompositor")[0].session, 1, "3: by " + label + ": unlockCompositor names the session");
        }

        // logind's Unlock while the password is merely pending (typed before the methods were known)
        const pending = locking().sendAll([confirmed(), enter("early"), { type: "unlockRequested", source: "logind" }]);
        assert(pending.state.secret === null && nothingRunning(pending.state), "3: a pending secret is dropped on unlock");

        // During a suspend the sleep region's timers stay, the lock's go
        const suspended = locked().sendAll([{ type: "prepareForSleep" }, { type: "unlockRequested", source: "logind" }]);
        assert(nothingRunning(suspended.state) && "missedResume" in suspended.state.timers,
               "3: an unlock while suspending keeps the sleep timers, nothing of the lock");

        // The lock ending while the inhibitor waits for it (going down, not yet confirmed):
        // there is nothing to wait for, the machine may go
        for (const [label, event] of [["logind's Unlock", { type: "unlockRequested", source: "logind" }],
                                      ["the compositor's refusal", finished()],
                                      ["Escape", [activity(), key("s1", "Escape")]]]) {
            const down = started().sendAll([{ type: "prepareForSleep" }, added("s1")]);
            assert(down.state.sleep.inhibitor === "held" && down.state.phase.status === "locking",
                   "3: (going down, the inhibitor held for the lock) — " + label);
            down.send(event);
            assert(down.state.phase.status === "unlocked" && down.state.sleep.inhibitor === "released"
                   && has(down.all.slice(-12), "releaseInhibitor") && !("inhibitor" in down.state.timers),
                   "3: the lock ended during a suspend by " + label + ": the inhibitor is released at once");
        }
    }

    // THE regression: lock → authenticate → unlock → lock again behaves as the first lock,
    // apart from the session number and the fresh ids
    function _behaviour3SecondLockEqualsFirst() {
        const sequence = [
            { type: "lockRequested", source: "ipc" },
            added("s1"),
            confirmed(),
            detected(allLines),
            activity(),
            submit("correct horse"),
            passwordPrompt(),
            pamCompleted("password", "success")
        ];
        const lock = started();
        const runOnce = () => {
            const base = lock.now;
            const steps = [];
            for (const event of sequence) {
                lock.send(event);
                steps.push(_normalised({ state: LockRules.describe(lock.state), effects: lock.effects.map(LockRules.describeEffect) }, base));
            }
            return steps;
        };
        const unlockedBefore = _normalised(LockRules.describe(lock.state), lock.now);
        const first = runOnce();
        lock.now += 3600000;
        const unlockedAfter = _normalised(LockRules.describe(lock.state), lock.now);
        const second = runOnce();
        let same = true;
        for (let i = 0; i < sequence.length; i++) {
            if (JSON.stringify(first[i]) !== JSON.stringify(second[i])) {
                same = false;
                fail("3: the second lock differs from the first at step " + i + ": " + JSON.stringify(first[i]) + " vs " + JSON.stringify(second[i]));
            }
        }
        assert(same, "3: lock → authenticate → unlock → lock again: same states and effects as the first lock");
        assert(lock.state.phase.session === 2, "3: … with the session number one more");
        assert(JSON.stringify(Object.assign({}, unlockedBefore, { phase: null }))
               === JSON.stringify(Object.assign({}, unlockedAfter, { phase: null })),
               "3: the state after an unlock is the state before the first lock (phase aside)");
        assert(second[3].effects.filter(effect => effect.type === "startPam").length === 2,
               "3: the second lock arms: both passive methods start once the methods are known");
    }

    // Ids and session numbers renamed by order of appearance, times made relative: what
    // is left must match exactly
    function _normalised(value, base) {
        const sessions = new Map();
        const ids = new Map();
        const rename = (map, number) => {
            if (!map.has(number))
                map.set(number, "#" + map.size);
            return map.get(number);
        };
        return JSON.parse(JSON.stringify(value, (key, item) => {
            if (key === "serial")
                return "serial";
            if (key === "message" && typeof item === "string")
                return item.replace(/session \d+/, "session #");
            if (typeof item !== "number")
                return item;
            if (key === "session")
                return rename(sessions, item);
            if (["conversation", "token", "generation", "id"].includes(key))
                return rename(ids, item);
            if (["due", "since", "deadline", "awakeUntil", "startedAt"].includes(key))
                return item - base;
            return item;
        }));
    }

    // ---- 4. Input before the methods are known, failures visible ----

    function _behaviour4InputBeforeMethods() {
        const lock = locking().send(confirmed());
        lock.send(activity());
        const epoch = lock.state.prompt.fieldEpoch;
        lock.send(submit("early bird"));
        assert(lock.state.password.status === "pending" && lock.state.secret === "early bird" && !has(lock.effects, "startPam"),
               "4: typed before the methods are known: held, nothing started");
        assert(lock.state.prompt.fieldEpoch === epoch + 1 && lock.state.password.refusal === "",
               "4: … and the input counts as taken (the field empties)");
        assertEqual(LockRules.view(lock.state).buttonText, "Verifying…", "4: … the view says it is being verified");
        lock.send(detected(allLines));
        const start = of(lock.effects, "startPam", { method: "password" })[0];
        assert(start !== undefined && start.configDirectory === "/etc/pam.d" && start.config === "h2s-shell-password",
               "4: the conversation starts when the methods are known, with the detected config");
        lock.send(passwordPrompt());
        assert(has(lock.effects, "respondPam", { method: "password", text: "early bird" }) && lock.state.secret === null,
               "4: the held text answers the first prompt, and is dropped from the state");

        const whileLocking = locking().sendAll([enter("fast"), detected(passwordOnly)]);
        assert(whileLocking.state.password.status === "pending" && !has(whileLocking.all, "startPam"),
               "4: before the compositor confirms the lock nothing starts");
        whileLocking.send(confirmed());
        assert(has(whileLocking.effects, "startPam", { method: "password" }), "4: … it starts once the lock is confirmed");

        const failed = locking().sendAll([confirmed(), enter("pw")]);
        failed.send(state => ({ type: "methodsFailed", generation: state.methods.generation, reason: "exited 1" }));
        assert(has(failed.effects, "startPam", { method: "password", configDirectory: "/shell/pam", config: "password" })
               && has(failed.effects, "log", { level: "warning" }),
               "4: detection failing falls back to the password fallback, and says so");
        assert(of(failed.effects, "log", { level: "warning" })[0].message.includes("the fallback")
               && !of(failed.effects, "log", { level: "warning" })[0].message.includes("last answer"),
               "4: … naming the fallback, not a last answer there was not: " + of(failed.effects, "log", { level: "warning" })[0].message);

        const timedOut = locking().sendAll([confirmed(), enter("pw")]);
        timedOut.send(timer("detect"), 5000);
        assert(has(timedOut.effects, "startPam", { method: "password", config: "password" }),
               "4: detection timing out falls back to the password fallback");
        timedOut.send(state => ({ type: "methodsDetected", generation: state.methods.generation, lines: allLines }));
        assertEqual(timedOut.ignored, "stale detection", "4: … and its late answer is ignored");

        const nothing = locking({ lockOnSleep: true, passwordFallback: null }).sendAll([confirmed(), enter("pw"), timer("detect")]);
        assert(nothing.state.password.status === "unavailable" && nothing.state.secret === null
               && LockRules.view(nothing.state).error === "Password check is not available" && !LockRules.view(nothing.state).busy,
               "4: no config at all: a visible error, never a permanent \"verifying\"");

        // Known methods without a password config: asked again before saying so
        const askAgain = locked([], { lockOnSleep: true, passwordFallback: null }).sendAll([activity(), detected([]), submit("pw")]);
        assert(askAgain.state.password.status === "pending" && has(askAgain.effects, "detectMethods"),
               "4: a password submitted with no password config known asks the methods script again");
        askAgain.send(detected(passwordOnly));
        assert(has(askAgain.effects, "startPam", { method: "password", config: "h2s-shell-password" }),
               "4: … and a config that turned up serves");
        const stillNone = locked([], { lockOnSleep: true, passwordFallback: null }).sendAll([activity(), detected([]), submit("pw"), detected([])]);
        assert(stillNone.state.password.status === "unavailable" && stillNone.state.secret === null,
               "4: … else the error shows");

        const noPasswordLine = locked(["fingerprint\t/etc/pam.d\th2s-shell-fingerprint"]).sendAll(enter("pw"));
        assert(has(noPasswordLine.effects, "startPam", { method: "password", configDirectory: "/shell/pam" }),
               "4: detection naming no password config: the fallback serves");

        const refused = locked().sendAll(enter("pw"));
        refused.send(submit("again"));
        assertEqual(refused.state.password.refusal, "busy", "4: (a submit while verifying: busy)");
        refused.send(state => ({ type: "pamStartFailed", method: "password", conversation: conversationOf(state, "password") }));
        assert(refused.state.password.status === "unavailable" && refused.state.password.conversation === null
               && LockRules.view(refused.state).error === "Password check could not start" && !LockRules.view(refused.state).busy
               && refused.state.secret === null && LockRules.view(refused.state).refusal === "",
               "4: a refused start() ends in a visible \"unavailable\" error, nothing left running, no stale refusal");
        refused.send(submit("pw again"));
        assert(has(refused.effects, "startPam", { method: "password" }), "4: … and the next submit tries again");

        const fpRefused = locked().send(state => ({ type: "pamStartFailed", method: "fingerprint",
                                                    conversation: conversationOf(state, "fingerprint") }));
        assert(fpRefused.state.passive.fingerprint.status === "broken" && fpRefused.state.passive.fingerprint.conversation === null,
               "4: a passive method's refused start leaves it broken, not running");

        const busy = locked().sendAll(enter("first"));
        const epochBusy = busy.state.prompt.fieldEpoch;
        busy.send(submit("second"));
        assert(busy.state.password.refusal === "busy" && busy.state.prompt.fieldEpoch === epochBusy
               && !has(busy.effects, "startPam") && !has(busy.effects, "respondPam"),
               "4: a second submit while verifying is refused with a reason, the field not emptied");
        assertEqual(LockRules.view(busy.state).refusal, "busy", "4: … the view has the reason");
        busy.send(pamCompleted("password", "failed"));
        assert(LockRules.view(busy.state).error === "Authentication failed" && LockRules.view(busy.state).refusal === "",
               "4: … and it is cleared when the verification ends: \"Authentication failed\" alone");

        const empty = locked().sendAll(enter(""));
        assert(empty.state.password.refusal === "empty" && empty.state.password.status === "idle" && !has(empty.effects, "startPam"),
               "4: an empty password is never sent (nullok; an Enter right after waking)");
    }

    // ---- 5. PAM facts ----

    function _behaviour5PamFacts() {
        const lock = locked(passwordOnly).sendAll([enter("pw"), passwordPrompt()]);
        assertEqual(of(lock.all, "respondPam").length, 1, "5: the password answers its prompt once");
        lock.send(passwordPrompt("Verification code: "));
        assert(!has(lock.effects, "respondPam") && lock.state.password.status === "asking",
               "5: a further prompt is not answered with anything held: it is asked");
        const asking = LockRules.view(lock.state);
        assert(asking.placeholder === "Verification code" && asking.answerVisible === false && !asking.busy,
               "5: the view shows the question, answer hidden as PAM asked");
        lock.send(submit("123456"));
        assert(has(lock.effects, "respondPam", { text: "123456" }) && lock.state.password.status === "verifying",
               "5: the next submit answers the question");
        lock.send(submit("654321"));
        assert(!has(lock.effects, "respondPam") && lock.state.password.refusal === "busy",
               "5: at most one answer per prompt: a second submit is refused");
        lock.send(pamCompleted("password", "success"));
        assert(lock.state.phase.status === "unlocked", "5: password and code accepted: unlocked");

        const visible = locked(passwordOnly).sendAll([enter("pw"),
                                                      pamMessage("password", { message: "Username:", responseRequired: true, responseVisible: true })]);
        assert(!has(visible.effects, "respondPam") && visible.state.secret === null && visible.state.password.answerVisible,
               "5: a prompt that shows its answer is no password prompt: the password is dropped, the question asked");

        const pamSays = locked(passwordOnly).sendAll([enter("pw"), passwordPrompt(),
                                                      pamMessage("password", { message: "Account locked for 10 minutes", messageIsError: true }),
                                                      pamCompleted("password", "failed")]);
        assert(pamSays.state.password.status === "failed" && LockRules.view(pamSays.state).error === "Account locked for 10 minutes",
               "5: a failure shows what PAM said when it said why");
        const maxTries = locked(passwordOnly).sendAll([enter("pw"), pamCompleted("password", "maxTries")]);
        assertEqual(maxTries.state.password.error, "Too many attempts", "5: MaxTries says so");
        const plain = locked(passwordOnly).sendAll([enter("pw"), pamCompleted("password", "failed")]);
        assertEqual(plain.state.password.error, "Authentication failed", "5: a plain failure");
        const errored = locked(passwordOnly).sendAll([enter("pw"), pamCompleted("password", "error")]);
        assert(errored.state.password.status === "unavailable" && errored.state.password.error === "Password check is not available",
               "5: an Error result: the password check is unavailable, said so");

        // A passive method's Error (Quickshell: every code but success/auth error/max tries,
        // a device not plugged in included) waits long and tries again; broken only after
        // several in a row
        const keyLock = locked();
        keyLock.send(pamCompleted("u2f", "error"));
        assert(keyLock.state.passive.u2f.status === "backoff" && has(keyLock.effects, "startTimer", { name: "retry:u2f", ms: 30000 }),
               "5: a passive method's Error: a long backoff (30 s), not broken");
        assertEqual(LockRules.view(keyLock.state).methods[1].text, "Security key not available, trying again later",
                    "5: … and the view says so");
        keyLock.send(activity(), 30000);
        assert(has(keyLock.effects, "startPam", { method: "u2f" }), "5: an eager method is tried again when somebody comes back");
        for (let i = 2; i < LockRules.limits.errorLimit; i++) {
            keyLock.send(pamCompleted("u2f", "error"), 100);
            keyLock.send(timer("retry:u2f"), 30000);
        }
        assertEqual(keyLock.state.passive.u2f.errors, LockRules.limits.errorLimit - 1, "5: (four Errors in a row)");
        keyLock.send(pamCompleted("u2f", "error"), 100);
        assert(keyLock.state.passive.u2f.status === "broken" && !("retry:u2f" in keyLock.state.timers)
               && LockRules.view(keyLock.state).methods[1].text === "Security key cannot be used",
               "5: the " + LockRules.limits.errorLimit + "th Error in a row: broken for the lock");
        keyLock.sendAll([timer("prompt"), activity()], 10000);
        assert(has(keyLock.effects, "startPam", { method: "u2f" }),
               "5: an eager method broken by Errors gets one more try each time somebody comes back (the key plugged in now)");
        keyLock.send(pamCompleted("u2f", "error"));
        assertEqual(keyLock.state.passive.u2f.status, "broken", "5: … broken again at once by the next Error");

        const resets = locked().sendAll([pamCompleted("fingerprint", "error"), timer("retry:fingerprint")], 30000);
        resets.sendAll([pamCompleted("fingerprint", "failed")], 100);
        assertEqual(resets.state.passive.fingerprint.errors, 0, "5: a round that ends otherwise resets the Error count");

        const fingerprintErrors = locked();
        for (let i = 0; i < LockRules.limits.errorLimit; i++)
            fingerprintErrors.sendAll([pamCompleted("fingerprint", "error"), timer("retry:fingerprint")], 30000);
        assertEqual(fingerprintErrors.state.passive.fingerprint.status, "broken", "5: the fingerprint too, after the same count");
        fingerprintErrors.sendAll([activity(), timer("prompt"), activity()], 10000);
        assertEqual(fingerprintErrors.state.passive.fingerprint.status, "broken", "5: … and, not eager, it stays broken for the lock");
        fingerprintErrors.sendAll([{ type: "prepareForSleep" }, { type: "resumed" }]);
        assert(fingerprintErrors.state.passive.fingerprint.status !== "broken" && fingerprintErrors.state.passive.fingerprint.errors === 0,
               "5: a wake from sleep clears it");
        fingerprintErrors.send(detected(allLines));
        fingerprintErrors.send(timer("settle:u2f"));
        assert(has(fingerprintErrors.all.slice(-8), "startPam", { method: "fingerprint" }), "5: … and it is started again after the new detection");

        // A passive method asked for input stops, broken; never answers an empty string
        const asks = locked();
        const fp = conversationOf(asks.state, "fingerprint");
        asks.send(pamMessage("fingerprint", { message: "Password: ", responseRequired: true }));
        assert(!has(asks.all, "respondPam") && has(asks.effects, "abortPam", { method: "fingerprint", conversation: fp })
               && asks.state.passive.fingerprint.status === "broken",
               "5: a passive method asked for input is stopped and marked broken at once, never answered");
        const asksKey = locked().send(pamMessage("u2f", { message: "PIN: ", responseRequired: true }));
        asksKey.sendAll([timer("settle:u2f"), activity()], 1000);
        assert(asksKey.state.passive.u2f.status === "broken" && !has(asksKey.effects, "startPam", { method: "u2f" }),
               "5: … and an eager one asking is not retried when somebody comes back");

        // Never started again in the step that aborts it: the restart waits for its settle timer
        const settle = locked().sendAll([{ type: "prepareForSleep" }, { type: "resumed" }, detected(allLines)]);
        assert(!has(settle.effects, "startPam"), "5: aborted for the sleep: not started at once after the wake's detection");
        settle.send(timer("settle:fingerprint"), 1000);
        assert(has(settle.effects, "startPam", { method: "fingerprint" }) && !has(settle.effects, "abortPam"),
               "5: … but when its settle timer has run, in a step that aborts nothing");

        const info = locked().send(pamMessage("fingerprint", { message: "Place your finger on the reader" }));
        assertEqual(LockRules.view(info.state).methods[0].text, "Place your finger on the reader",
                    "5: a passive method shows what PAM says while it waits");

        // The password restarts after a cancelled question: abort → settle → start
        const cancelled = locked(passwordOnly).sendAll([enter("pw"), passwordPrompt(), passwordPrompt("Code:")]);
        cancelled.send(timer("prompt"), 10000);
        assert(has(cancelled.effects, "abortPam", { method: "password" }) && cancelled.state.password.settling
               && "settle:password" in cancelled.state.timers,
               "5: a cancelled question aborts the conversation, which settles");
        cancelled.sendAll(enter("pw2"));
        assert(cancelled.state.password.status === "pending" && !has(cancelled.effects, "startPam"),
               "5: a password typed meanwhile waits for the settle");
        cancelled.send(timer("settle:password"), 1000);
        assert(has(cancelled.effects, "startPam", { method: "password" }) && cancelled.state.password.status === "verifying"
               && !cancelled.state.password.settling,
               "5: … and starts when it has settled");
        cancelled.sendAll([passwordPrompt(), pamCompleted("password", "success")]);
        assertEqual(cancelled.state.phase.status, "unlocked", "5: … and unlocks");
    }

    // ---- 6. The prompt ----

    function _behaviour6Prompt() {
        const two = locked().send(added("s2", "HDMI-A-1"));
        two.send(activity("s1"));
        assert(two.state.prompt.owner === "s1" && has(two.effects, "startTimer", { name: "prompt", ms: 10000 }),
               "6: activity wakes the prompt on its surface");
        assert(LockRules.view(two.state).promptSurface === "s1" && LockRules.view(two.state).promptScreen === "DP-1",
               "6: the view names the surface showing the prompt, and its screen");
        const deadline = two.state.prompt.awakeUntil;
        two.send(activity("s2"), 500);
        assert(two.state.prompt.owner === "s1" && two.state.prompt.awakeUntil === deadline + 500
               && two.effects.filter(effect => effect.type === "startTimer").length === 0,
               "6: activity on another surface keeps the prompt where it is, moves the deadline, restarts no timer");
        two.send(key("s2", "", "q"));
        assert(has(two.effects, "forwardKey", { surface: "s1", text: "q" }), "6: a key on another surface goes to the owner's field");
        two.send(submit("from the owner"));
        assertEqual(two.ignored, "", "6: (the owner's field submits)");
        const stray = locked().sendAll([added("s2", "HDMI-A-1"), activity("s1")]);
        stray.send({ type: "submit", surface: "s2", text: "pw" });
        assert(stray.ignored === "not the prompt's surface" && stray.state.secret === null,
               "6: a submit from a surface that does not show the prompt is ignored");
        const asleepSubmit = locked().send({ type: "submit", surface: "s1", text: "pw" });
        assertEqual(asleepSubmit.ignored, "prompt asleep", "6: … as is one while the prompt sleeps");

        for (const name of ["Enter", "Backspace"]) {
            const fresh = locked().send(key("s1", name, name === "Enter" ? "\r" : "\b"));
            const forwarded = of(fresh.effects, "forwardKey")[0];
            assert(fresh.state.prompt.owner === "s1" && forwarded !== undefined && forwarded.surface === "s1"
                   && forwarded.key === name && forwarded.text === "",
                   "6: " + name + " that wakes the prompt is not lost: forwarded to the field (its control character dropped)");
        }
        const wakeKey = locked().send(added("s2", "HDMI-A-1"));
        wakeKey.send(key("s2", "", "a"));
        assert(wakeKey.state.prompt.owner === "s2" && has(wakeKey.effects, "forwardKey", { surface: "s2", text: "a" }),
               "6: a key on any surface wakes the prompt there, and the key goes in");
        const character = locked().send(key("s1", "A", "a"));
        const characterForward = of(character.effects, "forwardKey")[0];
        assert(characterForward.key === "" && characterForward.text === "a",
               "6: a key named by a character is taken as text only (the key name dropped)");
        const control = locked().send(key("s1", "", "\u0001"));
        assert(!has(control.effects, "forwardKey") && control.state.prompt.owner === "s1",
               "6: a key with neither a known name nor printable text wakes the prompt and is not forwarded");

        // A press moves the prompt (the owner's decision); keys and motion do not
        const moving = locked(passwordOnly).sendAll([added("s2", "HDMI-A-1"), activity("s1")]);
        const epoch = moving.state.prompt.fieldEpoch;
        moving.send(press("s2"));
        assert(moving.state.prompt.owner === "s2" && moving.state.prompt.fieldEpoch === epoch + 1,
               "6: a press on another surface brings the prompt there, its field empty");
        moving.send(press("s2"));
        assertEqual(moving.state.prompt.fieldEpoch, epoch + 1, "6: a press on the owner changes nothing but the time");
        moving.sendAll([submit("pw"), passwordPrompt(), passwordPrompt("Code:")]);
        moving.send(press("s1"));
        assert(moving.state.prompt.owner === "s1" && moving.state.password.status === "asking"
               && LockRules.view(moving.state).placeholder === "Code",
               "6: a question moves with the prompt");
        moving.send(submit("123"));
        moving.send(press("s2"));
        assert(moving.state.password.status === "verifying" && !has(moving.effects, "abortPam"),
               "6: a verification in progress is not aborted by a move");
        moving.send(key("s1", "", "z"));
        assert(moving.state.prompt.owner === "s2" && has(moving.effects, "forwardKey", { surface: "s2" }),
               "6: keys elsewhere still go to the owner");

        // Time-out: re-armed while there was activity, then the prompt sleeps
        const timeout = locked().send(activity());
        timeout.send(activity(), 6000);
        timeout.send(timer("prompt"), 4000);
        assert(timeout.state.prompt.owner === "s1" && has(timeout.effects, "startTimer", { name: "prompt", ms: 6000 }),
               "6: the time-out re-arms for what is left after recent activity");
        const sleepEpoch = timeout.state.prompt.fieldEpoch;
        timeout.send(timer("prompt"), 6000);
        assert(timeout.state.prompt.owner === null && timeout.state.prompt.fieldEpoch === sleepEpoch + 1,
               "6: after its time without activity the prompt sleeps and its field empties");
        const early = locked().send(activity());
        early.send(timer("prompt"), 9970);
        assertEqual(early.state.prompt.owner, null, "6: a timer firing a little early counts as on time");
        const clockBack = locked().send(activity());
        clockBack.send(timer("prompt"), -3600000 + 10000);
        const rearm = of(clockBack.effects, "startTimer", { name: "prompt" })[0];
        assert(rearm !== undefined && rearm.ms <= 10000 && clockBack.state.prompt.awakeUntil <= clockBack.now + 10000,
               "6: the wall clock set back an hour: the time-out re-arms for at most its own length ("
               + (rearm ? rearm.ms : "none") + " ms)");
        clockBack.send(timer("prompt"), 10000);
        assertEqual(clockBack.state.prompt.owner, null, "6: … and the prompt then sleeps");

        const question = locked(passwordOnly).sendAll([enter("pw"), passwordPrompt(), passwordPrompt("Code:")]);
        question.send(timer("prompt"), 10000);
        assert(has(question.effects, "abortPam", { method: "password" }) && question.state.password.status === "idle"
               && question.state.password.question === "",
               "6: the time-out cancels a question left unanswered");

        const verifying = locked(passwordOnly).sendAll([enter("pw"), passwordPrompt()]);
        verifying.send(timer("prompt"), 10000);
        assert(!has(verifying.effects, "abortPam") && verifying.state.password.status === "verifying" && verifying.state.prompt.owner === null,
               "6: the time-out hides the prompt but never aborts a verification in progress");
        verifying.send(pamCompleted("password", "success"));
        assert(verifying.state.phase.status === "unlocked", "6: … which still unlocks when it succeeds");
        const pending = locking().sendAll([confirmed(), enter("pw"), timer("prompt")], 10000);
        assert(pending.state.password.status === "pending" && pending.state.secret === "pw",
               "6: nor a password waiting for the methods");

        const failedThenSleep = locked(passwordOnly).sendAll([enter("pw"), pamCompleted("password", "failed")]);
        assertEqual(LockRules.view(failedThenSleep.state).error, "Authentication failed", "6: (failed)");
        failedThenSleep.send(timer("prompt"), 10000);
        assert(failedThenSleep.state.password.status === "idle" && LockRules.view(failedThenSleep.state).error === "",
               "6: the prompt waking again starts clean");

        const methodsView = LockRules.view(locked().state);
        assert(methodsView.methods !== LockRules.view(locked().state).methods && Array.isArray(methodsView.methods),
               "6: view().methods is a fresh array each time (feed it through a ScriptModel)");
    }

    // Surfaces are instances: a screen's new surface may report itself before the old one's
    // removal (Quickshell's deleteLater)
    function _behaviour6Surfaces() {
        const reAdded = locked().send(added("s2", "DP-1"));
        assert(reAdded.ignored === "" && reAdded.state.prompt.surfaces.length === 2,
               "6s: a second instance on the same screen is taken (the old one not yet destroyed)");
        reAdded.send(removed("s1"));
        assert(reAdded.ignored === "" && reAdded.state.prompt.surfaces.length === 1 && reAdded.state.prompt.surfaces[0].id === "s2",
               "6s: the old instance's removal removes only it");
        reAdded.send(activity("s2"));
        reAdded.send(key("s2", "", "k"));
        assert(reAdded.ignored === "" && reAdded.state.prompt.owner === "s2" && has(reAdded.effects, "forwardKey", { surface: "s2" }),
               "6s: … and the screen keeps taking input (the lock-out by screen name)");

        const handover = locked().sendAll([added("s2", "HDMI-A-1"), activity("s1"), added("s3", "DP-1")]);
        const epoch = handover.state.prompt.fieldEpoch;
        handover.send(removed("s1"));
        assert(handover.state.prompt.owner === "s3" && handover.state.prompt.fieldEpoch === epoch + 1,
               "6s: the owner going away hands the prompt to its successor on the same screen (the newer instance)");
        handover.send(removed("s3"));
        assertEqual(handover.state.prompt.owner, "s2", "6s: … else to the first surface left");
        handover.send(removed("s2"));
        assert(handover.state.prompt.owner === null && !("prompt" in handover.state.timers), "6s: the last surface going away puts the prompt to sleep");
        handover.sendAll([added("s4", "DP-1"), activity("s4")]);
        assertEqual(handover.state.prompt.owner, "s4", "6s: a surface that comes back gets a working prompt");

        const keep = locked().sendAll([added("s2", "HDMI-A-1"), added("s3", "eDP-1"), activity("s2")]);
        const keepEpoch = keep.state.prompt.fieldEpoch;
        keep.send(removed("s3"));
        assert(keep.state.prompt.owner === "s2" && keep.state.prompt.fieldEpoch === keepEpoch,
               "6s: removing a surface that does not own the prompt leaves the owner and its field alone");
        keep.send(removed("s1"));
        assertEqual(keep.state.prompt.owner, "s2", "6s: … whichever it is");

        const relock = locked().sendAll([{ type: "unlockRequested", source: "logind" }, { type: "lockRequested", source: "idle" },
                                         added("s2", "DP-1"), removed("s1"), confirmed(), detected(allLines), activity("s2")]);
        assert(relock.state.prompt.owner === "s2" && relock.state.prompt.surfaces.length === 1,
               "6s: unlock and lock in one pass: the old surface's late removal does not touch the new one");

        const ghost = locked().send(activity("s9"));
        assert(ghost.ignored === "unknown surface" && ghost.state.prompt.owner === null, "6s: input from a surface not known is ignored");
        const dup = locked().send(added("s1", "HDMI-A-1"));
        assertEqual(dup.ignored, "surface already known", "6s: a surface reported twice counts once");
        const noId = locked().send({ type: "surfaceAdded", screen: "DP-1" });
        assertEqual(noId.ignored, "no surface", "6s: a surface without an id is refused");

        const questionMoves = locked(passwordOnly).sendAll([added("s2", "HDMI-A-1"), enter("pw"), passwordPrompt(), passwordPrompt("Code:"),
                                                            removed("s1")]);
        assert(questionMoves.state.password.status === "asking" && questionMoves.state.prompt.owner === "s2",
               "6s: a question survives its surface going away: it moves with the prompt");
    }

    // ---- 7. Sleep ----

    function _behaviour7Sleep() {
        const unlocked = started();
        assert(has(unlocked.effects, "holdInhibitor"), "7: the inhibitor is held from the start with lockOnSleep");
        unlocked.send({ type: "prepareForSleep" });
        assert(has(unlocked.effects, "lockCompositor") && has(unlocked.effects, "startTimer", { name: "inhibitor" })
               && !has(unlocked.effects, "releaseInhibitor"),
               "7: going to sleep unlocked: locks, and keeps the inhibitor until the compositor confirms");
        assert(unlocked.effects[0].type === "lockCompositor" && unlocked.effects[1].type === "announceLocked",
               "7: … the lock first of all: " + JSON.stringify(types(unlocked.effects)));
        unlocked.send(added("s1"));
        unlocked.send(detected(allLines));
        unlocked.send(confirmed());
        assert(has(unlocked.effects, "releaseInhibitor") && has(unlocked.effects, "stopTimer", { name: "inhibitor" }),
               "7: … released once the lock is confirmed");
        assert(!has(unlocked.all, "startPam"), "7: passive methods are not started while suspending, also when the lock came with it");

        const graceRunning = started().sendAll([{ type: "prepareForSleep" }, { type: "resumed" }, { type: "unlockRequested", source: "logind" }]);
        assert("resumeGrace" in graceRunning.state.timers, "7: (resumeGrace running, unlocked)");
        graceRunning.send({ type: "prepareForSleep" }, 1000);
        assert(graceRunning.effects[0].type === "lockCompositor" && graceRunning.effects[1].type === "announceLocked"
               && has(graceRunning.effects, "stopTimer", { name: "resumeGrace" }),
               "7: the lock comes first also with the sleep region's timers to stop: " + JSON.stringify(types(graceRunning.effects)));

        const fallbackRun = started().send({ type: "prepareForSleep" });
        fallbackRun.send(timer("inhibitor"), 4000);
        assert(has(fallbackRun.effects, "releaseInhibitor") && has(fallbackRun.effects, "log", { level: "warning" }),
               "7: no confirmation: the fallback lets the machine go, and says so");

        // An idle lock still waiting for the compositor when the machine goes down
        const idleLocking = started().send({ type: "lockRequested", source: "idle" });
        idleLocking.send({ type: "prepareForSleep" });
        assert(idleLocking.state.phase.session === 1 && !has(idleLocking.effects, "lockCompositor")
               && has(idleLocking.effects, "startTimer", { name: "inhibitor" }) && idleLocking.state.sleep.inhibitor === "held",
               "7: PrepareForSleep while an idle lock is still locking: no second lock, the inhibitor kept for its confirmation");
        idleLocking.send(confirmed());
        assert(idleLocking.state.phase.status === "locked" && has(idleLocking.effects, "releaseInhibitor"),
               "7: … and released at its confirmation");

        const lockedSleep = locked().send({ type: "prepareForSleep" });
        assert(has(lockedSleep.effects, "releaseInhibitor"), "7: going to sleep already locked: the inhibitor goes at once");
        assert(has(lockedSleep.effects, "abortPam", { method: "fingerprint" }) && has(lockedSleep.effects, "abortPam", { method: "u2f" })
               && lockedSleep.state.passive.fingerprint.status === "paused",
               "7: running passive methods are aborted for the sleep");
        lockedSleep.send(activity(), 1000);
        assert(lockedSleep.state.sleep.status === "suspending" && !has(lockedSleep.effects, "startPam"),
               "7: activity right after PrepareForSleep (the hand closing the lid) is not a wake");
        lockedSleep.send({ type: "resumed" }, 20000);
        assert(has(lockedSleep.effects, "detectMethods") && has(lockedSleep.effects, "holdInhibitor")
               && lockedSleep.state.sleep.status === "resuming",
               "7: resumed: a fresh detection, the inhibitor held again");
        lockedSleep.sendAll([detected(allLines), timer("settle:fingerprint"), timer("settle:u2f")], 1000);
        assert(lockedSleep.state.passive.fingerprint.status === "running" && lockedSleep.state.passive.u2f.status === "running",
               "7: … and the methods running again");

        const missed = locked().send({ type: "prepareForSleep" });
        missed.send(timer("missedResume"), 60000);
        assert(missed.state.sleep.status === "resuming" && has(missed.effects, "detectMethods"),
               "7: no resume signal: after its deadline the lock goes on as awake");
        const byActivity = locked().send({ type: "prepareForSleep" });
        byActivity.send(activity(), 30000);
        assert(byActivity.state.sleep.status === "resuming" && byActivity.state.prompt.owner === "s1"
               && has(byActivity.effects, "detectMethods"),
               "7: … or at the first activity well after going down, which also wakes the prompt");

        // A second PrepareForSleep while still suspending: the wake was missed, this is a new sleep
        const twice = started().sendAll([{ type: "prepareForSleep" }, added("s1"), confirmed()]);
        twice.send({ type: "unlockRequested", source: "logind" }, 3000);
        assert(twice.state.phase.status === "unlocked" && twice.state.sleep.status === "suspending", "7: (unlocked, the resume lost)");
        twice.send({ type: "prepareForSleep" }, 20000);
        assert(twice.ignored === "" && twice.state.phase.status === "locking" && twice.effects[0].type === "lockCompositor"
               && twice.state.sleep.status === "suspending" && has(twice.effects, "log", { level: "warning" }),
               "7: a second PrepareForSleep while suspending locks again (a missed wake, then a new sleep), and says so");
        const twiceLocked = locked().sendAll([{ type: "prepareForSleep" }, { type: "prepareForSleep" }]);
        assert(twiceLocked.ignored === "" && has(twiceLocked.effects, "detectMethods") && twiceLocked.state.sleep.status === "suspending"
               && !has(twiceLocked.effects, "startPam"),
               "7: … and while locked it is the missed wake (a fresh detection) and nothing starts for the new sleep");
        const whileResuming = started().sendAll([{ type: "prepareForSleep" }, added("s1"), confirmed(),
                                                 { type: "resumed" }, { type: "unlockRequested", source: "logind" }]);
        whileResuming.send({ type: "prepareForSleep" });
        assert(whileResuming.state.phase.status === "locking" && whileResuming.state.sleep.status === "suspending",
               "7: a PrepareForSleep while resuming is a new sleep: it locks");

        // resumed without a PrepareForSleep: running conversations may be dead
        const unannounced = locked();
        const fpBefore = conversationOf(unannounced.state, "fingerprint");
        unannounced.send({ type: "resumed" });
        assert(has(unannounced.effects, "abortPam", { method: "fingerprint", conversation: fpBefore }) && has(unannounced.effects, "detectMethods")
               && unannounced.state.sleep.status === "resuming",
               "7: resumed without PrepareForSleep still re-detects and restarts the running methods");
        unannounced.sendAll([detected(allLines), timer("settle:fingerprint")], 1000);
        assert(unannounced.state.passive.fingerprint.status === "running" && conversationOf(unannounced.state, "fingerprint") !== fpBefore,
               "7: … with a new conversation");

        const graceful = locked(passwordOnly).sendAll([{ type: "prepareForSleep" }, { type: "resumed" }, detected(passwordOnly)]);
        graceful.send(timer("resumeGrace"), 4000);
        assert(graceful.state.sleep.status === "awake" && has(graceful.effects, "detectMethods"),
               "7: after the wake's grace period, a lock without a passive method asks once more");

        const lockInSleep = started({ lockOnSleep: false, passwordFallback: fallback }).send({ type: "prepareForSleep" });
        assert(!has(lockInSleep.effects, "lockCompositor"), "7: lockOnSleep off: going to sleep does not lock");
        lockInSleep.sendAll([{ type: "lockRequested", source: "logind" }, added("s1"), confirmed(), detected(allLines)]);
        assert(!has(lockInSleep.all, "startPam") && lockInSleep.state.passive.fingerprint.status === "paused",
               "7: a lock that happens during a suspend starts no passive method");

        const toggle = started();
        toggle.send({ type: "settings", values: { lockOnSleep: false } });
        assert(has(toggle.effects, "releaseInhibitor") && toggle.state.sleep.inhibitor === "released",
               "7: lockOnSleep switched off: the inhibitor is let go");
        toggle.send({ type: "settings", values: { lockOnSleep: true } });
        assert(has(toggle.effects, "holdInhibitor"), "7: switched on again: held again");
        const offWhileDown = started().sendAll([{ type: "prepareForSleep" }, { type: "settings", values: { lockOnSleep: false } }]);
        assert(has(offWhileDown.effects, "releaseInhibitor"), "7: switched off while going down: let go at once");
        const notWhileDown = started({ lockOnSleep: false, passwordFallback: fallback }).sendAll([
            { type: "prepareForSleep" }, { type: "settings", values: { lockOnSleep: true } }]);
        assert(!has(notWhileDown.effects, "holdInhibitor"), "7: switched on while going down: taken only after the wake");
        notWhileDown.send({ type: "resumed" });
        assert(has(notWhileDown.effects, "holdInhibitor"), "7: … which it is");
    }

    // ---- 8. Lock requests while locked; a lock refused ----

    function _behaviour8RepeatedAndDeniedLocks() {
        const lock = locked();
        const before = lock.state;
        lock.send({ type: "lockRequested", source: "logind" });
        assert(lock.state === before && lock.ignored === "already locked" && lock.effects.length === 0,
               "8: a lock request while locked changes nothing: no second session, no restart");
        const lockingNow = started().send({ type: "lockRequested" });
        const lockingState = lockingNow.state;
        lockingNow.send({ type: "lockRequested", source: "idle" });
        assert(lockingNow.state === lockingState && lockingNow.ignored === "already locked", "8: … nor while locking");

        // The driver reads WlSessionLock.locked right after lockCompositor and reports a
        // refusal as compositorFinished for that session
        const denied = locking().send(finished());
        assert(denied.state.phase.status === "unlocked" && denied.state.phase.lastEnd === "denied"
               && has(denied.effects, "unlockCompositor", { reason: "denied", session: 1 }) && has(denied.effects, "announceLocked", { locked: false })
               && has(denied.effects, "log", { level: "warning" }) && nothingRunning(denied.state),
               "8: the compositor refusing the lock: back to unlocked, cleanly, and reported");
        denied.send({ type: "lockRequested" });
        assert(denied.state.phase.status === "locking" && denied.state.phase.session === 2, "8: … and the next lock request locks");
        const late = locked().send({ type: "unlockRequested", source: "logind" }).send(finished());
        assertEqual(late.ignored, "not locked", "8: the compositor's end after an unlock is ignored");
    }

    // A lock the compositor never confirms (Quickshell refuses some without any signal)
    function _behaviour8Unconfirmed() {
        const lock = locking().sendAll(enter("pw"));
        assert(lock.state.password.status === "pending" && "confirm" in lock.state.timers, "8u: (locking, a password held)");
        lock.send(timer("confirm"), 5000);
        const order = types(lock.effects);
        assert(order.indexOf("unlockCompositor") >= 0 && order.indexOf("unlockCompositor") < order.indexOf("lockCompositor")
               && has(lock.effects, "unlockCompositor", { session: 1, reason: "retry" }) && has(lock.effects, "lockCompositor", { session: 2 }),
               "8u: no confirmation in time: the lock is set again (unlock, then lock under a new session)");
        assert(lock.state.phase.status === "locking" && lock.state.phase.session === 2 && lock.state.phase.attempt === 2
               && lock.state.password.status === "pending" && !has(lock.effects, "announceLocked"),
               "8u: … still locking, the password still held, nothing announced again");
        lock.send({ type: "compositorLocked", session: 1 });
        assertEqual(lock.ignored, "stale session", "8u: a late confirmation of the abandoned session does not count");
        const retried = locking().sendAll([timer("confirm"), confirmed(), detected(passwordOnly)], 5000);
        assert(retried.state.phase.status === "locked" && !("confirm" in retried.state.timers),
               "8u: the retried session's confirmation locks");

        lock.send(timer("confirm"), 5000);
        assert(lock.state.phase.attempt === 3 && lock.state.phase.session === 3, "8u: (a second retry)");
        lock.send(timer("confirm"), 5000);
        assert(lock.state.phase.status === "unlocked" && lock.state.phase.lastEnd === "unconfirmed"
               && has(lock.effects, "unlockCompositor", { session: 3, reason: "unconfirmed" })
               && has(lock.effects, "announceLocked", { locked: false }) && has(lock.effects, "log", { level: "warning" })
               && nothingRunning(lock.state),
               "8u: after " + LockRules.limits.confirmAttempts + " attempts the lock is given up, said so, no secret left");
        lock.send({ type: "lockRequested", source: "idle" });
        assert(lock.ignored === "" && lock.state.phase.status === "locking" && lock.state.phase.session === 4,
               "8u: … and a later lock request locks again");

        // Going down with a lock that is never confirmed: the machine sleeps after the
        // fallback, and the lock is given up — the next sleep locks again
        const down = started().sendAll([{ type: "prepareForSleep" }, added("s1")]);
        down.send(timer("inhibitor"), 4000);
        down.sendAll([timer("confirm"), timer("confirm"), timer("confirm")], 5000);
        assertEqual(down.state.phase.lastEnd, "unconfirmed", "8u: (going down, never confirmed: given up)");
        down.sendAll([{ type: "resumed" }, { type: "prepareForSleep" }], 30000);
        assert(down.state.phase.status === "locking" && has(down.effects, "lockCompositor"),
               "8u: … and the next sleep locks again");
    }

    // ---- 9. Retries ----

    function _behaviour9Retry() {
        const delay = (previous, round, result) => LockRules.retryDelay(previous, round, result);
        assertEqual(delay(0, 300, "failed"), 500, "9: the first quick failure waits the minimum");
        assertEqual(delay(500, 300, "failed"), 1000, "9: each quick failure doubles the wait");
        assertEqual(delay(4000, 300, "failed"), 8000, "9: … 4 s → 8 s");
        assertEqual(delay(8000, 300, "failed"), 10000, "9: … up to the maximum");
        assertEqual(delay(10000, 300, "failed"), 10000, "9: … and stays there");
        assertEqual(delay(10000, 20000, "failed"), 500, "9: a round that ran its full time resets");
        assertEqual(delay(500, 1000, "maxTries"), 10000, "9: MaxTries: somebody failing, the longest wait at once");
        assertEqual(delay(500, 1000, "success"), null, "9: success: no retry");
        assertEqual(delay(500, 1000, "error"), null, "9: error: not this table's (errorRetry, counted)");
        assertEqual(LockRules.retryDelay(0, 300, "failed", Object.assign({}, LockRules.timings, { retryMin: 50 })), 50,
                    "9: the fourth parameter: the timings to use");

        const lock = locked();
        lock.send(pamMessage("fingerprint", { message: "Failed to match fingerprint", messageIsError: true }));
        lock.send(pamCompleted("fingerprint", "failed"), 2000);
        assert(lock.state.passive.fingerprint.status === "backoff" && has(lock.effects, "startTimer", { name: "retry:fingerprint", ms: 500 }),
               "9: a quick failure backs off");
        let fingerprint = LockRules.view(lock.state).methods[0];
        assert(!fingerprint.waiting && fingerprint.text === "Failed to match fingerprint, trying again shortly",
               "9: the view says it is backing off, not waiting");
        lock.send(timer("retry:fingerprint"), 500);
        fingerprint = LockRules.view(lock.state).methods[0];
        assert(lock.state.passive.fingerprint.status === "running" && fingerprint.waiting && fingerprint.text === "Touch the fingerprint reader",
               "9: when the retry runs it is waiting for the user again");
        lock.send(pamCompleted("fingerprint", "failed"), 1000);
        assert(has(lock.effects, "startTimer", { name: "retry:fingerprint", ms: 1000 }), "9: the next quick failure waits longer");
        lock.sendAll([timer("retry:fingerprint"), pamCompleted("fingerprint", "failed")], 30000);
        assert(has(lock.effects, "startTimer", { name: "retry:fingerprint", ms: 500 }), "9: a round that ran out resets the wait");
        lock.sendAll([timer("retry:fingerprint"), pamCompleted("fingerprint", "maxTries")], 1000);
        assert(has(lock.effects, "startTimer", { name: "retry:fingerprint", ms: 10000 })
               && LockRules.view(lock.state).methods[0].text === "Fingerprint: too many attempts, wait a moment",
               "9: MaxTries waits the longest and says so");

        const eager = locked().send(pamCompleted("u2f", "failed"));
        eager.send(activity());
        assert(has(eager.effects, "startPam", { method: "u2f" }) && has(eager.effects, "stopTimer", { name: "retry:u2f" }),
               "9: somebody at the prompt: the security key is tried at once rather than after its delay");
        const notEager = locked().send(pamCompleted("fingerprint", "failed"));
        notEager.send(activity());
        assert(!has(notEager.effects, "startPam"), "9: … the fingerprint keeps its delay");
        const none = locked(passwordOnly).send(activity());
        assert(has(none.effects, "detectMethods"), "9: a lock without a passive method asks again when somebody comes back");
        const eagerWithoutReader = locked(passwordAndKey).send(pamCompleted("u2f", "failed"));
        eagerWithoutReader.send(activity());
        assert(has(eagerWithoutReader.effects, "detectMethods") && has(eagerWithoutReader.effects, "startPam", { method: "u2f" }),
               "9: … and an eager retry is not held up by that re-detection (no fingerprint reader: the key still tried at once)");
    }

    // ---- 10. Settings ----

    function _behaviour10Settings() {
        const defaults = LockRules.initial();
        assert(defaults.settings.lockOnSleep === true && defaults.settings.passwordFallback === null
               && defaults.settings.timings.prompt === 10000,
               "10: defaults: lock before sleep on, no fallback, the default timings");
        const custom = LockRules.initial({ lockOnSleep: false, timings: { prompt: 3000 } });
        assert(custom.settings.lockOnSleep === false && custom.settings.timings.prompt === 3000 && custom.settings.timings.detect === 5000,
               "10: settings and timing overrides are taken, the rest default");
        const junk = LockRules.initial({ timings: { prompt: "soon", detect: null, settle: -5, verify: NaN, confirm: Infinity, bogus: 1 } });
        assert(junk.settings.timings.prompt === 10000 && junk.settings.timings.detect === 5000 && junk.settings.timings.settle === 1000
               && junk.settings.timings.verify === 90000 && junk.settings.timings.confirm === 5000 && !("bogus" in junk.settings.timings),
               "10: timings that are not non-negative numbers keep their defaults; unknown ones are dropped");
        const junkLock = machine({ timings: { prompt: "soon" } }).sendAll([{ type: "started" }, { type: "lockRequested" }, added("s1"), activity()]);
        assert(of(junkLock.all, "startTimer").every(effect => typeof effect.ms === "number" && isFinite(effect.ms)),
               "10: … so no timer starts with a time that is not a number");
        const given = { lockOnSleep: true, passwordFallback: { directory: "/a", config: "b" }, timings: { prompt: 3000 } };
        const copied = LockRules.initial(given);
        given.passwordFallback.directory = "/changed";
        given.timings.prompt = 1;
        assert(copied.settings.passwordFallback.directory === "/a" && copied.settings.timings.prompt === 3000,
               "10: the settings are copied: changing the caller's objects later changes nothing");
        const event = { type: "settings", values: { passwordFallback: { directory: "/etc/pam.d", config: "login" } } };
        const lock = started();
        lock.send({ type: "settings", values: { screensaverTimeout: 20 } });
        assertEqual(lock.ignored, "no known setting", "10: idle and screensaver settings are not the rules' (the driver's IdleMonitor)");
        lock.send(event);
        event.values.passwordFallback.config = "changed";
        lock.sendAll([{ type: "lockRequested" }, added("s1"), confirmed(), enter("pw"), timer("detect")]);
        assert(has(lock.effects, "startPam", { method: "password", configDirectory: "/etc/pam.d", config: "login" }),
               "10: a changed password fallback is used (copied, not the event's object)");
        const prompt = locked(null, { lockOnSleep: true, passwordFallback: fallback, timings: { prompt: 3000 } })
            .send(activity());
        assert(has(prompt.effects, "startTimer", { name: "prompt", ms: 3000 }), "10: the prompt's time-out follows its timing");
    }

    // ---- 11. Nothing hangs for good ----

    function _behaviour11Hangs() {
        // A PAM conversation that never answers
        const hung = locked(passwordOnly).sendAll(enter("pw"));
        assert(has(hung.effects, "startTimer", { name: "verify", ms: 90000 }), "11: a submitted password arms the verify timer (90 s)");
        hung.sendAll([passwordPrompt(), submit("again")]);
        hung.send(timer("verify"), 90000);
        assert(has(hung.effects, "abortPam", { method: "password" }) && hung.state.password.status === "failed"
               && hung.state.password.error === "Password check timed out" && hung.state.password.refusal === ""
               && !LockRules.view(hung.state).busy && hung.state.secret === null,
               "11: a verification PAM never answers is aborted at the verify timer: an error shown, the field usable");
        hung.sendAll(enter("pw"));
        assert(hung.state.password.status === "pending" && !has(hung.effects, "startPam"), "11: … the next password waits for the abort to settle");
        hung.send(timer("settle:password"), 1000);
        assert(has(hung.effects, "startPam", { method: "password" }), "11: … and then starts a fresh conversation");

        const answered = locked(passwordOnly).sendAll([enter("pw"), passwordPrompt(), passwordPrompt("Code:")]);
        assert(!("verify" in answered.state.timers), "11: a question (waiting for the user, not PAM) stops the verify timer");
        answered.send(submit("123"), 60000);
        assert(has(answered.effects, "startTimer", { name: "verify", ms: 90000 }), "11: … the answer arms it afresh");
        answered.send(pamCompleted("password", "failed"));
        assert(!("verify" in answered.state.timers), "11: … and the end of the conversation stops it");

        // A password pending because nothing starts (the lock not confirmed)
        const neverStarts = locking().sendAll(enter("pw"));
        neverStarts.send(timer("verify"), 90000);
        assert(neverStarts.state.password.status === "failed" && neverStarts.state.secret === null
               && neverStarts.state.password.error === "Password check timed out",
               "11: a password stuck pending gets the same bound");

        // An internal error on a PAM completion still ends that conversation
        const base = locked().sendAll(enter("pw"));
        const throwing = new Proxy({}, { get: () => { throw new Error("planted"); }, has: () => { throw new Error("planted"); },
                                         ownKeys: () => { throw new Error("planted"); },
                                         getOwnPropertyDescriptor: () => { throw new Error("planted"); } });
        const poisoned = Object.assign({}, base.state, { timers: throwing });
        const fp = LockRules.step(poisoned, { type: "pamCompleted", method: "fingerprint", conversation: conversationOf(base.state, "fingerprint"),
                                              result: "failed" }, base.now + 10);
        assert(fp.error === true && fp.ignored === "" && fp.state.passive.fingerprint.conversation === null
               && fp.state.passive.fingerprint.status === "broken" && has(fp.effects, "log", { level: "error" }),
               "11: an internal error on a passive method's completion still ends that conversation (broken, said so)");
        const pw = LockRules.step(poisoned, { type: "pamCompleted", method: "password", conversation: conversationOf(base.state, "password"),
                                              result: "failed" }, base.now + 10);
        assert(pw.error === true && pw.state.password.conversation === null && pw.state.password.status === "failed"
               && pw.state.secret === null && !LockRules.view(pw.state).busy,
               "11: … and the password's: not verifying any more, no secret, usable");
        const startFailed = LockRules.step(poisoned, { type: "pamStartFailed", method: "u2f", conversation: conversationOf(base.state, "u2f") }, base.now + 10);
        assert(startFailed.error === true && startFailed.state.passive.u2f.conversation === null, "11: … and a refused start's");
        const stale = LockRules.step(poisoned, { type: "pamCompleted", method: "u2f", conversation: -7, result: "failed" }, base.now + 10);
        assert(stale.ignored !== "" && stale.state === poisoned, "11: (a stale completion is still just ignored)");
        const other = LockRules.step(poisoned, activity(), base.now + 10);
        assert(other.error === true && other.state === poisoned && other.effects.length === 0,
               "11: an internal error on any other event leaves the state as it was");
    }

    // ---- 12. Re-detection ----

    function _behaviour12Redetection() {
        // A re-detection that no longer names a method running: stopped, unavailable
        const fewer = locked(passwordAndFingerprint);
        const running = conversationOf(fewer.state, "fingerprint");
        fewer.send(activity());
        assert(has(fewer.effects, "detectMethods"), "12: (u2f missing: somebody coming back asks again)");
        fewer.send(detected(passwordOnly));
        assert(has(fewer.effects, "abortPam", { method: "fingerprint", conversation: running })
               && fewer.state.passive.fingerprint.status === "unavailable" && fewer.state.passive.fingerprint.conversation === null,
               "12: a re-detection without the running fingerprint aborts it, unavailable");
        fewer.send({ type: "pamCompleted", method: "fingerprint", conversation: running, result: "error" });
        assert(!fewer.error && fewer.ignored === "method not running" && fewer.state.passive.fingerprint.status === "unavailable",
               "12: its late completion is simply ignored (it was an internal error)");
        assert(!LockRules.view(fewer.state).methods[0].visible, "12: … and nothing shows it running");

        const backoff = locked(passwordAndFingerprint).send(pamCompleted("fingerprint", "failed"));
        backoff.sendAll([activity(), detected(passwordOnly)]);
        assert(backoff.state.passive.fingerprint.status === "unavailable" && !("retry:fingerprint" in backoff.state.timers),
               "12: … one backing off: its retry stopped");
        const stillBroken = locked(passwordAndFingerprint).send(pamMessage("fingerprint", { responseRequired: true }));
        stillBroken.sendAll([activity(), detected(passwordOnly), detected(passwordAndFingerprint)]);
        assertEqual(stillBroken.state.passive.fingerprint.status, "broken", "12: a broken method stays broken through re-detections");

        // Detection failing keeps this lock's last answer
        const keeps = locked(passwordAndFingerprint).send(activity());
        keeps.send(state => ({ type: "methodsFailed", generation: state.methods.generation, reason: "exited 1" }));
        const warning = of(keeps.effects, "log", { level: "warning" })[0];
        assert(keeps.state.methods.status === "known" && keeps.state.methods.configs.fingerprint !== null
               && keeps.state.methods.configs.password.config === "h2s-shell-password"
               && keeps.state.passive.fingerprint.status === "running",
               "12: a failed re-detection keeps this lock's last answer");
        assert(warning.message.includes("last answer") && warning.message.includes("from that answer"),
               "12: … and says so: " + warning.message);
        const lastNoPassword = locked(["fingerprint\t/etc/pam.d\tfp"]).send(activity());
        lastNoPassword.send(timer("detect"), 5000);
        const fallbackWarning = of(lastNoPassword.effects, "log", { level: "warning" })[0];
        assert(fallbackWarning.message.includes("the fallback") && lastNoPassword.state.methods.configs.password.directory === "/shell/pam",
               "12: … the password from the fallback where that answer named none, said so: " + fallbackWarning.message);
    }

    // ---- Parsers ----

    function _parsers() {
        const methods = LockRules.parseMethods([
            "password\t/etc/pam.d\th2s-shell-password",
            "fingerprint\t/home/u/src/h2s-shell/pam\tfingerprint\r",
            "",
            "garbage line without tabs",
            "u2f\t/etc/pam.d",
            "u2f\trelative/dir\tu2f",
            "u2f\t/etc/pam.d\tnested/config",
            "password\t/elsewhere\tsecond",
            "Weird Name\t/etc/pam.d\tx",
            "u2f\t/etc/pam.d\th2s-shell-u2f\textra",
            "u2f \t /etc/pam.d \t h2s-shell-u2f "
        ]);
        assertEqual(JSON.stringify(methods),
                    JSON.stringify({ password: { directory: "/etc/pam.d", config: "h2s-shell-password" },
                                     fingerprint: { directory: "/home/u/src/h2s-shell/pam", config: "fingerprint" },
                                     u2f: { directory: "/etc/pam.d", config: "h2s-shell-u2f" } }),
                    "parseMethods: the script's lines, junk skipped, first line per method wins");
        assertEqual(JSON.stringify(LockRules.parseMethods("password\t/etc/pam.d\tlogin\n")),
                    JSON.stringify({ password: { directory: "/etc/pam.d", config: "login" } }),
                    "parseMethods: the NixOS fallback line, as one string");
        assertEqual(JSON.stringify(LockRules.parseMethods(null)), "{}", "parseMethods: nothing");

        const session = "/org/freedesktop/login1/session/_34";
        const logind = line => JSON.stringify(LockRules.parseLogind(line, session));
        assertEqual(logind("/org/freedesktop/login1/session/_34: org.freedesktop.login1.Session.Lock ()"),
                    JSON.stringify({ type: "lockRequested", source: "logind" }), "parseLogind: Lock on our session");
        assertEqual(logind("/org/freedesktop/login1/session/_34: org.freedesktop.login1.Session.Unlock ()"),
                    JSON.stringify({ type: "unlockRequested", source: "logind" }), "parseLogind: Unlock on our session");
        assertEqual(logind("/org/freedesktop/login1/session/_35: org.freedesktop.login1.Session.Unlock ()"), "null",
                    "parseLogind: another session's Unlock is not ours");
        assertEqual(logind("/org/freedesktop/login1/session/_341: org.freedesktop.login1.Session.Lock ()"), "null",
                    "parseLogind: a session path that only starts like ours is not ours");
        assertEqual(JSON.stringify(LockRules.parseLogind("/org/freedesktop/login1/session/_34: org.freedesktop.login1.Session.Unlock ()", "")),
                    "null", "parseLogind: without a session of our own, no Lock or Unlock counts");
        assertEqual(logind("/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)"),
                    JSON.stringify({ type: "prepareForSleep" }), "parseLogind: PrepareForSleep (true,)");
        assertEqual(logind("/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)"),
                    JSON.stringify({ type: "resumed" }), "parseLogind: PrepareForSleep (false,)");
        assertEqual(logind("/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (true,)"), "null",
                    "parseLogind: other Manager signals");
        assertEqual(logind("/org/freedesktop/login1/session/_34: org.freedesktop.DBus.Properties.PropertiesChanged ('org.freedesktop.login1.Session', {'IdleHint': <true>}, @as [])"),
                    "null", "parseLogind: a property change on our session");
        assertEqual(logind("/org/freedesktop/login1: org.freedesktop.login1.Manager.SessionNew ('35', objectpath '/org/freedesktop/login1/session/_35')"),
                    "null", "parseLogind: another unrelated signal");
        assertEqual(logind("Monitoring signals on object /org/freedesktop/login1/session/_34 owned by org.freedesktop.login1"), "null",
                    "parseLogind: the header line");
        assertEqual(logind("The name org.freedesktop.login1 is owned by :1.7"), "null", "parseLogind: the owner line");
        assertEqual(logind(""), "null", "parseLogind: an empty line");

        assertEqual(LockRules.parseSessionPath("(objectpath '/org/freedesktop/login1/session/_34',)\n"),
                    "/org/freedesktop/login1/session/_34", "parseSessionPath: GetSession's answer");
        assertEqual(LockRules.parseSessionPath("Error: GDBus.Error:org.freedesktop.login1.NoSuchSession: No session '' known"), "",
                    "parseSessionPath: an error (no XDG_SESSION_ID)");
        assertEqual(LockRules.parseSessionPath(""), "", "parseSessionPath: nothing");
        assertEqual(LockRules.parseSessionPath("(objectpath '/org/freedesktop/login1/user/_1000',)"), "",
                    "parseSessionPath: a path that is no session");
    }

    // ---- Secrets ----

    function _secrets() {
        const lock = locking().sendAll([confirmed(), enter("tr0ub4dor&3")]);
        assertEqual(lock.state.secret, "tr0ub4dor&3", "secrets: (held while the methods are not known)");
        const shown = JSON.stringify(LockRules.describe(lock.state));
        assert(!shown.includes("tr0ub4dor") && LockRules.describe(lock.state).hasSecret === true,
               "secrets: describe() leaves the secret out, saying only that there is one");
        assert(JSON.stringify(JSON.parse(shown)) === shown, "secrets: describe() is JSON-serialisable");
        lock.sendAll([detected(passwordOnly), passwordPrompt()]);
        const respond = of(lock.effects, "respondPam")[0];
        assert(respond.text === "tr0ub4dor&3" && LockRules.describeEffect(respond).text === "<redacted>",
               "secrets: describeEffect() redacts the answer in respondPam");
        assertEqual(LockRules.describeEvent({ type: "submit", surface: "s1", text: "pw" }).text, "<redacted>", "secrets: describeEvent() redacts a submit");
        assertEqual(LockRules.describeEvent({ type: "key", surface: "s1", key: "", text: "p" }).text, "<redacted>",
                    "secrets: … and a key's text");
        const named = LockRules.describeEvent({ type: "key", surface: "s1", key: "A", text: "a" });
        assert(named.key === "<redacted>" && named.text === "<redacted>", "secrets: … and a key named by its character");
        assertEqual(LockRules.describeEvent({ type: "key", surface: "s1", key: "Enter", text: "" }).key, "Enter",
                    "secrets: … but a named key is kept");
        const forward = LockRules.describeEffect({ type: "forwardKey", surface: "s1", key: "q", text: "p" });
        assert(forward.text === "<redacted>" && forward.key === "<redacted>", "secrets: … and a forwarded key's");
        assert(lock.state.secret === null, "secrets: dropped once PAM has it");

        // Log effects never carry typed text, on any path a password takes
        const typed = "c0rrect-h0rse-typed";
        const paths = [
            locked(passwordOnly).sendAll([enter(typed), passwordPrompt(), pamCompleted("password", "failed")]),
            locked(passwordOnly).sendAll([enter(typed), timer("verify")], 90000),
            locking().sendAll([enter(typed), timer("confirm"), timer("confirm"), timer("confirm")], 5000),
            locked([], { passwordFallback: null }).sendAll([enter(typed), detected([])]),
            locked(passwordOnly).sendAll([enter(typed), passwordPrompt("Code:"), submit(typed), pamCompleted("password", "error")]),
            locked(passwordOnly).sendAll([activity(), key("s1", typed, typed), submit(typed), { type: "unlockRequested", source: "logind" }])
        ];
        assert(paths.every(path => of(path.all, "log").every(effect => !JSON.stringify(effect).includes(typed))),
               "secrets: no log effect contains typed text (failed, timed out, unconfirmed, unavailable, answered, unlocked)");
        assert(paths.every(path => path.all.filter(effect => effect.type !== "respondPam" && effect.type !== "forwardKey")
                                       .every(effect => !JSON.stringify(effect).includes(typed))),
               "secrets: … nor any effect but respondPam (and forwardKey for a key's own text)");
    }

    // ---- Every transition total ----

    function _totality() {
        const lock = locked();
        const garbage = [null, undefined, 5, "lock", {}, { type: 42 }, { type: "toString" }, { type: "__proto__" },
                         { type: "submit" }, { type: "key", surface: 5 }, { type: "timer" }, { type: "pamCompleted" },
                         { type: "methodsDetected", lines: 7 }, { type: "settings", values: "x" }, { type: "settings", values: null },
                         { type: "surfaceRemoved" }, { type: "press" }, { type: "surfaceAdded", surface: {}, screen: "x" },
                         { type: "pamCompleted", method: "__proto__", conversation: 1, result: "success" },
                         { type: "pamCompleted", method: "hasOwnProperty", result: "success" },
                         { type: "timer", name: "__proto__" }, { type: "timer", name: "constructor" },
                         { type: "compositorLocked", session: "1" }];
        let survived = true;
        for (const event of garbage) {
            const result = LockRules.step(lock.state, event, 1);
            if (result.error === true || !Array.isArray(result.effects) || result.state.phase.status !== "locked")
                survived = false;
        }
        assert(survived, "total: malformed events are ignored, never throw, never unlock");
        const unknown = LockRules.step(lock.state, { type: "toString" }, 1);
        assert(unknown.state === lock.state && unknown.ignored === "unknown event", "total: an unknown event is reported as ignored");
        assertEqual(LockRules.step(lock.state, activity(), NaN).ignored, "no time", "total: no time, no step");
        assertEqual(LockRules.step(null, { type: "started" }, 1).ignored, "no state", "total: no state, no step");
        const unlocked = started();
        for (const type of ["submit", "activity", "press", "key", "surfaceAdded", "pamCompleted", "methodsDetected", "compositorLocked"]) {
            unlocked.send({ type: type, surface: "s1", screen: "DP-1", text: "x", session: 0 });
            assert(unlocked.ignored !== "" && unlocked.effects.length === 0, "total: " + type + " while unlocked is ignored: " + unlocked.ignored);
        }
    }

    // ---- Liveness ----

    // From any state, the owner comes back and types the right password: the lock must
    // open within `livenessSteps` steps and `livenessTime` ms of simulated time. The world
    // is kind but not helpful: the compositor confirms, the methods script answers, PAM
    // answers conversations started from here on (a hidden prompt, then success for the
    // right password). Conversations from before never answer (hung), passive methods
    // never succeed, and pending timers fire when their time comes. The bound: a missed
    // resume (60 s) + a hung verification (90 s) + the detection, settle and prompt time-outs
    // on the way, with room to spare.
    readonly property int livenessSteps: 120
    readonly property int livenessTime: 200000

    function _liveness(state, now) {
        const rightPassword = "the-right-password";
        let current = state;
        let clock = now;
        const start = now;
        const ours = {};
        const trail = [];
        let pokedSleep = false;
        const apply = (event, at) => {
            const result = LockRules.step(current, event, at);
            trail.push(JSON.stringify(LockRules.describeEvent(event)) + (result.ignored ? " → ignored: " + result.ignored : ""));
            if (result.error === true)
                return "internal error: " + result.ignored;
            for (const effect of result.effects) {
                if (effect.type === "startPam" && effect.method === "password")
                    ours[effect.conversation] = { prompted: false, answer: null };
                if (effect.type === "respondPam" && ours[effect.conversation])
                    ours[effect.conversation].answer = effect.text;
            }
            current = result.state;
            clock = at;
            return "";
        };
        for (let steps = 0; steps < livenessSteps; steps++) {
            if (current.phase.status === "unlocked") {
                return current.phase.lastEnd === "authenticated" && current.password.status === "idle"
                    ? "" : "ended as " + current.phase.lastEnd;
            }
            if (clock - start > livenessTime)
                break;
            const surfaces = current.prompt.surfaces;
            const owner = current.prompt.owner;
            const password = current.password;
            const conversation = password.conversation !== null ? ours[password.conversation.id] : undefined;
            let event = null;
            let at = clock + 10;
            if (surfaces.length === 0)
                event = added("oracle-surface", "DP-9");
            else if (current.phase.status === "locking")
                event = { type: "compositorLocked", session: current.phase.session };
            else if (current.methods.status === "detecting")
                event = { type: "methodsDetected", generation: current.methods.generation, lines: allLines };
            else if (password.status === "verifying" && conversation && !conversation.prompted) {
                conversation.prompted = true;
                event = { type: "pamMessage", method: "password", conversation: password.conversation.id, message: "Password: ",
                          messageIsError: false, responseRequired: true, responseVisible: false };
            } else if (password.status === "verifying" && conversation && conversation.answer !== null)
                event = { type: "pamCompleted", method: "password", conversation: password.conversation.id,
                          result: conversation.answer === rightPassword ? "success" : "failed" };
            else if (current.sleep.status === "suspending" && !pokedSleep) {
                pokedSleep = true;
                event = activity(surfaces[0].id);
            } else if (owner === null)
                event = activity(surfaces[0].id);
            else if (password.status === "asking")
                event = { type: "submit", surface: owner, text: "000000" };
            else if (["idle", "failed", "unavailable"].includes(password.status))
                event = { type: "submit", surface: owner, text: rightPassword };
            else {
                // Nothing to do but wait: the next timer in due order
                const names = Object.keys(current.timers);
                if (names.length === 0)
                    return "stuck with no timer running (password " + password.status + ")\n      " + trail.join("\n      ");
                names.sort((a, b) => current.timers[a].due - current.timers[b].due);
                const name = names[0];
                at = Math.max(clock, current.timers[name].due);
                event = { type: "timer", name: name, token: current.timers[name].token };
            }
            const problem = apply(event, at);
            if (problem !== "")
                return problem + "\n      " + trail.join("\n      ");
        }
        return "not unlocked within " + livenessSteps + " steps / " + livenessTime + " ms (at " + (clock - start) + " ms, phase "
            + current.phase.status + ", password " + current.password.status + ")\n      " + trail.slice(-30).join("\n      ");
    }

    function _livenessCases() {
        const cases = [
            ["a hung verification", locked(passwordOnly).sendAll([enter("wrong"), passwordPrompt()])],
            ["a cancelled question", locked(passwordOnly).sendAll([enter("pw"), passwordPrompt(), passwordPrompt("Code:"), timer("prompt")], 10000)],
            ["a lost resume", locked().send({ type: "prepareForSleep" })],
            ["no password config", locked([], { passwordFallback: null })],
            ["locking with a password held", locking().sendAll(enter("early"))],
            ["a surface swap", locked().sendAll([added("s2"), removed("s1")])],
            ["no surface", locked().send(removed("s1"))]
        ];
        for (const [label, from] of cases) {
            const problem = _liveness(from.state, from.now);
            assert(problem === "", "liveness: from " + label + ", the right password unlocks within the bound" + (problem ? ": " + problem : ""));
        }
    }

    // ---- The sweep ----

    // A small seeded PRNG (mulberry32): the same sequences on every run
    function _random(seed) {
        let state = seed >>> 0;
        return () => {
            state = (state + 0x6D2B79F5) >>> 0;
            let t = state;
            t = Math.imul(t ^ (t >>> 15), t | 1);
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
    }

    readonly property var _lineSets: [
        [], ["password\t/etc/pam.d\tlogin"], ["fingerprint\t/etc/pam.d\tfp", "u2f\t/etc/pam.d\tu2f"],
        ["junk", "password\t/x\ty"], ["password\t/etc/pam.d\tpw", "fingerprint\t/etc/pam.d\tfp", "u2f\t/etc/pam.d\tu2f"],
        ["password\t/etc/pam.d\tpw", "fingerprint\t/etc/pam.d\tfp"], ["password\t/etc/pam.d\tpw", "u2f\t/etc/pam.d\tu2f"],
        ["fingerprint\t/etc/pam.d\tfp"], ["u2f\t/etc/pam.d\tu2f"]
    ]

    // Characters only a key event carries: they may reach forwardKey, nothing else
    readonly property var _keyCharacters: ["ж", "ß", "ŋ", "ø"]

    // An event, mostly one that makes sense in this state (the current ids, tokens,
    // surfaces), some nonsense. Unlocks come rarely, so that sequences also relock.
    function _randomEvent(state, random, context) {
        const pick = list => list[Math.floor(random() * list.length)];
        const chance = p => random() < p;
        const surfaces = state.prompt.surfaces.map(surface => surface.id);
        const knownSurface = () => surfaces.length > 0 && chance(0.9) ? pick(surfaces) : pick(["s1", "s2", "gone", 7]);
        const typedText = () => {
            const text = "typed-" + context.typed.length + "-" + Math.floor(random() * 1e6);
            context.typed.push(text);
            return text;
        };
        const conversations = LockRules.running(state).conversations;
        const phase = state.phase.status;
        if (chance(0.8)) {
            const roll = random();
            if (phase === "unlocked") {
                if (roll < 0.35) return { type: "lockRequested", source: pick(["ipc", "logind", "sleep", "idle"]) };
                if (roll < 0.5) return { type: chance(0.5) ? "prepareForSleep" : "resumed" };
                if (roll < 0.6) return { type: "settings", values: pick([{ lockOnSleep: true }, { lockOnSleep: false }, { passwordFallback: null }, { passwordFallback: fallback }]) };
                if (roll < 0.65) return { type: "compositorFinished", session: state.phase.session };
                if (roll < 0.7) return removed(pick(["s1", "s2"]));
            }
            // The driver reports a lock's surfaces as soon as they exist
            if (phase !== "unlocked" && surfaces.length === 0 && chance(0.7)) {
                context.surfaceCount++;
                return added("s" + context.surfaceCount, pick(["DP-1", "HDMI-A-1"]));
            }
            if (phase === "locking" && roll < 0.25)
                return chance(0.97) ? { type: "compositorLocked", session: state.phase.session } : { type: "compositorFinished", session: state.phase.session };
            const names = Object.keys(state.timers);
            if (roll < 0.15 && names.length > 0) {
                const name = pick(names);
                return { type: "timer", name: name, token: state.timers[name].token };
            }
            if (roll < 0.22 && state.methods.status === "detecting")
                return chance(0.85) ? { type: "methodsDetected", generation: state.methods.generation, lines: pick(_lineSets) }
                                    : { type: "methodsFailed", generation: state.methods.generation, reason: "exited 1" };
            if (roll < 0.4 && conversations.length > 0 && phase === "locked") {
                const conversation = pick(conversations);
                const id = conversation.conversation;
                const kind = random();
                if (kind < 0.45)
                    return { type: "pamMessage", method: conversation.method, conversation: id,
                             message: pick(["Password: ", "Code:", "", "Place your finger", "Account locked"]),
                             messageIsError: chance(0.3), responseRequired: chance(conversation.method === "password" ? 0.6 : 0.1),
                             responseVisible: chance(0.2) };
                if (kind < 0.95)
                    return { type: "pamCompleted", method: conversation.method, conversation: id,
                             result: chance(0.05) ? "success" : pick(["failed", "failed", "error", "maxTries", "bogus"]) };
                return { type: "pamStartFailed", method: conversation.method, conversation: id };
            }
            if (roll < 0.5)
                return pick([activity(knownSurface()), press(knownSurface()), activity(knownSurface())]);
            if (roll < 0.58) {
                const asleep = state.prompt.owner === null;
                const name = pick(asleep ? ["", "Enter", "Backspace", "Escape", "A"] : ["", "", "Enter", "Backspace", "Tab", "A", chance(0.15) ? "Escape" : ""]);
                return key(knownSurface(), name, pick([pick(_keyCharacters), "", "\r"]));
            }
            if (roll < 0.7) {
                const owner = state.prompt.owner;
                return { type: "submit", surface: owner !== null && chance(0.9) ? owner : knownSurface(), text: chance(0.15) ? "" : typedText() };
            }
            if (roll < 0.76) {
                context.surfaceCount++;
                return added("s" + context.surfaceCount, pick(["DP-1", "HDMI-A-1", "DP-1"]));
            }
            if (roll < 0.8 && surfaces.length > 0)
                return removed(pick(surfaces));
            if (roll < 0.86)
                return { type: chance(0.6) ? "prepareForSleep" : "resumed" };
            if (roll < 0.88)
                return { type: "unlockRequested", source: "logind" };
            if (roll < 0.92)
                return { type: "lockRequested", source: pick(["ipc", "idle"]) };
            return { type: "settings", values: pick([{ lockOnSleep: true }, { lockOnSleep: false }, { lockOnSleep: "yes" }, {}]) };
        }
        // Nonsense: stale ids, wrong sessions, unknown sources and names, malformed events
        const method = pick(["password", "fingerprint", "u2f", "smartcard"]);
        const current = method === "password" ? state.password.conversation : state.passive[method] ? state.passive[method].conversation : null;
        const conversation = pick([0, 1, 2, state.serial, state.serial + 1, -3, current !== null ? String(current.id) : "1", current !== null ? [current.id] : [1]]);
        switch (Math.floor(random() * 10)) {
        case 0: return { type: "unlockRequested", source: pick(["ipc", "view", "", "escape", "Escape", "LOGIND", "sleep", undefined]) };
        case 1: return { type: pick(["compositorLocked", "compositorFinished"]), session: pick([state.phase.session - 1, state.phase.session + 1, undefined, String(state.phase.session)]) };
        case 2: return { type: "pamCompleted", method: method, conversation: conversation, result: pick(["success", "failed", "error"]) };
        case 3: return { type: "pamMessage", method: method, conversation: conversation, message: "Password:", responseRequired: true };
        case 4: return { type: "timer", name: pick(["prompt", "detect", "retry:u2f", "settle:password", "confirm", "verify"]), token: pick([0, -1, state.serial]) };
        case 5: return { type: "methodsDetected", generation: pick([0, 1, state.serial + 5]), lines: pick(_lineSets) };
        case 6: return { type: "pamStartFailed", method: method, conversation: conversation };
        case 7: return { type: "submit", surface: pick(["gone", null, 7]), text: typedText() };
        case 8: return activity(pick(["gone", "", null]));
        default: return pick([null, {}, { type: 42 }, { type: "toString" }, { type: "key" }, { type: "timer" }, { type: "pamCompleted" }]);
        }
    }

    // Did the event that ended the lock have the right to? → "" or what is wrong
    function _unlockViolation(before, event, after) {
        const end = after.phase.lastEnd;
        if (event.type === "pamCompleted") {
            const conversation = event.method === "password" ? before.password.conversation
                               : before.passive[event.method] ? before.passive[event.method].conversation : null;
            return event.result === "success" && conversation !== null && conversation.id === event.conversation
                   && before.phase.status === "locked" && end === "authenticated" ? "" : "a PAM completion unlocked without being the current success";
        }
        if (event.type === "unlockRequested")
            return event.source === "logind" && end === "logind" ? "" : "unlockRequested from " + event.source + " unlocked";
        if (event.type === "key")
            return event.key === "Escape" && before.prompt.owner !== null && LockRules.escapeUnlocks && end === "escape" ? "" : "a key other than Escape at an awake prompt unlocked";
        if (event.type === "compositorFinished")
            return event.session === before.phase.session && end === (before.phase.status === "locking" ? "denied" : "compositor") ? "" : "a compositorFinished not of this session unlocked";
        if (event.type === "timer" && event.name === "confirm")
            return before.phase.status === "locking" && before.phase.attempt >= LockRules.limits.confirmAttempts && end === "unconfirmed" ? "" : "the confirm timer ended the lock early";
        return event.type + " unlocked";
    }

    // What must hold after every step, whatever led there; "" or what is wrong
    function _violation(before, state, effects) {
        const prompt = state.prompt;
        if (prompt.owner !== null && !prompt.surfaces.some(surface => surface.id === prompt.owner))
            return "the prompt's owner is not a known surface";
        const password = state.password;
        if (state.secret !== null && password.status !== "pending" && password.status !== "verifying")
            return "a secret held outside pending/verifying";
        if (password.status === "pending" && state.secret === null)
            return "pending without the secret";
        if ((password.status === "verifying" || password.status === "asking") !== (password.conversation !== null))
            return "password conversation and status disagree";
        const locked = state.phase.status !== "unlocked";
        if (locked && (password.status === "pending" || password.status === "verifying") !== ("verify" in state.timers))
            return "the verify timer does not run exactly while the password waits for PAM";
        if ((state.phase.status === "locking") !== ("confirm" in state.timers))
            return "the confirm timer does not run exactly while locking";
        if (!locked && !nothingRunning(state))
            return "something of the lock left while unlocked";
        if (state.methods.status === "detecting" && !("detect" in state.timers))
            return "detecting without a detect timer";
        const suspending = state.sleep.status === "suspending";
        for (const method of LockRules.passiveMethods) {
            const passive = state.passive[method.name];
            if ((passive.status === "running") !== (passive.conversation !== null))
                return method.name + ": running and conversation disagree";
            if (suspending && passive.status === "running")
                return method.name + " running while suspending";
            if (suspending && has(effects, "startPam", { method: method.name }))
                return method.name + " started while suspending";
            if ((passive.status === "backoff") !== (("retry:" + method.name) in state.timers))
                return method.name + ": backoff and its retry timer disagree";
        }
        for (const method of ["password"].concat(LockRules.passiveMethods.map(m => m.name))) {
            if (has(effects, "abortPam", { method: method }) && has(effects, "startPam", { method: method }))
                return method + " aborted and started in one step";
        }
        if (!suspending && (state.sleep.inhibitor === "held") !== state.settings.lockOnSleep)
            return "inhibitor not held exactly when wanted";
        const lastTimerEffect = {};
        for (const effect of effects) {
            if (effect.type === "startTimer" || effect.type === "stopTimer")
                lastTimerEffect[effect.name] = effect;
        }
        for (const name of Object.keys(lastTimerEffect)) {
            const effect = lastTimerEffect[name];
            if (effect.type === "startTimer" && (!state.timers[name] || state.timers[name].token !== effect.token))
                return "a timer started but not recorded: " + name;
            if (effect.type === "stopTimer" && name in state.timers)
                return "a timer stopped but still recorded: " + name;
        }
        for (const effect of of(effects, "startTimer")) {
            if (effects.filter(other => other.type === "startTimer" && other.name === effect.name).length > 1)
                return "a timer started twice in one step: " + effect.name;
            if (!LockRules.timerNames.includes(effect.name))
                return "a timer name not in timerNames: " + effect.name;
            if (typeof effect.ms !== "number" || !isFinite(effect.ms) || effect.ms < 0)
                return "a timer started with " + effect.ms;
        }
        for (const effect of of(effects, "forwardKey")) {
            if (effect.surface !== prompt.owner || (effect.key !== "" && !LockRules.namedKeys.includes(effect.key))
                    || /[\u0000-\u001f]/.test(effect.text))
                return "a forwardKey not to the owner, or with a key or text the field cannot take: " + JSON.stringify(effect);
        }
        const locks = of(effects, "lockCompositor");
        if (locks.length > 0 && locks[locks.length - 1].session !== state.phase.session)
            return "lockCompositor's session is not the state's";
        if (before.phase.status === "unlocked" && locked
                && !(effects[0].type === "lockCompositor" && effects[1].type === "announceLocked" && effects[1].locked === true))
            return "entering the lock did not begin with lockCompositor, announceLocked(true)";
        if (!locked && before.phase.status !== "unlocked") {
            const order = effects.map(effect => effect.type);
            const unlockAt = effects.findIndex(effect => effect.type === "unlockCompositor" && effect.reason !== "retry");
            if (unlockAt < 0 || order.lastIndexOf("abortPam") > unlockAt || order.lastIndexOf("startTimer") > unlockAt
                    || effects.findIndex(effect => effect.type === "announceLocked" && effect.locked === false) < unlockAt)
                return "leaving the lock: not aborts first, then unlockCompositor, then announceLocked(false)";
        }
        LockRules.view(state);
        return "";
    }

    // Typed text (submitted) appears in no effect but respondPam, in no log, in no ignored
    // reason; a key's characters only in forwardKey
    function _effectLeak(result, context) {
        const shown = [result.ignored];
        const outsideForward = [result.ignored];
        for (const effect of result.effects) {
            const text = JSON.stringify(effect);
            if (effect.type !== "respondPam")
                shown.push(text);
            if (effect.type !== "forwardKey")
                outsideForward.push(text);
        }
        const all = shown.join("\n");
        if (context.typed.some(text => all.includes(text)))
            return "typed text in an effect, a log or the ignored reason";
        const elsewhere = outsideForward.join("\n");
        if (_keyCharacters.some(character => elsewhere.includes(character)))
            return "a key's character outside forwardKey";
        return "";
    }

    // Typed text lives in `secret` and nowhere else in the state — which is what makes
    // describe() (the state without `secret`) safe. `serialised` is the state as JSON: the
    // secret may be there once, as `secret`; no other typed text and no key's character.
    function _stateLeak(serialised, secret, context) {
        for (const text of context.typed) {
            const first = serialised.indexOf(text);
            if (first < 0)
                continue;
            if (text !== secret || serialised.indexOf(text, first + 1) >= 0)
                return "typed text in the state outside `secret`";
        }
        if (_keyCharacters.some(character => serialised.includes(character)))
            return "a key's character in the state";
        return "";
    }

    function _describeLeak(state, context) {
        const described = JSON.stringify(LockRules.describe(state));
        return context.typed.some(text => described.includes(text)) ? "typed text in describe()" : "";
    }

    // Each of the unlocks, applied to this state, unlocks it and leaves nothing behind
    function _mirrorViolation(state) {
        const unlocks = [{ type: "unlockRequested", source: "logind" }, { type: "compositorFinished", session: state.phase.session }];
        if (state.prompt.owner !== null)
            unlocks.push(key(state.prompt.surfaces[0].id, "Escape"));
        if (state.phase.status === "locked") {
            for (const conversation of LockRules.running(state).conversations)
                unlocks.push({ type: "pamCompleted", method: conversation.method, conversation: conversation.conversation, result: "success" });
        }
        const conversations = LockRules.running(state).conversations;
        for (const event of unlocks) {
            const result = LockRules.step(state, event, 1e12);
            if (result.ignored !== "" || result.state.phase.status !== "unlocked" || !has(result.effects, "unlockCompositor", { session: state.phase.session }))
                return JSON.stringify(event) + " did not unlock (" + result.ignored + ")";
            if (!nothingRunning(result.state))
                return JSON.stringify(event) + " left something running";
            if (!conversations.every(c => has(result.effects, "abortPam", { method: c.method, conversation: c.conversation })
                                     || (event.type === "pamCompleted" && event.method === c.method)))
                return JSON.stringify(event) + " did not abort every conversation";
            if (result.state.sleep.status === "suspending" && result.state.sleep.inhibitor === "held")
                return JSON.stringify(event) + " kept the inhibitor held after the lock ended during a suspend";
        }
        return "";
    }

    function _sweep(sequences, length, seed) {
        const random = _random(seed);
        const settingsSets = [
            { lockOnSleep: true, passwordFallback: fallback }, { lockOnSleep: false, passwordFallback: fallback },
            { lockOnSleep: true, passwordFallback: null }, { lockOnSleep: false, passwordFallback: null }
        ];
        let steps = 0;
        let ignoredSteps = 0;
        let mirrored = 0;
        let livenessChecked = 0;
        let unlocks = 0;
        let relocks = 0;
        let firstFailure = "";
        const statuses = {};
        const ignoredReasons = {};
        const phases = { unlocked: 0, locking: 0, locked: 0 };
        const starts = ["unlocked", "locking", "locked"];
        for (let sequence = 0; sequence < sequences && firstFailure === ""; sequence++) {
            const settings = settingsSets[sequence % settingsSets.length];
            const startAs = starts[sequence % 3];
            const lines = _lineSets[Math.floor(random() * _lineSets.length)];
            const lock = startAs === "unlocked" ? started(settings) : startAs === "locking" ? locking(settings) : locked(lines, settings);
            const context = { typed: [], surfaceCount: 1 };
            const trail = [];
            const livenessAt = Math.floor(random() * length);
            let wasUnlockedAfterLock = false;
            for (let i = 0; i < length; i++) {
                const event = _randomEvent(lock.state, random, context);
                const now = lock.now + [0, 5, 300, 1000, 4000, 11000, 70000][Math.floor(random() * 7)];
                trail.push(event);
                const before = lock.state;
                // Serialising whole states is the costly part: every other step
                const checkInput = i % 2 === 0;
                const frozen = checkInput ? JSON.stringify(before) : "";
                const result = LockRules.step(before, event, now);
                steps++;
                let problem = "";
                if (checkInput && JSON.stringify(before) !== frozen)
                    problem = "the input state was mutated";
                else if (checkInput && _stateLeak(frozen, before.secret, context) !== "")
                    problem = _stateLeak(frozen, before.secret, context);
                else if (result.error === true)
                    problem = "internal error: " + result.ignored;
                else if (result.ignored !== "" && (result.state !== before || result.effects.length > 0))
                    problem = "an ignored event changed something";
                else if (before.phase.status !== "unlocked" && result.state.phase.status === "unlocked")
                    problem = _unlockViolation(before, event, result.state);
                if (problem === "")
                    problem = _violation(before, result.state, result.effects) || _effectLeak(result, context);
                if (result.ignored !== "") {
                    ignoredSteps++;
                    const reason = result.ignored.replace(/: .*/, "");
                    ignoredReasons[reason] = (ignoredReasons[reason] ?? 0) + 1;
                }
                if (before.phase.status !== "unlocked" && result.state.phase.status === "unlocked") {
                    unlocks++;
                    wasUnlockedAfterLock = true;
                }
                if (before.phase.status === "unlocked" && result.state.phase.status !== "unlocked" && wasUnlockedAfterLock)
                    relocks++;
                lock.state = result.state;
                lock.now = now;
                if (problem === "" && i % 4 === 3) {
                    problem = (lock.state.phase.status !== "unlocked" ? _mirrorViolation(lock.state) : "")
                        || (i % 8 === 7 ? _describeLeak(lock.state, context) : "");
                    mirrored++;
                }
                if (problem === "" && i >= livenessAt && lock.state.phase.status !== "unlocked" && livenessChecked < sequence + 1) {
                    const stuck = _liveness(lock.state, lock.now);
                    if (stuck !== "")
                        problem = "liveness: " + stuck;
                    livenessChecked++;
                }
                phases[lock.state.phase.status]++;
                const count = name => statuses[name] = (statuses[name] ?? 0) + 1;
                count("password " + lock.state.password.status);
                for (const method of LockRules.passiveMethods)
                    count(method.name + " " + lock.state.passive[method.name].status);
                count("sleep " + lock.state.sleep.status);
                if (lock.state.password.settling)
                    count("password settling");
                if (lock.state.prompt.surfaces.length > 1)
                    count("several surfaces");
                if (problem !== "") {
                    firstFailure = "sequence " + sequence + " (from " + startAs + "), step " + i + ": " + problem + "\n    events: "
                        + trail.map(item => JSON.stringify(LockRules.describeEvent(item))).join("\n            ");
                    break;
                }
            }
        }
        if (firstFailure !== "")
            fail("sweep: " + firstFailure);
        assert(firstFailure === "", "sweep: " + sequences + " seeded sequences (" + steps + " steps) from unlocked, locking and locked: "
               + "only the unlock events unlock, the invariants hold, no typed text leaks");
        assert(firstFailure !== "" || mirrored >= sequences * 4, "sweep: from " + mirrored + " reached states, each unlock event unlocks and leaves nothing running");
        assert(firstFailure !== "" || livenessChecked >= sequences * 0.8,
               "sweep: liveness from " + livenessChecked + " reached states: the right password unlocks within "
               + livenessSteps + " steps and " + livenessTime / 1000 + " s");
        assert(firstFailure !== "" || ignoredSteps / steps < 0.35, "sweep: most events are taken (" + Math.round(100 * ignoredSteps / steps) + " % ignored)");
        assert(firstFailure !== "" || relocks > sequences / 10, "sweep: sequences unlock (" + unlocks + ") and lock again (" + relocks + ")");
        const reached = ["password pending", "password verifying", "password asking", "password failed", "password unavailable", "password settling",
                         "fingerprint running", "fingerprint backoff", "fingerprint paused", "fingerprint broken", "fingerprint unavailable",
                         "u2f running", "u2f backoff", "u2f broken", "several surfaces", "sleep suspending", "sleep resuming"];
        assert(reached.every(status => statuses[status]), "sweep: the sequences reach every interesting status: missing "
               + reached.filter(status => !statuses[status]).join(", "));
        console.log("  INFO: sweep: " + steps + " steps, " + Math.round(1000 * ignoredSteps / steps) / 10 + " % ignored; steps per phase "
                    + JSON.stringify(phases) + "; unlocks " + unlocks + ", relocks " + relocks + "; mirrored " + mirrored
                    + "; liveness samples " + livenessChecked);
        console.log("  INFO: sweep statuses: " + JSON.stringify(statuses));
        console.log("  INFO: sweep ignored: " + JSON.stringify(ignoredReasons));
    }
}
