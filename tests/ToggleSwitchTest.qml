import QtQuick
import qs.components
import qs.singletons

// The switch looks the same in every size and place: its colours come from the theme
// alone (no caller can set an off colour), the small and the large switch draw the same
// track in every state — off, on, each under the pointer (the `shownLit` preview), not
// enabled — and the off track stands out from every background a switch sits on.
TestCase {
    suiteName: "ToggleSwitch"

    property var _smallOff: ToggleSwitch {}
    property var _smallOn: ToggleSwitch { checked: true }
    property var _largeOff: ToggleSwitch { width: 44; height: 24 }
    property var _largeOn: ToggleSwitch { width: 44; height: 24; checked: true }

    // The backgrounds a switch sits on: the settings page, a popup and a side panel
    // (popupBackground), and a card on a settings page (surface)
    readonly property var backgrounds: [
        { place: "the settings page, popups and side panels", color: "popupBackground" },
        { place: "a settings card", color: "surface" }
    ]

    function _pointerArea(toggle) {
        for (const child of toggle.children)
            if (child.shownLit !== undefined)
                return child;
        return null;
    }

    // WCAG's relative luminance and contrast ratio
    function _luminance(color) {
        const channel = value => value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
    }

    function _contrast(first, second) {
        const a = _luminance(first);
        const b = _luminance(second);
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    }

    function _look(toggle) {
        return toggle.trackColor.toString() + " " + toggle.color.toString() + " " + toggle.opacity;
    }

    function _same(small, large, state) {
        assertEqual(_look(large), _look(small), state + ": the large switch draws what the small one does");
    }

    function run() {
        assert(!("offColor" in _smallOff), "a switch takes no off colour from its caller");

        // --- the states, both sizes ---
        _same(_smallOff, _largeOff, "off");
        _same(_smallOn, _largeOn, "on");
        assertEqual(_smallOff.color.toString(), Theme.switchOff.toString(), "off: the theme's switchOff");
        assertEqual(_smallOn.color.toString(), Theme.accent.toString(), "on: the accent");

        for (const toggle of [_smallOff, _smallOn, _largeOff, _largeOn])
            _pointerArea(toggle).shownLit = true;
        _same(_smallOff, _largeOff, "off, under the pointer");
        _same(_smallOn, _largeOn, "on, under the pointer");
        assertEqual(_smallOff.trackColor.toString(), Theme.switchOffHover.toString(), "off under the pointer: the theme's switchOffHover");
        assertEqual(_smallOn.trackColor.toString(), Theme.accentHover.toString(), "on under the pointer: the accent's hover");
        assert(!Qt.colorEqual(Theme.switchOffHover, Theme.switchOff), "under the pointer, off looks unlike off at rest");
        for (const toggle of [_smallOff, _smallOn, _largeOff, _largeOn])
            _pointerArea(toggle).shownLit = false;

        for (const toggle of [_smallOff, _smallOn, _largeOff, _largeOn])
            toggle.enabled = false;
        _same(_smallOff, _largeOff, "not enabled, off");
        _same(_smallOn, _largeOn, "not enabled, on");
        assert(_smallOff.opacity < 1, "not enabled, it is dimmed");
        for (const toggle of [_smallOff, _smallOn, _largeOff, _largeOn])
            toggle.enabled = true;

        // --- the off track on every background ---
        for (const background of backgrounds) {
            const ratio = _contrast(Theme.switchOff, Theme[background.color]);
            assert(ratio >= 3, "the off track stands out from " + background.place + " (" + background.color + "): " + ratio.toFixed(2) + ":1, at least 3:1");
        }
        assertEqual(Theme.switchOff.a, 1, "the off track is opaque: the same on every background");
    }
}
