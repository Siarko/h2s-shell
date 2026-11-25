pragma Singleton

import Quickshell
import QtQuick

// Which interaction an input event on a bar cell is, which binding it runs and which action
// of that binding runs now. Pure functions, so tests/InteractionRulesTest.qml checks every
// decision without a screen; the cell's input layer feeds them what Qt reports.
//
// The words used here:
// - an interaction is a name ("leftClick", "tap", "scrollUp", …);
// - a ref names one action: { action: "own:<id>" }, { action: "shell:<id>", …args },
//   { action: "command", command, root, movement }, or null — explicitly nothing;
// - a binding is what one interaction runs: { mode: "single", action: ref },
//   { mode: "pair", on: ref, off: ref } (start and end of an interaction with a natural
//   end) or { mode: "cycle", actions: [ref, …] } (alternate is a cycle of two);
// - a resolved binding is undefined (unassigned: nothing stored, nothing declared), null
//   (bound to nothing, which stops a finger's fallback) or a binding.
Singleton {
    id: root

    // ---- The interactions -----------------------------------------------------------------

    // Pointer (mouse, touchpad, stylus): the ones the editor shows first
    readonly property var _corePointer: ["leftClick", "middleClick", "rightClick", "scroll", "scrollUp", "scrollDown", "hover"]
    // Pointer: behind "More interactions"
    readonly property var _morePointer: ["doubleClick", "longPress", "shiftClick", "ctrlClick", "altClick", "scrollLeft", "scrollRight", "scrollSideways"]
    // Finger: told apart from the pointer per event
    readonly property var _finger: ["tap", "doubleTap", "touchHold", "swipeLeft", "swipeRight", "swipeUp", "swipeDown"]

    // Each a new copy: a list handed out is never one shared value
    function coreInteractions(): var {
        return _corePointer.slice();
    }
    function moreInteractions(): var {
        return _morePointer.slice();
    }
    function fingerInteractions(): var {
        return _finger.slice();
    }
    function interactions(): var {
        return _corePointer.concat(_morePointer, _finger);
    }

    function isInteraction(name): bool {
        return typeof name === "string" && interactions().includes(name);
    }

    // Continuous movement: takes an `adjust` action or a command, the amount as measured
    function isMovement(interaction): bool {
        return interaction === "scroll" || interaction === "scrollSideways";
    }

    // One step of a movement in a direction: any action; an `adjust` one gets ±1
    function isStepped(interaction): bool {
        return ["scrollUp", "scrollDown", "scrollLeft", "scrollRight", "swipeLeft", "swipeRight", "swipeUp", "swipeDown"].includes(interaction);
    }

    // Interactions with a natural end, so a pair runs one action at the start, one at the end
    function hasEnd(interaction): bool {
        return interaction === "hover" || interaction === "longPress" || interaction === "touchHold";
    }

    // Where an action may run each time the pointer or a finger passes by, without a click
    function isPassing(interaction): bool {
        return interaction === "hover" || isMovement(interaction) || isStepped(interaction);
    }

    // The modes the editor offers for an interaction (alternate and cycle are one stored
    // mode, two names)
    function modesFor(interaction): var {
        if (!isInteraction(interaction))
            return [];
        return hasEnd(interaction) ? ["single", "pair", "alternate", "cycle"] : ["single", "alternate", "cycle"];
    }

    // The mode's name in the editor: a cycle of two is "alternate"
    function modeName(binding): string {
        if (!binding)
            return "";
        if (binding.mode === "cycle")
            return binding.actions.length === 2 ? "alternate" : "cycle";
        return binding.mode;
    }

    // ---- Which interaction an event is -----------------------------------------------------

    // A press that ended. `event`: { button (Qt.LeftButton, …), modifiers, byTouch, held (the
    // press-and-hold fired: its release is no click), second (the second click of a double
    // click, only counted where one waits, waitsForDouble), swiped (a finger swipe took it) }.
    // "" when it is no interaction: a release after a swipe, a modifier combination
    // with no name (Super is the compositor's), a button the cell does not take.
    function pressInteraction(event): string {
        if (!event || event.swiped)
            return "";
        if (event.byTouch) {
            if (event.held)
                return "touchHold";
            return event.second ? "doubleTap" : "tap";
        }
        // Middle and right clicks ignore modifiers, as the middle click always has, and a
        // hold: only the left button has a long press, so theirs is still the click
        if (event.button === Qt.MiddleButton)
            return "middleClick";
        if (event.button === Qt.RightButton)
            return "rightClick";
        if (event.button !== Qt.LeftButton)
            return "";
        if (event.held)
            return "longPress";
        const modifiers = event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (modifiers === 0)
            return event.second ? "doubleClick" : "leftClick";
        if (modifiers === Qt.ShiftModifier)
            return "shiftClick";
        if (modifiers === Qt.ControlModifier)
            return "ctrlClick";
        if (modifiers === Qt.AltModifier)
            return "altClick";
        return "";
    }

    // The hold fired: what it starts now (its release ends a pair). A middle or right button
    // held is still its click on release.
    function holdInteraction(button, byTouch): string {
        if (byTouch)
            return "touchHold";
        return button === Qt.LeftButton ? "longPress" : "";
    }

    // Hover is the pointer's only: a finger's press comes with a hover that means nothing
    function hoverInteraction(byTouch): string {
        return byTouch ? "" : "hover";
    }

    // Whether a press `nowMs` is the second of a double click after the first at `firstMs`
    // (-1: none), with the system's interval
    function isSecondClick(firstMs, nowMs, intervalMs): bool {
        return firstMs >= 0 && nowMs >= firstMs && nowMs - firstMs <= intervalMs;
    }

    // Whether a plain left click (a tap by finger) waits the double-click interval before it
    // runs: only when a double click (a double tap, or its fallback) is bound — otherwise
    // every click runs at once and a quick second one is another click
    function waitsForDouble(byTouch, lookup): bool {
        return isBound(effective(byTouch ? "doubleTap" : "doubleClick", lookup).binding);
    }

    // A wheel event on one axis ("vertical" or "horizontal"). `notches` is the movement in
    // notches, signed as Qt's angleDelta (positive is up, and on the horizontal axis left);
    // `whole` the signed whole notches it completed (ScrollNotches.feed). The continuous
    // interaction takes it when it is bound to an action, else each whole notch is a step.
    // [{ interaction, amount, direction, times }]: amount positive up and right.
    function scrollInteractions(axis, notches, whole, lookup): var {
        const vertical = axis === "vertical";
        const continuous = vertical ? "scroll" : "scrollSideways";
        const sign = vertical ? 1 : -1;
        if (isBound(effective(continuous, lookup).binding)) {
            const amount = sign * notches;
            if (amount === 0 || !isFinite(amount))
                return [];
            return [{ interaction: continuous, amount: amount, direction: direction(vertical, amount), times: 1 }];
        }
        const steps = sign * whole;
        const forward = Math.sign(steps);
        if (forward !== 1 && forward !== -1)
            return [];
        const step = vertical ? (forward === 1 ? "scrollUp" : "scrollDown") : (forward === 1 ? "scrollRight" : "scrollLeft");
        return [{ interaction: step, amount: forward, direction: direction(vertical, steps), times: Math.abs(Math.round(steps)) }];
    }

    function direction(vertical, amount): string {
        const forward = Math.sign(amount) === 1;
        if (vertical)
            return forward ? "up" : "down";
        return forward ? "right" : "left";
    }

    // A finger drag that ended: `deltaX`/`deltaY` in px (down and right positive), `meantX`/
    // `meantY` whether that axis went far or fast enough (SwipeGesture.meant). The larger
    // axis decides; not meant: "" and the release may be a tap.
    function swipeInteraction(deltaX, deltaY, meantX, meantY): string {
        if (Math.abs(deltaX) >= Math.abs(deltaY)) {
            if (!meantX || deltaX === 0)
                return "";
            return Math.sign(deltaX) === 1 ? "swipeRight" : "swipeLeft";
        }
        if (!meantY)
            return "";
        return Math.sign(deltaY) === 1 ? "swipeDown" : "swipeUp";
    }

    // The swipes a cell offers: on a top or bottom bar the up/down pair crosses the cell's
    // short side, on a left or right bar the left/right pair; that pair only where a swipe
    // that short can be told from a tap (`shortAxisWorks`)
    function offeredSwipes(barVertical, shortAxisWorks): var {
        const longPair = barVertical ? ["swipeUp", "swipeDown"] : ["swipeLeft", "swipeRight"];
        const shortPair = barVertical ? ["swipeLeft", "swipeRight"] : ["swipeUp", "swipeDown"];
        return shortAxisWorks ? longPair.concat(shortPair) : longPair;
    }

    // What one step of a stepped interaction is to an `adjust` action
    function stepAmount(interaction): int {
        if (["scrollUp", "scrollRight", "swipeUp", "swipeRight"].includes(interaction))
            return 1;
        if (["scrollDown", "scrollLeft", "swipeDown", "swipeLeft"].includes(interaction))
            return -1;
        return 0;
    }

    function stepDirection(interaction): string {
        const words = { scrollUp: "up", scrollDown: "down", scrollLeft: "left", scrollRight: "right",
                        swipeUp: "up", swipeDown: "down", swipeLeft: "left", swipeRight: "right" };
        return Object.prototype.hasOwnProperty.call(words, interaction) ? words[interaction] : "";
    }

    // ---- Binding shape ---------------------------------------------------------------------

    function _plainObject(value): bool {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function _own(object, key) {
        return Object.prototype.hasOwnProperty.call(object, key) ? object[key] : undefined;
    }

    readonly property var _idPattern: /^[A-Za-z][A-Za-z0-9_.-]*$/
    readonly property var _variablePattern: /^[A-Za-z_][A-Za-z0-9_]*$/

    // How a command wants a movement, besides H2S_AMOUNT and H2S_DIRECTION: as its first
    // parameter or under a variable the user names; the signed amount or the direction word
    function validMovement(movement): bool {
        if (movement === undefined)
            return true;
        if (!_plainObject(movement))
            return false;
        const form = _own(movement, "form");
        if (form !== undefined && form !== "amount" && form !== "direction")
            return false;
        const to = _own(movement, "to");
        if (to === "parameter")
            return true;
        if (to === "variable")
            return typeof _own(movement, "name") === "string" && _variablePattern.test(movement.name);
        return false;
    }

    // One action reference; null is "nothing". `ownIds` (optional): the widget's declared
    // actions, an own ref naming another counts as invalid.
    function validRef(ref, ownIds): bool {
        if (ref === null)
            return true;
        if (!_plainObject(ref))
            return false;
        const action = _own(ref, "action");
        if (typeof action !== "string")
            return false;
        if (action === "command") {
            const command = _own(ref, "command");
            const rootFlag = _own(ref, "root");
            return typeof command === "string" && command.trim() !== ""
                && (rootFlag === undefined || typeof rootFlag === "boolean")
                && validMovement(_own(ref, "movement"));
        }
        if (action.startsWith("own:")) {
            const id = action.slice(4);
            return _idPattern.test(id) && (!Array.isArray(ownIds) || ownIds.includes(id));
        }
        if (action.startsWith("shell:")) {
            if (!_idPattern.test(action.slice(6)))
                return false;
            // A shell action's arguments are plain values
            return Object.keys(ref).every(key => key === "action" || ["string", "number", "boolean"].includes(typeof ref[key]));
        }
        return false;
    }

    // A stored binding for `interaction`: null (nothing) or one of the three modes. A pair
    // only where the interaction has an end; a cycle of at least two.
    function validBinding(binding, interaction, ownIds): bool {
        if (!isInteraction(interaction))
            return false;
        if (binding === null)
            return true;
        if (!_plainObject(binding))
            return false;
        const mode = _own(binding, "mode");
        if (mode === "single")
            return Object.prototype.hasOwnProperty.call(binding, "action") && validRef(binding.action, ownIds);
        if (mode === "pair")
            return hasEnd(interaction)
                && Object.prototype.hasOwnProperty.call(binding, "on") && Object.prototype.hasOwnProperty.call(binding, "off")
                && validRef(binding.on, ownIds) && validRef(binding.off, ownIds);
        if (mode === "cycle") {
            const actions = _own(binding, "actions");
            return Array.isArray(actions) && actions.length >= 2 && actions.every(ref => validRef(ref, ownIds));
        }
        return false;
    }

    // A valid binding in one form: a single on nothing is nothing
    function _normal(binding) {
        if (binding === null || (binding.mode === "single" && binding.action === null))
            return null;
        return binding;
    }

    // Bound to an action (not unassigned, not nothing)
    function isBound(resolved): bool {
        return resolved !== undefined && resolved !== null;
    }

    // ---- Resolving an entry's binding ------------------------------------------------------

    readonly property var _popupToggle: ({ mode: "single", action: { action: "shell:popup.toggle" } })
    readonly property var _popupOpen: ({ mode: "single", action: { action: "shell:popup.open" } })

    // What a popup type's `popupMode` implies for `interaction`, until the migration turns it
    // into stored bindings: click → left click toggles the popup; hover → hovering opens it
    // (a tap still toggles it: the tap rule, `effective`); none → neither. An unknown mode is
    // the default, click.
    function popupImplied(interaction, popupMode) {
        const mode = ["click", "hover", "none"].includes(popupMode) ? popupMode : "click";
        if (interaction === "leftClick" && mode === "click")
            return _popupToggle;
        if (interaction === "hover" && mode === "hover")
            return _popupOpen;
        return undefined;
    }

    // An entry's binding for `interaction`. `stored`: its preset's own value (undefined:
    // none); `declared`: the type's declared bindings ({ interaction: binding }, or
    // undefined); `hasPopup`/`popupMode`: the popup and the profile's mode for the type.
    // A stored value wins, then a declared one, then the popup's. A stored or declared value
    // that fails its shape counts as not there. A declared left click overrides the popup's.
    // { binding (resolved), from: "preset" | "declared" | "popup" | "", invalid: a stored
    // value was dropped }
    function resolve(interaction, stored, declared, hasPopup, popupMode, ownIds): var {
        let invalid = false;
        if (stored !== undefined) {
            if (validBinding(stored, interaction, ownIds))
                return { binding: _normal(stored), from: "preset", invalid: false };
            invalid = true;
        }
        const own = _plainObject(declared) ? _own(declared, interaction) : undefined;
        if (own !== undefined && validBinding(own, interaction, ownIds))
            return { binding: _normal(own), from: "declared", invalid: invalid };
        if (hasPopup) {
            const implied = popupImplied(interaction, popupMode);
            if (implied !== undefined)
                return { binding: implied, from: "popup", invalid: invalid };
        }
        return { binding: undefined, from: "", invalid: invalid };
    }

    // A lookup over one entry: interaction → resolved binding. `stored`: the preset's own
    // values by interaction ({ leftClick: …, … }).
    function lookupFor(stored, declared, hasPopup, popupMode, ownIds): var {
        const values = _plainObject(stored) ? stored : {};
        return interaction => resolve(interaction, _own(values, interaction), declared, hasPopup, popupMode, ownIds).binding;
    }

    // A finger interaction's fallback while it is unassigned
    function fallbackOf(interaction): string {
        const fallbacks = { tap: "leftClick", doubleTap: "doubleClick", touchHold: "rightClick" };
        return Object.prototype.hasOwnProperty.call(fallbacks, interaction) ? fallbacks[interaction] : "";
    }

    function _opensPopup(binding): bool {
        return !!binding && binding.mode === "single" && ["shell:popup.open", "shell:popup.toggle"].includes(binding.action?.action);
    }

    // The binding an interaction runs, its fallback followed: { interaction (whose binding
    // it is), binding }. An unassigned finger interaction does what its pointer one does; an
    // explicit nothing stops that. The tap rule: a tap on a cell whose left click runs
    // nothing while hovering opens its popup toggles the popup — a finger cannot hover.
    function effective(interaction, lookup): var {
        const own = lookup(interaction);
        if (own !== undefined)
            return { interaction: interaction, binding: own };
        const fallback = fallbackOf(interaction);
        if (fallback === "")
            return { interaction: interaction, binding: undefined };
        const pointer = lookup(fallback);
        if (interaction === "tap" && !isBound(pointer) && _opensPopup(lookup("hover")))
            return { interaction: interaction, binding: _popupToggle };
        return { interaction: fallback, binding: pointer };
    }

    // ---- Which action runs -----------------------------------------------------------------

    // Where a cycle stands in memory for one bar entry and interaction: { key, position }.
    // A key is the binding as text, so a changed binding starts again from the first.
    function cycleKey(binding): string {
        return JSON.stringify(binding);
    }

    // Whether a cycle's next step can come from the actions' state: each step reports
    // whether its effect holds (`holds[i]` a bool; undefined where it cannot tell)
    function stateKnown(binding, holds): bool {
        if (!binding || binding.mode !== "cycle" || !Array.isArray(holds) || holds.length !== binding.actions.length)
            return false;
        return holds.every(holding => typeof holding === "boolean");
    }

    // The ref to run for `phase` ("start", or "end" of an interaction with an end) and the
    // memory to keep: { ref (undefined: nothing runs), memory, step (from 0, -1 none) }.
    // single: at the start. pair: on at the start, off at the end. cycle (at the start): with
    // known state, the step after the last whose effect holds, the first when none holds;
    // else the position in memory, the first at shell start or after the binding changed.
    function step(binding, phase, holds, memory): var {
        const kept = memory ?? null;
        if (!isBound(binding))
            return { ref: undefined, memory: kept, step: -1 };
        if (binding.mode === "pair")
            return { ref: (phase === "end" ? binding.off : binding.on) ?? undefined, memory: kept, step: phase === "end" ? 1 : 0 };
        if (phase !== "start")
            return { ref: undefined, memory: kept, step: -1 };
        if (binding.mode === "single")
            return { ref: binding.action ?? undefined, memory: kept, step: 0 };
        const count = binding.actions.length;
        const key = cycleKey(binding);
        let index;
        if (stateKnown(binding, holds)) {
            const last = holds.lastIndexOf(true);
            index = last < 0 ? 0 : (last + 1) % count;
        } else {
            const position = kept && kept.key === key && Number.isInteger(kept.position) ? kept.position : 0;
            index = ((position % count) + count) % count;
        }
        return { ref: binding.actions[index] ?? undefined, memory: { key: key, position: (index + 1) % count }, step: index };
    }

    // Whether a ref runs on `interaction` and with what: `kind` is the action's ("run" or
    // "adjust"; a command is its own). A continuous movement takes an adjust action or a
    // command only — a run action there is split into its stepped interactions instead.
    // `amount`: the measured movement for a continuous one; a stepped one gives ±1.
    // { runs, amount, direction }
    function runFor(interaction, ref, kind, amount): var {
        if (!ref)
            return { runs: false, amount: 0, direction: "" };
        const isCommand = ref.action === "command";
        if (isMovement(interaction)) {
            const runs = isCommand || kind === "adjust";
            const measured = runs && isFinite(amount) ? amount : 0;
            return { runs: runs && measured !== 0, amount: measured, direction: measured === 0 ? "" : direction(interaction === "scroll", measured) };
        }
        if (isStepped(interaction))
            return { runs: true, amount: stepAmount(interaction), direction: stepDirection(interaction) };
        return { runs: true, amount: 0, direction: "" };
    }

    // ---- The editor's warnings -------------------------------------------------------------

    // The warnings a binding on `interaction` gets in the editor — never a refusal. `info(ref)`
    // describes an action: { kind, asks (may ask for a password or end the session), state
    // (reports whether its effect holds) }; `legacy`: a module widget that declares no actions
    // and may also react by itself. Codes:
    //   asks             an asking action or a root command where it runs by passing over
    //   commandOnHover   a command runs each time the pointer passes over
    //   doubleWaits      a bound double click or double tap makes single ones wait
    //   startsFromFirst  alternate/cycle with a step that cannot report its state
    //   split            a run action on a continuous movement: offered as two stepped ones
    //   reactsByItself   the widget may also react by itself
    function warnings(interaction, binding, info, legacy): var {
        const found = [];
        const refs = !isBound(binding) ? []
            : binding.mode === "single" ? [binding.action]
            : binding.mode === "pair" ? [binding.on, binding.off]
            : binding.actions;
        const real = refs.filter(ref => !!ref);
        const described = ref => (ref.action === "command" ? null : info(ref)) ?? {};
        if (isPassing(interaction) && real.some(ref => (ref.action === "command" && ref.root === true) || described(ref).asks === true))
            found.push("asks");
        if (interaction === "hover" && real.some(ref => ref.action === "command"))
            found.push("commandOnHover");
        if ((interaction === "doubleClick" || interaction === "doubleTap") && isBound(binding))
            found.push("doubleWaits");
        if (isBound(binding) && binding.mode === "cycle" && !binding.actions.every(ref => ref === null || (ref.action !== "command" && described(ref).state === true)))
            found.push("startsFromFirst");
        if (isMovement(interaction) && real.some(ref => ref.action !== "command" && described(ref).kind !== "adjust"))
            found.push("split");
        if (legacy)
            found.push("reactsByItself");
        return found;
    }
}
