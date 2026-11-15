import QtQuick
import qs.api
import qs.singletons

// The module system's rules (singletons/ModuleRules.qml): the manifest, API compatibility,
// namespaces, the import check, search-path precedence, the state model, merging — on
// realistic and on hostile manifests. Nothing here may throw.
TestCase {
    suiteName: "ModuleRules"

    function _manifest(fields) {
        return JSON.stringify(Object.assign({ id: "tailscale", name: "Tailscale", version: "0.1.0", api: "1.0" }, fields ?? {}));
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }

    function run() {
        const rules = ModuleRules;

        // --- the API version ---
        assertEqual(Api.version, "1.0", "the module API is 1.0 (api/Api.qml)");
        assert(rules.parseApi(Api.version) !== null, "the shell's API version is major.minor");
        assert(rules.apiCompatibility("1.0", "1.0").compatible, "same version: compatible");
        assert(rules.apiCompatibility("1.0", "1.3").compatible, "an older minor on a newer shell: compatible");
        assert(!rules.apiCompatibility("1.4", "1.3").compatible, "a newer minor than the shell's: not");
        assert(_has([rules.apiCompatibility("1.4", "1.3").reason], "newer shell"), "… and it says a newer shell is needed");
        assert(!rules.apiCompatibility("2.0", "1.9").compatible, "another major (newer): not");
        assert(!rules.apiCompatibility("0.9", "1.0").compatible, "another major (older): not");
        assert(_has([rules.apiCompatibility("0.9", "1.0").reason], "needs updating"), "… the module needs updating");
        for (const bad of ["1", "1.0.0", "v1.0", " 1.0", "1.0 ", "01.0", "1.-1", "", null, undefined, 1.0, {}, [], "1.0\n"])
            assert(!rules.apiCompatibility(bad, "1.0").compatible, "not major.minor: incompatible — " + JSON.stringify(bad));
        assert(rules.parseApi("10.25").major === 10 && rules.parseApi("10.25").minor === 25, "two-digit parts");

        // --- a realistic manifest ---
        const tailscale = rules.parseManifest(JSON.stringify({
            id: "tailscale", name: "Tailscale", version: "0.3.0-beta.1", api: "1.0",
            description: "Tailscale among the VPNs", main: "Main.qml",
            widgets: [{ type: "tailscale", name: "Tailscale", widget: "TailscaleWidget.qml",
                        popup: "tailscale", popupPanel: "TailscalePanel.qml", settings: "settings/WidgetSettings.qml" }],
            settingsPages: [{ id: "tailscale", label: "Tailscale", component: "TailscaleSettings.qml", tab: "system", parent: "network" }],
            settings: [
                { key: "mod.tailscale.showIp", label: "Show the address", type: "bool", default: true },
                { key: "mod.tailscale.poll", label: "Refresh", type: "interval", default: 5000, min: 0, max: 60000 },
                { key: "mod.tailscale.exitNodeMode", label: "Exit node", type: "enum", default: "auto",
                  options: [{ value: "auto", label: "Suggested" }, { value: "none", label: "None" }] },
                { key: "mod.tailscale.hidden", label: "Hidden devices", type: "stringList", default: [] }
            ],
            facts: [{ fact: "tailscale.connected", label: "Tailscale connected", type: "bool" },
                    { fact: "tailscale.exitNode", label: "Exit node", type: "enum", options: ["none", "mullvad"] }],
            slots: [{ slot: "network.vpn.row", component: "ExitNodeRow.qml" }],
            requires: { programs: ["tailscale"] },
            setupHints: ["Enable services.tailscale in your NixOS configuration"],
            tests: ["tests/TailscaleRulesTest.qml"]
        }));
        assert(tailscale.valid, "a realistic manifest is valid");
        assertEqual(tailscale.errors.length, 0, "… without errors: " + tailscale.errors.join("; "));
        assertEqual(tailscale.warnings.length, 0, "… without warnings");
        assertEqual(tailscale.id + " " + tailscale.version + " " + tailscale.api + " " + tailscale.main,
                    "tailscale 0.3.0-beta.1 1.0 Main.qml", "the required fields and main");
        assertEqual(tailscale.widgets.length, 1, "its widget");
        assertEqual(tailscale.widgets[0].popupPanel, "TailscalePanel.qml", "… with its popup panel");
        assertEqual(tailscale.widgets[0].multiple, false, "… multiple defaults to false");
        assertEqual(tailscale.settingsPages[0].parent, "network", "its settings page, under the network group");
        assertEqual(tailscale.settings.length, 4, "its four settings");
        assertEqual(tailscale.settings[0].group, "mod.tailscale", "a setting's group defaults to mod.<id>");
        assertEqual(tailscale.settings[2].options.length, 2, "an enum's options kept");
        assertEqual(tailscale.facts.length, 2, "its facts");
        assertEqual(tailscale.slots[0].slot, "network.vpn.row", "its slot contribution");
        assertEqual(JSON.stringify(tailscale.programs), "[\"tailscale\"]", "the programs it requires");
        assertEqual(tailscale.setupHints.length, 1, "its setup hint");
        assertEqual(tailscale.tests[0], "tests/TailscaleRulesTest.qml", "its tests");
        assertEqual(JSON.stringify(rules.manifestFiles(tailscale)),
                    JSON.stringify(["Main.qml", "TailscaleWidget.qml", "TailscalePanel.qml", "settings/WidgetSettings.qml",
                                    "TailscaleSettings.qml", "ExitNodeRow.qml"]),
                    "the files the import check reads: main and every component named, once");

        // A minimal one: no main, nothing else
        const minimal = rules.parseManifest(_manifest());
        assert(minimal.valid && minimal.main === "" && minimal.widgets.length === 0, "only the required fields: valid, no main");

        // --- required fields ---
        for (const field of ["id", "name", "version", "api"]) {
            const object = { id: "x", name: "X", version: "1", api: "1.0" };
            delete object[field];
            const result = rules.parseManifest(JSON.stringify(object));
            assert(!result.valid && _has(result.errors, "missing required field \"" + field + "\""), "missing " + field + ": invalid, said");
        }
        const wrongTypes = rules.parseManifest(JSON.stringify({ id: 7, name: [], version: 3, api: 1.0, main: {} }));
        assert(!wrongTypes.valid, "every required field of the wrong type: invalid");
        assertEqual(wrongTypes.errors.length, 5, "… one error each (id, name, version, api, main)");

        // --- ids ---
        for (const good of ["tailscale", "a", "my-module", "dictation2", "x_y"])
            assert(rules.validId(good) && rules.parseManifest(_manifest({ id: good })).id === good, "a valid id: " + good);
        for (const bad of ["Tailscale", "1password", "-x", "my.module", "my module", "", "a".repeat(33), "ä", "x/y",
                           "__proto__", "constructor", "prototype", "hasOwnProperty", "toString"]) {
            const result = rules.parseManifest(_manifest({ id: bad }));
            assert(!result.valid && result.id === "", "not a usable id: " + JSON.stringify(bad));
        }
        for (const reserved of ["lockscreen", "battery", "power", "network", "mod", "core", "api", "qs", "settings"])
            assert(_has(rules.parseManifest(_manifest({ id: reserved })).errors, "reserved"), "reserved: " + reserved);
        // Every core namespace a module could collide with is reserved: the first part of every
        // core setting and fact
        const corePrefixes = [];
        for (const entry of SettingsSchema.entries ?? [])
            corePrefixes.push(String(entry.key).split(".")[0]);
        for (const type of ProfileRules.factTypes)
            corePrefixes.push(type.fact.split(".")[0]);
        const unreserved = corePrefixes.filter((prefix, index) => corePrefixes.indexOf(prefix) === index
                                               && !rules.reservedIds.includes(prefix.toLowerCase()));
        assert(corePrefixes.length > 10, "the core's settings and facts were found (" + corePrefixes.length + ")");
        assertEqual(unreserved.join(", "), "", "every core setting and fact prefix is a reserved id");

        // --- versions ---
        for (const good of ["1.0.0", "0.3.0-beta.1", "2024.11.15", "1", "1.0+git.abc"])
            assert(rules.parseManifest(_manifest({ version: good })).valid, "a version: " + good);
        for (const bad of ["", " 1.0", "1.0 beta", "-1", "x".repeat(65), "1.0\n"])
            assert(!rules.parseManifest(_manifest({ version: bad })).valid, "not a version: " + JSON.stringify(bad));

        // --- hostile input: nothing throws ---
        for (const text of [null, undefined, 42, "", "null", "[]", "42", "\"text\"", "true", "{", "{}}", "{\"id\":",
                            "\u0000", "[{\"id\":\"x\"}]"]) {
            let result = null;
            try {
                result = rules.parseManifest(text);
            } catch (error) {
                fail("parseManifest threw on " + JSON.stringify(text) + ": " + error);
                continue;
            }
            assert(!result.valid && result.errors.length > 0, "not a manifest, said so: " + JSON.stringify(text));
        }
        assert(_has(rules.parseManifest("{ not json").errors, "not valid JSON"), "not JSON: said so");
        assert(_has(rules.parseManifest("[1]").errors, "not a JSON object"), "a JSON array: not an object");
        const huge = "{\"id\":\"x\",\"pad\":\"" + "a".repeat(rules.maxManifestBytes) + "\"}";
        assert(_has(rules.parseManifest(huge).errors, "too large"), "a huge module.json is refused before parsing");
        // Prototype keys as fields: kept as data, never as the prototype
        const proto = rules.parseManifest("{\"id\":\"x\",\"name\":\"X\",\"version\":\"1\",\"api\":\"1.0\","
                                          + "\"__proto__\":{\"valid\":true,\"main\":\"Evil.qml\"},\"constructor\":1}");
        assert(proto.valid, "a manifest with __proto__ and constructor fields is still read");
        assertEqual(proto.main, "", "… __proto__ does not inject a main");
        assert(_has(proto.warnings, "__proto__") && _has(proto.warnings, "constructor"), "… both reported as unknown fields");
        assertEqual(({}).valid, undefined, "… and Object.prototype is untouched");
        const protoEntries = rules.parseManifest(_manifest({ settings: [JSON.parse("{\"__proto__\":{\"key\":\"mod.tailscale.x\"},\"label\":\"L\",\"type\":\"bool\",\"default\":true}")] }));
        assertEqual(protoEntries.settings.length, 0, "a setting whose key comes only from __proto__ is dropped");
        // Wrong types everywhere: each list not a list, each entry not an object
        const everythingWrong = rules.parseManifest(_manifest({
            description: 5, main: "../escape.qml", widgets: "x", settingsPages: {}, settings: 3, facts: null,
            slots: [1, "a", null, []], requires: [], setupHints: [{}, 5, ""], tests: [7, "/abs.qml", "x.js"]
        }));
        assert(!everythingWrong.valid, "a main outside the directory: invalid (the module fails)");
        assert(_has(everythingWrong.errors, "main"), "… said so");
        assert(_has(everythingWrong.errors, "widgets: not a list") && _has(everythingWrong.errors, "settings: not a list")
               && _has(everythingWrong.errors, "settingsPages: not a list") && _has(everythingWrong.errors, "facts: not a list"),
               "lists that are not lists: one error each");
        assert(_has(everythingWrong.errors, "slots[3]: not an object"), "entries that are not objects: dropped, said");
        assert(_has(everythingWrong.errors, "requires: not an object"), "requires not an object: said");
        assertEqual(everythingWrong.setupHints.length, 0, "setup hints that are not texts: dropped");
        assertEqual(everythingWrong.tests.length, 0, "tests that are not .qml files inside: dropped");
        assert(_has(everythingWrong.warnings, "description"), "a description that is not a text: a warning");
        const tooMany = rules.parseManifest(_manifest({ facts: Array.from({ length: 300 }, (_, i) => ({ fact: "tailscale.f" + i, label: "F", type: "bool" })) }));
        assertEqual(tooMany.facts.length, rules.maxEntries, "at most maxEntries entries of a list are read");
        assert(_has(tooMany.errors, "only the first"), "… said so");

        // --- unknown fields: kept, warned ---
        const newer = rules.parseManifest(_manifest({ permissions: ["network"], icon: "vpn" }));
        assert(newer.valid, "a manifest with fields this shell does not know still loads");
        assertEqual(JSON.stringify(newer.unknownFields), "[\"permissions\",\"icon\"]", "… their names listed");
        assertEqual(JSON.stringify(newer.raw.permissions), "[\"network\"]", "… their values kept in raw");
        assertEqual(newer.warnings.length, 2, "… one warning each");
        const unknownInEntry = rules.parseManifest(_manifest({ facts: [{ fact: "tailscale.up", label: "Up", type: "bool", color: "red" }] }));
        assert(unknownInEntry.facts.length === 1 && _has(unknownInEntry.warnings, "facts[0]: unknown field \"color\""),
               "an unknown field in an entry: the entry kept, a warning");

        // --- paths ---
        for (const good of ["Main.qml", "sub/Panel.qml", "a-b_c.qml", "x/y/z.qml"])
            assertEqual(rules.pathProblem(good), "", "a module file: " + good);
        for (const bad of ["/etc/x.qml", "../x.qml", "a/../../x.qml", "./x.qml", "a//b.qml", "x.js", "x", "",
                           "a b.qml", "x.qml\u0000", "file:///x.qml", "C:\\x.qml", "~/x.qml", null, 3, "a".repeat(301) + ".qml"])
            assert(rules.pathProblem(bad) !== "", "not a module file: " + JSON.stringify(bad));
        assertEqual(rules.canonicalPath("/a//b/./c/../d/"), "/a/b/d", "canonical: repeated /, ., .., trailing / gone");
        assertEqual(rules.canonicalPath("/../a"), "/a", "canonical: above the root stays at the root");
        for (const bad of ["a/b", "", "./a", null, 5, "~/x"])
            assertEqual(rules.canonicalPath(bad), "", "not absolute: " + JSON.stringify(bad));
        assertEqual(rules.fileUrl("/m/x/", "a/B.qml"), "file:///m/x/a/B.qml", "a file's URL");
        assertEqual(rules.fileUrl("/m//x/.", "B.qml"), rules.fileUrl("/m/x", "B.qml"), "one file, one URL, however the directory is spelled");
        assertEqual(rules.fileUrl("/m/a#b?c%d", "B.qml"), "file:///m/a%23b%3Fc%25d/B.qml", "what a URL cannot hold is escaped");

        // --- the module list (H2S_SHELL_MODULES) ---
        const list = rules.moduleDirectories("/a/x::/b/y/:relative:/a//x:/c/../b/y:/");
        assertEqual(JSON.stringify(list.directories), "[\"/a/x\",\"/b/y\"]", "canonical, in order, each once");
        assertEqual(JSON.stringify(list.ignored), "[\"relative\",\"/\"]", "what is not a module directory is reported");
        assertEqual(rules.moduleDirectories(["/a", 3, null, "/a/"]).directories.length, 1, "a list works as well; junk ignored");
        assertEqual(rules.moduleDirectories(undefined).directories.length, 0, "nothing: no directories");

        // --- namespaces ---
        assert(rules.isOwnSettingKey("tailscale", "mod.tailscale.showIp"), "mod.<id>.<name>: its own setting");
        assert(rules.isOwnSettingKey("tailscale", "mod.tailscale.exit.node"), "… nested");
        for (const bad of ["tailscale.showIp", "mod.tailscale", "mod.tailscale.", "mod.other.x", "lockscreen.enabled",
                           "mod.tailscalex.y", "mod.tailscale..x", "mod.tailscale.a-b", "mod.tailscale.__proto__.x.", 5])
            assert(!rules.isOwnSettingKey("tailscale", bad), "not its setting: " + JSON.stringify(bad));
        assert(rules.isOwnFact("tailscale", "tailscale.connected"), "<id>.<name>: its own fact");
        for (const bad of ["tailscale", "battery.percent", "tailscalex.y", "mod.tailscale.x", "tailscale.", ""])
            assert(!rules.isOwnFact("tailscale", bad), "not its fact: " + JSON.stringify(bad));
        assert(rules.isOwnName("tailscale", "tailscale") && rules.isOwnName("tailscale", "tailscale.devices"),
               "a widget type, popup or page: <id> or <id>.<name>");
        assert(!rules.isOwnName("tailscale", "clock") && !rules.isOwnName("tailscale", "tailscale2"), "… not another's");

        // A violation drops that entry with an error; the module still loads
        const collisions = rules.parseManifest(_manifest({
            widgets: [{ type: "clock", name: "Clock", widget: "W.qml" }, { type: "tailscale", name: "T", widget: "W.qml" },
                      { type: "tailscale.x", name: "P", widget: "W.qml", popup: "music" }],
            settings: [{ key: "lockscreen.enabled", label: "L", type: "bool", default: true },
                       { key: "mod.good.greeting", label: "G", type: "string", default: "" },
                       { key: "mod.tailscale.ok", label: "Ok", type: "bool", default: false },
                       { key: "mod.tailscale.ok", label: "Again", type: "bool", default: true }],
            facts: [{ fact: "battery.percent", label: "B", type: "percent" }, { fact: "tailscale.up", label: "U", type: "bool" }],
            settingsPages: [{ id: "lockscreen", label: "L", component: "P.qml" }, { id: "tailscale", label: "T", component: "P.qml" }]
        }));
        assert(collisions.valid, "keys outside the namespace do not fail the module");
        assertEqual(collisions.widgets.map(widget => widget.type).join(","), "tailscale", "only its own widget type kept (clock dropped, a popup of another's dropped)");
        assertEqual(collisions.settings.map(setting => setting.key).join(","), "mod.tailscale.ok", "only its own setting kept, once");
        assert(_has(collisions.errors, "lockscreen.enabled") && _has(collisions.errors, "mod.good.greeting"), "… the core's key and another module's: errors");
        assert(_has(collisions.errors, "listed twice"), "… a key listed twice: the second dropped, said");
        assertEqual(collisions.facts.map(fact => fact.fact).join(","), "tailscale.up", "only its own fact kept");
        assertEqual(collisions.settingsPages.map(page => page.id).join(","), "tailscale", "only its own settings page kept");

        // Settings: types and defaults
        const typed = rules.parseManifest(_manifest({ settings: [
            { key: "mod.tailscale.a", label: "A", type: "bool", default: "yes" },
            { key: "mod.tailscale.b", label: "B", type: "number", default: "5" },
            { key: "mod.tailscale.c", label: "C", type: "slider", default: 50, min: 0, max: 10 },
            { key: "mod.tailscale.d", label: "D", type: "enum", default: "x", options: [{ value: "y", label: "Y" }] },
            { key: "mod.tailscale.e", label: "E", type: "enum", default: "x" },
            { key: "mod.tailscale.f", label: "F", type: "stringList", default: [1] },
            { key: "mod.tailscale.g", label: "G", type: "barSection", default: [] },
            { key: "mod.tailscale.h", label: "H", type: "string" },
            { key: "mod.tailscale.i", type: "bool", default: true },
            { key: "mod.tailscale.j", label: "J", type: "number", default: NaN },
            { key: "mod.tailscale.k", label: "K", type: "string", default: "", group: "lockscreen" },
            { key: "mod.tailscale.ok", label: "Ok", type: "interval", default: 0, min: 0, global: true }
        ] }));
        assertEqual(typed.settings.map(setting => setting.key).join(","), "mod.tailscale.ok", "every malformed setting dropped, the good one kept");
        assertEqual(typed.errors.length, 11, "… one error each");
        assert(typed.settings[0].global === true, "global kept");
        assert(_has(typed.errors, "core editor") || _has(typed.errors, "type \"barSection\""), "a core-only type is refused");

        // Facts
        const facts = rules.parseManifest(_manifest({ facts: [
            { fact: "tailscale.a", label: "A", type: "color" }, { fact: "tailscale.b", label: "B", type: "enum" },
            { fact: "tailscale.c", type: "bool" }, { fact: "tailscale.d", label: "D", type: "percent" }] }));
        assertEqual(facts.facts.map(fact => fact.fact).join(","), "tailscale.d", "malformed facts dropped");

        // Widgets and pages
        const widgets = rules.parseManifest(_manifest({
            widgets: [{ type: "tailscale", name: "T" }, { type: "tailscale.b", name: "B", widget: "/abs.qml" },
                      { type: "tailscale.c", name: "C", widget: "W.qml", popupPanel: "P.qml" },
                      { type: "tailscale.d", name: "D", widget: "W.qml", multiple: "yes" },
                      { type: "tailscale.e", name: "E", widget: "W.qml", multiple: true }],
            settingsPages: [{ id: "tailscale", label: "T", component: "P.qml", tab: "secret" },
                            { id: "tailscale.b", label: "B", component: "P.qml", parent: "Net Work" },
                            { id: "tailscale.c", label: "C", component: "P.qml" }],
            slots: [{ slot: "Network", component: "S.qml" }, { slot: "network.vpn.row", component: "../S.qml" },
                    { slot: "network.vpn.card", component: "Card.qml" }] }));
        assertEqual(widgets.widgets.map(widget => widget.type).join(","), "tailscale.e", "malformed widgets dropped");
        assertEqual(widgets.settingsPages.map(page => page.id + ":" + page.tab).join(","), "tailscale.c:behaviour",
                    "malformed pages dropped; tab defaults to behaviour");
        assertEqual(widgets.slots.map(slot => slot.slot).join(","), "network.vpn.card", "malformed slot contributions dropped");

        // Requires
        const requires = rules.parseManifest(_manifest({ requires: { programs: ["tailscale", "tailscale", "../bin/x", "a b", 5, "jq"],
                                                                      services: ["tailscaled"] } }));
        assertEqual(JSON.stringify(requires.programs), "[\"tailscale\",\"jq\"]", "program names, each once; paths and junk dropped");
        assert(_has(requires.warnings, "requires: unknown field \"services\""), "an unknown requirement: a warning");

        // --- qmldir ---
        assertEqual(JSON.stringify(rules.qmldirFiles("module foo\nsingleton Ts 1.0 Ts.qml\nHelper 1.0 Helper.qml\n"
                                                     + "internal Hidden Hidden.qml\n# comment\nplugin x\nimport QtQuick\nBad 1.0 ../Bad.qml\n")),
                    "[\"Ts.qml\",\"Helper.qml\",\"Hidden.qml\"]", "the files a qmldir names, inside the directory");
        assertEqual(rules.qmldirFiles(null).length, 0, "no qmldir: none");

        // --- the import check: warnings, never a refusal ---
        const header = "// A comment\n/* import qs.singletons in a block comment */\npragma Singleton\n"
            + "import QtQuick\nimport QtQuick.Layouts 1.15\nimport QtQml.Models\nimport Quickshell\nimport Quickshell.Io\n"
            + "import qs.api\nimport qs.components\nimport \".\"\nimport \"sub\" as Sub\nimport \"Rules.js\" as Rules\n"
            + "import qs.singletons\nimport Quickshell.Hyprland; import \"../core\"\nimport \"file:///etc\" as E\n"
            + "QtObject {\n    // import qs.panels after the header is not an import\n}\nimport qs.panels\n";
        assertEqual(rules.importsOf(header).length, 14, "the imports of the header, block comments skipped, two on one line");
        const warnings = rules.importWarnings("Main.qml", header);
        assertEqual(warnings.length, 4, "outside the allowlist: qs.singletons, Quickshell.Hyprland, ../core, a file URL");
        assert(_has(warnings, "Main.qml imports qs.singletons"), "… each names the file and the import");
        assert(!_has(warnings, "qs.panels"), "… nothing after the header counts");
        assertEqual(rules.importWarnings("A.qml", "import QtQuick\nQtObject {}").length, 0, "an allowed file: no warning");
        assertEqual(rules.importWarnings("A.qml", null).length, 0, "no text: no warning, no throw");
        assert(Array.isArray(rules.importWarnings("A.qml", "import ".repeat(100000))), "a huge garbage header: no throw");
        assert(!rules.importAllowed({ name: "QtQuickX", directory: false }), "QtQuickX is not under QtQuick");

        // --- precedence: the first id wins ---
        const order = rules.precedence([{ directory: "/home/m/ts", id: "tailscale" }, { directory: "/sys/m/x", id: "" },
                                        { directory: "/sys/m/ts", id: "tailscale" }, { directory: "/sys/m/y", id: "" },
                                        { directory: "/sys/m/z", id: "__proto__" }, { directory: "/sys/m/z2", id: "__proto__" }]);
        assertEqual(order.map(entry => entry.winner).join(","), "true,true,false,true,true,false", "the first of an id wins; no id never conflicts");
        assertEqual(order[2].shadowedBy, "/home/m/ts", "the later one is reported with the winner's directory");
        assertEqual(rules.precedence(null).length, 0, "nothing: nothing");

        // --- the state model ---
        const base = { valid: true, compatible: true, duplicate: false, safeMode: false, settingsKnown: true, enabled: true,
                       programsKnown: true, missingPrograms: [], mainError: "" };
        const state = changes => rules.stateOf(Object.assign({}, base, changes));
        assertEqual(state({}), "loaded", "all fine: loaded");
        assertEqual(state({ valid: false, duplicate: true, compatible: false }), "failed", "an unusable manifest first: failed");
        assertEqual(state({ duplicate: true, compatible: false }), "duplicate", "shadowed: duplicate (before API)");
        assertEqual(state({ compatible: false, safeMode: true }), "incompatible", "wrong API: incompatible");
        assertEqual(state({ safeMode: true, enabled: false }), "safe-mode", "safe mode: nothing loads");
        assertEqual(state({ settingsKnown: false, enabled: false }), "pending", "the config not read yet: pending (not even a disabled one runs)");
        assertEqual(state({ enabled: false, programsKnown: false }), "disabled", "turned off: disabled (its programs are not looked for)");
        assertEqual(state({ programsKnown: false }), "pending", "programs not checked yet: pending");
        assertEqual(state({ missingPrograms: ["tailscale"] }), "missing-program", "a program missing");
        assertEqual(state({ mainError: "Main.qml: syntax error" }), "failed", "a main that failed");
        assertEqual(rules.stateOf(null), "failed", "nothing known: failed, no throw");
        for (const each of rules.states)
            assertEqual(rules.contributes(each), each === "loaded", "contributions count only when loaded: " + each);
        const status = rules.statusOf({ manifest: tailscale, directory: "/m/ts", state: "missing-program", enabled: true,
                                        errors: ["e"], warnings: [], missingPrograms: ["tailscale"], shadowedBy: "" });
        assertEqual(status.id + " " + status.state + " " + status.setupHints.length + " " + status.missingPrograms[0],
                    "tailscale missing-program 1 tailscale", "a status: id, state, the setup hints when a program is missing");
        assertEqual(rules.statusOf({ manifest: tailscale, state: "loaded" }).setupHints.length, 0, "… not otherwise");
        assertEqual(rules.statusOf(null).state, "failed", "a status of nothing: failed, no throw");
        assertEqual(Object.keys(status).sort().join(","),
                    "api,description,directory,enabled,errors,id,missingPrograms,name,setupHints,shadowedBy,state,version,warnings",
                    "a status holds exactly these fields (plain data)");

        // --- merging ---
        const zeta = rules.parseManifest(JSON.stringify({ id: "zeta", name: "Z", version: "1", api: "1.0",
            widgets: [{ type: "zeta", name: "Z", widget: "Z.qml" }],
            settings: [{ key: "mod.zeta.a", label: "A", type: "bool", default: true }],
            facts: [{ fact: "zeta.a", label: "A", type: "bool" }],
            slots: [{ slot: "network.vpn.row", component: "Row.qml" }, { slot: "constructor", component: "C.qml" }] }));
        const alpha = rules.parseManifest(JSON.stringify({ id: "alpha", name: "A", version: "1", api: "1.0",
            widgets: [{ type: "alpha", name: "A1", widget: "A1.qml", popup: "alpha", popupPanel: "P.qml" },
                      { type: "alpha.two", name: "A2", widget: "A2.qml" }],
            settingsPages: [{ id: "alpha", label: "A", component: "Page.qml" }],
            slots: [{ slot: "network.vpn.row", component: "Row.qml" }] }));
        const merged = rules.merge([{ id: "zeta", directory: "/z", manifest: zeta }, { id: "alpha", directory: "/a/", manifest: alpha },
                                    null, { id: 5 }]);
        assertEqual(merged.widgetEntries.map(entry => entry.type).join(","), "alpha,alpha.two,zeta",
                    "merged by module id, then manifest order — not search order");
        assertEqual(merged.widgetEntries[0].widget, "file:///a/A1.qml", "files become absolute file:// URLs");
        assertEqual(merged.widgetEntries[0].popupPanel, "file:///a/P.qml", "… the popup panel too");
        assertEqual(merged.widgetEntries[2].module, "zeta", "every entry names its module");
        assertEqual(merged.settingsPages[0].component, "file:///a/Page.qml", "a settings page's component URL");
        assertEqual(merged.settingEntries.length + "," + merged.factTypes.length, "1,1", "settings and facts merged");
        assertEqual(rules.slotContributions(merged.slots, "network.vpn.row").map(entry => entry.module).join(","), "alpha,zeta",
                    "a slot's contributions, in module order");
        assertEqual(rules.slotContributions(merged.slots, "constructor").length, 1, "a slot named like a prototype key is just a slot");
        assertEqual(rules.slotContributions(merged.slots, "toString").length, 0, "a slot nobody fills: none (not the prototype's)");
        assertEqual(rules.slotContributions(merged.slots, "hasOwnProperty").length, 0, "… none");
        assertEqual(rules.slotContributions(null, "x").length, 0, "no slots: none");
        const again = rules.merge([{ id: "alpha", directory: "/a", manifest: alpha }, { id: "zeta", directory: "/z", manifest: zeta }]);
        assertEqual(JSON.stringify(again.widgetEntries), JSON.stringify(merged.widgetEntries), "stable: the input order does not matter");
        assertEqual(rules.merge(null).widgetEntries.length, 0, "nothing to merge: empty lists");
    }
}
