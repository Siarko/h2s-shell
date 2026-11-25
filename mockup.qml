//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
// Imported so that Quickshell takes the kit into the tree it resolves `qs.…` against: it
// follows the imports of the files it loads at the start, not of a file created later
import qs.mockups.kit

// The one root entry of the mockups (development only): loads the mockup H2S_MOCKUP names
// against this tree, so that its `import qs.…` lines reach the real singletons and
// components. Mockup code and the protocol: mockups/kit/MockupWindow.qml.
//
//   H2S_MOCKUP=<kind>/<name>   mockups/<kind>/<name>/Mockup.qml; the kind is components,
//                              views or plans, the name lowercase letters, digits and "-"
//   H2S_MOCKUP=gallery         on screen: every component in one window
//                              (mockups/kit/Gallery.qml)
//   H2S_MOCKUP_BASE            "tests/fixtures/mockups" loads the runners' fixture mockups
//                              instead of mockups/; nothing else is taken
//   H2S_MOCKUP_SHOT=1          headless: every state or scene in turn, a MOCKUP-SHOT line each,
//                              stepped by `ipc call mockup next`; then MOCKUP-DONE, exit 0
//   H2S_MOCKUP_SHOT_LIMIT_MS   how long the shots may take in all (60000 by default), a
//                              guard against a hang: then MOCKUP-ERROR
//   H2S_MOCKUP_STATE=<state>   on screen: opens a component or view on that state alone
//                              (without it, one with state cells shows every state)
//   H2S_MOCKUP_SCENE=<scene>   on screen: opens a plan on that scene (each variable is
//                              refused for the other kind)
//   H2S_MOCKUP_THEME=<theme>   on screen: shown in that theme ("default" or a theme file's
//                              name; Theme.preview, saved nowhere); refused while shooting,
//                              whose pictures are always drawn in the built-in theme
//   H2S_MOCKUP_CHECK=1         checks the element and exits, without making a window:
//                              about.txt read, Mockup.qml loaded, the kit's list accepted;
//                              then MOCKUP-CHECKED <count> <states|scenes>, exit 0
//
// The states or scenes come from the element's about.txt, beside Mockup.qml (the format:
// tests/mockup-about.sh, whose rules the reader below keeps), handed to the kit as the
// mockup is created. Any error prints MOCKUP-ERROR <text> and exits with status 2.
//
// On screen, closing the window (by the user or the compositor) ends the process, status 0.
//
// The process is isolated from the session it runs in (Isolation: no module loads, no
// notification server, nothing sent), the configuration is read-only, the tree's files are
// not watched (a reload would start the states again), and animations are instant.
//
// Several mockups can run at once on one display: they share the config path, so a tool
// addresses one with `qs ipc --id <instance id>` (the id `qs list` shows, also in the
// "Saving logs to …/by-id/<id>/" line) or `--pid`, after asking each `ipc call mockup name`.
ShellRoot {
    id: root

    // First of all, before any singleton that reaches the session is made
    readonly property bool _isolated: { Isolation.active = true; return true; }
    readonly property bool _configReadOnly: { Config.readOnly = true; return true; }
    readonly property bool _noReload: { Quickshell.watchFiles = false; return true; }
    readonly property bool _instant: { Theme.instantAnimations = true; return true; }

    readonly property var _bases: ["mockups", "tests/fixtures/mockups"]
    property var _window: null

    // _readAbout(<kind>/<name> folder URL, word): { description, names, descriptions, error },
    // by tests/mockup-about.sh's rules
    function _readAbout(folder, word) {
        const other = word === "state" ? "scene" : "state";
        const path = decodeURIComponent(folder.toString().replace(/^file:\/\//, "")) + "/about.txt";
        const file = _aboutReader.createObject(root, { path: path });
        const text = file.text();
        const failed = file.failed;
        file.destroy();
        const answer = { description: "", names: [], descriptions: [], error: "" };
        if (failed || text === "") {
            answer.error = "about.txt is missing, empty or unreadable: every element declares its description and its " + word + "s there";
            return answer;
        }
        const errors = [];
        const seen = Object.create(null);
        let descriptions = 0, declared = 0;
        const lines = text.split("\n");
        if (lines.length > 0 && lines[lines.length - 1] === "")
            lines.pop();
        for (let i = 0; i < lines.length; i++) {
            const at = "about.txt line " + (i + 1) + ": ";
            const line = lines[i].replace(/\r$/, "");
            if (/^\s*(#.*)?$/.test(line))
                continue;
            const match = /^([a-z]+):(.*)$/.exec(line);
            if (!match) {
                errors.push(at + "not 'description:', '" + word + ":' or a comment");
                continue;
            }
            const rest = match[2].trim();
            if (match[1] === "description") {
                if (++descriptions > 1)
                    errors.push(at + "a second description");
                else if (rest === "")
                    errors.push(at + "the description is empty");
                else if (rest.length > 100)
                    errors.push(at + "the description is " + rest.length + " characters, over 100");
                else
                    answer.description = rest;
            } else if (match[1] === word) {
                declared++;
                const name = rest.split(/\s/)[0];
                const description = rest.slice(name.length).trim();
                if (name === "")
                    errors.push(at + "a " + word + " without a name");
                else if (!/^[A-Za-z0-9][A-Za-z0-9-]*$/.test(name))
                    errors.push(at + "the " + word + " name '" + name + "' is not letters, digits and '-' (starting with a letter or digit)");
                else if (seen[name])
                    errors.push(at + "the " + word + " name '" + name + "' is repeated (line " + seen[name] + ")");
                else if (description === "")
                    errors.push(at + "the " + word + " '" + name + "' has no description");
                else if (description.length > 100)
                    errors.push(at + "the " + word + " '" + name + "' has a description of " + description.length + " characters, over 100");
                else {
                    seen[name] = i + 1;
                    answer.names.push(name);
                    answer.descriptions.push(description);
                }
            } else if (match[1] === other) {
                errors.push(at + (word === "state" ? "'scene:' is a plan's; a component or a view declares 'state:' lines"
                                                   : "'state:' is a component's or a view's; a plan declares 'scene:' lines"));
            } else {
                errors.push(at + "'" + match[1] + ":' is not 'description:' or '" + word + ":'");
            }
        }
        if (descriptions === 0)
            errors.push("about.txt: no 'description:' line");
        if (declared === 0)
            errors.push("about.txt: no '" + word + ":' line");
        if (answer.names.length > 30)
            errors.push("about.txt: " + answer.names.length + " " + word + "s, over 30");
        answer.error = errors.join("; ");
        return answer;
    }

    // One read of an about.txt: the first load, blocking, so text() is the file's
    readonly property Component _aboutReader: Component {
        FileView {
            property bool failed: false
            blockLoading: true
            printErrors: false
            onLoadFailed: failed = true
        }
    }

    function _fail(text) {
        console.error("MOCKUP-ERROR " + text);
        _exit(2);
    }

    // Not from inside the load: Quickshell handles the engine's exit only once the
    // configuration has loaded
    function _exit(code) {
        Qt.callLater(() => Qt.exit(code));
    }

    // The gallery: on screen only, without a state or scene of its own
    function _startGallery(base, shooting) {
        const refused = shooting ? "H2S_MOCKUP_SHOT" : Quickshell.env("H2S_MOCKUP_CHECK") === "1" ? "H2S_MOCKUP_CHECK"
            : (Quickshell.env("H2S_MOCKUP_STATE") ?? "") !== "" ? "H2S_MOCKUP_STATE"
            : (Quickshell.env("H2S_MOCKUP_SCENE") ?? "") !== "" ? "H2S_MOCKUP_SCENE" : "";
        if (refused !== "") {
            _fail(refused + " is set for the gallery: it is only opened on a screen, every element in all its states");
            return;
        }
        if (!_bases.includes(base)) {
            _fail("H2S_MOCKUP_BASE is '" + base + "': " + _bases.join(" or "));
            return;
        }
        const component = Qt.createComponent(Qt.resolvedUrl("mockups/kit/Gallery.qml"), Component.PreferSynchronous);
        const gallery = component.status === Component.Ready
            ? component.createObject(root, { visible: false, baseUrl: Qt.resolvedUrl(base), readAbout: _readAbout }) : null;
        if (!gallery) {
            _fail("gallery: " + component.errorString().replace(/\s+/g, " ").trim());
            return;
        }
        _window = gallery;
        gallery.closed.connect(() => root._exit(0));
        const error = gallery.start();
        if (error !== "") {
            _fail("gallery: " + error);
            return;
        }
        gallery.visible = true;
    }

    Component.onCompleted: {
        const name = Quickshell.env("H2S_MOCKUP") ?? "";
        const base = Quickshell.env("H2S_MOCKUP_BASE") || "mockups";
        const shooting = Quickshell.env("H2S_MOCKUP_SHOT") === "1";
        const themeWanted = Quickshell.env("H2S_MOCKUP_THEME") ?? "";
        if (themeWanted !== "" && themeWanted !== "default" && shooting) {
            _fail("H2S_MOCKUP_THEME is '" + themeWanted + "' while shooting: shots and baselines are always drawn in the built-in theme (a theme is for a mockup open on a screen)");
            return;
        }
        if (themeWanted !== "" && !/^[A-Za-z0-9_. -]+$/.test(themeWanted)) {
            _fail("H2S_MOCKUP_THEME is '" + themeWanted + "': a theme's name (letters, digits, spaces, '.', '_' and '-')");
            return;
        }
        MockupTheme.shooting = shooting;
        // Set before the mockup is made, so that it is drawn in it from the first frame; the
        // name is checked against the theme files by the screen tool (they are listed later)
        if (themeWanted !== "" && !shooting)
            Theme.preview = themeWanted;
        if (name === "gallery") {
            _startGallery(base, shooting);
            return;
        }
        if (/^planning\//.test(name)) {
            _fail("H2S_MOCKUP is '" + name + "': mockups/planning/ is now mockups/plans/ (git mv mockups/planning/<name> mockups/plans/<name>), the name plans/<name>");
            return;
        }
        if (!/^(components|views|plans)\/[a-z0-9-]+$/.test(name)) {
            _fail("H2S_MOCKUP is '" + name + "': <kind>/<name>, the kind components, views or plans, the name lowercase letters, digits and '-', or gallery");
            return;
        }
        // A plan has scenes, a component or a view states: the variable of the other kind is
        // a mistake, never quietly ignored
        const plan = name.startsWith("plans/");
        const stateWanted = Quickshell.env("H2S_MOCKUP_STATE") ?? "";
        const sceneWanted = Quickshell.env("H2S_MOCKUP_SCENE") ?? "";
        if (plan && stateWanted !== "") {
            _fail("H2S_MOCKUP_STATE is set for the plan " + name + ": a plan has scenes (H2S_MOCKUP_SCENE)");
            return;
        }
        if (!plan && sceneWanted !== "") {
            _fail("H2S_MOCKUP_SCENE is set for " + name + ": a component or a view has states (H2S_MOCKUP_STATE)");
            return;
        }
        if (!_bases.includes(base)) {
            _fail("H2S_MOCKUP_BASE is '" + base + "': " + _bases.join(" or "));
            return;
        }
        const checking = Quickshell.env("H2S_MOCKUP_CHECK") === "1";
        if (checking && shooting) {
            _fail("H2S_MOCKUP_CHECK and H2S_MOCKUP_SHOT are both set: one of them");
            return;
        }
        const word = plan ? "scene" : "state";
        const about = _readAbout(Qt.resolvedUrl(base + "/" + name), word);
        if (about.error !== "") {
            _fail(name + ": " + about.error);
            return;
        }
        const component = Qt.createComponent(Qt.resolvedUrl(base + "/" + name + "/Mockup.qml"), Component.PreferSynchronous);
        if (component.status !== Component.Ready) {
            const error = component.errorString().replace(/\s+/g, " ").trim();
            // The list is about.txt's: the kit's read-only names, or its old name scenes
            const declared = /non-existent property "scenes?"/.test(error) || /onSceneChanged/.test(error)
                ? " (the kit's scenes and scene are now names and current, and the " + word + "s are declared in about.txt)"
                : /"names" is a read-only property/.test(error) || /read-only property.*names/.test(error)
                ? " (the " + word + "s are declared in about.txt, not in Mockup.qml)" : "";
            _fail(name + ": " + error + declared);
            return;
        }
        // Hidden until its root is known to be a MockupWindow: nothing else is ever shown
        const window = component.createObject(root, { visible: false, declaredNames: about.names, declaredDescriptions: about.descriptions });
        if (!window) {
            _fail(name + ": " + component.errorString().replace(/\s+/g, " ").trim());
            return;
        }
        if (!(window instanceof MockupWindow)) {
            window.destroy();
            _fail(name + ": the root of Mockup.qml is not a MockupWindow (qs.mockups.kit)");
            return;
        }
        _window = window;
        window.mockupName = name;
        if (checking) {
            const problem = window.check();
            window.destroy();
            if (problem !== "") {
                _fail(name + ": " + problem);
                return;
            }
            console.info("MOCKUP-CHECKED " + about.names.length + " " + word + "s");
            _exit(0);
            return;
        }
        window.shooting = shooting;
        const limit = Number(Quickshell.env("H2S_MOCKUP_SHOT_LIMIT_MS") || 60000);
        if (!(limit > 0)) {
            _fail("H2S_MOCKUP_SHOT_LIMIT_MS is '" + Quickshell.env("H2S_MOCKUP_SHOT_LIMIT_MS") + "': a number of milliseconds");
            return;
        }
        window.shotLimitMs = limit;
        window.finished.connect(() => {
            console.info("MOCKUP-DONE");
            root._exit(0);
        });
        window.failed.connect(text => _fail(name + ": " + text));
        // On screen, a closed window ends the process: none is left running without one
        window.closed.connect(() => root._exit(0));
        const error = window.start(shooting ? "" : plan ? sceneWanted : stateWanted);
        if (error !== "") {
            window.destroy();
            _fail(name + ": " + error);
            return;
        }
        window.visible = true;
    }
}
