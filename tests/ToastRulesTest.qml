import QtQuick
import qs.singletons

TestCase {
    suiteName: "ToastRules"

    function _screens(focused, fullscreen) {
        return ["DP-2", "HDMI-A-1", "eDP-1"].map(name => ({
            name: name, focused: name === focused, fullscreen: (fullscreen ?? []).includes(name)
        }));
    }

    function run() {
        const at = (settings, screens) => ToastRules.screenFor(settings, screens);
        const defaults = { screen: "", fullscreen: "show", fullscreenScreen: "" };
        const with_ = change => Object.assign({}, defaults, change);

        // --- where ---
        assertEqual(at(defaults, _screens("HDMI-A-1")), "HDMI-A-1", "the focused screen");
        assertEqual(at(with_({ screen: "DP-2" }), _screens("HDMI-A-1")), "DP-2", "a chosen screen, focused or not");
        assertEqual(at(with_({ screen: "DP-3" }), _screens("HDMI-A-1")), "HDMI-A-1",
                    "a chosen screen not connected: the focused one");
        assertEqual(at(defaults, [{ name: "eDP-1", focused: false, fullscreen: false }]), "eDP-1",
                    "none focused (not known yet): the first");
        assertEqual(at(defaults, []), "", "no screens: nowhere");
        assertEqual(at(undefined, _screens("DP-2")), "DP-2", "no settings: the focused screen");

        // --- a fullscreen window on the toasts' screen ---
        assertEqual(at(defaults, _screens("DP-2", ["DP-2"])), "DP-2", "show anyway");
        assertEqual(at(with_({ fullscreen: "hide" }), _screens("DP-2", ["DP-2"])), "", "hide: nowhere");
        assertEqual(at(with_({ fullscreen: "hide" }), _screens("DP-2", ["HDMI-A-1"])), "DP-2",
                    "hide looks at the toasts' screen only: fullscreen elsewhere changes nothing");
        assertEqual(ToastRules.screenFor(with_({ fullscreen: "hide" }), _screens("DP-2", ["DP-2"]), true), "DP-2",
                    "hide: a critical toast still shows on its screen");
        assertEqual(ToastRules.screenFor(with_({ fullscreen: "show" }), _screens("DP-2", ["DP-2"]), true), "DP-2",
                    "show anyway: a critical toast too");
        assertEqual(ToastRules.screenFor(with_({ fullscreen: "elsewhere" }), _screens("DP-2", ["DP-2"]), true), "HDMI-A-1",
                    "elsewhere: a critical toast goes elsewhere like the rest");
        assertEqual(at(with_({ screen: "HDMI-A-1", fullscreen: "hide" }), _screens("DP-2", ["DP-2"])), "HDMI-A-1",
                    "a chosen screen without one: fullscreen on the focused screen changes nothing");

        // --- elsewhere ---
        const elsewhere = with_({ fullscreen: "elsewhere" });
        assertEqual(at(elsewhere, _screens("DP-2", ["DP-2"])), "HDMI-A-1", "any free screen: the first free one");
        assertEqual(at(elsewhere, _screens("HDMI-A-1", ["DP-2", "HDMI-A-1"])), "eDP-1", "skipping others in fullscreen");
        assertEqual(at(elsewhere, _screens("DP-2", ["DP-2", "HDMI-A-1", "eDP-1"])), "", "none free: nowhere");
        assertEqual(at(elsewhere, [{ name: "eDP-1", focused: true, fullscreen: true }]), "",
                    "one screen, in fullscreen: nowhere");
        const onHdmi = with_({ fullscreen: "elsewhere", fullscreenScreen: "HDMI-A-1" });
        assertEqual(at(onHdmi, _screens("DP-2", ["DP-2"])), "HDMI-A-1", "a chosen screen for fullscreen");
        assertEqual(at(onHdmi, _screens("DP-2", ["DP-2", "HDMI-A-1"])), "",
                    "the chosen screen in fullscreen too: nowhere");
        assertEqual(at(onHdmi, _screens("HDMI-A-1", ["HDMI-A-1"])), "",
                    "the chosen screen is the toasts' screen, in fullscreen: nowhere");
        assertEqual(at(with_({ fullscreen: "elsewhere", fullscreenScreen: "DP-3" }), _screens("DP-2", ["DP-2"])), "",
                    "the chosen screen not connected: nowhere");
        assertEqual(at(onHdmi, _screens("DP-2", [])), "DP-2", "no fullscreen window: where it would be");

        // --- how long a toast shows: the sender's time, else the user's ---
        const time = change => ToastRules.timing(Object.assign({ critical: false, defaultSeconds: 5, followSender: true }, change));
        const said = (change, expected, message) => assertEqual(JSON.stringify(time(change)), JSON.stringify(expected), message);
        said({ expireTimeout: -1 }, { ms: 5000, kind: "default" }, "-1 (the server decides): the user's time");
        said({ expireTimeout: -7 }, { ms: 5000, kind: "default" }, "below 0: the user's time");
        said({}, { ms: 5000, kind: "default" }, "absent: the user's time");
        said({ expireTimeout: null }, { ms: 5000, kind: "default" }, "null: the user's time");
        said({ expireTimeout: NaN }, { ms: 5000, kind: "default" }, "NaN: the user's time");
        said({ expireTimeout: "soon" }, { ms: 5000, kind: "default" }, "not a number: the user's time");
        said({ expireTimeout: 0 }, { ms: 0, kind: "stays" }, "0: stays");
        said({ expireTimeout: 500 }, { ms: 1000, kind: "own" }, "500 ms: at least 1 s, counted by itself");
        said({ expireTimeout: 30000 }, { ms: 30000, kind: "own" }, "30 s: 30 s");
        said({ expireTimeout: 2000, defaultSeconds: 12 }, { ms: 2000, kind: "own" }, "the sender's time, not the user's");
        said({ expireTimeout: -1, defaultSeconds: 12 }, { ms: 12000, kind: "default" }, "the user's time as set");
        for (const expire of [-1, undefined, NaN, 0, 500, 30000])
            said({ expireTimeout: expire, critical: true }, { ms: 0, kind: "stays" }, "critical, expire " + expire + ": stays");
        for (const expire of [-1, undefined, NaN, 0, 500, 30000])
            said({ expireTimeout: expire, followSender: false }, { ms: 5000, kind: "default" },
                 "\"Apps choose how long\" off, expire " + expire + ": the user's time");
        said({ expireTimeout: 0, critical: true, followSender: false }, { ms: 0, kind: "stays" },
             "critical with the setting off: still stays");
        assertEqual(ToastRules.duration({ expireTimeout: 2000, defaultSeconds: 5, followSender: true }), 2000, "duration: the time alone");

        // --- resident ones, the shell's own jobs, and "Apps choose how long" off ---
        for (const expire of [-1, undefined, 0])
            said({ expireTimeout: expire, resident: true }, { ms: 0, kind: "stays" }, "resident, expire " + expire + ": stays");
        said({ expireTimeout: 4000, resident: true }, { ms: 4000, kind: "own" }, "resident with a time of its own: that time");
        said({ expireTimeout: -1, resident: true, residentHide: true }, { ms: 5000, kind: "default" },
             "resident hidden: counts down like any other");
        said({ expireTimeout: 0, resident: true, residentHide: true }, { ms: 0, kind: "stays" },
             "resident hidden, the app asks to stay: stays, as any app");
        said({ expireTimeout: -1, resident: true, followSender: false }, { ms: 0, kind: "stays" },
             "\"Apps choose how long\" off: a resident one still stays");
        said({ expireTimeout: 0, resident: true, residentHide: true, followSender: false }, { ms: 5000, kind: "default" },
             "resident hidden and \"Apps choose how long\" off: the user's time");
        said({ expireTimeout: -1, resident: true, shellJob: true }, { ms: 5000, kind: "default" },
             "a shell job (always resident) that is brief or finished: the user's time");
        said({ expireTimeout: 0, resident: true, shellJob: true }, { ms: 0, kind: "stays" },
             "a shell job on screen while running: stays");
        said({ expireTimeout: 0, resident: true, shellJob: true, followSender: false }, { ms: 0, kind: "stays" },
             "\"Apps choose how long\" off: a shell job on screen while running still stays");
        said({ expireTimeout: -1, shellJob: true, followSender: false }, { ms: 5000, kind: "default" },
             "a brief shell job with the setting off: the user's time");
        said({ expireTimeout: 4000, resident: true, followSender: false }, { ms: 4000, kind: "own" },
             "\"Apps choose how long\" off: a resident one keeps its own time");
        said({ expireTimeout: 4000, resident: true, residentHide: true, followSender: false }, { ms: 5000, kind: "default" },
             "resident hidden, \"Apps choose how long\" off: the user's time");
        said({ expireTimeout: 0, followSender: false }, { ms: 5000, kind: "default" },
             "\"Apps choose how long\" off: an app's stay counts down");

        _queues();
    }

    // The three queues (critical, staying, ordinary), over the rules' plain state
    function _queues() {
        const R = ToastRules;
        const json = value => JSON.stringify(value);
        const state = (shown, waiting, moved) => ({
            waiting: Object.assign({ critical: [], staying: [], ordinary: [] }, waiting ?? {}),
            shown: Object.assign({ critical: [], staying: [], ordinary: [] }, shown ?? {}),
            moved: moved ?? []
        });
        const same = (actual, expected, message) => assertEqual(json(actual), json(expected), message);
        const one = R.limits({});
        const empty = R.emptyState();
        same(empty, state(), "empty: nothing shown, nothing waits, no modals");

        // --- which queue ---
        assertEqual(R.queueFor({ critical: true, timingKind: "stays" }), "critical", "queue: critical first");
        assertEqual(R.queueFor({ critical: true, timingKind: "default" }), "critical", "queue: critical whatever its time");
        assertEqual(R.queueFor({ critical: false, timingKind: "stays" }), "staying", "queue: one that stays");
        assertEqual(R.queueFor({ timingKind: "own" }), "ordinary", "queue: the sender's time: ordinary");
        assertEqual(R.queueFor({ timingKind: "default" }), "ordinary", "queue: the user's time: ordinary");
        assertEqual(R.queueFor(undefined), "ordinary", "queue: nothing known: ordinary");
        const kindOf = args => R.queueFor({ critical: args.critical === true, timingKind: R.timing(Object.assign(
            { defaultSeconds: 5, followSender: true }, args)).kind });
        assertEqual(kindOf({ critical: true, expireTimeout: 0 }), "critical", "queue: critical with expire 0 never in staying");
        assertEqual(kindOf({ expireTimeout: -1, resident: true }), "staying", "queue: resident stays");
        assertEqual(kindOf({ expireTimeout: -1, resident: true, residentHide: true }), "ordinary", "queue: resident hidden: ordinary");
        assertEqual(kindOf({ expireTimeout: -1, resident: true, shellJob: true }), "ordinary", "queue: a brief shell job: ordinary");
        assertEqual(kindOf({ expireTimeout: 0, resident: true, shellJob: true }), "staying", "queue: a shell job while running: staying");
        assertEqual(kindOf({ expireTimeout: 0, followSender: false }), "ordinary", "queue: an app's stay with the setting off: ordinary");

        // --- limits ---
        same(one, { critical: 1, staying: 1, ordinary: 1 }, "limits: defaults 1, 1, one at a time");
        same(R.limits({ critical: 3, staying: 5, layout: "column", columnSize: 4 }), { critical: 3, staying: 5, ordinary: 4 },
             "limits: as set");
        same(R.limits({ critical: 0, staying: 0, layout: "column", columnSize: 0 }), { critical: 1, staying: 1, ordinary: 2 },
             "limits: below the least: the least");
        same(R.limits({ critical: 4, staying: 9, layout: "column", columnSize: 25 }), { critical: 3, staying: 5, ordinary: 10 },
             "limits: above the most: the most");
        same(R.limits({ critical: NaN, staying: "x", layout: "column" }), { critical: 1, staying: 1, ordinary: 3 },
             "limits: not numbers: the defaults");
        same(R.limits({ critical: "2", staying: "4", layout: "queue", columnSize: 6 }), { critical: 2, staying: 4, ordinary: 1 },
             "limits: numbers as strings; one at a time ignores the column");

        // --- which queue takes a toast now ---
        assert(R.accepts("ordinary", {}), "accepts: nothing in the way");
        assert(!R.accepts("critical", { toastsOn: false }), "accepts: toasts off, not even critical");
        assert(!R.accepts("ordinary", { centreOpen: true }), "accepts: centre open, no ordinary one");
        assert(R.accepts("staying", { centreOpen: true }) && R.accepts("critical", { centreOpen: true }),
               "accepts: centre open, critical and staying ones still");
        assert(R.accepts("critical", { fullscreenHidden: true }), "accepts: fullscreen \"Don't show\", critical still");
        assert(!R.accepts("staying", { fullscreenHidden: true }) && !R.accepts("ordinary", { fullscreenHidden: true }),
               "accepts: fullscreen \"Don't show\", nothing else");
        assert(!R.accepts("other", {}), "accepts: no such queue");
        assert(!R.accepts("critical", { hasScreen: false }), "accepts: no screen to show it on");
        assert(R.accepts("critical", { hasScreen: true, fullscreenHidden: true }), "accepts: a screen for a critical one");

        // --- enqueue, where, nextWaiting, show, fill ---
        let current = R.enqueue(empty, 1, "ordinary");
        same(current, state({}, { ordinary: [1] }), "enqueue: waits in its queue");
        same(R.where(current, 1), { place: "waiting", queue: "ordinary" }, "where: waiting");
        same(R.where(current, 9), { place: "none", queue: "" }, "where: nowhere");
        assertEqual(R.enqueue(current, 1, "staying"), current, "enqueue: one already in a queue stays where it is");
        assertEqual(R.enqueue(current, 2, "other"), current, "enqueue: no such queue: nothing");
        assertEqual(R.enqueue(current, 2, "ordinary", { centreOpen: true }), current, "enqueue: a queue that does not take it now");
        same(R.enqueue(R.enqueue(empty, 5, "staying"), 3, "staying").waiting.staying, [3, 5], "enqueue: by age");
        assert(empty.waiting.ordinary.length === 0, "enqueue: the state given is never changed");
        assertEqual(R.nextWaiting(empty, "ordinary", one), -1, "next: nothing waits");
        assertEqual(R.nextWaiting(current, "ordinary", one), 1, "next: the oldest waiting, room in its queue");
        assertEqual(R.nextWaiting(current, "other", one), -1, "next: no such queue");
        current = R.show(current, 1);
        same(current, state({ ordinary: [1] }), "show: from waiting to shown");
        same(R.where(current, 1), { place: "shown", queue: "ordinary" }, "where: shown");
        assertEqual(R.show(current, 1), current, "show: one shown already: nothing");
        current = R.enqueue(R.enqueue(current, 2, "ordinary"), 3, "staying");
        assertEqual(R.nextWaiting(current, "ordinary", one), -1, "next: its queue full, it waits");
        assertEqual(R.nextWaiting(current, "staying", one), 3, "next: another queue full does not hold this one");
        assertEqual(R.nextWaiting(current, "ordinary", R.limits({ layout: "column", columnSize: 2 })), 2, "next: a column has room");
        const filled = R.fill(R.enqueue(current, 4, "critical"), one);
        same(filled.shown, [{ id: 4, queue: "critical" }, { id: 3, queue: "staying" }], "fill: every queue with room takes its oldest");
        same(filled.state, state({ critical: [4], staying: [3], ordinary: [1] }, { ordinary: [2] }), "fill: the rest waits");

        // --- the mockup's scenario: two critical with limit 1, staying and ordinary fill apart ---
        let screen = empty;
        for (const [id, queue] of [[1, "critical"], [2, "critical"], [3, "staying"], [4, "staying"], [5, "ordinary"], [6, "ordinary"]])
            screen = R.fill(R.enqueue(screen, id, queue), one).state;
        same(screen, state({ critical: [1], staying: [3], ordinary: [5] }, { critical: [2], staying: [4], ordinary: [6] }),
             "scenario: one of each shown, one of each waits");
        same(R.badges(screen), { critical: 1, staying: 1, ordinary: 1 }, "badges: one waits in each");
        assertEqual(R.describe(screen, one, "critical"), "1/1 shown, 1 wait", "describe: shown and waiting");
        assertEqual(R.describe(empty, one, "staying"), "0/1 shown", "describe: nothing waits");
        same(R.onScreen(screen).stack, [{ id: 1, queue: "critical" }, { id: 3, queue: "staying" }, { id: 5, queue: "ordinary" }],
             "on screen: critical, staying, ordinary");
        same(R.onScreen(R.fill(screen, { critical: 2, staying: 2, ordinary: 2 }).state).stack.map(entry => entry.id), [2, 1, 4, 3, 6, 5],
             "on screen: each queue newest first");

        // --- remove ---
        same(R.fill(R.remove(screen, 1), one).state.shown.critical, [2], "remove: a shown one frees its slot for the next");
        same(R.remove(screen, 4).waiting.staying, [], "remove: a waiting one no longer waits");
        same(R.remove(empty, 7), empty, "remove: one nowhere: nothing changes");

        // --- a job's kind changes ---
        let job = R.requeue(screen, 4, "ordinary");
        same(job.waiting, { critical: [2], staying: [], ordinary: [4, 6] }, "requeue: a job ending while it waits in staying goes to ordinary, by age");
        same(R.requeue(screen, 3, "ordinary"), screen, "requeue: one shown keeps its place");
        same(R.requeue(screen, 4, "staying"), screen, "requeue: the same queue: nothing");
        same(R.requeue(screen, 4, "ordinary", { centreOpen: true }).waiting, { critical: [2], staying: [], ordinary: [6] },
             "requeue: to ordinary while the centre is open: no longer waits");
        const toStaying = R.requeue(screen, 5, "staying", {}, one);
        same(toStaying, state({ critical: [1], staying: [3] }, { critical: [2], staying: [4, 5], ordinary: [6] }),
             "requeue: a shown ordinary one that now stays leaves the ordinary slot, waits in staying (full), by age");
        same(R.nextWaiting(toStaying, "ordinary", one), 6, "requeue: the ordinary slot is free for the next");
        same(R.requeue(screen, 5, "staying", {}, R.limits({ staying: 2 })).shown, { critical: [1], staying: [3, 5], ordinary: [] },
             "requeue: a shown ordinary one that now stays shows in staying when it has room");
        same(R.requeue(screen, 5, "staying").waiting.staying, [4, 5], "requeue: no limits given: the defaults");
        same(R.requeue(screen, 5, "staying", { fullscreenHidden: true }, one), screen,
             "requeue: staying does not take it now: it stays where it is");
        assert(R.canMove(R.requeue(screen, 5, "staying", {}, R.limits({ staying: 2 })), 5, true),
               "requeue: in staying it can be moved");
        same(R.counting(screen, { 1: "stays", 3: "stays", 5: "default" }), [5],
             "counting: critical and staying stay, ordinary counts");
        same(R.counting(screen, { 1: "stays", 3: "default", 5: "own" }), [5, 3],
             "counting: a job ended while shown in staying counts where it is");
        same(R.counting(state({ ordinary: [1, 2, 3, 4] }), { 1: "default", 2: "own", 3: "default", 4: "own" }), [1, 2, 4],
             "counting: the user's time one at a time, the oldest; the sender's at once");
        same(R.counting(state({}, {}, [{ id: 8, queue: "staying", x: 0, y: 0 }, { id: 9, queue: "critical", x: 0, y: 0 }]), { 8: "default" }), [8],
             "counting: a modal that no longer stays counts; one unknown stays");

        // --- the centre opens ---
        const opened = R.centreOpened(screen);
        same(opened.hidden, [5], "centre: the shown ordinary ones go");
        same(opened.dropped, [6], "centre: the waiting ordinary ones are dropped");
        same(opened.state, state({ critical: [1], staying: [3] }, { critical: [2], staying: [4] }), "centre: critical and staying stay, shown and waiting");
        same(R.centreOpened(R.moveOut(screen, 3, 10, 20, true)).state.moved, [{ id: 3, queue: "staying", x: 10, y: 20 }], "centre: modals stay");

        // --- fullscreen "Don't show": only critical ---
        const hid = R.fullscreenHid(R.moveOut(screen, 1, 5, 5, true));
        same(hid.hidden, [3, 5], "fullscreen: shown staying and ordinary go");
        same(hid.dropped, [4, 6], "fullscreen: their waiting ones are dropped");
        same(hid.state.waiting.critical, [2], "fullscreen: critical ones still wait");
        same(R.onScreen(R.fill(hid.state, one).state, true), { stack: [{ id: 2, queue: "critical" }], modals: [] },
             "fullscreen: only critical shown; modals kept but not shown");
        same(R.onScreen(hid.state, false).modals, [{ id: 1, queue: "critical", x: 5, y: 5 }], "fullscreen gone: the modals show again");

        // --- toasts off ---
        const off = R.dropWaiting(screen);
        same(off.dropped, [2, 4, 6], "toasts off: what waits is dropped, every queue");
        same(off.state, state({ critical: [1], staying: [3], ordinary: [5] }), "toasts off: shown ones stay");

        // --- badges ---
        same(R.badges(empty), { critical: 0, staying: 0, ordinary: 0 }, "badges: nothing waits");
        same(R.badgeLook("critical", 2), { shown: true, label: "+2", border: "error" }, "badge: critical, the critical outline");
        same(R.badgeLook("staying", 1), { shown: true, label: "+1", border: "outline" }, "badge: staying, the usual outline");
        same(R.badgeLook("ordinary", 0), { shown: false, label: "+0", border: "outline" }, "badge: nothing waits: not shown");
        same(R.badgeLook("ordinary", NaN).shown, false, "badge: not a number: not shown");

        // --- modals: moved out ---
        assert(!R.canMove(screen, 3, false), "move: the option off");
        assert(R.canMove(screen, 1, true) && R.canMove(screen, 3, true), "move: critical and staying shown");
        assert(!R.canMove(screen, 5, true), "move: not an ordinary one");
        assert(!R.canMove(screen, 4, true), "move: not one waiting");
        const moved = R.moveOut(screen, 3, 100, 200, true);
        same(moved.moved, [{ id: 3, queue: "staying", x: 100, y: 200 }], "move: a modal at its place");
        assert(R.isModal(moved, 3) && !R.isModal(moved, 1), "modal: the flag");
        same(R.where(moved, 3), { place: "moved", queue: "staying" }, "where: moved, its queue kept");
        same(R.nextWaiting(moved, "staying", one), 4, "move: its slot is free for the next");
        same(R.fill(moved, one).state.shown.staying, [4], "move: the next shows in its slot");
        same(R.moveOut(moved, 3, 7, 8, true).moved, [{ id: 3, queue: "staying", x: 7, y: 8 }], "move: a modal again just changes place");
        assert(R.canMove(moved, 3, true), "move: a modal can be moved again");
        same(R.moveOut(screen, 5, 1, 1, true), screen, "move: not allowed: nothing");
        same(R.onScreen(moved).modals, [{ id: 3, queue: "staying", x: 100, y: 200 }], "on screen: the modals apart from the stack");
        same(R.onScreen(moved).stack.map(entry => entry.id), [1, 5], "on screen: a modal is not in the stack");
        same(R.remove(moved, 3).moved, [], "remove: a modal ends (\"×\", unpinned, its time ran out)");
        same(R.announceEffect(moved, 3, { toastsOn: true, hasScreen: true, alive: true, queue: "ordinary" }), "restart", "announce: a modal starts its time again");

        // --- modals: pinned from the centre ---
        same(R.pin(empty, 9, "ordinary").moved, [{ id: 9, queue: "ordinary", x: null, y: null }], "pin: one in no queue, not placed yet");
        same(R.pin(screen, 4, "staying").waiting.staying, [], "pin: a waiting one leaves its queue");
        const pinned = R.pin(screen, 5, "ordinary");
        same(pinned.shown.ordinary, [], "pin: a shown one frees its slot");
        same(R.nextWaiting(pinned, "ordinary", one), 6, "pin: the next takes the slot");
        same(R.pin(moved, 3, "staying"), moved, "pin: a modal already stays as it is");
        same(R.pin(empty, 9, "other"), empty, "pin: no queue known: nothing");
        same(R.pin(empty, 9, "ordinary", "default").moved, [{ id: 9, queue: "ordinary", x: null, y: null, keep: true }],
             "pin: one that counts down is kept on screen (keep)");
        same(R.pin(empty, 9, "staying", "stays").moved, [{ id: 9, queue: "staying", x: null, y: null }], "pin: one that stays: kept by its kind");
        const kept = R.pin(screen, 5, "ordinary", "default");
        same(R.counting(kept, { 5: "default" }), [], "counting: a pinned one kept: no countdown");
        same(R.counting(R.moveOut(screen, 3, 1, 1, true), { 1: "stays", 3: "own" }), [3], "counting: a modal dragged out whose job ended counts");
        const running = R.modalRetimed(kept, 5, "stays");
        same(running.moved, [{ id: 5, queue: "staying", x: null, y: null }], "retimed: a kept modal that now stays is kept by its kind");
        same(R.counting(running, { 5: "own" }), [5], "… so when it stops staying it counts");
        same(R.modalRetimed(kept, 5, "own"), kept, "retimed: still counting: still kept");
        same(R.modalRetimed(screen, 3, "stays"), screen, "retimed: not a modal: nothing");
        const draggedPinned = R.moveOut(R.placeModal(kept, 5, 40, 60), 5, 300, 400, true);
        same(draggedPinned.moved, [{ id: 5, queue: "ordinary", x: 300, y: 400, keep: true }], "move: a pinned modal dragged keeps its keep");
        same(R.counting(draggedPinned, { 5: "default" }), [], "… and still does not count down");
        same(R.modalRetimed(kept, 5, "stays", "staying").moved, [{ id: 5, queue: "staying", x: null, y: null }],
             "retimed: its queue follows the new kind");
        same(R.returnToQueue(R.modalRetimed(kept, 5, "default", "staying"), 5).waiting.staying, [4, 5],
             "… so its screen gone, it waits in its new queue");
        same(R.modalRetimed(kept, 5, "default", "ordinary"), kept, "retimed: same queue, still counting: nothing");
        same(R.modalRetimed(kept, 5, "default", "none").moved, kept.moved, "retimed: no valid queue, still counting: the ordinary one its kind gives");
        same(R.modalRetimed(kept, 5, "stays", undefined).moved, [{ id: 5, queue: "staying", x: null, y: null }],
             "retimed: no valid queue, now staying: the staying queue");
        const criticalModal = { waiting: { critical: [], staying: [], ordinary: [] }, shown: { critical: [], staying: [], ordinary: [] },
                                moved: [{ id: 8, queue: "critical", x: 10, y: 20 }] };
        same(R.modalRetimed(criticalModal, 8, "default", ""), criticalModal, "retimed: no valid queue, a critical one stays critical");
        same(R.modalRetimed(R.modalRetimed(kept, 5, "stays", "staying"), 5, "default", "bogus").moved, [{ id: 5, queue: "ordinary", x: null, y: null }],
             "retimed: a staying modal whose job ended, no valid queue: back to ordinary");
        same(R.dropWaiting(kept).state.moved, kept.moved, "toasts off: keep survives a copy");

        // --- modals: placed ---
        same(R.placeModal(kept, 5, 40, 60).moved, [{ id: 5, queue: "ordinary", x: 40, y: 60, keep: true }], "place: a pinned modal at its first place");
        same(R.placeModal(screen, 3, 1, 1), screen, "place: not a modal: nothing");
        const spotArgs = { modals: [], width: 360, height: 100, screenWidth: 1920, screenHeight: 1080, column: 1520, top: 56, gap: 16 };
        same(R.pinSpot(spotArgs), { x: 1144, y: 56 }, "pin spot: left of the toasts' column, at the top");
        same(R.pinSpot(Object.assign({}, spotArgs, { modals: [{ x: 1144, y: 56 }, { x: 1144, y: 104 }, { x: 10, y: 152 }, { x: null, y: null }] })),
             { x: 1144, y: 152 }, "pin spot: below the ones there (a step each), others and unplaced ones ignored");
        same(R.pinSpot(Object.assign({}, spotArgs, { top: 1050 })), { x: 1144, y: 980 }, "pin spot: inside the screen");
        same(R.pinSpot(Object.assign({}, spotArgs, { column: 100 })).x, 0, "pin spot: a narrow screen: at its left");

        // --- the centre's pin control: label and effect together ---
        assertEqual(R.pinScreen("DP-2", "HDMI-A-1"), "DP-2", "pinned from the centre: the centre's screen");
        assertEqual(R.pinScreen("", "HDMI-A-1"), "HDMI-A-1", "… not known: the toasts' screen");
        assertEqual(R.pinScreen(undefined, ""), "", "… neither: nowhere");
        assertEqual(R.showsTimer({ staying: true, modal: false, counting: false }), false, "timer bar: a staying toast has none");
        assertEqual(R.showsTimer({ staying: false, modal: false, counting: false }), true, "timer bar: an ordinary one waiting its turn shows it full");
        assertEqual(R.showsTimer({ staying: false, modal: false, counting: true }), true, "timer bar: counting: shown");
        assertEqual(R.showsTimer({ staying: false, modal: true, counting: false }), false, "timer bar: a pinned (kept) modal not counting: none");
        assertEqual(R.showsTimer({ staying: false, modal: true, counting: true }), true, "timer bar: a modal counting (its job ended): shown");
        assertEqual(R.showsTimer({ staying: true, modal: true, counting: false }), false, "timer bar: a staying modal: none");
        same(R.pinLook(false), { glyph: "󰐃", tip: "Pin on the screen", action: "pin" }, "pin control: not a modal: pins");
        same(R.pinLook(true), { glyph: "󰐄", tip: "Unpin from the screen", action: "unpin" }, "pin control: a modal: unpins");

        // --- modals: their screen gone ---
        same(R.returnToQueue(moved, 3).waiting.staying, [3, 4], "screen gone: a modal waits again, by age");
        same(R.returnToQueue(moved, 3).moved, [], "screen gone: no longer a modal");
        same(R.returnToQueue(screen, 1), screen, "screen gone: not a modal: nothing");

        // --- a toast dropped partly off its screen ---
        same(R.clampToScreen(100, 50, 300, 100, 1920, 1080), { x: 100, y: 50 }, "clamp: inside: where dropped");
        same(R.clampToScreen(1800, 1000, 300, 100, 1920, 1080), { x: 1620, y: 980 }, "clamp: past the right and bottom: inside");
        same(R.clampToScreen(-150, -20, 300, 100, 1920, 1080), { x: 0, y: 0 }, "clamp: past the left and top: inside");
        same(R.clampToScreen(10, 10, 2000, 100, 1920, 1080), { x: 0, y: 10 }, "clamp: wider than the screen: at its left");
        same(R.clampToScreen(NaN, "x", 300, 100, 1920, 1080), { x: 0, y: 0 }, "clamp: not numbers: the corner");
        const topBar = { top: 40, bottom: 0, left: 0, right: 0 };
        same(R.clampToScreen(100, 10, 300, 100, 1920, 1080, topBar), { x: 100, y: 40 }, "clamp: onto a top bar: below it");
        same(R.clampToScreen(100, 1000, 300, 100, 1920, 1080, { top: 0, bottom: 40, left: 0, right: 0 }), { x: 100, y: 940 }, "clamp: onto a bottom bar: above it");
        same(R.clampToScreen(-50, 500, 300, 100, 1920, 1080, { top: 0, bottom: 0, left: 48, right: 0 }), { x: 48, y: 500 }, "clamp: onto a left bar: right of it");
        same(R.clampToScreen(1800, 500, 300, 100, 1920, 1080, { top: 0, bottom: 0, left: 0, right: 48 }), { x: 1572, y: 500 }, "clamp: onto a right bar: left of it");
        same(R.clampToScreen(NaN, NaN, 300, 100, 1920, 1080, topBar), { x: 0, y: 40 }, "clamp: not numbers: the corner off the bar");
        same(R.pinSpot(Object.assign({}, spotArgs, { top: 1050, insets: { top: 0, bottom: 40, left: 0, right: 0 } })).y, 940, "pin spot: off a bottom bar");

        // --- the toasts' column beside the open centre ---
        const edgeArgs = change => Object.assign({ screenWidth: 1920, insets: topBar, centre: null, reach: 432, gap: 16 }, change);
        same(R.stackEdge(edgeArgs()), { right: 1920, free: false }, "stack edge: centre closed: the screen's edge");
        same(R.stackEdge(edgeArgs({ insets: { top: 0, bottom: 0, left: 0, right: 48 } })), { right: 1872, free: false }, "stack edge: a right bar: off it");
        same(R.stackEdge(edgeArgs({ centre: { x: 1440, y: 40, width: 470, height: 700 } })), { right: 1424, free: true }, "stack edge: centre open at the right: left of it, by the gap");
        same(R.stackEdge(edgeArgs({ centre: { x: 1440.6, y: 40, width: 470, height: 700 } })).right, 1425, "stack edge: on whole pixels");
        same(R.stackEdge(edgeArgs({ centre: { x: 1200, y: 40, width: 470, height: 700 } })), { right: 1184, free: true }, "stack edge: centre reaching into the column: left of it");
        same(R.stackEdge(edgeArgs({ centre: { x: 60, y: 0, width: 470, height: 700 } })), { right: 1920, free: false }, "stack edge: centre away from the column (a left bar): where it was");
        same(R.stackEdge(edgeArgs({ centre: { x: 1488, y: 0, width: 0, height: 0 } })), { right: 1920, free: false }, "stack edge: a centre of no width: where it was");
        same(R.stackEdge(edgeArgs({ centre: { x: 100, y: 0, width: 1800, height: 700 } })), { right: 432, free: true }, "stack edge: a centre as wide as the screen: the column stays on it");
        same(R.stackEdge(edgeArgs({ centre: { x: "x", width: 470 } })), { right: 1920, free: false }, "stack edge: not numbers: where it was");
        same(R.stackEdge(undefined), { right: 0, free: false }, "stack edge: nothing known");

        // --- a click on a badge ---
        assertEqual(R.badgeClick("DP-1", "DP-1", false), "open", "badge click: its screen's bar, centre closed: opens there");
        assertEqual(R.badgeClick("DP-1", "DP-1", true), "close", "badge click: its screen's bar, centre open there: closes");
        assertEqual(R.badgeClick("DP-1", "eDP-1", false), "none", "badge click: another screen's bar: nothing (not the other monitor)");
        assertEqual(R.badgeClick("DP-1", "eDP-1", true), "none", "badge click: centre open on another screen: that bar leaves it, the badge's opens and closes it");
        assertEqual(R.badgeClick("", "", false), "none", "badge click: the screen not known: nothing");
        assertEqual(R.badgeClick(undefined, undefined, false), "none", "badge click: nothing known: nothing");

        // --- a notification announced again ---
        const announce = (id, change) => R.announceEffect(screen, id, Object.assign({ toastsOn: true, hasScreen: true, alive: true, centreOpen: false, queue: "ordinary" }, change));
        assertEqual(announce(5), "restart", "announce: shown: its time starts again");
        assertEqual(announce(6), "none", "announce: waiting already: nothing");
        assertEqual(announce(7), "queue", "announce: off screen: back like a new one");
        assertEqual(announce(7, { centreOpen: true }), "none", "announce: ordinary while the centre is open: nothing");
        assertEqual(announce(7, { centreOpen: true, queue: "staying" }), "queue", "announce: staying while the centre is open: queued");
        assertEqual(announce(7, { fullscreenHidden: true, queue: "staying" }), "none", "announce: fullscreen \"Don't show\": not staying");
        assertEqual(announce(7, { fullscreenHidden: true, queue: "critical" }), "queue", "announce: fullscreen \"Don't show\": critical still");
        assertEqual(announce(5, { toastsOn: false }), "none", "announce: toasts off: nothing");
        assertEqual(announce(5, { alive: false }), "none", "announce: its entry gone: nothing");
        assertEqual(announce(7, { hasScreen: false }), "none", "announce: no screen to show it on: not queued");
        assertEqual(announce(5, { hasScreen: false }), "none", "announce: no screen: nothing, as before");
        assertEqual(announce(7, { hasScreen: undefined }), "none", "announce: the screen not known: nothing");
        assertEqual(announce(5, { centreOpen: true }), "restart", "announce: shown while the centre is open (one that stays there): its time starts again");
        assertEqual(R.announceEffect(screen, 7, undefined), "none", "announce: nothing known: nothing");
    }
}
