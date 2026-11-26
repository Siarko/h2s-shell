import QtQuick
import qs.components
import qs.singletons

// The switch looks the same in every size and place: its colours come from the theme
// alone (no caller can set an off colour), the small and the large switch draw the same
// track in every state — off, on, each under the pointer (the `shownLit` preview), not
// enabled — the off track stands out from every background a switch sits on, and the knob
// from the track in every state. The rules behind them (ThemeRules.switchTrack,
// switchTrackHover, switchKnob) on made-up themes: dark, light, a track too close to its
// background, one with alpha.
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

    function _contrast(first, second) {
        return ThemeRules.contrast(first, second);
    }

    function _knobStandsOut(toggle, state) {
        const ratio = _contrast(toggle.knobColor, toggle.trackColor);
        assert(ratio >= 3, state + ": the knob stands out from the track: " + ratio.toFixed(2) + ":1, at least 3:1");
    }

    function _rules() {
        const rules = ThemeRules;
        // WCAG's own figures: white on black 21:1, a colour on itself 1:1
        assertEqual(rules.contrast(Qt.color("white"), Qt.color("black")).toFixed(2), "21.00", "contrast: white on black is 21:1");
        assertEqual(rules.contrast(Qt.color("#777777"), Qt.color("#777777")).toFixed(2), "1.00", "contrast: a colour on itself is 1:1");

        const dark = [Qt.color("#4d4d4d"), Qt.color("#3b3b3b")];
        const light = [Qt.color("#f4f4f4"), Qt.color("#ffffff")];
        const far = rules.switchTrack(Qt.color("#aaaaaa"), dark, 3);
        assertEqual(far.toString(), "#aaaaaa", "a track already 3:1 from every background stays as it is");
        const near = rules.switchTrack(Qt.color("#5a5a5a"), dark, 3);
        assert(Math.min(rules.contrast(near, dark[0]), rules.contrast(near, dark[1])) >= 3, "a track too close to dark backgrounds is moved to 3:1: " + near);
        assert(rules.luminance(near) > rules.luminance(Qt.color("#5a5a5a")), "… lighter, away from them");
        assert(rules.luminance(near) < rules.luminance(rules.switchTrack(Qt.color("#5a5a5a"), dark, 4.5)), "… only as far as it takes");
        const seeThrough = rules.switchTrack(Qt.rgba(0.67, 0.67, 0.67, 0.2), dark, 3);
        assertEqual(seeThrough.a, 1, "a track given with alpha comes out opaque");
        const onLight = rules.switchTrack(Qt.color("#dddddd"), light, 3);
        assert(Math.min(rules.contrast(onLight, light[0]), rules.contrast(onLight, light[1])) >= 3, "a track too close to light backgrounds is moved to 3:1: " + onLight);
        assert(rules.luminance(onLight) < rules.luminance(Qt.color("#dddddd")), "… darker, away from them");
        const hoverDark = rules.switchTrackHover(far, dark);
        const hoverLight = rules.switchTrackHover(onLight, light);
        assert(rules.contrast(hoverDark, dark[0]) > rules.contrast(far, dark[0]), "under the pointer, over dark backgrounds, the track stands further out (lighter)");
        assert(rules.contrast(hoverLight, light[0]) > rules.contrast(onLight, light[0]), "under the pointer, over light backgrounds, the track stands further out (darker)");
        const white = Qt.color("white");
        const grey = Qt.color("#4d4d4d");
        assertEqual(rules.switchKnob(Qt.color("#aaaaaa"), [white, grey]).toString(), grey.toString(), "the knob on a light track is the dark one");
        assertEqual(rules.switchKnob(Qt.color("#202020"), [white, grey]).toString(), white.toString(), "the knob on a dark track is the light one");
    }

    function _look(toggle) {
        return toggle.trackColor.toString() + " " + toggle.color.toString() + " " + toggle.knobColor.toString() + " " + toggle.opacity;
    }

    function _same(small, large, state) {
        assertEqual(_look(large), _look(small), state + ": the large switch draws what the small one does");
    }

    function run() {
        _rules();
        assert(!("offColor" in _smallOff), "a switch takes no off colour from its caller");

        // --- the states, both sizes ---
        _same(_smallOff, _largeOff, "off");
        _same(_smallOn, _largeOn, "on");
        assertEqual(_smallOff.color.toString(), Theme.switchOff.toString(), "off: the theme's switchOff");
        assertEqual(_smallOn.color.toString(), Theme.accent.toString(), "on: the accent");
        _knobStandsOut(_smallOff, "off");
        _knobStandsOut(_smallOn, "on");

        for (const toggle of [_smallOff, _smallOn, _largeOff, _largeOn])
            _pointerArea(toggle).shownLit = true;
        _same(_smallOff, _largeOff, "off, under the pointer");
        _same(_smallOn, _largeOn, "on, under the pointer");
        assertEqual(_smallOff.trackColor.toString(), Theme.switchOffHover.toString(), "off under the pointer: the theme's switchOffHover");
        assertEqual(_smallOn.trackColor.toString(), Theme.accentHover.toString(), "on under the pointer: the accent's hover");
        assert(!Qt.colorEqual(Theme.switchOffHover, Theme.switchOff), "under the pointer, off looks unlike off at rest");
        _knobStandsOut(_smallOff, "off, under the pointer");
        _knobStandsOut(_smallOn, "on, under the pointer");
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
