import QtQuick

// Turns wheel movement into whole notches, for things that step — a track, a player, a
// slider's unit — rather than move smoothly. Feed it each wheel event's angleDelta; a
// touchpad's or a high-resolution wheel's small steps add up until they make a notch.
// Used by BarWidget and CustomMouseArea.
QtObject {
    // angleDelta is in eighths of a degree, and a standard wheel's notch is 15°, 120 of
    // them; a little less counts, so a high-resolution wheel whose steps add up just
    // short of 120 still makes its notch
    readonly property real notchDelta: 112

    // The movement towards the next notch, in notches; signed by its direction
    property real _buffer: 0

    // A wheel event's movement in notches, fractional
    function notches(angleDelta) {
        return angleDelta / notchDelta;
    }

    // Takes one wheel event; returns 1 or -1 when it completes a notch that way, else 0.
    // Turning back starts afresh, so the first notch the other way is not eaten by what
    // was left over.
    function feed(angleDelta) {
        const amount = notches(angleDelta);
        if (_buffer * amount < 0)
            _buffer = 0;
        _buffer += amount;
        if (Math.abs(_buffer) < 1)
            return 0;
        const direction = _buffer > 0 ? 1 : -1;
        _buffer -= direction;
        return direction;
    }
}
