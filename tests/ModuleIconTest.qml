import QtQuick
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons

// A module's icon (module API 1.26): a host of the suite's own pointed at the icon fixtures
// (tests/fixtures/modules/icon-*), each drawn by components/ModuleIcon.qml in a small window —
// a glyph as text in the place's colour; a one-colour SVG painted in the place's colour; an
// SVG in its own colours; a picture fitted in its square, never stretched; and the first
// letter of the name in the muted colour for a module with no icon, one too big, one that is
// a link out of its directory, one whose file is missing — each with its error in the status
// — and one whose file passes the check but cannot be drawn (the error once it is first
// drawn). Read back from the pixels drawn.
//
// Opens a small window in a corner of the screen for a moment (a layer surface, so it moves
// no windows).
TestCase {
    id: suite
    suiteName: "ModuleIcon"
    asynchronous: true

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"
    readonly property var names: ["icon-glyph", "icon-svg", "icon-svg-own", "icon-image", "icon-undrawable", "icon-too-big",
                                  "icon-link", "icon-missing", "icon-none"]
    // The place's colour the suite gives every icon: a glyph and a painted SVG come out in it
    readonly property color placeColour: "#2060c0"

    property ModuleHost host: ModuleHost {
        logStates: false
    }
    property var _icons: ({})

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 400
        implicitHeight: 80
        color: Theme.surface
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Row {
            id: row
            x: 10; y: 10
            spacing: 10
        }

        QT.TestCase {
            id: driver
            name: "ModuleIconDriver"
            when: false
        }
    }

    property Component _iconComponent: Component {
        ModuleIcon {
            host: suite.host
            color: suite.placeColour
        }
    }

    function _until(condition, limitMs = 5000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _status(id) {
        return host.status(id);
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }

    // The colour drawn in `image` (the row's, grabbed once) at a point of the icon, as
    // "r g b" in 0–255 — by default its centre
    function _drawn(image, icon, x, y) {
        const point = icon.mapToItem(row, x ?? icon.width / 2, y ?? icon.height / 2);
        return _at(image, Math.floor(point.x), Math.floor(point.y));
    }

    // The colour of a grabbed image's pixel, as "r g b"
    function _at(image, x, y) {
        return [image.red(x, y), image.green(x, y), image.blue(x, y)].join(" ");
    }

    function _rgb(colour) {
        return [colour.r, colour.g, colour.b].map(part => Math.round(part * 255)).join(" ");
    }

    function runAsync() {
        host.load(names.map(name => fixtures + "/" + name), {});
        if (!_until(() => host.settled && names.every(name => _status(name) !== null), 10000)) {
            fail("the icon fixtures did not settle: " + JSON.stringify(host.statuses.map(status => status.id + " " + status.state)));
            host.unload();
            finish();
            return;
        }
        for (const name of names) {
            const status = _status(name);
            assertEqual(status?.state, "loaded", name + ": loaded (an icon never fails a module)" + (status?.state !== "loaded" ? " " + JSON.stringify(status?.errors) : ""));
            _icons[name] = _iconComponent.createObject(row, { moduleId: name });
        }

        // What each shows before anything is drawn
        assertEqual(names.map(name => _icons[name].shownAs).join(","),
                    "glyph,svg,svg,image,svg,letter,letter,letter,letter",
                    "each kind shown as itself; too big, a link out, missing and none: the letter");
        assertEqual(JSON.stringify(host.icons["icon-glyph"]), JSON.stringify({ kind: "glyph", glyph: "", url: "", colors: "theme" }),
                    "the host's icons: a glyph");
        assertEqual(JSON.stringify(host.icons["icon-svg-own"]),
                    JSON.stringify({ kind: "svg", glyph: "", url: "file://" + fixtures + "/icon-svg-own/icon.svg", colors: "own" }),
                    "… an SVG in its own colours, by its file's URL");
        assertEqual(host.icons["icon-svg"]?.colors + " " + host.icons["icon-image"]?.colors, "theme own",
                    "… an SVG in the theme's colour by default, a picture in its own");
        assertEqual(["icon-too-big", "icon-link", "icon-missing", "icon-none"].filter(name => ModuleRules.has(host.icons, name)).length, 0,
                    "… none for a bad file or none declared");
        assertEqual(_status("icon-glyph").errors.length + _status("icon-svg").errors.length + _status("icon-image").errors.length
                    + _status("icon-none").errors.length, 0, "good icons and none: no error");
        assert(_has(_status("icon-too-big").errors, "icon icon.svg is larger than 65536 bytes (no icon)"),
               "too big: said in the status — " + JSON.stringify(_status("icon-too-big").errors));
        assert(_has(_status("icon-link").errors, "icon icon.svg leaves the module directory through a link (no icon)"),
               "a link out: not followed, said — " + JSON.stringify(_status("icon-link").errors));
        assert(_has(_status("icon-missing").errors, "icon icon.svg does not exist (no icon)"),
               "missing: said — " + JSON.stringify(_status("icon-missing").errors));
        assertEqual(_icons["icon-none"].letter + _icons["icon-too-big"].letter + _icons["icon-link"].letter, "NTL",
                    "the letter: the first of the module's name, upper case");

        // Drawn
        const square = _icons["icon-glyph"].size;
        assert(square > 0 && names.every(name => _icons[name].width === square && _icons[name].height === square),
               "each a square as tall as a line of body text (" + square + ")");
        if (!_until(() => _icons["icon-undrawable"].shownAs === "letter" && _icons["icon-svg"].painted.visible
                    && _icons["icon-svg-own"].picture.status === Image.Ready && _icons["icon-image"].picture.status === Image.Ready))
            fail("the pictures did not load, or the undrawable one did not fall back");
        assert(_has(_status("icon-undrawable").errors, "icon icon.svg cannot be drawn"),
               "a file that passes the check but cannot be drawn: an error once it is drawn — " + JSON.stringify(_status("icon-undrawable").errors));
        assertEqual(_status("icon-undrawable").errors.length, 1, "… once");
        assertEqual(_icons["icon-undrawable"].letter, "U", "… and the letter in its place");
        assert(!ModuleRules.has(host.icons, "icon-undrawable"), "… for every place from now on (no icon in the host's list)");
        driver.wait(100);
        const drawn = driver.grabImage(row);
        assertEqual(_drawn(drawn, _icons["icon-svg"]), _rgb(placeColour), "a one-colour SVG (black) painted in the place's colour");
        assertEqual(_drawn(drawn, _icons["icon-svg-own"]), "255 0 0", "an SVG in its own colours: red");
        assertEqual(_drawn(drawn, _icons["icon-image"]), "0 255 0", "a picture in its own colours: green");
        assertEqual(_drawn(drawn, _icons["icon-image"], square / 2, 1), _rgb(Theme.surface),
                    "… twice as wide as tall: fitted, never stretched (the square's top row is the background)");
        assertEqual(_rgb(_icons["icon-glyph"].children.find(child => child.text !== undefined).color), _rgb(placeColour),
                    "a glyph in the place's colour");
        assertEqual(_rgb(_icons["icon-none"].children.find(child => child.text !== undefined).color), _rgb(Theme.textMuted),
                    "the letter in the muted colour");

        for (const name of names)
            _icons[name].destroy();
        host.unload();
        finish();
    }
}
