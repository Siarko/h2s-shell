import QtQuick
import Quickshell
import Quickshell.Services.Pam

// The PAM adapter of one method (password, fingerprint, u2f): one PamContext, turned into
// the rules' events, and the rules' effects turned into calls on it. No decisions: what to
// start, when to answer and what a result means are LockRules'. What is here is only what
// Quickshell 0.3.2's PamContext needs around it (docs/plans/lockscreen.md, section 1):
//
// - Every event carries the conversation id the rules gave in startPam. An event from a
//   conversation that is no longer the current one still carries its own id, and the
//   rules ignore it.
// - start() can refuse without any signal (a config that is not there): its return value
//   is the only word, reported as pamStartFailed. When it fails because the PAM helper
//   could not be forked, Quickshell has already emitted completed(Error) inside start():
//   then the completion is the report and no pamStartFailed follows.
// - abortPam / respondPam for a conversation that is not the current one are dropped: a
//   late effect must not abort or answer the next conversation.
// - At most one respond() per prompt: PamContext hands a second one to the next prompt.
// - config / configDirectory are set only while the context is inactive; set while
//   active, PamContext drops the new value silently.
//
// The typed password passes through respond() only, as an argument: nothing here keeps
// it. Created with the lock's scope (LockScope) and destroyed with it, which kills a
// conversation still running — no reset list to keep.
Scope {
    id: root

    // The method's name, as in LockRules: "password", "fingerprint", "u2f"
    required property string method

    // An event for the rules (Lockscreen dispatches it)
    signal event(var event)
    // A line for the shell log about the I/O itself (never typed text)
    signal logLine(string level, string message)

    // The conversation id of the one running, or null
    property var _conversation: null
    // The current conversation's last message asked for a response not given yet
    property bool _awaitingResponse: false
    // Set when a completion was reported from inside start() (see above)
    property bool _completedInStart: false

    function start(conversation, configDirectory, config) {
        if (_context.active) {
            // The rules never start a method that runs (an abort, then a settle, come
            // first). Should it happen anyway, the new one is refused rather than aborting
            // and starting in one pass (the child is only killed at the next pass, and the
            // config cannot change while active): the running conversation keeps its own id,
            // which the rules then ignore
            logLine("error", method + ": asked to start while a conversation still runs: refused");
            root.event({ type: "pamStartFailed", method: method, conversation: conversation });
            return;
        }
        _conversation = null;
        _awaitingResponse = false;
        // Only while inactive: PamContext drops a config set during a conversation
        _context.configDirectory = configDirectory;
        _context.config = config;
        _conversation = conversation;
        _completedInStart = false;
        const started = _context.start();
        if (started || _completedInStart)
            return;
        _conversation = null;
        logLine("warning", method + ": PamContext.start() refused " + configDirectory + "/" + config);
        root.event({ type: "pamStartFailed", method: method, conversation: conversation });
    }

    function abort(conversation) {
        if (_conversation === null || conversation !== _conversation)
            return;
        _conversation = null;
        _awaitingResponse = false;
        _context.abort();
    }

    // `text` is the secret or a typed answer: used here, never stored
    function respond(conversation, text) {
        if (_conversation === null || conversation !== _conversation)
            return;
        if (!_awaitingResponse) {
            logLine("warning", method + ": a response with no prompt waiting for one was dropped");
            return;
        }
        _awaitingResponse = false;
        _context.respond(text);
    }

    function _resultName(result) {
        switch (result) {
        case PamResult.Success: return "success";
        case PamResult.Failed: return "failed";
        case PamResult.MaxTries: return "maxTries";
        default: return "error";
        }
    }

    PamContext {
        id: _context

        onPamMessage: {
            if (root._conversation === null)
                return;
            root._awaitingResponse = responseRequired;
            root.event({
                type: "pamMessage",
                method: root.method,
                conversation: root._conversation,
                message: message,
                messageIsError: messageIsError,
                responseRequired: responseRequired,
                responseVisible: responseVisible
            });
        }

        // Emitted right before completed(Error): which kind of failure it was is only
        // known here
        onError: error => {
            if (root._conversation !== null)
                root.logLine("warning", root.method + ": PAM error: " + PamError.toString(error));
        }

        onCompleted: result => {
            const conversation = root._conversation;
            if (conversation === null)
                return;
            root._conversation = null;
            root._awaitingResponse = false;
            root._completedInStart = true;
            root.event({ type: "pamCompleted", method: root.method, conversation: conversation, result: root._resultName(result) });
        }
    }
}
