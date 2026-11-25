pragma Singleton

import Quickshell
import QtQuick

// The one input layer's dispatcher: every bar cell hands it each interaction it reports
// (BarWidget), and it runs what the cell's bar entry binds to it. Which action runs, with
// what amount, is InteractionRules.dispatch; this only reads the widget's state and acts:
// own actions through the widget's runAction, the popup's through the widget
// (PopupWidget). Other shell actions and commands do not run yet: each is logged once.
Singleton {
    id: root

    // The refs logged as not runnable, as text: once each
    property var _logged: []

    function handle(widget, interaction, details) {
        if (!widget)
            return;
        const type = widget.widgetType ?? "";
        const memory = widget._actionMemory ?? {};
        const chosen = InteractionRules.dispatch(interaction, details, widget.bindingLookup,
            ref => _holds(widget, type, ref), key => memory[key], ref => _kind(type, ref));
        if (chosen.memoryKey !== "" && widget._actionMemory !== undefined)
            widget._actionMemory[chosen.memoryKey] = chosen.memory;
        if (chosen.ref === undefined)
            return;
        const given = Object.freeze({ interaction: interaction, amount: chosen.amount, direction: chosen.direction,
                                      byTouch: details?.byTouch === true,
                                      preset: typeof widget.preset === "string" ? widget.preset : "" });
        _run(widget, type, chosen.ref, chosen.target, given);
    }

    function _run(widget, type, ref, target, given) {
        if (target.kind === "own" && typeof widget.runAction === "function") {
            widget.runAction(target.id, given);
            return;
        }
        if (target.kind === "shell" && target.id === "popup.toggle" && typeof widget.togglePopup === "function") {
            widget.togglePopup(given.byTouch);
            return;
        }
        if (target.kind === "shell" && target.id === "popup.open" && typeof widget.openPopup === "function") {
            widget.openPopup(InteractionRules.popupStays(given.interaction), given.byTouch);
            return;
        }
        if (target.kind === "shell" && target.id === "popup.close" && typeof widget.closePopup === "function") {
            widget.closePopup();
            return;
        }
        const text = type + " " + JSON.stringify(ref);
        if (_logged.includes(text))
            return;
        _logged = _logged.concat([text]);
        console.log("[WidgetActions] " + WidgetRegistry.displayName(type) + ": " + JSON.stringify(ref) + " cannot run here");
    }

    // Whether a ref's effect holds: the popup's from the widget's popupOpen, an own action's
    // from the widget where the action says it can tell (`state`); undefined elsewhere
    function _holds(widget, type, ref) {
        const target = InteractionRules.target(ref);
        if (target.kind === "shell")
            return typeof widget.popupOpen === "boolean" ? InteractionRules.shellHolds(target.id, widget.popupOpen) : undefined;
        if (target.kind === "own" && WidgetRegistry.action(type, target.id)?.state === true && typeof widget.actionHolds === "function") {
            const holds = widget.actionHolds(target.id);
            return typeof holds === "boolean" ? holds : undefined;
        }
        return undefined;
    }

    function _kind(type, ref) {
        const target = InteractionRules.target(ref);
        return target.kind === "own" ? (WidgetRegistry.action(type, target.id)?.kind ?? "run") : "run";
    }
}
