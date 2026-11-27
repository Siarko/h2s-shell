pragma Singleton

import Quickshell
import QtQuick

// The shell's modal questions (components/SettingsModalHost.qml) as one: where a question
// can stand, which one is open, and a module's questions (module API 1.44: module.ask,
// api/ModuleHandle.qml; the decisions are ApiElementRules').
//
// - Places: a host covers a place's root (the Settings window's content, a bar popup's
//   body), registered by key while it exists; an item asks in the place of the nearest
//   root above it. A host may refuse questions where it stands (the tray menu's popup).
//   Nothing else is a place: the bar, the lock screen, an anchor in no popup or window.
// - One question is open in the whole shell at a time: each host that opens one says so
//   here under a token of its own, and says it closed — also at its destruction, through
//   the token alone.
// - A module's question is answered once, through its `done`: by the user, or withdrawn by
//   the shell (`blocked`) when the session locks, its window, page or popup closes, or the
//   module is turned off. A question not asked is answered after the call returns; one
//   asked while the module is off is not answered at all.
Singleton {
    id: root

    // The places: [{ key, root, host }]
    property var _places: []
    property int _lastKey: 0

    // A new key for a host's place or open question
    function newKey() {
        return ++_lastKey;
    }

    function addPlace(key, placeRoot, host) {
        _places = _places.filter(entry => entry.key !== key).concat([{ key: key, root: placeRoot, host: host }]);
    }

    function forgetPlace(key) {
        if (_places.some(entry => entry.key === key))
            _places = _places.filter(entry => entry.key !== key);
    }

    // The host of the nearest place above `item` (or `item` itself), or null
    function hostAbove(item) {
        let step = item !== null && typeof item === "object" ? item : null;
        for (let depth = 0; step && depth < 1000; depth++, step = step.parent ?? null) {
            const entry = _places.find(candidate => candidate.root === step);
            if (entry)
                return entry.host;
        }
        return null;
    }

    // The keys of the hosts with a question open (one, unless a host does not share the
    // rule: SettingsModalHost.shared)
    property var _openKeys: []
    readonly property bool busy: _openKeys.length > 0

    function opened(key) {
        if (!_openKeys.includes(key))
            _openKeys = _openKeys.concat([key]);
    }

    function closed(key) {
        if (_openKeys.includes(key))
            _openKeys = _openKeys.filter(other => other !== key);
    }

    // The session locked: the lock screen's word, or the test kit's in module test mode
    readonly property bool locked: ApiElements.sessionLocked

    // A module's open question: { handle, host, done, answered }
    property var _moduleCall: null

    // A module's question (module.ask): `handle` the module's handle, `from` the asking item
    // → a frozen handle { open, cancel() }
    function ask(handle, from, question, done) {
        const call = { handle: handle, host: null, done: typeof done === "function" ? done : null, answered: false };
        const callHandle = Object.freeze({
            get open() {
                return !call.answered;
            },
            cancel: function () {
                if (!call.answered && call.host)
                    call.host.cancel("asker");
            }
        });
        const spec = ApiElementRules.modalQuestion(question);
        const host = hostAbove(from);
        const refusal = ApiElementRules.modalAskRefusal(handle?.active === true, locked, host !== null,
                                                        host !== null && host.placeRefusal !== "", busy || host?.open === true,
                                                        host?.placeShown === true);
        if (refusal === "module") {
            call.answered = true;
            return callHandle;
        }
        if (refusal !== "") {
            _refuse(call, refusal, spec.subject);
            return callHandle;
        }
        const moduleId = String(handle.moduleId ?? "");
        for (const label of ApiElementRules.modalLongLabels(spec))
            ApiElements.once("ask.label:" + moduleId + ":" + label, "[" + moduleId + "] module.ask: the button label \""
                + label.slice(0, 80) + "\" is longer than the button text rule's " + ApiElementRules.modalLabelWords + " words");
        call.host = host;
        const asked = host.ask(spec, answer => {
            if (call.answered)
                return;
            call.answered = true;
            call.host = null;
            if (root._moduleCall === call)
                root._moduleCall = null;
            root._deliver(call, ApiElementRules.modalAnswer(answer, call.handle?.active === true));
        });
        if (asked !== "") {
            call.host = null;
            _refuse(call, locked ? "locked" : host.placeShown !== true ? "closed" : "busy", spec.subject);
            return callHandle;
        }
        _moduleCall = call;
        return callHandle;
    }

    // The module is off: its open question is withdrawn (blocked "module")
    function ownerGone(handle) {
        const call = _moduleCall;
        if (call !== null && call.handle === handle && !call.answered && call.host)
            call.host.cancel("module");
    }

    // Answered after the call that asked has returned
    function _refuse(call, blocked, subject) {
        call.answered = true;
        const answer = ApiElementRules.modalRefused(blocked, subject);
        // Not to a module turned off meanwhile
        Qt.callLater(() => {
            if (call.handle?.active === true)
                root._deliver(call, answer);
        });
    }

    function _deliver(call, answer) {
        if (!call.done)
            return;
        try {
            call.done(answer);
        } catch (error) {
            console.warn("[" + String(call.handle?.moduleId ?? "") + "] module.ask: the answer's handler threw: " + error);
        }
    }

    // ---- Module test mode (tests/ModuleTestKit.qml) ----

    // "" when the open question is module `moduleId`'s, else why it cannot be answered
    function _testProblem(moduleId) {
        const call = _moduleCall;
        if (call === null || call.answered || !call.host)
            return "no question is open";
        const owner = String(call.handle?.moduleId ?? "");
        if (owner !== String(moduleId ?? ""))
            return "the open question is module " + ModuleRules.show(owner) + "'s, not " + ModuleRules.show(moduleId);
        return "";
    }

    // The open module question as shown, frozen { moduleId, kind, title, body, items,
    // checks, buttons: [{ id, label, kind }] }, or null
    function testQuestion() {
        const call = _moduleCall;
        if (call === null || call.answered || !call.host)
            return null;
        const modal = call.host.modal;
        return ReadOnlyRules.copy({
            moduleId: String(call.handle?.moduleId ?? ""), kind: modal.look.kind, title: modal.title,
            body: ApiElementRules.modalBody(modal.body).map(line => line.text), items: ApiElementRules.modalItems(modal.items),
            checks: ApiElementRules.modalChecks(modal.checks).map(check => check.key),
            buttons: modal.buttonList.map(button => ({ id: button.id, label: button.label, kind: button.kind }))
        });
    }

    // The user clicked the button `buttonId` ("cancel": the cancel) of module `moduleId`'s
    // question, its checkboxes as `checked` ({ key: true }) → "" or why not
    function testAnswer(moduleId, buttonId, checked) {
        const problem = _testProblem(moduleId);
        if (problem !== "")
            return problem;
        const host = _moduleCall.host;
        const index = host.modal.buttonList.findIndex(button => button.id === String(buttonId));
        if (index < 0)
            return "the question has no button " + ModuleRules.show(buttonId);
        const values = {};
        for (const check of ApiElementRules.modalChecks(host.modal.checks))
            values[check.key] = checked?.[check.key] === true;
        host.modal.values = values;
        host._answer(index);
        return "";
    }
}
