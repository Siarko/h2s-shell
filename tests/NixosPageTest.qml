import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons
import qs.distributions.nixos
import qs.panels.settings

// Settings → System → NixOS (panels/settings/NixosSettings.qml) under clicks, on stand-in
// readings: each state — not connected, found (the one-time setup), the home-folder warning,
// connected — its facts one per line, reading when shown and on Look again, Select directory and
// Choose another… through the folder chooser, Use it; Create through the root step only on
// its click (a stand-in writer records it; a dismissed prompt is quiet, a refusal said), and
// Create of the user's own configuration's file by the real scripts/nixos-create.sh as the
// user in a scratch folder (never overwriting); Copy gives the exact line. The page's place in
// the settings window's registry: under System, listed only while the distribution is NixOS
// (the shell's Distribution answering arch, generic and nixos in turn: its own process).
//
// Stand-ins only: never pkexec, polkit, nix, /etc or the shell's settings. Opens a small
// window for a moment in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "NixosPage"
    asynchronous: true
    // Its window takes the keyboard, and it makes the shell's Distribution answer otherwise
    ownProcess: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-nixos-page-test-" + Date.now()
    property string _copied: ""
    property var _chooserCalls: []
    property var _chooserDone: null

    // The stand-in reading: what current() gives, set by the suite; each read() answers it
    property QtObject _configuration: QtObject {
        property int revision: 0
        property bool busy: false
        property var value: null
        property int reads: 0
        property var chosen: []
        property var acknowledged: []
        function current() {
            return value === null ? null : JSON.parse(JSON.stringify(value));
        }
        function read() {
            reads++;
            busy = true;
            Qt.callLater(() => {
                busy = false;
                revision++;
            });
        }
        function choose(folder, host) {
            chosen = chosen.concat([folder + "|" + host]);
        }
        function acknowledgeHome(real) {
            acknowledged = acknowledged.concat([real]);
        }
    }

    // The stand-in root step's writer: records each run asked, answers as `answer` says
    property QtObject _writer: QtObject {
        property bool busy: false
        property var runs: []
        // "created" | "dismissed" | "refused"
        property string answer: "created"
        function apply(value, handlers) {
            runs = runs.concat([{ op: value.op, folder: value.reading?.configuration?.folder ?? "" }]);
            const outcome = answer === "created" ? { ok: true, quiet: false, kind: "created", error: "" }
                : answer === "dismissed" ? { ok: false, quiet: true, kind: "", error: "" }
                : { ok: false, quiet: false, kind: "refused", error: NixosApplyRules.texts.owner };
            Qt.callLater(() => handlers.done(outcome));
            return { started: true, refusal: null };
        }
    }

    property var _creator: null
    property Component _creatorComponent: Component {
        NixosCreate {}
    }

    property var _window: FloatingWindow {
        title: "h2s-tests nixos page"
        visible: false
        implicitWidth: 900
        implicitHeight: 900
        color: Theme.popupBackground

        Item {
            id: area
            anchors.fill: parent
        }

        WindowDriver {
            id: driver
            name: "NixosPageDriver"
        }
    }

    property Component _pageComponent: Component {
        NixosSettings {
            configuration: suite._configuration
            creator: suite._creator
            copyText: text => suite._copied = text
            delayCapability: suite._delayCapability
            delayInForce: suite._delayInForce
            delayBusy: ""
            delayUndoable: suite._delayUndoable
            delayPicked: 10800
            readDelay: () => suite._delayReads++
            applyDelay: (request, flow) => suite._delayCalls = suite._delayCalls.concat(["apply " + JSON.stringify(request)])
            undoDelay: flow => suite._delayCalls = suite._delayCalls.concat(["undo"])
            chooseFolder: (start, done) => {
                suite._chooserCalls = suite._chooserCalls.concat([start]);
                suite._chooserDone = done;
            }
        }
    }
    property var _page: null
    // The hibernation delay's stand-ins: copied until a test says otherwise
    property var _delayCapability: ({ mode: "copy", trial: false, undo: false, inForce: true, anyway: false, reason: "", known: true })
    property var _delayInForce: null
    property bool _delayUndoable: false
    property int _delayReads: 0
    property var _delayCalls: []

    // ── Readings ──

    function _reading(more) {
        const folder = more?.folder ?? "/srv/nixos-config";
        const result = Object.assign({
            configuration: { found: true, folder, entry: "flake.nix", type: "flake" },
            real: folder, owner: "root", rootWrites: true, git: "present", gitKnowsFile: "tracked", host: "nixos",
            file: { path: folder + "/h2s-shell.json", state: "absent", sha256: "" },
            fileStatus: "notCreated", module: "present", published: "absent",
            generations: { count: 14, current: 14 }, state: "found", homeWarning: false
        }, more ?? {});
        delete result.folder;
        result.facts = NixosConfigRules.facts(result);
        return result;
    }

    // The page reads again; its answer is `value`
    function _show(value) {
        _configuration.value = value;
        const reads = _configuration.reads;
        _page.lookAgain();
        return _until(() => _configuration.reads > reads && !_configuration.busy && _page.reading?.state === value.state
                      && JSON.stringify(_page.reading) === JSON.stringify(value));
    }

    // ── Helpers ──

    function _until(condition, limitMs = 8000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = _find(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function _item(name) {
        return _find(_page, name);
    }

    function _visible(item) {
        for (let at = item; at; at = at.parent) {
            if (!at.visible)
                return false;
        }
        return item !== null;
    }

    function _shown(name) {
        return _visible(_item(name));
    }

    function _text(name) {
        const item = _item(name);
        return _visible(item) ? item.text : "(hidden)";
    }

    function _settle(item) {
        let last = "", same = 0;
        for (let waited = 0; waited < 3000 && same < 3; waited += 16) {
            const place = item.mapToItem(area, 0, 0);
            const now = place.x + "," + place.y + "," + item.width + "," + item.height;
            same = now === last ? same + 1 : 0;
            last = now;
            driver.wait(16);
        }
    }

    function _click(name) {
        const item = _item(name);
        if (!item || !_visible(item))
            return false;
        _settle(item);
        const inPage = item.mapToItem(_page.contentItem, 0, 0);
        _page.contentY = Math.max(0, Math.min(inPage.y - 200, _page.contentHeight - _page.height));
        _settle(item);
        driver.mouseClick(item, item.width / 2, item.height / 2);
        return true;
    }

    function _fileText(path) {
        let text = null;
        _exec(["sh", "-c", "if [ -f \"$1\" ]; then cat \"$1\"; else printf '(none)'; fi", "sh", path], (code, stdout) => text = stdout);
        _until(() => text !== null);
        return text;
    }

    // ── The run ──

    function runAsync() {
        const override = Distribution._reader.override;
        let window = null;
        try {
            _run();
            window = _registry();
        } finally {
            window?.destroy();
            Distribution._reader.override = override;
            _page?.destroy();
            _creator?.destroy();
            _window.visible = false;
            let removed = false;
            _exec(["rm", "-rf", "--", _scratch], () => removed = true);
            _until(() => removed);
        }
        finish();
    }

    function _run() {
        let ready = false;
        _exec(["mkdir", "-p", _scratch + "/home/nixos-config", _scratch + "/locked"], () => ready = true);
        assert(_until(() => ready), "the scratch folders made");
        _creator = _creatorComponent.createObject(suite, { writer: suite._writer });
        _configuration.value = _reading({ state: "notConnected" });

        _window.visible = true;
        assert(_until(() => _window.visible && driver.waitShown()), "the window shows");
        _page = _pageComponent.createObject(area, { objectName: "page" });
        assert(_page !== null, "the page built");
        assert(_until(() => _configuration.reads === 1 && _page.reading !== null), "… it reads when shown");

        // --- not connected ---
        assertEqual(_text("nixos:intro"), "The shell can keep its settings in your NixOS configuration and apply them by rebuilding NixOS. Turn that on here.",
                    "the intro");
        assertEqual(_text("nixos:status"), "Not connected", "not connected: the status");
        assertEqual(_text("nixos:caption"), "No NixOS configuration found that imports the shell's NixOS module. Built on another machine? Then keep copying the lines.",
                    "… the lines to copy stay");
        assertEqual([_shown("nixos:chooseFolder"), _shown("nixos:lookAgain"), _shown("nixos:change"), _shown("nixos:setup"), _shown("nixos:fact:Configuration")].join(" "),
                    "true true false false false", "… Choose folder… and Look again, no facts, no setup");
        const reads = _configuration.reads;
        assert(_click("nixos:lookAgain") && _until(() => _configuration.reads === reads + 1), "Look again reads again");

        // Choose folder…: the chooser, its answer chosen and read
        const chooserCalls = _chooserCalls.length;
        assert(_click("nixos:chooseFolder") && _until(() => _chooserCalls.length === chooserCalls + 1), "Choose folder… opens the chooser");
        const readsBefore = _configuration.reads;
        _chooserDone(FileChooserRules.result({ paths: ["/srv/other"] }));
        assert(_until(() => _configuration.reads === readsBefore + 1), "… a folder chosen: read again");
        assertEqual(_configuration.chosen[_configuration.chosen.length - 1], "/srv/other|", "… that folder, the host from the system");
        _chooserDone(FileChooserRules.result({ cancelled: true }));
        assertEqual(_configuration.chosen.length, 1, "… cancelled: nothing chosen");

        // --- found, root-owned ---
        assert(_show(_reading()), "found: shown");
        assertEqual(_text("nixos:status"), "Found, not connected yet: the shell's file is not in force.", "found: the status");
        assertEqual(["Configuration", "Type", "Git", "Host", "The shell's file", "File status"].map(name => _text("nixos:fact:" + name)).join(" | "),
                    "/srv/nixos-config | Flake | Yes | nixos | /srv/nixos-config/h2s-shell.json | Not created", "… the facts, one per line");
        assert(!_shown("nixos:fact:Generations") && !_shown("nixos:generations"), "… no Generations yet");
        assertEqual([_shown("nixos:change"), _shown("nixos:lookAgain"), _shown("nixos:chooseFolder"), _shown("nixos:home")].join(" "),
                    "true true false false", "… Select directory and Look again");
        assertEqual(_item("nixos:change").label, "Select directory", "… the folder's button: its label");
        assertEqual(_text("nixos:createStep") + " | " + _shown("nixos:create") + " " + _shown("nixos:createMark"),
                    "Create the shell's file, h2s-shell.json. | true true", "… step 1: Create, marked as asking the password");
        assertEqual(_text("nixos:line"), "{ programs.h2s-shell.settingsFile = ./h2s-shell.json; }", "… step 2: the line, a module for the flake's list");
        assertEqual(_text("nixos:lineCaption"), "In flake.nix, in your system's modules list. This page notices when it is in force.", "… where it goes");
        assert(!_shown("nixos:git"), "… git knows the file: no git line");
        assertEqual(_writer.runs.length, 0, "nothing asked the password: shown, read, read again");

        // Create: the root step, only on its click
        assert(_click("nixos:create") && _until(() => _writer.runs.length === 1), "Create: the root step asked");
        assertEqual(JSON.stringify(_writer.runs[0]), JSON.stringify({ op: "create", folder: "/srv/nixos-config" }), "… its create, for the folder shown");
        const readsCreated = _configuration.reads;
        assert(_until(() => _configuration.reads === readsCreated + 1 || _configuration.reads > readsCreated), "… created: read again");
        assertEqual(_text("nixos:createNote"), "(hidden)", "… nothing to say");
        _writer.answer = "dismissed";
        const readsDismissed = _configuration.reads;
        assert(_click("nixos:create") && _until(() => _writer.runs.length === 2), "Create again: asked");
        driver.wait(50);
        assertEqual(_text("nixos:createNote") + " " + (_configuration.reads === readsDismissed), "(hidden) true", "… dismissed: quiet, nothing read");
        _writer.answer = "refused";
        assert(_click("nixos:create") && _until(() => _text("nixos:createNote") === NixosApplyRules.texts.owner), "… refused: said");

        // Copy: the exact line
        assert(_click("nixos:copy") && _until(() => _copied !== ""), "Copy");
        assertEqual(_copied, "{ programs.h2s-shell.settingsFile = ./h2s-shell.json; }", "… gives the exact one-time line");
        assert(_show(_reading({ folder: "/etc/nixos", configuration: { found: true, folder: "/etc/nixos", entry: "configuration.nix", type: "classic" } })),
               "a classic configuration: shown");
        assertEqual(_text("nixos:line") + " | " + _text("nixos:lineCaption"),
                    "programs.h2s-shell.settingsFile = ./h2s-shell.json; | In configuration.nix, among its options. This page notices when it is in force.",
                    "… the line as an option of configuration.nix, beside the file");
        assert(_click("nixos:copy") && _until(() => _copied === "programs.h2s-shell.settingsFile = ./h2s-shell.json;"), "… Copy gives that line");
        assertEqual(_item("nixos:copy").label, "Copied", "… and says so");

        // --- the home folder's warning ---
        const home = _scratch + "/home/nixos-config";
        assert(_show(_reading({ folder: home, owner: "yours", rootWrites: false, homeWarning: true, gitKnowsFile: "untracked" })), "home folder: shown");
        assertEqual([_shown("nixos:home"), _shown("nixos:setup"), _shown("nixos:useIt"), _shown("nixos:chooseAnother")].join(" "), "true false true true",
                    "… the warning, Use it and Choose another…, the setup held back");
        const chooserHome = _chooserCalls.length;
        assert(_click("nixos:chooseAnother") && _until(() => _chooserCalls.length === chooserHome + 1), "Choose another… opens the chooser");
        assertEqual(_chooserCalls[_chooserCalls.length - 1], home, "… starting at the folder shown");
        const readsHome = _configuration.reads;
        assert(_click("nixos:useIt") && _until(() => _configuration.reads === readsHome + 1), "Use it: read again");
        assertEqual(_configuration.acknowledged.join(","), home, "… the warning taken for that folder's real path");

        // --- found, the user's own: written as the user ---
        assert(_show(_reading({ folder: home, owner: "yours", rootWrites: false, homeWarning: false, gitKnowsFile: "untracked" })), "the user's own: shown");
        assertEqual([_shown("nixos:create"), _shown("nixos:createMark"), _shown("nixos:git")].join(" "), "true false true",
                    "… Create without the mark, the git line");
        assertEqual(_text("nixos:git"), "In git: run git add h2s-shell.json once. The shell never commits.", "… its text");
        const runs = _writer.runs.length;
        const readsUser = _configuration.reads;
        assert(_click("nixos:create") && _until(() => _configuration.reads > readsUser), "Create: written, read again");
        assertEqual(_fileText(home + "/h2s-shell.json"), "{\"version\":1}\n", "… the file as the user, the shell's first content");
        assertEqual(_writer.runs.length, runs, "… no root step: no password");
        // The stand-in still says absent: a second Create finds it there (changed by hand since)
        // and changes nothing
        let edited = false;
        _exec(["sh", "-c", "printf '%s' '{\"version\":1,\"own\":true}' > \"$1\"", "sh", home + "/h2s-shell.json"], () => edited = true);
        assert(_until(() => edited), "the file changed by hand");
        assert(_click("nixos:create") && _until(() => _text("nixos:createNote") === "h2s-shell.json is already there."), "Create again: there already");
        assertEqual(_fileText(home + "/h2s-shell.json"), "{\"version\":1,\"own\":true}", "… not overwritten");
        // The name taken by a folder, a link to a folder, a link that leads nowhere: nothing
        // written, nothing written into them
        let taken = false;
        _exec(["sh", "-c", "set -e; cd \"$1\"; mkdir -p dir/h2s-shell.json tofolder elsewhere dangling; ln -s ../elsewhere tofolder/h2s-shell.json; ln -s ../nowhere dangling/h2s-shell.json", "sh", _scratch],
              () => taken = true);
        assert(_until(() => taken), "names taken");
        for (const name of ["dir", "tofolder", "dangling"]) {
            assert(_show(_reading({ folder: _scratch + "/" + name, owner: "yours", rootWrites: false })), name + ": shown");
            assert(_click("nixos:create") && _until(() => _text("nixos:createNote") === "h2s-shell.json is already there."), "… Create: there already (" + name + ")");
        }
        let left = null;
        _exec(["sh", "-c", "cd \"$1\"; echo $(ls -A dir/h2s-shell.json | wc -l) $(ls -A elsewhere | wc -l) $(ls -A dir tofolder dangling | grep -c '^[.]h2s') $([ -e nowhere ] && echo made || echo none)", "sh", _scratch],
              (code, stdout) => left = stdout.trim());
        assert(_until(() => left !== null), "… looked at");
        assertEqual(left, "0 0 0 none", "… the folders stay empty, nothing made where the link leads, no temporary file left");
        // A folder the user cannot write
        let locked = false;
        _exec(["chmod", "555", _scratch + "/locked"], () => locked = true);
        assert(_until(() => locked), "a folder not writable");
        assert(_show(_reading({ folder: _scratch + "/locked", owner: "yours", rootWrites: false })), "… shown");
        assert(_click("nixos:create") && _until(() => _text("nixos:createNote") === "h2s-shell.json could not be written: nothing changed."),
               "… Create there: said it could not be written");
        _exec(["chmod", "755", _scratch + "/locked"], () => {});

        // --- connected ---
        assert(_show(_reading({ state: "connected", published: "present", fileStatus: "inForce", file: { path: "/srv/nixos-config/h2s-shell.json", state: "present", sha256: "a" } })),
               "connected: shown");
        assertEqual(_text("nixos:status"), "Connected", "connected: the status");
        assertEqual(_text("nixos:fact:File status") + " | " + _text("nixos:fact:Generations"), "In force | 14", "… File status and Generations");
        assertEqual(_text("nixos:generations"), "Each Apply adds a generation. The shell never deletes them.", "… the generations line");
        assertEqual([_shown("nixos:change"), _shown("nixos:lookAgain"), _shown("nixos:setup"), _shown("nixos:caption")].join(" "), "true false false false",
                    "… Select directory, no Look again, no setup");
        assertEqual(_writer.runs.length, 3, "only the three Create clicks asked the root step");

        // The hibernation delay, kept in the shell's file
        assert(!_shown("nixos:delay") && !_shown("nixos:delayTitle"), "the delay copied (not connected for it): no row");
        assert(_delayReads > 0, "… what is in force read with the page");
        _delayCapability = { mode: "declare", trial: false, undo: true, inForce: true, anyway: false, reason: "", known: true };
        _delayInForce = { state: "set", value: 600, from: "/srv/nixos-config", elsewhere: "/srv/nixos-config", file: null, afterOwn: true, shadowed: null };
        assert(_until(() => _shown("nixos:delay")), "declared: the row shows");
        assertEqual(_text("nixos:delayTitle"), "Hibernate after", "… its title");
        assertEqual(_text("nixos:delayLine"), "In force: 10 min.", "the configuration's own value: only the value said");
        assertEqual([_shown("nixos:delayControlled"), _shown("nixos:delayApply"), _item("nixos:delayApply").available, _shown("nixos:delayUndo")].join(" "),
                    "true true false false", "… the system's mark beside a disabled Apply, no Undo");
        assertEqual(_item("nixos:delayControlled").tip, "This setting is controlled by your system configuration", "… the mark's tooltip");
        _delayInForce = { state: "set", value: 3600, from: "/srv/nixos-config/h2s-shell.json", elsewhere: "", file: null, afterOwn: false, shadowed: null };
        assert(_until(() => _shown("nixos:delayApply") && _item("nixos:delayApply").available), "the shell's own in force: Apply");
        assert(!_shown("nixos:delayControlled"), "… no system's mark");
        assertEqual(_text("nixos:delayLine"), "Picked 3 h; the system now hibernates after 1 h. Apply rebuilds NixOS.", "… what is picked and in force");
        assert(_click("nixos:delayApply") && _until(() => _delayCalls.length === 1), "Apply clicked");
        assertEqual(_delayCalls[0], "apply " + JSON.stringify({ seconds: 10800, current: null, replace: false }), "… the picked time applied");
        _delayInForce = { state: "set", value: 10800, from: "/srv/nixos-config/h2s-shell.json", elsewhere: "", file: null, afterOwn: false, shadowed: null };
        _delayUndoable = true;
        assert(_until(() => _shown("nixos:delayUndo")), "applied: Undo");
        assertEqual(_shown("nixos:delayApply") + " | " + _text("nixos:delayLine"), "false | Undo puts back the shell's previous value and rebuilds NixOS.",
                    "… no Apply for the time in force");
        assert(_click("nixos:delayUndo") && _until(() => _delayCalls.length === 2 && _delayCalls[1] === "undo"), "Undo clicked");
        _delayUndoable = false;
        _delayInForce = null;
        assert(_until(() => !_shown("nixos:delayApply") && _text("nixos:delayLine") === "Picked 3 h; the system's delay could not be read. What NixOS has in force could not be read."),
               "not read: no Apply, said");
        _delayCapability = { mode: "copy", trial: false, undo: false, inForce: true, anyway: false, reason: "", known: true };

        // Shown again, with Create offered: read again, nothing asked
        assert(_show(_reading()), "found again: shown");
        const readsShown = _configuration.reads;
        const runsShown = _writer.runs.length;
        _window.visible = false;
        _window.visible = true;
        assert(_until(() => _configuration.reads > readsShown && !_configuration.busy), "the window shown again: read again");
        driver.wait(50);
        assertEqual(_writer.runs.length, runsShown, "… and the root step not asked: only a click asks");
    }

    // The registry: under System, listed only on NixOS
    function _registry() {
        const component = Qt.createComponent(Qt.resolvedUrl("../panels/SettingsWindow.qml"), Component.PreferSynchronous);
        const window = component.status === Component.Ready ? component.createObject(suite, { visible: false }) : null;
        assert(window !== null, "the settings window can be made (" + component.errorString() + ")");
        if (!window)
            return null;
        const ids = window.allCorePages.map(page => page.id);
        const entry = window.allCorePages.find(page => page.id === "nixos") ?? null;
        assertEqual(entry ? entry.label + " " + entry.tab : "(none)", "NixOS system", "the page: NixOS, under System");
        assertEqual(ids.indexOf("nixos") > ids.indexOf("network_vpn") && ids.indexOf("nixos") < ids.indexOf("modules"), true,
                    "… after Network, before Modules");
        window.selectedPage = "authentication";
        const rowOf = pageId => {
            const walk = item => {
                if (!item)
                    return null;
                if (item.page !== undefined && item.page?.id === pageId && item.row !== undefined)
                    return item;
                for (const child of item.children) {
                    const found = walk(child);
                    if (found)
                        return found;
                }
                return null;
            };
            return walk(window.contentItem);
        };
        const answer = id => {
            Distribution._reader.override = id;
            return _until(() => Distribution.detection.ready && Distribution.detection.id === id);
        };
        for (const id of ["arch", "generic"]) {
            assert(answer(id), "the distribution answers " + id);
            assert(rowOf("authentication")?.visible === true, "… the System list shows (" + id + ")");
            assertEqual([rowOf("nixos") === null, window.pages.some(page => page.id === "nixos"), Shell.settingsPageIds.includes("nixos")].join(" "),
                        "true false false", "… the page not listed on " + id + ", not among the pages IPC openPage and Shell.openSettings may name");
            // Asked for by id anyway (what Shell.openSettings and IPC openPage set)
            window.selectedPage = "nixos";
            assertEqual(window.selectedPage + " " + window._currentPage.id, "authentication authentication", "… asked for by id: System's first page instead");
            window.openAt("nixos", "");
            assertEqual(window.selectedPage, "authentication", "… also through openAt");
        }
        assertEqual(Nixos.configuration.revision + " " + Nixos.configuration.busy, "0 false", "off NixOS nothing read the configuration");
        assertEqual((window.nixosRebuild.rebuild === null) + " " + window.rebuildDrawer.open, "true false", "… and the rebuild not reached: no run, no panel");
        assert(answer("nixos"), "the distribution answers nixos");
        assertEqual([rowOf("nixos")?.visible, window.pages.some(page => page.id === "nixos"), Shell.settingsPageIds.includes("nixos")].join(" "),
                    "true true true", "… the page listed on NixOS");
        window.selectedPage = "nixos";
        assertEqual(window.selectedPage + " " + window._currentPage.id, "nixos nixos", "… and opened by id");
        // The window's one rebuild panel: the run's, opened by its notification's action
        assertEqual((window.nixosRebuild.rebuild === Nixos.rebuild) + " " + window.rebuildDrawer.open, "true false", "… the rebuild reached, its panel closed");
        Nixos.rebuild.opened();
        assert(_until(() => window.rebuildDrawer.open && window.rebuildDrawer.objectName === "nixosRebuildDrawer"), "… the run's open: the window's panel opens");
        assertEqual(window.rebuildDrawer.title, "Applying: rebuilding NixOS", "… titled for the run");
        window.nixosRebuild.panelRequested("closeButton");
        assertEqual(window.rebuildDrawer.open + " " + Nixos.rebuild.phase, "false idle", "… closed again, the run untouched");
        // The window is hidden: the page is built but not shown, so it reads nothing
        assert(answer("arch"), "the distribution answers arch while the page is open");
        assertEqual(window.selectedPage + " " + window._currentPage.id, "authentication authentication", "… the page leaves: System's first page");
        assertEqual(Nixos.configuration.revision + " " + Nixos.configuration.busy, "0 false", "… nothing read the configuration");
        return window;
    }

    function _exec(command, done) {
        const process = _process.createObject(suite, { command: command });
        process.finished.connect((code, stdout, stderr) => done?.(code, stdout, stderr));
        process.running = true;
    }

    property Component _process: Component {
        Process {
            id: _run
            signal finished(int code, string stdout, string stderr)
            property bool _exited: false
            property bool _finished: false
            property bool _errorFinished: false
            property int _code: -1
            property string _stdout: ""
            property string _stderr: ""
            function _over() {
                if (!(_exited && _finished && _errorFinished))
                    return;
                _run.finished(_code, _stdout, _stderr);
                _run.destroy();
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    _run._stdout = text;
                    _run._finished = true;
                    _run._over();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    _run._stderr = text;
                    _run._errorFinished = true;
                    _run._over();
                }
            }
            onExited: code => {
                _run._code = code;
                _run._exited = true;
                _run._over();
            }
        }
    }
}
