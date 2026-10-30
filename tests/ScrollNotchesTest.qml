import QtQuick
import qs.components

TestCase {
    suiteName: "ScrollNotches"

    property ScrollNotches _wheel: ScrollNotches {}

    // Each event's result, as text: assertEqual compares arrays by identity
    function _feedAll(deltas) {
        return deltas.map(delta => _wheel.feed(delta)).join(" ");
    }

    function run() {
        // --- a standard wheel: 120 per notch ---
        assertEqual(_wheel.feed(120), 1, "the very first notch up goes up");
        assertEqual(_wheel.feed(120), 1, "and the next");
        assertEqual(_wheel.feed(-120), -1, "turning back: the first notch down goes down");
        assertEqual(_wheel.feed(-120), -1, "and the next");
        assertEqual(_wheel.feed(120), 1, "back up again at once");

        // --- small steps: a high-resolution wheel or a touchpad ---
        _wheel._buffer = 0;
        assertEqual(_feedAll([30, 30, 30]), "0 0 0", "a quarter notch at a time: not yet");
        assertEqual(_wheel.feed(30), 1, "the fourth makes the notch");
        _wheel._buffer = 0;
        assertEqual(_feedAll([28, 28, 28, 28]), "0 0 0 1", "steps adding up a little short of 120 still count");
        _wheel._buffer = 0;
        assertEqual(_feedAll([60, -30, -30, -30, -30]), "0 0 0 0 -1", "a partial notch up is dropped on turning back");

        // --- the smooth amount, as the volume uses it ---
        assertEqual(_wheel.notches(112), 1, "one notch's worth");
        assertEqual(_wheel.notches(-56), -0.5, "half a notch down");
    }
}
