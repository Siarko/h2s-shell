import QtQuick
import qs.components
import qs.panels.calendar
import qs.singletons

// The fields' and choices' preview of a look without the pointer or the keyboard (the
// mockups' pointer and keyboard states): InputField, Checkbox, Dropdown, DateField and
// TimeField drawn as with the keyboard (`shownFocused`), Dropdown as under the pointer
// (`shownLit`), each with neither there, and back at rest when the preview is off.
// DeleteButton's: ButtonKindsTest.
TestCase {
    id: suite
    suiteName: "FieldPreview"
    asynchronous: true

    property var _input: InputField { placeholder: "Name" }
    property var _checkbox: Checkbox { label: "x" }
    property var _dropdown: Dropdown { options: [{ value: 1, label: "One" }]; value: 1 }
    property var _date: DateField { date: "2026-01-15" }
    property var _time: TimeField {}

    // The colours change through their Behaviors (instant in the suites, done on a later
    // frame): each stage checks what the one before it changed once its colour is there (at
    // most a generous deadline: the check then fails)
    property int _stage: 0
    property real _waited: 0
    property Timer _poll: Timer {
        interval: 10
        repeat: true
        onTriggered: {
            suite._waited += interval;
            const stage = suite._stages()[suite._stage];
            if (stage.ready() || suite._waited >= 3000) {
                stop();
                suite._run();
            }
        }
    }

    function _is(colour, name) {
        return Qt.colorEqual(colour, Theme[name]);
    }

    function _all(item, typeName) {
        let found = [];
        for (const child of item.children) {
            if (child.toString().startsWith(typeName))
                found.push(child);
            found = found.concat(_all(child, typeName));
        }
        return found;
    }

    // Each stage: when it may check (the colour it expects is there), and its checks and
    // the change the next one checks
    function _stages() {
        return [
            { ready: () => _input.border.color.a === 0, run: _inputAtRest },
            { ready: () => _is(_input.border.color, "accent"), run: _inputFocused },
            { ready: () => _is(_input.border.color, "error"), run: _inputProblem },
            { ready: () => _input.border.color.a === 0, run: _inputBack },
            { ready: () => _is(_box().border.color, "textDisabled"), run: _checkboxAtRest },
            { ready: () => _ringLit(_checkbox), run: _checkboxFocused },
            { ready: () => _is(_box().border.color, "textDisabled"), run: _checkboxBack },
            { ready: () => _is(_dropdown.border.color, "outline"), run: _dropdownAtRest },
            { ready: () => _is(_dropdown.border.color, "textMuted"), run: _dropdownLit },
            { ready: () => _ringLit(_dropdown), run: _dropdownFocused },
            { ready: () => _is(_dropdown.border.color, "outline"), run: _dropdownBack },
            { ready: () => _is(_dateFrame().border.color, "outline"), run: _dateAtRest },
            { ready: () => _is(_dateFrame().border.color, "accent"), run: _dateFocused },
            { ready: () => _is(_dateFrame().border.color, "outline"), run: _dateBack },
            { ready: () => _is(_dateFrame().border.color, "accent"), run: _dateArmed },
            { ready: () => _is(_timeFrame().border.color, "outline"), run: _timeAtRest },
            { ready: () => _is(_timeFrame().border.color, "accent"), run: _timeFocused },
            { ready: () => _is(_timeFrame().border.color, "outline"), run: _timeBack }
        ];
    }

    function runAsync() {
        _stage = 0;
        _waited = 0;
        _poll.start();
    }

    function _run() {
        _stages()[_stage].run();
        _stage++;
        if (_stage >= _stages().length) {
            finish();
            return;
        }
        _waited = 0;
        _poll.start();
    }

    // --- InputField: the accent border, the placeholder gone ---
    function _placeholder() {
        return _all(_input, "QQuickText").find(text => text.text === "Name");
    }
    function _inputAtRest() {
        assert(_input.border.color.a === 0, "a field at rest: no border");
        assert(_placeholder().visible, "an empty field at rest: its placeholder");
        _input.shownFocused = true;
    }
    function _inputFocused() {
        assert(!_input.editing && _is(_input.border.color, "accent"), "shownFocused, without the keyboard: the accent border");
        assert(_ringLit(_input), "… and the keyboard's ring");
        assert(!_placeholder().visible, "… and no placeholder, as with the keyboard");
        _input.problem = true;
    }
    function _inputProblem() {
        assert(_is(_input.border.color, "error"), "a problem keeps its red border in the preview");
        _input.problem = false;
        _input.shownFocused = false;
    }
    function _inputBack() {
        assert(_input.border.color.a === 0 && _placeholder().visible, "shownFocused off: at rest again");
    }

    // The keyboard's ring of a control (FocusRing) is lit
    function _ringLit(item) {
        const walk = node => Array.from(node.children).some(child => (child.focusRing === true && child.lit) || walk(child));
        return walk(item);
    }

    // --- Checkbox: the keyboard's ring round the box, its border as it was ---
    function _box() {
        return _all(_checkbox, "QQuickRectangle")[0];
    }
    function _checkboxAtRest() {
        assert(_is(_box().border.color, "textDisabled"), "a checkbox at rest: the box's border dim");
        _checkbox.shownFocused = true;
    }
    function _checkboxFocused() {
        assert(!_checkbox.activeFocus && _ringLit(_checkbox), "shownFocused, without the keyboard: the keyboard's ring");
        assert(_is(_box().border.color, "textDisabled"), "… the box's border as at rest");
        _checkbox.shownFocused = false;
    }
    function _checkboxBack() {
        assert(_is(_box().border.color, "textDisabled") && !_ringLit(_checkbox), "shownFocused off: at rest again");
    }

    // --- Dropdown: lighter under the pointer, the keyboard's ring with the keyboard ---
    function _dropdownAtRest() {
        assert(_is(_dropdown.border.color, "outline"), "a dropdown at rest: the outline");
        _dropdown.shownLit = true;
    }
    function _dropdownLit() {
        assert(_is(_dropdown.border.color, "textMuted"), "shownLit, no pointer over it: drawn as under the pointer");
        _dropdown.shownFocused = true;
    }
    function _dropdownFocused() {
        assert(!_dropdown.activeFocus && _ringLit(_dropdown), "shownFocused, without the keyboard: the keyboard's ring");
        assert(_is(_dropdown.border.color, "textMuted"), "… the border as under the pointer");
        _dropdown.shownLit = false;
        _dropdown.shownFocused = false;
    }
    function _dropdownBack() {
        assert(_is(_dropdown.border.color, "outline") && !_ringLit(_dropdown), "both off: at rest again");
        assert(!_dropdown.open, "a preview opens nothing");
    }

    // --- DateField: the accent border, the day selected ---
    function _dateFrame() {
        return _all(_date, "QQuickRectangle")[0];
    }
    function _day() {
        return _all(_date, "QQuickTextInput")[0];
    }
    function _dateAtRest() {
        assert(_is(_dateFrame().border.color, "outline") && _day().selectedText === "", "a date field at rest: the outline, nothing selected");
        _date.shownFocused = true;
        assertEqual(_day().selectedText, "15", "shownFocused: the day selected, as a click leaves it");
        _date.date = "2026-02-03";
        assertEqual(_day().selectedText, "03", "a date set anew: the new day selected");
    }
    function _dateFocused() {
        assert(!_date.editing && _is(_dateFrame().border.color, "accent") && _ringLit(_date), "shownFocused, without the keyboard: the accent border and the keyboard's ring");
        _date.shownFocused = false;
        assertEqual(_day().selectedText, "", "shownFocused off: nothing selected");
    }
    function _dateBack() {
        assert(_is(_dateFrame().border.color, "outline"), "shownFocused off: the outline again");
        _date.armed = true;
        _date.shownFocused = true;
    }
    function _dateArmed() {
        assertEqual(_dateFrame().border.width, Theme.border.width, "armed and focused: the plain border, as with the keyboard");
        _date.armed = false;
        _date.shownFocused = false;
    }

    // --- TimeField: the accent border, the hours selected ---
    function _timeFrame() {
        return _all(_time, "QQuickRectangle")[0];
    }
    function _hours() {
        return _all(_time, "QQuickTextInput")[0];
    }
    function _timeAtRest() {
        _time.setValue("10:30");
        assert(_is(_timeFrame().border.color, "outline") && _hours().selectedText === "", "a time field at rest: the outline, nothing selected");
        _time.shownFocused = true;
        assertEqual(_hours().selectedText, "10", "shownFocused: the hours selected");
        _time.setValue("07:05");
        assertEqual(_hours().selectedText, "07", "a value set anew: the new hours selected");
        assertEqual(_time.text, "07:05", "the preview leaves the value as it is");
    }
    function _timeFocused() {
        assert(_is(_timeFrame().border.color, "accent") && _ringLit(_time), "shownFocused, without the keyboard: the accent border and the keyboard's ring");
        _time.shownFocused = false;
        assertEqual(_hours().selectedText, "", "shownFocused off: nothing selected");
    }
    function _timeBack() {
        assert(_is(_timeFrame().border.color, "outline"), "shownFocused off: the outline again");
    }
}
