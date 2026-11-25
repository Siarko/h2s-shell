import QtQuick
import qs.singletons

TestCase {
    suiteName: "InteractionRules"

    readonly property var toggle: ({ mode: "single", action: { action: "shell:popup.toggle" } })
    readonly property var open: ({ mode: "single", action: { action: "shell:popup.open" } })
    readonly property var mute: ({ mode: "single", action: { action: "own:mute" } })
    readonly property var nothing: ({ mode: "single", action: null })

    function lookup(stored, declared, hasPopup, popupMode) {
        return InteractionRules.lookupFor(stored, declared, hasPopup ?? false, popupMode ?? "", undefined);
    }

    function run() {
        const R = InteractionRules;

        // --- the interactions ---
        const all = R.interactions();
        assertEqual(all.length, 22, "seven core, eight more and seven finger interactions");
        assert(["tap", "doubleTap", "touchHold", "swipeLeft", "swipeRight", "swipeUp", "swipeDown"].every(name => all.includes(name)), "every finger interaction is one");
        assert(R.coreInteractions().includes("rightClick") && !R.coreInteractions().includes("doubleClick"), "right click is core, double click is behind more");
        assert(R.moreInteractions().includes("scrollSideways") && R.moreInteractions().includes("altClick"), "horizontal scroll and modifier clicks are behind more");
        assertEqual(R.fingerInteractions().length, 7, "seven finger interactions");
        assert(R.fingerInteractions().includes("touchHold") && !R.fingerInteractions().includes("leftClick"), "the finger's list is the finger's");
        const copy = R.interactions();
        copy.push("made-up");
        assert(!R.isInteraction("made-up"), "a list handed out is a copy");
        assert(!R.isInteraction(undefined) && !R.isInteraction("toString"), "not a name, or an inherited one, is no interaction");
        assert(R.isMovement("scroll") && R.isMovement("scrollSideways") && !R.isMovement("scrollUp"), "only the continuous scrolls are movements");
        assert(R.isStepped("swipeDown") && R.isStepped("scrollLeft") && !R.isStepped("scroll") && !R.isStepped("tap"), "steps: the directed scrolls and the swipes");
        assert(R.hasEnd("hover") && R.hasEnd("longPress") && R.hasEnd("touchHold") && !R.hasEnd("leftClick"), "hover and holds have an end");
        assert(R.isPassing("hover") && R.isPassing("scroll") && R.isPassing("swipeUp") && !R.isPassing("middleClick") && !R.isPassing("touchHold"), "passing: hover, scrolls, swipes");

        // --- modes ---
        assertEqual(JSON.stringify(R.modesFor("hover")), JSON.stringify(["single", "pair", "alternate", "cycle"]), "hover offers the pair");
        assertEqual(JSON.stringify(R.modesFor("middleClick")), JSON.stringify(["single", "alternate", "cycle"]), "a click offers no pair");
        assertEqual(R.modesFor("bogus").length, 0, "an unknown interaction offers nothing");
        assertEqual(R.modeName({ mode: "cycle", actions: [null, null] }), "alternate", "a cycle of two is alternate");
        assertEqual(R.modeName({ mode: "cycle", actions: [null, null, null] }), "cycle", "of three, cycle");
        assertEqual(R.modeName(mute), "single", "single");
        assertEqual(R.modeName(null), "", "nothing has no mode");

        // --- presses ---
        const press = (fields) => R.pressInteraction(Object.assign({ button: Qt.LeftButton, modifiers: 0, byTouch: false, held: false, second: false, swiped: false }, fields));
        assertEqual(press({}), "leftClick", "a left click");
        assertEqual(press({ button: Qt.MiddleButton }), "middleClick", "a middle click");
        assertEqual(press({ button: Qt.RightButton }), "rightClick", "a right click");
        assertEqual(press({ button: Qt.BackButton }), "", "another button is none");
        assertEqual(press({ button: Qt.MiddleButton, modifiers: Qt.ShiftModifier }), "middleClick", "middle ignores modifiers");
        assertEqual(press({ button: Qt.RightButton, held: true }), "rightClick", "a held right button is still its click: it has no long press");
        assertEqual(press({ button: Qt.MiddleButton, held: true }), "middleClick", "so is a held middle button");
        assertEqual(press({ second: true }), "doubleClick", "the second click of a double");
        assertEqual(press({ held: true }), "longPress", "a held left press");
        assertEqual(press({ modifiers: Qt.ShiftModifier }), "shiftClick", "shift click");
        assertEqual(press({ modifiers: Qt.ControlModifier }), "ctrlClick", "ctrl click");
        assertEqual(press({ modifiers: Qt.AltModifier }), "altClick", "alt click");
        assertEqual(press({ modifiers: Qt.ShiftModifier, second: true }), "shiftClick", "a modified second click is a modified click");
        assertEqual(press({ modifiers: Qt.KeypadModifier }), "leftClick", "the keypad flag is no modifier");
        assertEqual(press({ modifiers: Qt.ShiftModifier | Qt.ControlModifier }), "", "two modifiers have no name");
        assertEqual(press({ modifiers: Qt.MetaModifier }), "", "super is the compositor's");
        assertEqual(press({ byTouch: true }), "tap", "a finger's press is a tap");
        assertEqual(press({ byTouch: true, second: true }), "doubleTap", "the second tap of a double");
        assertEqual(press({ byTouch: true, held: true }), "touchHold", "a finger held");
        assertEqual(press({ byTouch: true, modifiers: Qt.ShiftModifier }), "tap", "a finger with shift held is still a tap");
        assertEqual(press({ byTouch: true, swiped: true }), "", "a swipe is never also a tap");
        assertEqual(press({ swiped: true }), "", "nor a click");
        assertEqual(R.pressInteraction(null), "", "no event, nothing");
        assertEqual(R.holdInteraction(Qt.LeftButton, false), "longPress", "the hold of the left button starts a long press");
        assertEqual(R.holdInteraction(Qt.RightButton, false), "", "a held right button starts nothing");
        assertEqual(R.holdInteraction(Qt.LeftButton, true), "touchHold", "a finger's hold starts a touch hold");
        assertEqual(R.hoverInteraction(false), "hover", "the pointer hovers");
        assertEqual(R.hoverInteraction(true), "", "a finger never hovers");

        // --- double click timing ---
        assert(R.isSecondClick(1000, 1300, 400), "within the interval: the second click");
        assert(R.isSecondClick(1000, 1400, 400), "at the interval exactly: still");
        assert(!R.isSecondClick(1000, 1401, 400), "after it: a new first click");
        assert(!R.isSecondClick(-1, 100, 400), "no first click: none");
        assert(R.isSecondClick(0, 100, 400), "a first click at time zero counts");
        assert(R.isSecondClick(1000, 1000, 400), "at the same instant: the second click");
        assert(!R.isSecondClick(1000, 999, 400), "a clock that went back: none");
        assert(!R.waitsForDouble(false, lookup({})), "nothing on double click: a click runs at once");
        assert(R.waitsForDouble(false, lookup({ doubleClick: mute })), "a bound double click makes the click wait");
        assert(!R.waitsForDouble(false, lookup({ doubleClick: null })), "a double click bound to nothing does not");
        assert(R.waitsForDouble(true, lookup({ doubleClick: mute })), "a tap waits for its fallback, the double click");
        assert(!R.waitsForDouble(true, lookup({ doubleClick: mute, doubleTap: null })), "a double tap bound to nothing stops it");
        assert(R.waitsForDouble(true, lookup({ doubleTap: mute })), "a bound double tap");
        assert(!R.waitsForDouble(false, lookup({ doubleTap: mute })), "a double tap does not delay a mouse click");

        // --- scroll ---
        const volume = { mode: "single", action: { action: "own:volume" } };
        let events = R.scrollInteractions("vertical", 0.5, 0, lookup({ scroll: volume }));
        assertEqual(JSON.stringify(events), JSON.stringify([{ interaction: "scroll", amount: 0.5, direction: "up", times: 1 }]), "a bound scroll takes the fraction as measured");
        events = R.scrollInteractions("vertical", -2, -2, lookup({ scroll: volume, scrollDown: mute }));
        assertEqual(events[0].interaction + " " + events[0].amount + " " + events[0].direction, "scroll -2 down", "the continuous one wins over the steps, down negative");
        assertEqual(R.scrollInteractions("vertical", 0, 0, lookup({ scroll: volume })).length, 0, "no movement, nothing");
        events = R.scrollInteractions("vertical", 1.1, 1, lookup({}));
        assertEqual(JSON.stringify(events), JSON.stringify([{ interaction: "scrollUp", amount: 1, direction: "up", times: 1 }]), "unbound scroll: a whole notch up is a step up");
        events = R.scrollInteractions("vertical", -2.2, -2, lookup({ scroll: null }));
        assertEqual(JSON.stringify(events), JSON.stringify([{ interaction: "scrollDown", amount: -1, direction: "down", times: 2 }]), "scroll bound to nothing (split): two steps down");
        assertEqual(R.scrollInteractions("vertical", 0.4, 0, lookup({})).length, 0, "no whole notch yet: no step");
        events = R.scrollInteractions("horizontal", 1, 1, lookup({}));
        assertEqual(events[0].interaction + " " + events[0].direction, "scrollLeft left", "angleDelta.x positive is left");
        events = R.scrollInteractions("horizontal", -1, -1, lookup({}));
        assertEqual(events[0].interaction + " " + events[0].amount, "scrollRight 1", "negative is right, positive to an adjust action");
        events = R.scrollInteractions("horizontal", 0.5, 0, lookup({ scrollSideways: volume }));
        assertEqual(events[0].interaction + " " + events[0].amount + " " + events[0].direction, "scrollSideways -0.5 left", "sideways continuous: right positive");
        assertEqual(R.scrollInteractions("vertical", NaN, 0, lookup({ scroll: volume })).length, 0, "no number, nothing");
        events = R.scrollInteractions("horizontal", -0.5, 0, lookup({ scrollSideways: volume }));
        assertEqual(events[0].direction, "right", "half a notch right is right");
        events = R.scrollInteractions("vertical", -0.5, 0, lookup({ scroll: volume }));
        assertEqual(events[0].direction, "down", "half a notch down is down");
        assertEqual(R.scrollInteractions("vertical", 0, NaN, lookup({})).length, 0, "no number of notches, no step");

        // --- swipes ---
        assertEqual(R.swipeInteraction(80, 10, true, false), "swipeRight", "far right");
        assertEqual(R.swipeInteraction(-80, 10, true, false), "swipeLeft", "far left");
        assertEqual(R.swipeInteraction(5, -60, false, true), "swipeUp", "up is negative y");
        assertEqual(R.swipeInteraction(5, 60, false, true), "swipeDown", "down");
        assertEqual(R.swipeInteraction(80, 10, false, false), "", "not meant: no swipe");
        assertEqual(R.swipeInteraction(80, 70, false, true), "", "the larger axis decides even when the other is meant");
        assertEqual(R.swipeInteraction(0, 0, true, true), "", "no movement is no swipe");
        assertEqual(R.swipeInteraction(0.5, 0.2, true, false), "swipeRight", "a fraction right is right");
        assertEqual(R.swipeInteraction(0.2, 0.5, false, true), "swipeDown", "a fraction down is down");
        assertEqual(JSON.stringify(R.offeredSwipes(false, false)), JSON.stringify(["swipeLeft", "swipeRight"]), "top bar: the long axis only");
        assertEqual(JSON.stringify(R.offeredSwipes(false, true)), JSON.stringify(["swipeLeft", "swipeRight", "swipeUp", "swipeDown"]), "top bar, short axis works: all four");
        assertEqual(JSON.stringify(R.offeredSwipes(true, false)), JSON.stringify(["swipeUp", "swipeDown"]), "side bar: up and down");
        assertEqual(JSON.stringify(R.offeredSwipes(true, true)), JSON.stringify(["swipeUp", "swipeDown", "swipeLeft", "swipeRight"]), "side bar, short axis works: all four");
        assertEqual(R.stepAmount("swipeUp") + R.stepAmount("scrollRight"), 2, "up and right step +1");
        assertEqual(R.stepAmount("swipeLeft") + R.stepAmount("scrollDown"), -2, "left and down step -1");
        assertEqual(R.stepAmount("leftClick"), 0, "a click is no step");
        assertEqual(R.stepDirection("swipeLeft") + R.stepDirection("scrollUp"), "leftup", "step directions");
        assertEqual(R.stepDirection("constructor"), "", "an inherited name has no direction");

        // --- shapes ---
        assert(R.validRef(null), "nothing is a ref");
        assert(R.validRef({ action: "own:mute" }), "own");
        assert(R.validRef({ action: "shell:settings.open", page: "bar" }), "shell with a plain argument");
        assert(!R.validRef({ action: "shell:settings.open", page: { nested: 1 } }), "shell with an object argument");
        assert(!R.validRef({ action: "shell:" }), "shell without id");
        assert(!R.validRef({ action: "shell:1x" }), "a shell id starts with a letter");
        assert(R.validRef({ action: "shell:a" }), "a shell id of one letter");
        assert(!R.validRef({ action: "own:" }), "own without id");
        assert(!R.validRef({ action: "own:1x" }), "an id starts with a letter");
        assert(!R.validRef({ action: "other:x" }), "unknown family");
        assert(!R.validRef("own:mute"), "a bare string");
        assert(!R.validRef([{ action: "own:mute" }]), "an array");
        assert(!R.validRef({ }), "no action");
        assert(R.validRef({ action: "own:mute" }, ["mute"]), "a declared own action");
        assert(!R.validRef({ action: "own:mute" }, ["play"]), "an undeclared one");
        assert(R.validRef({ action: "command", command: "playerctl next" }), "a command");
        assert(R.validRef({ action: "command", command: "x", root: true }), "a root command");
        assert(!R.validRef({ action: "command", command: "   " }), "a blank command");
        assert(!R.validRef({ action: "command", command: 5 }), "a command not text");
        assert(!R.validRef({ action: "command", command: "x", root: "yes" }), "root not a bool");
        assert(R.validRef({ action: "command", command: "x", movement: { to: "parameter", form: "amount" } }), "movement as a parameter");
        assert(R.validRef({ action: "command", command: "x", movement: { to: "variable", name: "STEP_1", form: "direction" } }), "movement as a variable");
        assert(!R.validRef({ action: "command", command: "x", movement: { to: "variable", name: "1BAD" } }), "a variable name not an identifier");
        assert(!R.validRef({ action: "command", command: "x", movement: { to: "variable" } }), "a variable without name");
        assert(!R.validRef({ action: "command", command: "x", movement: { to: "stdin" } }), "an unknown way");
        assert(!R.validRef({ action: "command", command: "x", movement: { to: "parameter", form: "speed" } }), "an unknown form");
        assert(!R.validRef({ action: "command", command: "x", movement: "amount" }), "movement not an object");

        assert(R.validBinding(null, "tap"), "nothing on an interaction");
        assert(R.validBinding(mute, "middleClick"), "single");
        assert(R.validBinding(nothing, "middleClick"), "single on nothing");
        assert(!R.validBinding({ mode: "single" }, "middleClick"), "single without action");
        assert(!R.validBinding(mute, "bogus"), "an unknown interaction");
        assert(R.validBinding({ mode: "pair", on: { action: "own:a" }, off: null }, "hover"), "a pair on hover");
        assert(R.validBinding({ mode: "pair", on: null, off: { action: "own:a" } }, "touchHold"), "a pair on a touch hold");
        assert(!R.validBinding({ mode: "pair", on: { action: "own:a" }, off: null }, "leftClick"), "no pair on a click");
        assert(!R.validBinding({ mode: "pair", on: { action: "own:a" } }, "hover"), "a pair without off");
        assert(R.validBinding({ mode: "cycle", actions: [{ action: "own:a" }, null] }, "leftClick"), "alternate");
        assert(!R.validBinding({ mode: "cycle", actions: [{ action: "own:a" }] }, "leftClick"), "a cycle of one");
        assert(!R.validBinding({ mode: "cycle", actions: [{ action: "own:a" }, "x"] }, "leftClick"), "a cycle with a bad step");
        assert(!R.validBinding({ mode: "cycle", actions: "ab" }, "leftClick"), "a cycle not a list");
        assert(!R.validBinding({ mode: "alternate", actions: [null, null] }, "leftClick"), "alternate is stored as cycle");
        assert(!R.validBinding({ mode: "single", action: { action: "own:mute" } }, "middleClick", ["play"]), "an undeclared own action in a binding");
        assert(!R.validBinding([mute], "middleClick"), "a list is no binding");
        assert(R.isBound(mute) && !R.isBound(null) && !R.isBound(undefined), "bound means an action");

        // --- resolution ---
        let resolved = R.resolve("middleClick", undefined, { middleClick: mute }, false, "", undefined);
        assertEqual(resolved.from, "declared", "nothing stored: the declared default");
        resolved = R.resolve("middleClick", null, { middleClick: mute }, false, "", undefined);
        assert(resolved.binding === null && resolved.from === "preset", "stored nothing overrides the default");
        resolved = R.resolve("middleClick", nothing, { middleClick: mute }, false, "", undefined);
        assert(resolved.binding === null, "a single on nothing is nothing");
        resolved = R.resolve("middleClick", { mode: "weird" }, { middleClick: mute }, false, "", undefined);
        assert(resolved.from === "declared" && resolved.invalid, "a stored value of a bad shape counts as not there, and says so");
        resolved = R.resolve("middleClick", { mode: "weird" }, undefined, false, "", undefined);
        assert(resolved.binding === undefined && resolved.invalid, "… and with nothing declared it is unassigned");
        resolved = R.resolve("middleClick", undefined, { middleClick: { mode: "weird" } }, false, "", undefined);
        assert(resolved.binding === undefined && !resolved.invalid, "a bad declared value is no default");
        resolved = R.resolve("leftClick", undefined, undefined, true, "click", undefined);
        assertEqual(JSON.stringify(resolved.binding), JSON.stringify(toggle), "click mode: left click toggles the popup");
        assert(R.resolve("hover", undefined, undefined, true, "click", undefined).binding === undefined, "click mode: hover unassigned");
        assertEqual(JSON.stringify(R.resolve("hover", undefined, undefined, true, "hover", undefined).binding), JSON.stringify(open), "hover mode: hovering opens it");
        assert(R.resolve("leftClick", undefined, undefined, true, "hover", undefined).binding === undefined, "hover mode: left click unassigned");
        assert(R.resolve("leftClick", undefined, undefined, true, "none", undefined).binding === undefined, "none: left click unassigned");
        assert(R.resolve("hover", undefined, undefined, true, "none", undefined).binding === undefined, "none: hover unassigned");
        assertEqual(R.resolve("leftClick", undefined, undefined, true, "", undefined).from, "popup", "an unknown mode is click");
        assert(R.resolve("leftClick", undefined, undefined, false, "click", undefined).binding === undefined, "no popup: nothing implied");
        resolved = R.resolve("leftClick", undefined, { leftClick: mute }, true, "click", undefined);
        assertEqual(resolved.from, "declared", "a declared left click overrides the popup's");
        resolved = R.resolve("leftClick", toggle, { leftClick: mute }, true, "click", undefined);
        assertEqual(resolved.from, "preset", "a stored one beats both");
        assert(!resolved.invalid, "a valid stored value is not reported");
        assertEqual(R.resolve("rightClick", undefined, { rightClick: toggle }, true, "hover", undefined).from, "declared", "a popup on a declared right click whatever the mode");
        assertEqual(R.lookupFor("junk", undefined, true, "click", undefined)("leftClick").action.action, "shell:popup.toggle", "stored values not an object: none stored");

        // --- finger fallbacks ---
        assertEqual(R.fallbackOf("tap"), "leftClick", "tap falls back to left click");
        assertEqual(R.fallbackOf("doubleTap"), "doubleClick", "double tap to double click");
        assertEqual(R.fallbackOf("touchHold"), "rightClick", "touch hold to right click");
        assertEqual(R.fallbackOf("swipeUp"), "", "a swipe has none");
        assertEqual(R.fallbackOf("hasOwnProperty"), "", "an inherited name has none");
        let effective = R.effective("tap", lookup({ leftClick: mute }));
        assert(effective.interaction === "leftClick" && effective.binding === mute, "an unassigned tap does the left click");
        effective = R.effective("tap", lookup({ leftClick: mute, tap: null }));
        assert(effective.interaction === "tap" && effective.binding === null, "an explicit nothing stops the fallback");
        effective = R.effective("tap", lookup({ leftClick: mute, tap: toggle }));
        assert(effective.interaction === "tap" && effective.binding === toggle, "an assigned tap runs its own");
        effective = R.effective("touchHold", lookup({ rightClick: toggle }));
        assert(effective.interaction === "rightClick", "an unassigned touch hold does the right click");
        effective = R.effective("doubleTap", lookup({ doubleClick: mute }));
        assert(effective.interaction === "doubleClick", "an unassigned double tap does the double click");
        effective = R.effective("swipeLeft", lookup({ leftClick: mute }));
        assert(effective.interaction === "swipeLeft" && effective.binding === undefined, "an unassigned swipe does nothing");
        effective = R.effective("leftClick", lookup({ tap: mute }));
        assert(effective.binding === undefined, "a pointer interaction never takes a finger's");
        // The tap rule: a finger cannot hover
        effective = R.effective("tap", lookup({}, undefined, true, "hover"));
        assertEqual(JSON.stringify(effective.binding), JSON.stringify(toggle), "hover mode: a tap toggles the popup");
        effective = R.effective("tap", lookup({ leftClick: null, hover: open }, undefined, true, "click"));
        assertEqual(JSON.stringify(effective.binding), JSON.stringify(toggle), "stored hover opening with left click nothing: a tap toggles");
        effective = R.effective("tap", lookup({}, undefined, true, "none"));
        assert(effective.binding === undefined, "no popup trigger: a tap does nothing");
        effective = R.effective("tap", lookup({ tap: null }, undefined, true, "hover"));
        assert(effective.binding === null, "a tap bound to nothing stays nothing in hover mode");
        effective = R.effective("tap", lookup({}, { leftClick: mute }, true, "hover"));
        assert(effective.interaction === "leftClick" && effective.binding.action.action === "own:mute", "a declared left click: the tap does it, not the popup");
        effective = R.effective("tap", lookup({ hover: mute }, undefined, true, "click"));
        assertEqual(effective.binding.action.action, "shell:popup.toggle", "click mode with a hover action: the tap does the left click");
        effective = R.effective("tap", lookup({ leftClick: null, hover: mute }));
        assert(effective.binding === null && effective.interaction === "leftClick", "hover running something else: the tap does the left click's nothing");
        effective = R.effective("tap", lookup({ leftClick: null, hover: { mode: "pair", on: { action: "shell:popup.open" }, off: null } }));
        assert(effective.binding === null, "a pair on hover is no popup opening for the tap rule");

        // --- steps ---
        let step = R.step(mute, "start", undefined, null);
        assertEqual(step.ref.action, "own:mute", "single runs at the start");
        assertEqual(step.step, 0, "as the first step");
        assert(R.step(mute, "end", undefined, null).ref === undefined && R.step(mute, "end", undefined, null).step === -1, "and nothing at the end");
        assert(R.step(null, "start", undefined, null).ref === undefined && R.step(null, "start", undefined, null).step === -1, "nothing runs nothing");
        assert(R.step(undefined, "start", undefined, null).ref === undefined, "unassigned runs nothing");
        assert(R.step(nothing, "start", undefined, null).ref === undefined, "a single on nothing runs nothing");
        const pair = { mode: "pair", on: { action: "own:a" }, off: { action: "own:b" } };
        assertEqual(R.step(pair, "start", undefined, null).ref.action, "own:a", "pair: on at the start");
        assertEqual(R.step(pair, "end", undefined, null).ref.action, "own:b", "pair: off at the end");
        assertEqual(R.step(pair, "start", undefined, null).step, 0, "pair: the start is step one");
        assertEqual(R.step(pair, "end", undefined, null).step, 1, "pair: the end is step two");
        assert(R.step({ mode: "pair", on: null, off: { action: "own:b" } }, "start", undefined, null).ref === undefined, "a pair's nothing runs nothing");
        const cycle = { mode: "cycle", actions: [{ action: "own:a" }, { action: "own:b" }, { action: "own:c" }] };
        step = R.step(cycle, "start", undefined, null);
        assert(step.step === 0 && step.memory.position === 1, "unknown state starts from the first");
        step = R.step(cycle, "start", undefined, step.memory);
        assertEqual(step.step, 1, "then the second");
        step = R.step(cycle, "start", undefined, step.memory);
        assertEqual(step.step, 2, "then the third");
        step = R.step(cycle, "start", undefined, step.memory);
        assertEqual(step.step, 0, "and round again");
        assertEqual(R.step(cycle, "end", undefined, step.memory).ref, undefined, "a cycle runs nothing at an end");
        const other = { mode: "cycle", actions: [{ action: "own:a" }, { action: "own:x" }] };
        step = R.step(other, "start", undefined, { key: R.cycleKey(cycle), position: 1 });
        assertEqual(step.step, 0, "a changed binding starts from the first");
        assertEqual(R.step(cycle, "start", undefined, { key: R.cycleKey(cycle), position: 7 }).step, 1, "a position past the end wraps");
        assertEqual(R.step(cycle, "start", undefined, { key: R.cycleKey(cycle), position: 1.5 }).step, 0, "a position not whole is the first");
        assertEqual(R.step(cycle, "start", [false, true, false], null).step, 2, "known state: the step after the last that holds");
        assertEqual(R.step(cycle, "start", [true, false, false], null).step, 1, "the first holds: the second");
        assertEqual(R.step(cycle, "start", [true, true, false], null).step, 2, "the last one holding decides");
        assertEqual(R.step(cycle, "start", [false, false, true], null).step, 0, "the last holds: round to the first");
        assertEqual(R.step(cycle, "start", [false, false, false], { key: R.cycleKey(cycle), position: 2 }).step, 0, "none holds: the first, whatever memory says");
        assertEqual(R.step(cycle, "start", [true, undefined, false], { key: R.cycleKey(cycle), position: 2 }).step, 2, "one step that cannot tell: memory decides");
        assertEqual(R.step(cycle, "start", [true, false], { key: R.cycleKey(cycle), position: 2 }).step, 2, "holds of another length: memory decides");
        assert(R.stateKnown(cycle, [false, false, true]) && !R.stateKnown(cycle, [false, "yes", true]) && !R.stateKnown(mute, [true]), "state known only when every step tells");

        // --- what runs ---
        const adjust = { action: "own:volume" };
        const command = { action: "command", command: "x" };
        let run = R.runFor("scroll", adjust, "adjust", 0.5);
        assert(run.runs && run.amount === 0.5 && run.direction === "up", "an adjust action takes the scroll as measured");
        run = R.runFor("scrollSideways", command, "", -2);
        assert(run.runs && run.amount === -2 && run.direction === "left", "a command takes a sideways movement");
        run = R.runFor("scroll", { action: "own:mute" }, "run", 1);
        assert(!run.runs, "a run action does not take a continuous movement");
        assert(!R.runFor("scroll", adjust, "adjust", 0).runs, "no movement runs nothing");
        assert(!R.runFor("scroll", adjust, "adjust", NaN).runs, "no number runs nothing");
        run = R.runFor("scrollDown", adjust, "adjust", 3);
        assert(run.runs && run.amount === -1 && run.direction === "down", "a step down is -1 to an adjust action");
        run = R.runFor("swipeRight", { action: "own:mute" }, "run", 0);
        assert(run.runs && run.amount === 1 && run.direction === "right", "a run action takes a step");
        run = R.runFor("leftClick", adjust, "adjust", 4);
        assert(run.runs && run.amount === 0 && run.direction === "", "a click carries no movement");
        run = R.runFor("leftClick", null, "run", 0);
        assert(!run.runs && run.amount === 0 && run.direction === "", "nothing runs nothing, with no movement");
        run = R.runFor("scroll", adjust, "adjust", 1);
        assert(run.runs && run.amount === 1 && run.direction === "up", "one whole notch up");

        // --- warnings ---
        const info = ref => ({ "own:connect": { kind: "run", asks: true, state: true },
                               "own:volume": { kind: "adjust", asks: false, state: false },
                               "own:wifiOn": { kind: "run", asks: false, state: true },
                               "own:wifiOff": { kind: "run", asks: false, state: true } })[ref.action];
        const single = ref => ({ mode: "single", action: ref });
        const has = (list, code) => list.includes(code);
        assert(has(R.warnings("hover", single({ action: "own:connect" }), info, false), "asks"), "an asking action on hover");
        assert(has(R.warnings("swipeUp", single({ action: "own:connect" }), info, false), "asks"), "on a swipe");
        assert(has(R.warnings("scrollDown", single({ action: "own:connect" }), info, false), "asks"), "on a scroll step");
        assert(!has(R.warnings("middleClick", single({ action: "own:connect" }), info, false), "asks"), "not on a click");
        assert(has(R.warnings("hover", single({ action: "command", command: "x", root: true }), info, false), "asks"), "a root command on hover");
        assert(!has(R.warnings("swipeUp", single(command), info, false), "asks"), "a user command on a swipe does not ask");
        assert(has(R.warnings("hover", { mode: "pair", on: null, off: { action: "own:connect" } }, info, false), "asks"), "a pair's end counts");
        assert(has(R.warnings("hover", single(command), info, false), "commandOnHover"), "a command on hover");
        assert(!has(R.warnings("leftClick", single(command), info, false), "commandOnHover"), "not on a click");
        assert(has(R.warnings("doubleClick", single({ action: "own:volume" }), info, false), "doubleWaits"), "a bound double click");
        assert(has(R.warnings("doubleTap", single({ action: "own:volume" }), info, false), "doubleWaits"), "a bound double tap");
        assert(!has(R.warnings("doubleClick", null, info, false), "doubleWaits"), "a double click on nothing");
        assert(has(R.warnings("leftClick", { mode: "cycle", actions: [command, { action: "own:wifiOn" }] }, info, false), "startsFromFirst"), "alternate with a command");
        assert(has(R.warnings("leftClick", { mode: "cycle", actions: [{ action: "own:volume" }, { action: "own:wifiOn" }] }, info, false), "startsFromFirst"), "alternate with a step without state");
        assert(has(R.warnings("leftClick", { mode: "cycle", actions: [{ action: "own:unknown" }, { action: "own:wifiOn" }] }, info, false), "startsFromFirst"), "an action not described has no state");
        assert(!has(R.warnings("leftClick", { mode: "cycle", actions: [{ action: "own:wifiOff" }, { action: "own:wifiOn" }] }, info, false), "startsFromFirst"), "alternate with known state");
        assert(!has(R.warnings("leftClick", { mode: "cycle", actions: [null, { action: "own:wifiOn" }] }, info, false), "startsFromFirst"), "a nothing step needs no state");
        assert(has(R.warnings("scroll", single({ action: "own:wifiOn" }), info, false), "split"), "a run action on scroll: split offered");
        assert(!has(R.warnings("scroll", single({ action: "own:volume" }), info, false), "split"), "an adjust action fits");
        assert(!has(R.warnings("scroll", single(command), info, false), "split"), "a command fits");
        assert(!has(R.warnings("scrollUp", single({ action: "own:wifiOn" }), info, false), "split"), "a step takes any action");
        assert(has(R.warnings("leftClick", null, info, true), "reactsByItself"), "a legacy widget");
        assertEqual(R.warnings("middleClick", single({ action: "own:wifiOn" }), info, false).length, 0, "a plain binding has no warning");
        assertEqual(R.warnings("hover", undefined, info, false).length, 0, "unassigned has none");
    }
}
