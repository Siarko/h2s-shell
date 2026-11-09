import QtQuick
import qs.singletons

TestCase {
    suiteName: "ToastRules"

    function _screens(focused, fullscreen) {
        return ["DP-2", "HDMI-A-1", "eDP-1"].map(name => ({
            name: name, focused: name === focused, fullscreen: (fullscreen ?? []).includes(name)
        }));
    }

    function run() {
        const at = (settings, screens) => ToastRules.screenFor(settings, screens);
        const defaults = { screen: "", fullscreen: "show", fullscreenScreen: "" };
        const with_ = change => Object.assign({}, defaults, change);

        // --- where ---
        assertEqual(at(defaults, _screens("HDMI-A-1")), "HDMI-A-1", "the focused screen");
        assertEqual(at(with_({ screen: "DP-2" }), _screens("HDMI-A-1")), "DP-2", "a chosen screen, focused or not");
        assertEqual(at(with_({ screen: "DP-3" }), _screens("HDMI-A-1")), "HDMI-A-1",
                    "a chosen screen not connected: the focused one");
        assertEqual(at(defaults, [{ name: "eDP-1", focused: false, fullscreen: false }]), "eDP-1",
                    "none focused (not known yet): the first");
        assertEqual(at(defaults, []), "", "no screens: nowhere");
        assertEqual(at(undefined, _screens("DP-2")), "DP-2", "no settings: the focused screen");

        // --- a fullscreen window on the toasts' screen ---
        assertEqual(at(defaults, _screens("DP-2", ["DP-2"])), "DP-2", "show anyway");
        assertEqual(at(with_({ fullscreen: "hide" }), _screens("DP-2", ["DP-2"])), "", "hide: nowhere");
        assertEqual(at(with_({ fullscreen: "hide" }), _screens("DP-2", ["HDMI-A-1"])), "DP-2",
                    "hide looks at the toasts' screen only: fullscreen elsewhere changes nothing");
        assertEqual(at(with_({ screen: "HDMI-A-1", fullscreen: "hide" }), _screens("DP-2", ["DP-2"])), "HDMI-A-1",
                    "a chosen screen without one: fullscreen on the focused screen changes nothing");

        // --- elsewhere ---
        const elsewhere = with_({ fullscreen: "elsewhere" });
        assertEqual(at(elsewhere, _screens("DP-2", ["DP-2"])), "HDMI-A-1", "any free screen: the first free one");
        assertEqual(at(elsewhere, _screens("HDMI-A-1", ["DP-2", "HDMI-A-1"])), "eDP-1", "skipping others in fullscreen");
        assertEqual(at(elsewhere, _screens("DP-2", ["DP-2", "HDMI-A-1", "eDP-1"])), "", "none free: nowhere");
        assertEqual(at(elsewhere, [{ name: "eDP-1", focused: true, fullscreen: true }]), "",
                    "one screen, in fullscreen: nowhere");
        const onHdmi = with_({ fullscreen: "elsewhere", fullscreenScreen: "HDMI-A-1" });
        assertEqual(at(onHdmi, _screens("DP-2", ["DP-2"])), "HDMI-A-1", "a chosen screen for fullscreen");
        assertEqual(at(onHdmi, _screens("DP-2", ["DP-2", "HDMI-A-1"])), "",
                    "the chosen screen in fullscreen too: nowhere");
        assertEqual(at(onHdmi, _screens("HDMI-A-1", ["HDMI-A-1"])), "",
                    "the chosen screen is the toasts' screen, in fullscreen: nowhere");
        assertEqual(at(with_({ fullscreen: "elsewhere", fullscreenScreen: "DP-3" }), _screens("DP-2", ["DP-2"])), "",
                    "the chosen screen not connected: nowhere");
        assertEqual(at(onHdmi, _screens("DP-2", [])), "DP-2", "no fullscreen window: where it would be");
    }
}
