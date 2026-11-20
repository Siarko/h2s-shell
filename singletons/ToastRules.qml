pragma Singleton

import Quickshell
import QtQuick

// Where and how long toasts show — pure, so tests/ToastRulesTest.qml checks every case
// without the monitors or a notification server at hand. Notifications holds the live
// answers (`toastScreen`, the shown toasts and their times).
//
// Which screen — notifications' toasts and the shell's own messages:
// A rule and its exception, not two choices side by side:
// - where: the screen with the focused workspace, or a chosen one (by its port: "DP-2");
//   a chosen screen that is not connected falls back to the focused one;
// - when that screen — only that one — has a fullscreen window: show anyway, show
//   nowhere (critical toasts still show there), or show on another screen: a chosen
//   one, or the first without a fullscreen window. A chosen one that has one too, or
//   none free: nowhere.
// Nowhere: the notification goes to the panel only.
Singleton {
    id: root

    // `settings`: { screen: "" (the focused one) or a port, fullscreen: "show" | "hide" |
    // "elsewhere", fullscreenScreen: "" (any free one) or a port }; `screens`: [{ name,
    // focused, fullscreen }] in the compositor's order; `critical`: for a critical toast,
    // which "Don't show" leaves on its screen. → a screen's name, or "" for none.
    function screenFor(settings, screens, critical): string {
        const list = screens ?? [];
        const named = name => list.find(screen => screen.name === name) ?? null;
        const focused = list.find(screen => screen.focused) ?? list[0] ?? null;
        const chosen = settings?.screen ? named(settings.screen) : null;
        const base = chosen ?? focused;
        if (base === null)
            return "";
        if (!base.fullscreen)
            return base.name;
        const behaviour = settings?.fullscreen ?? "show";
        if (behaviour === "hide")
            return critical === true ? base.name : "";
        if (behaviour !== "elsewhere")
            return base.name;
        if (settings?.fullscreenScreen) {
            const target = named(settings.fullscreenScreen);
            return target !== null && target !== base && !target.fullscreen ? target.name : "";
        }
        const free = list.find(screen => screen !== base && !screen.fullscreen);
        return free ? free.name : "";
    }

    // How long a notification's toast shows, from the time its sender asks for (the spec's
    // expire_timeout: -1 the server decides, 0 never expires, else milliseconds). Only the
    // toast: the entry stays in the centre until dismissed.
    // `args`: { expireTimeout, critical, defaultSeconds (the user's "Show each toast for"),
    // followSender (the user's "Apps choose how long"), resident (the spec's hint),
    // residentHide (the user's "Resident notification hide"), shellJob (the shell's own
    // progress handle: hint x-qs-progress-run) }
    // → { ms: how long, 0 for a toast that stays until taken away;
    //     kind: "default" (the user's time: these count down one at a time, the oldest
    //     first), "own" (the sender's time: counts by itself, at once), "stays" }
    // "Apps choose how long" off replaces an outside app's time, 0 included, by the user's;
    // critical ones, resident ones and the shell's own jobs are not an app's time and keep
    // theirs. A resident one the server times (-1) stays, unless the user hides resident
    // ones: then it is like any other. Not for the shell's jobs: Notifier makes every handle
    // resident, so every brief or finished job would stay; theirs is what the handle sends
    // (0 while running when set so, -1 otherwise).
    function timing(args): var {
        const defaultMs = Math.max(1, Number(args?.defaultSeconds) || 5) * 1000;
        if (args?.critical === true)
            return { ms: 0, kind: "stays" };
        const asked = Number(args?.expireTimeout);
        const given = args?.expireTimeout !== undefined && args?.expireTimeout !== null && Number.isFinite(asked);
        const shellJob = args?.shellJob === true;
        const resident = !shellJob && args?.resident === true && args?.residentHide !== true;
        if (resident && (!given || asked <= 0))
            return { ms: 0, kind: "stays" };
        if ((args?.followSender === false && !shellJob) || !given || asked < 0)
            return { ms: defaultMs, kind: "default" };
        if (asked === 0)
            return { ms: 0, kind: "stays" };
        // A shorter time would not be seen
        return { ms: Math.max(1000, Math.round(asked)), kind: "own" };
    }

    // The toast's time alone, in ms; 0: it stays
    function duration(args): int {
        return timing(args).ms;
    }

    // Room for toasts on screen. The layout's slots are for toasts that count down: 1 for
    // "One at a time" (layout "queue"), the column's size (2–10) for "A column". Toasts that
    // stay take none of them: they stack above, at most `maxStaying` (1–5); more wait in the
    // queue. `staying`: how many that stay are on screen now (a toast whose time changed
    // while shown may put it past the limit).
    // → { counting, maxStaying, stayingRoom (how many more that stay may show), total (the
    //     slots that may be in use at once) }
    function slots(layout, columnSize, staying, maxStaying): var {
        const clamp = (value, low, high, fallback) => {
            const number = Math.round(Number(value));
            return Number.isFinite(number) ? Math.min(high, Math.max(low, number)) : fallback;
        };
        const counting = layout === "column" ? clamp(columnSize, 2, 10, 3) : 1;
        const limit = clamp(maxStaying, 1, 5, 3);
        const shown = Math.max(0, Math.round(Number(staying)) || 0);
        return { counting: counting, maxStaying: limit, stayingRoom: Math.max(0, limit - shown), total: counting + limit };
    }

    // Which queued toast a free slot takes: the oldest that has room — one that stays while
    // fewer than the limit stay, any other while the layout's slots are not all taken by
    // toasts that count down. `kinds`: the queue's kinds (timing().kind), oldest first;
    // `countingShown`: the toasts on screen that do not stay; `room`: slots().
    // → its index in the queue, or -1: none fits, they wait
    function nextToast(kinds, countingShown, room): int {
        const list = kinds ?? [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] === "stays" ? room.stayingRoom > 0 : countingShown < room.counting)
                return i;
        }
        return -1;
    }

    // The order of the toasts on screen, top to bottom: those that stay above the others,
    // each group newest first. `shown`: ids oldest first; `staying`: the ids among them
    // that stay.
    function stackOrder(shown, staying): var {
        const newestFirst = (shown ?? []).slice().reverse();
        const stays = id => (staying ?? []).includes(id);
        return newestFirst.filter(stays).concat(newestFirst.filter(id => !stays(id)));
    }

    // ---- The three queues (notes/plans/notification-flow.md §8.2) ----
    // Toasts stack in three queues, top to bottom: critical, staying (they stay until taken
    // away), ordinary (they count down). Each shows up to its limit; the rest wait, oldest
    // first, and its badge counts them. A modal — a toast dragged out of its queue, or a
    // notification pinned from the centre — is out of the queues: it frees its slot and
    // stays where it is put until "×", unpinning or its own end.
    // State, plain data (ids grow with arrival, so "oldest" is the smallest id):
    // { waiting: { critical, staying, ordinary: [ids oldest first] },
    //   shown:   { critical, staying, ordinary: [ids oldest first] },
    //   moved:   [{ id, queue, x, y }] }   the modals; x, y null: not placed yet
    // Every function returns a new state; the one given is never changed.

    readonly property var queues: ["critical", "staying", "ordinary"]

    function emptyState(): var {
        return { waiting: { critical: [], staying: [], ordinary: [] }, shown: { critical: [], staying: [], ordinary: [] }, moved: [] };
    }

    function _copy(state): var {
        const lists = group => ({ critical: (group?.critical ?? []).slice(), staying: (group?.staying ?? []).slice(),
                                  ordinary: (group?.ordinary ?? []).slice() });
        return { waiting: lists(state?.waiting), shown: lists(state?.shown),
                 moved: (state?.moved ?? []).map(entry => ({ id: entry.id, queue: entry.queue, x: entry.x, y: entry.y })) };
    }

    function _clamp(value, low, high, fallback): var {
        const number = Math.round(Number(value));
        return Number.isFinite(number) ? Math.min(high, Math.max(low, number)) : fallback;
    }

    function _insertByAge(list, id): var {
        const copy = list.slice();
        let at = copy.length;
        while (at > 0 && copy[at - 1] > id)
            at--;
        copy.splice(at, 0, id);
        return copy;
    }

    // Which queue a notification goes to. `args`: { critical, timingKind (timing().kind) }.
    // Critical first: a critical one is never in staying.
    function queueFor(args): string {
        if (args?.critical === true)
            return "critical";
        return args?.timingKind === "stays" ? "staying" : "ordinary";
    }

    // How many each queue shows at once. `settings`: { critical (1–3, 1), staying (1–5, 1),
    // layout ("queue" | "column"), columnSize (2–10, 3) }; ordinary: 1 in "One at a time",
    // the column's size in "A column".
    function limits(settings): var {
        return {
            critical: _clamp(settings?.critical, 1, 3, 1),
            staying: _clamp(settings?.staying, 1, 5, 1),
            ordinary: settings?.layout === "column" ? _clamp(settings?.columnSize, 2, 10, 3) : 1
        };
    }

    // Whether a queue takes a new toast now. `conditions`: { toastsOn, centreOpen (an
    // ordinary one is seen in the centre), fullscreenHidden (a fullscreen window on the
    // toasts' screen, "Don't show": only critical ones) }
    function accepts(queue, conditions): bool {
        if (!queues.includes(queue) || conditions?.toastsOn === false)
            return false;
        if (conditions?.fullscreenHidden === true && queue !== "critical")
            return false;
        return !(conditions?.centreOpen === true && queue === "ordinary");
    }

    // Where a notification is: { place: "waiting" | "shown" | "moved" | "none", queue }
    function where(state, id): var {
        for (const queue of queues) {
            if ((state?.shown?.[queue] ?? []).includes(id))
                return { place: "shown", queue: queue };
            if ((state?.waiting?.[queue] ?? []).includes(id))
                return { place: "waiting", queue: queue };
        }
        const modal = (state?.moved ?? []).find(entry => entry.id === id);
        return modal ? { place: "moved", queue: modal.queue } : { place: "none", queue: "" };
    }

    // A modal: moved out of its queue or pinned
    function isModal(state, id): bool {
        return where(state, id).place === "moved";
    }

    // A new toast waits in its queue, by age; one already somewhere stays where it is, and a
    // queue that does not take it now (`conditions`, as accepts(); none: it does) leaves it out
    function enqueue(state, id, queue, conditions): var {
        if (where(state, id).place !== "none" || !queues.includes(queue)
                || (conditions !== undefined && !accepts(queue, conditions)))
            return state;
        const next = _copy(state);
        next.waiting[queue] = _insertByAge(next.waiting[queue], id);
        return next;
    }

    // The toast a free slot of `queue` takes: its oldest waiting while it shows fewer than
    // its limit (`limit`: limits()), else -1. Queues never overtake each other.
    function nextWaiting(state, queue, limit): int {
        if (!queues.includes(queue))
            return -1;
        const waiting = state?.waiting?.[queue] ?? [];
        const shown = state?.shown?.[queue] ?? [];
        return waiting.length > 0 && shown.length < (limit?.[queue] ?? 0) ? waiting[0] : -1;
    }

    // A waiting toast goes on screen, in its queue (the pull form: the slot that takes it)
    function show(state, id): var {
        const at = where(state, id);
        if (at.place !== "waiting")
            return state;
        const next = _copy(state);
        next.waiting[at.queue] = next.waiting[at.queue].filter(entry => entry !== id);
        next.shown[at.queue].push(id);
        return next;
    }

    // Every queue shows its oldest waiting while it has room. → { state, shown: [{ id, queue }] }
    function fill(state, limit): var {
        let next = state;
        const shown = [];
        for (const queue of queues) {
            for (let id = nextWaiting(next, queue, limit); id !== -1; id = nextWaiting(next, queue, limit)) {
                next = show(next, id);
                shown.push({ id: id, queue: queue });
            }
        }
        return { state: next, shown: shown };
    }

    // Off the screen and out of every queue (its time ran out, "×", an action, its entry gone,
    // unpinned)
    function remove(state, id): var {
        const next = _copy(state);
        for (const queue of queues) {
            next.shown[queue] = next.shown[queue].filter(entry => entry !== id);
            next.waiting[queue] = next.waiting[queue].filter(entry => entry !== id);
        }
        next.moved = next.moved.filter(entry => entry.id !== id);
        return next;
    }

    // A waiting toast whose kind changed (a job ended, a sender changed its time) waits in
    // its new queue, by its age — or, when that queue does not take it now (`conditions`, as
    // accepts()), no longer waits. Shown and moved ones keep their place: they count down
    // where they are (counting()).
    function requeue(state, id, queue, conditions): var {
        const at = where(state, id);
        if (at.place !== "waiting" || at.queue === queue || !queues.includes(queue))
            return state;
        const next = _copy(state);
        next.waiting[at.queue] = next.waiting[at.queue].filter(entry => entry !== id);
        if (conditions === undefined || accepts(queue, conditions))
            next.waiting[queue] = _insertByAge(next.waiting[queue], id);
        return next;
    }

    // The centre opened: only the ordinary toasts go, shown and waiting; critical, staying
    // and modals stay. → { state, hidden: [shown ids], dropped: [waiting ids] }
    function centreOpened(state): var {
        const next = _copy(state);
        const result = { state: next, hidden: next.shown.ordinary, dropped: next.waiting.ordinary };
        next.shown.ordinary = [];
        next.waiting.ordinary = [];
        return result;
    }

    // A fullscreen window on the toasts' screen with "Don't show": only critical toasts stay.
    // Staying and ordinary ones go, shown and waiting; modals are kept but not shown while it
    // lasts (onScreen()). → { state, hidden: [shown ids], dropped: [waiting ids] }
    function fullscreenHid(state): var {
        const next = _copy(state);
        const result = { state: next, hidden: next.shown.staying.concat(next.shown.ordinary),
                         dropped: next.waiting.staying.concat(next.waiting.ordinary) };
        next.shown.staying = [];
        next.shown.ordinary = [];
        next.waiting.staying = [];
        next.waiting.ordinary = [];
        return result;
    }

    // Toasts switched off: what waits is dropped, in every queue; shown and modals stay.
    // → { state, dropped }
    function dropWaiting(state): var {
        const next = _copy(state);
        const dropped = next.waiting.critical.concat(next.waiting.staying, next.waiting.ordinary);
        next.waiting = { critical: [], staying: [], ordinary: [] };
        return { state: next, dropped: dropped };
    }

    // What is on screen. `fullscreenHidden`: as accepts(). → { stack: [{ id, queue }] top to
    // bottom — critical, staying, ordinary, each newest first; modals: [{ id, queue, x, y }] }
    function onScreen(state, fullscreenHidden): var {
        const stack = [];
        for (const queue of queues) {
            if (fullscreenHidden === true && queue !== "critical")
                continue;
            for (const id of (state?.shown?.[queue] ?? []).slice().reverse())
                stack.push({ id: id, queue: queue });
        }
        const modals = fullscreenHidden === true ? [] : _copy(state).moved;
        return { stack: stack, modals: modals };
    }

    // Which toasts count down now. `kinds`: { id: timing kind }. In the ordinary queue the
    // sender's time ("own") counts at once, the user's ("default") one at a time, the oldest
    // first. Elsewhere (a job that ended while shown in critical or staying, or a modal)
    // anything that no longer stays counts at once, where it is. → [ids]
    function counting(state, kinds): var {
        const kindOf = id => kinds?.[id] ?? "stays";
        const ids = [];
        let defaultTaken = false;
        for (const id of (state?.shown?.ordinary ?? [])) {
            const kind = kindOf(id);
            if (kind === "own") {
                ids.push(id);
            } else if (kind === "default" && !defaultTaken) {
                ids.push(id);
                defaultTaken = true;
            }
        }
        const others = (state?.shown?.critical ?? []).concat(state?.shown?.staying ?? [],
                                                             (state?.moved ?? []).map(entry => entry.id));
        for (const id of others) {
            if (kindOf(id) !== "stays")
                ids.push(id);
        }
        return ids;
    }

    // How many wait in each queue: { critical, staying, ordinary }
    function badges(state): var {
        return { critical: (state?.waiting?.critical ?? []).length, staying: (state?.waiting?.staying ?? []).length,
                 ordinary: (state?.waiting?.ordinary ?? []).length };
    }

    // A queue's badge: { shown (something waits), label ("+N"), border: "error" (the
    // critical queue's: the critical outline) or "outline" }
    function badgeLook(queue, count): var {
        const number = Math.max(0, Math.round(Number(count)) || 0);
        return { shown: number > 0, label: "+" + number, border: queue === "critical" ? "error" : "outline" };
    }

    // Whether a toast can be dragged: the option is on and it is a critical or staying toast
    // on screen, or a modal already
    function canMove(state, id, movable): bool {
        if (movable !== true)
            return false;
        const at = where(state, id);
        return at.place === "moved" || (at.place === "shown" && (at.queue === "critical" || at.queue === "staying"));
    }

    // Dropped at (x, y): a modal — its queue's slot is free for the next; a modal already
    // just changes place
    function moveOut(state, id, x, y, movable): var {
        if (!canMove(state, id, movable))
            return state;
        const at = where(state, id);
        const next = _copy(state);
        if (at.place === "moved") {
            next.moved = next.moved.map(entry => entry.id === id ? { id: id, queue: entry.queue, x: x, y: y } : entry);
            return next;
        }
        next.shown[at.queue] = next.shown[at.queue].filter(entry => entry !== id);
        next.moved.push({ id: id, queue: at.queue, x: x, y: y });
        return next;
    }

    // Pinned from the centre: a modal, not placed yet (x, y null), whichever queue it is
    // in — or none (`queue`: the one it belongs to); shown or waiting, it leaves that queue.
    // A modal already stays as it is.
    function pin(state, id, queue): var {
        const at = where(state, id);
        if (at.place === "moved" || (at.place === "none" && !queues.includes(queue)))
            return state;
        const next = remove(state, id);
        next.moved.push({ id: id, queue: at.place === "none" ? queue : at.queue, x: null, y: null });
        return next;
    }

    // Its screen gone: a modal waits again in its queue, by age
    function returnToQueue(state, id): var {
        const at = where(state, id);
        if (at.place !== "moved")
            return state;
        const next = remove(state, id);
        next.waiting[at.queue] = _insertByAge(next.waiting[at.queue], id);
        return next;
    }

    // A toast dropped partly off its screen comes back inside it, whole where it fits
    function clampToScreen(x, y, width, height, screenWidth, screenHeight): var {
        const inside = (value, size, room) => {
            const number = Number(value);
            const high = Math.max(0, (Number(room) || 0) - (Number(size) || 0));
            return Number.isFinite(number) ? Math.min(high, Math.max(0, Math.round(number))) : 0;
        };
        return { x: inside(x, width, screenWidth), y: inside(y, height, screenHeight) };
    }

    // A notification announced again (a job started, stalled or ended). `args`: { toastsOn,
    // centreOpen, fullscreenHidden, alive, queue (the one it belongs to now) }
    // → "restart" (on screen: its time starts again), "queue" (back like a new one), "none"
    function announceEffect(state, id, args): string {
        if (args?.alive !== true || args?.toastsOn !== true)
            return "none";
        const at = where(state, id);
        if (at.place === "shown" || at.place === "moved")
            return "restart";
        if (at.place === "waiting")
            return "none";
        return accepts(args.queue, args) ? "queue" : "none";
    }

    // "1/1 shown, 2 wait" for the log
    function describe(state, limit, queue): string {
        const waiting = (state?.waiting?.[queue] ?? []).length;
        return (state?.shown?.[queue] ?? []).length + "/" + (limit?.[queue] ?? 0) + " shown"
            + (waiting > 0 ? ", " + waiting + " wait" : "");
    }
}
