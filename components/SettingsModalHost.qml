import QtQuick
import qs.singletons

// Where the Settings window's modal shows (SettingsModal): a layer over the whole window,
// one modal at a time. A page asks with `ask(spec, onAnswer)`:
//
//   spec: { kind, title, body, checks, content, buttons, cancelLabel, size, subject }
//     kind     "danger", "warning", "success" or "info" (ThemeRules.modalLook)
//     body     lines: strings or { text, strong }, plain text
//     checks   checkboxes, [{ key, label }], unchecked each time it opens
//     content  an optional Component under them; its item's `values`, when it has one, are
//              added to the answer's
//     buttons  [{ id, label, kind, cancel }] — always one cancel, last; none but the cancel:
//              the modal informs (ApiElementRules.modalButtons)
//     subject  the ids the question acts on; `withdraw(subject)` closes it when they go
//   onAnswer(answer): { button, cancelled, reason, values, subject } — `button` the id of
//     the button clicked, "cancel" when cancelled; `reason` "button", "close" (×),
//     "escape", "lock" (the session locked), "window" (the window hid or went), "page"
//     (the window turned to another page: `page` changed), "subject" (withdrawn); `values` the checkboxes' states by key and the content's; `subject` the
//     spec's, so the answer acts on what was asked about.
//
// `ask` returns "" when the modal opens, else why not: another is open (a question never
// replaces another under the user's pointer), or the session is locked — said in the log
// once until the outcome changes.
Item {
    id: root

    readonly property bool open: _spec !== null
    readonly property alias modal: _modal

    property var _spec: null
    property var _onAnswer: null
    // The last refusal logged: the same one again is not (log on a change of outcome)
    property string _lastRefusal: ""

    // What the window shows (its page's id): another one cancels the open question, whose
    // page went
    property var page: null
    onPageChanged: cancel("page")

    readonly property bool _locked: ApiElements.sessionLocked
    readonly property bool _windowShown: Window.window?.visible ?? false

    on_LockedChanged: if (_locked) cancel("lock")
    on_WindowShownChanged: if (!_windowShown) cancel("window")
    Component.onDestruction: cancel("window")

    function ask(spec, onAnswer) {
        const refusal = ApiElementRules.modalRefusal(open, _locked);
        if (refusal !== "") {
            if (_lastRefusal !== refusal)
                console.warn("[SettingsModal] not opened: " + refusal);
            _lastRefusal = refusal;
            return refusal;
        }
        _lastRefusal = "";
        _spec = spec !== null && typeof spec === "object" ? spec : {};
        _onAnswer = typeof onAnswer === "function" ? onAnswer : null;
        return "";
    }

    // The open modal closes as cancelled, for `reason`
    function cancel(reason) {
        if (open)
            _finish("cancel", true, reason);
    }

    // The open modal's subject went (removed, reloaded): it closes as cancelled
    function withdraw(subject) {
        if (open && ApiElementRules.sameSubject(_spec.subject, subject))
            cancel("subject");
    }

    function _answer(index) {
        const button = _modal.buttonList[index];
        if (!open || !button)
            return;
        _finish(button.cancel ? "cancel" : button.id, button.cancel, "button");
    }

    function _finish(button, cancelled, reason) {
        // Read before it closes: the content goes with it
        const contentValues = _modal.contentItem?.values;
        const values = Object.assign({}, _modal.values,
            contentValues !== null && typeof contentValues === "object" ? contentValues : {});
        const subject = _spec.subject;
        const callback = _onAnswer;
        _spec = null;
        _onAnswer = null;
        _lastRefusal = "";
        if (!callback)
            return;
        try {
            callback({ button: button, cancelled: cancelled, reason: reason, values: values, subject: subject });
        } catch (error) {
            console.warn("[SettingsModal] the answer's handler threw: " + error);
        }
    }

    SettingsModal {
        id: _modal
        anchors.fill: parent
        open: root.open
        kind: root._spec?.kind ?? "info"
        title: root._spec?.title ?? ""
        body: root._spec?.body ?? []
        checks: root._spec?.checks ?? []
        content: root._spec?.content ?? null
        buttons: root._spec?.buttons ?? []
        cancelLabel: root._spec?.cancelLabel ?? ""
        size: root._spec?.size ?? "m"
        onAnswered: index => root._answer(index)
        onRequested: event => root.cancel(event === "escape" ? "escape" : "close")
    }
}
