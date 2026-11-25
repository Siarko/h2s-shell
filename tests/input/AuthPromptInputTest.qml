import QtQuick
import Quickshell
import qs.polkit
import qs.singletons
import qs.tests

// The polkit prompt (polkit/AuthPrompt.qml, on a stand-in flow: nothing reaches polkit) under
// a real pointer and keyboard: a click on the "As user" picker takes the keys, and once its
// list closes — Escape, a press beside it, the same account picked — typing goes to the
// password field again, and Enter answers rather than opening the list.
TestCase {
    id: suite
    suiteName: "AuthPromptInput"
    asynchronous: true

    // A suite to wait for first: one window at a time takes the keyboard
    property var after: null
    property var submitted: []

    component StandInFlow: QtObject {
        property string message: "Authentication is needed to run `/usr/bin/true' as the super user"
        property string actionId: "org.freedesktop.policykit.exec"
        property var identities: [{ displayName: "alice" }, { displayName: "bob" }]
        property var selectedIdentity: identities[0]
        property bool isResponseRequired: true
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property string inputPrompt: "Password:"
        signal authenticationFailed()
        function submit(text) { suite.submitted = suite.submitted.concat([text]); }
        function cancelAuthenticationRequest() {}
    }
    property Component _flowComponent: Component { StandInFlow {} }
    property Component _promptComponent: Component { AuthPrompt {} }

    property var _driver: WindowDriver {}

    function _until(condition, limitMs = 5000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            _driver.wait(10);
        return condition();
    }

    function _find(item, test) {
        for (const child of item.children) {
            if (test(child))
                return child;
            const found = _find(child, test);
            if (found)
                return found;
        }
        return null;
    }

    function runAsync() {
        if (after)
            _until(() => after.done, 110000);
        const flow = _flowComponent.createObject(suite);
        const prompt = _promptComponent.createObject(suite, { flow: flow });
        const input = _inputComponent.createObject(prompt.contentItem, { driver: _driver });
        const field = _find(prompt.contentItem, child => child.echoMode === TextInput.Password);
        const picker = _find(prompt.contentItem, child => child.objectName === "identityPicker");
        assert(field !== null && picker !== null && picker.visible, "the prompt with its password field and the account picker");
        assert(_until(() => field.activeFocus), "the password field has the keys");

        const pick = picker;
        const clickPicker = () => input.click(picker, 20, picker.height / 2);

        // Escape
        clickPicker();
        assert(_until(() => pick.open), "a click opens the account list");
        input.key("Escape");
        assert(_until(() => !pick.open), "Escape closes the list (the prompt stays)");
        input.type("ab");
        assert(_until(() => field.text === "ab"), "typing then goes to the password field (" + JSON.stringify(field.text) + ")");

        // A press beside the list
        clickPicker();
        assert(_until(() => pick.open), "the list open again");
        input.click(field, 5, field.height / 2);
        assert(_until(() => !pick.open), "a press beside it closes it");
        input.type("c");
        assert(_until(() => field.text === "abc"), "… typing goes to the field (" + JSON.stringify(field.text) + ")");

        // The same account picked
        clickPicker();
        assert(_until(() => pick.open), "the list open again");
        input.key("Return");
        assert(_until(() => !pick.open), "Enter on the current account closes it");
        input.type("d");
        assert(_until(() => field.text === "abcd"), "… typing goes to the field (" + JSON.stringify(field.text) + ")");
        input.key("Return");
        assert(_until(() => submitted.length === 1), "Enter answers with the password");
        assert(!pick.open, "… and does not open the list");

        input.destroy();
        prompt.destroy();
        flow.destroy();
        finish();
    }

    property Component _inputComponent: Component { InputDriver {} }
}
