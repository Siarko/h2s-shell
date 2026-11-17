import QtQuick
import qs.api
import qs.singletons

// The module system's rules (singletons/ModuleRules.qml and the four Module…Rules files
// beside it): the manifest, API compatibility, namespaces, the import check, search-path
// precedence, the state model, merging — on realistic and on hostile manifests. Nothing here
// may throw.
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
        assertEqual(Api.version, "1.3", "the module API is 1.3 (api/Api.qml)");
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
        const tailscale = ModuleManifestRules.parseManifest(JSON.stringify({
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
        assertEqual(JSON.stringify(ModuleFileRules.manifestFiles(tailscale)),
                    JSON.stringify(["Main.qml", "TailscaleWidget.qml", "TailscalePanel.qml", "settings/WidgetSettings.qml",
                                    "TailscaleSettings.qml", "ExitNodeRow.qml"]),
                    "the files the import check reads: main and every component named, once");

        // A minimal one: no main, nothing else
        const minimal = ModuleManifestRules.parseManifest(_manifest());
        assert(minimal.valid && minimal.main === "" && minimal.widgets.length === 0, "only the required fields: valid, no main");

        // --- required fields ---
        for (const field of ["id", "name", "version", "api"]) {
            const object = { id: "x", name: "X", version: "1", api: "1.0" };
            delete object[field];
            const result = ModuleManifestRules.parseManifest(JSON.stringify(object));
            assert(!result.valid && _has(result.errors, "missing required field \"" + field + "\""), "missing " + field + ": invalid, said");
        }
        const wrongTypes = ModuleManifestRules.parseManifest(JSON.stringify({ id: 7, name: [], version: 3, api: 1.0, main: {} }));
        assert(!wrongTypes.valid, "every required field of the wrong type: invalid");
        assertEqual(wrongTypes.errors.length, 5, "… one error each (id, name, version, api, main)");

        // --- ids ---
        for (const good of ["tailscale", "a", "my-module", "dictation2", "x_y"])
            assert(ModuleManifestRules.validId(good) && ModuleManifestRules.parseManifest(_manifest({ id: good })).id === good, "a valid id: " + good);
        for (const bad of ["Tailscale", "1password", "-x", "my.module", "my module", "", "a".repeat(33), "ä", "x/y",
                           "__proto__", "constructor", "prototype", "hasOwnProperty", "toString"]) {
            const result = ModuleManifestRules.parseManifest(_manifest({ id: bad }));
            assert(!result.valid && result.id === "", "not a usable id: " + JSON.stringify(bad));
        }
        for (const reserved of ["lockscreen", "battery", "power", "network", "mod", "core", "api", "qs", "settings"])
            assert(_has(ModuleManifestRules.parseManifest(_manifest({ id: reserved })).errors, "reserved"), "reserved: " + reserved);
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
            assert(ModuleManifestRules.parseManifest(_manifest({ version: good })).valid, "a version: " + good);
        for (const bad of ["", " 1.0", "1.0 beta", "-1", "x".repeat(65), "1.0\n"])
            assert(!ModuleManifestRules.parseManifest(_manifest({ version: bad })).valid, "not a version: " + JSON.stringify(bad));

        // --- hostile input: nothing throws ---
        for (const text of [null, undefined, 42, "", "null", "[]", "42", "\"text\"", "true", "{", "{}}", "{\"id\":",
                            "\u0000", "[{\"id\":\"x\"}]"]) {
            let result = null;
            try {
                result = ModuleManifestRules.parseManifest(text);
            } catch (error) {
                fail("parseManifest threw on " + JSON.stringify(text) + ": " + error);
                continue;
            }
            assert(!result.valid && result.errors.length > 0, "not a manifest, said so: " + JSON.stringify(text));
        }
        assert(_has(ModuleManifestRules.parseManifest("{ not json").errors, "not valid JSON"), "not JSON: said so");
        assert(_has(ModuleManifestRules.parseManifest("[1]").errors, "not a JSON object"), "a JSON array: not an object");
        const huge = "{\"id\":\"x\",\"pad\":\"" + "a".repeat(rules.maxManifestBytes) + "\"}";
        assert(_has(ModuleManifestRules.parseManifest(huge).errors, "too large"), "a huge module.json is refused before parsing");
        // Prototype keys as fields: kept as data, never as the prototype
        const proto = ModuleManifestRules.parseManifest("{\"id\":\"x\",\"name\":\"X\",\"version\":\"1\",\"api\":\"1.0\","
                                          + "\"__proto__\":{\"valid\":true,\"main\":\"Evil.qml\"},\"constructor\":1}");
        assert(proto.valid, "a manifest with __proto__ and constructor fields is still read");
        assertEqual(proto.main, "", "… __proto__ does not inject a main");
        assert(_has(proto.warnings, "__proto__") && _has(proto.warnings, "constructor"), "… both reported as unknown fields");
        assertEqual(({}).valid, undefined, "… and Object.prototype is untouched");
        const protoEntries = ModuleManifestRules.parseManifest(_manifest({ settings: [JSON.parse("{\"__proto__\":{\"key\":\"mod.tailscale.x\"},\"label\":\"L\",\"type\":\"bool\",\"default\":true}")] }));
        assertEqual(protoEntries.settings.length, 0, "a setting whose key comes only from __proto__ is dropped");
        // Wrong types everywhere: each list not a list, each entry not an object
        const everythingWrong = ModuleManifestRules.parseManifest(_manifest({
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
        const tooMany = ModuleManifestRules.parseManifest(_manifest({ facts: Array.from({ length: 300 }, (_, i) => ({ fact: "tailscale.f" + i, label: "F", type: "bool" })) }));
        assertEqual(tooMany.facts.length, rules.maxEntries, "at most maxEntries entries of a list are read");
        assert(_has(tooMany.errors, "only the first"), "… said so");

        // --- unknown fields: kept, warned ---
        const newer = ModuleManifestRules.parseManifest(_manifest({ permissions: ["network"], icon: "vpn" }));
        assert(newer.valid, "a manifest with fields this shell does not know still loads");
        assertEqual(JSON.stringify(newer.unknownFields), "[\"permissions\",\"icon\"]", "… their names listed");
        assertEqual(JSON.stringify(newer.raw.permissions), "[\"network\"]", "… their values kept in raw");
        assertEqual(newer.warnings.length, 2, "… one warning each");
        const unknownInEntry = ModuleManifestRules.parseManifest(_manifest({ facts: [{ fact: "tailscale.up", label: "Up", type: "bool", color: "red" }] }));
        assert(unknownInEntry.facts.length === 1 && _has(unknownInEntry.warnings, "facts[0]: unknown field \"color\""),
               "an unknown field in an entry: the entry kept, a warning");

        // --- paths ---
        for (const good of ["Main.qml", "sub/Panel.qml", "a-b_c.qml", "x/y/z.qml"])
            assertEqual(ModuleFileRules.pathProblem(good), "", "a module file: " + good);
        for (const bad of ["/etc/x.qml", "../x.qml", "a/../../x.qml", "./x.qml", "a//b.qml", "x.js", "x", "",
                           "a b.qml", "x.qml\u0000", "file:///x.qml", "C:\\x.qml", "~/x.qml", null, 3, "a".repeat(301) + ".qml"])
            assert(ModuleFileRules.pathProblem(bad) !== "", "not a module file: " + JSON.stringify(bad));
        assertEqual(ModuleFileRules.canonicalPath("/a//b/./c/../d/"), "/a/b/d", "canonical: repeated /, ., .., trailing / gone");
        assertEqual(ModuleFileRules.canonicalPath("/../a"), "/a", "canonical: above the root stays at the root");
        for (const bad of ["a/b", "", "./a", null, 5, "~/x"])
            assertEqual(ModuleFileRules.canonicalPath(bad), "", "not absolute: " + JSON.stringify(bad));
        assertEqual(ModuleFileRules.fileUrl("/m/x/", "a/B.qml"), "file:///m/x/a/B.qml", "a file's URL");
        assertEqual(ModuleFileRules.fileUrl("/m//x/.", "B.qml"), ModuleFileRules.fileUrl("/m/x", "B.qml"), "one file, one URL, however the directory is spelled");
        assertEqual(ModuleFileRules.fileUrl("/m/a#b?c%d", "B.qml"), "file:///m/a%23b%3Fc%25d/B.qml", "what a URL cannot hold is escaped");

        // --- the module list (H2S_SHELL_MODULES) ---
        const list = ModuleFileRules.moduleDirectories("/a/x::/b/y/:relative:/a//x:/c/../b/y:/");
        assertEqual(JSON.stringify(list.directories), "[\"/a/x\",\"/b/y\"]", "canonical, in order, each once");
        assertEqual(JSON.stringify(list.ignored), "[\"relative\",\"/\"]", "what is not a module directory is reported");
        assertEqual(ModuleFileRules.moduleDirectories(["/a", 3, null, "/a/"]).directories.length, 1, "a list works as well; junk ignored");
        assertEqual(ModuleFileRules.moduleDirectories(undefined).directories.length, 0, "nothing: no directories");

        // --- namespaces ---
        assert(ModuleManifestRules.isOwnSettingKey("tailscale", "mod.tailscale.showIp"), "mod.<id>.<name>: its own setting");
        assert(ModuleManifestRules.isOwnSettingKey("tailscale", "mod.tailscale.exit.node"), "… nested");
        for (const bad of ["tailscale.showIp", "mod.tailscale", "mod.tailscale.", "mod.other.x", "lockscreen.enabled",
                           "mod.tailscalex.y", "mod.tailscale..x", "mod.tailscale.a-b", "mod.tailscale.__proto__.x.", 5])
            assert(!ModuleManifestRules.isOwnSettingKey("tailscale", bad), "not its setting: " + JSON.stringify(bad));
        assert(ModuleManifestRules.isOwnFact("tailscale", "tailscale.connected"), "<id>.<name>: its own fact");
        for (const bad of ["tailscale", "battery.percent", "tailscalex.y", "mod.tailscale.x", "tailscale.", ""])
            assert(!ModuleManifestRules.isOwnFact("tailscale", bad), "not its fact: " + JSON.stringify(bad));
        assert(ModuleManifestRules.isOwnName("tailscale", "tailscale") && ModuleManifestRules.isOwnName("tailscale", "tailscale.devices"),
               "a widget type, popup or page: <id> or <id>.<name>");
        assert(!ModuleManifestRules.isOwnName("tailscale", "clock") && !ModuleManifestRules.isOwnName("tailscale", "tailscale2"), "… not another's");

        // A violation drops that entry with an error; the module still loads
        const collisions = ModuleManifestRules.parseManifest(_manifest({
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
        const typed = ModuleManifestRules.parseManifest(_manifest({ settings: [
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
        const facts = ModuleManifestRules.parseManifest(_manifest({ facts: [
            { fact: "tailscale.a", label: "A", type: "color" }, { fact: "tailscale.b", label: "B", type: "enum" },
            { fact: "tailscale.c", type: "bool" }, { fact: "tailscale.d", label: "D", type: "percent" }] }));
        assertEqual(facts.facts.map(fact => fact.fact).join(","), "tailscale.d", "malformed facts dropped");

        // Widgets and pages
        const widgets = ModuleManifestRules.parseManifest(_manifest({
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
        const requires = ModuleManifestRules.parseManifest(_manifest({ requires: { programs: ["tailscale", "tailscale", "../bin/x", "a b", 5, "jq"],
                                                                      services: ["tailscaled"] } }));
        assertEqual(JSON.stringify(requires.programs), "[\"tailscale\",\"jq\"]", "program names, each once; paths and junk dropped");
        assert(_has(requires.warnings, "requires: unknown field \"services\""), "an unknown requirement: a warning");

        // --- qmldir ---
        assertEqual(JSON.stringify(ModuleFileRules.qmldirFiles("module foo\nsingleton Ts 1.0 Ts.qml\nHelper 1.0 Helper.qml\n"
                                                     + "internal Hidden Hidden.qml\n# comment\nplugin x\nimport QtQuick\nBad 1.0 ../Bad.qml\n")),
                    "[\"Ts.qml\",\"Helper.qml\",\"Hidden.qml\"]", "the files a qmldir names, inside the directory");
        assertEqual(ModuleFileRules.qmldirFiles(null).length, 0, "no qmldir: none");

        // --- the import check: warnings, never a refusal ---
        const header = "// A comment\n/* import qs.singletons in a block comment */\npragma Singleton\n"
            + "import QtQuick\nimport QtQuick.Layouts 1.15\nimport QtQml.Models\nimport Quickshell\nimport Quickshell.Io\n"
            + "import qs.api\nimport qs.components\nimport \".\"\nimport \"sub\" as Sub\nimport \"Rules.js\" as Rules\n"
            + "import qs.singletons\nimport Quickshell.Hyprland; import \"../core\"\nimport \"file:///etc\" as E\n"
            + "QtObject {\n    // import qs.panels after the header is not an import\n}\nimport qs.panels\n";
        assertEqual(ModuleSourceRules.importsOf(header).length, 14, "the imports of the header, block comments skipped, two on one line");
        const warnings = ModuleSourceRules.importWarnings("Main.qml", header);
        assertEqual(warnings.length, 4, "outside the allowlist: qs.singletons, Quickshell.Hyprland, ../core, a file URL");
        assert(_has(warnings, "Main.qml imports qs.singletons"), "… each names the file and the import");
        assert(!_has(warnings, "qs.panels"), "… nothing after the header counts");
        assertEqual(ModuleSourceRules.importWarnings("A.qml", "import QtQuick\nQtObject {}").length, 0, "an allowed file: no warning");
        assertEqual(ModuleSourceRules.importWarnings("A.qml", null).length, 0, "no text: no warning, no throw");
        assert(Array.isArray(ModuleSourceRules.importWarnings("A.qml", "import ".repeat(100000))), "a huge garbage header: no throw");
        assert(!ModuleSourceRules.importAllowed({ name: "QtQuickX", directory: false }), "QtQuickX is not under QtQuick");

        // --- precedence: the first id wins ---
        const order = ModuleMergeRules.precedence([{ directory: "/home/m/ts", id: "tailscale" }, { directory: "/sys/m/x", id: "" },
                                        { directory: "/sys/m/ts", id: "tailscale" }, { directory: "/sys/m/y", id: "" },
                                        { directory: "/sys/m/z", id: "__proto__" }, { directory: "/sys/m/z2", id: "__proto__" }]);
        assertEqual(order.map(entry => entry.winner).join(","), "true,true,false,true,true,false", "the first of an id wins; no id never conflicts");
        assertEqual(order[2].shadowedBy, "/home/m/ts", "the later one is reported with the winner's directory");
        assertEqual(ModuleMergeRules.precedence(null).length, 0, "nothing: nothing");

        // --- the state model ---
        const base = { valid: true, compatible: true, duplicate: false, safeMode: false, settingsKnown: true, enabled: true,
                       programsKnown: true, missingPrograms: [], mainError: "" };
        const state = changes => ModuleMergeRules.stateOf(Object.assign({}, base, changes));
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
        assertEqual(ModuleMergeRules.stateOf(null), "failed", "nothing known: failed, no throw");
        for (const each of rules.states)
            assertEqual(ModuleMergeRules.contributes(each), each === "loaded", "contributions count only when loaded: " + each);
        const status = ModuleMergeRules.statusOf({ manifest: tailscale, directory: "/m/ts", state: "missing-program", enabled: true,
                                        errors: ["e"], warnings: [], missingPrograms: ["tailscale"], shadowedBy: "" });
        assertEqual(status.id + " " + status.state + " " + status.setupHints.length + " " + status.missingPrograms[0],
                    "tailscale missing-program 1 tailscale", "a status: id, state, the setup hints when a program is missing");
        assertEqual(ModuleMergeRules.statusOf({ manifest: tailscale, state: "loaded" }).setupHints.length, 0, "… not otherwise");
        assertEqual(ModuleMergeRules.statusOf(null).state, "failed", "a status of nothing: failed, no throw");
        assertEqual(Object.keys(status).sort().join(","),
                    "api,description,directory,enabled,errors,id,missingPrograms,name,setupHints,shadowedBy,state,version,warnings",
                    "a status holds exactly these fields (plain data)");

        // --- merging ---
        const zeta = ModuleManifestRules.parseManifest(JSON.stringify({ id: "zeta", name: "Z", version: "1", api: "1.0",
            widgets: [{ type: "zeta", name: "Z", widget: "Z.qml" }],
            settings: [{ key: "mod.zeta.a", label: "A", type: "bool", default: true }],
            facts: [{ fact: "zeta.a", label: "A", type: "bool" }],
            slots: [{ slot: "network.vpn.row", component: "Row.qml" }, { slot: "constructor", component: "C.qml" }] }));
        const alpha = ModuleManifestRules.parseManifest(JSON.stringify({ id: "alpha", name: "A", version: "1", api: "1.0",
            widgets: [{ type: "alpha", name: "A1", widget: "A1.qml", popup: "alpha", popupPanel: "P.qml" },
                      { type: "alpha.two", name: "A2", widget: "A2.qml" }],
            settingsPages: [{ id: "alpha", label: "A", component: "Page.qml" }],
            slots: [{ slot: "network.vpn.row", component: "Row.qml" }] }));
        const merged = ModuleMergeRules.merge([{ id: "zeta", directory: "/z", manifest: zeta }, { id: "alpha", directory: "/a/", manifest: alpha },
                                    null, { id: 5 }]);
        assertEqual(merged.widgetEntries.map(entry => entry.type).join(","), "alpha,alpha.two,zeta",
                    "merged by module id, then manifest order — not search order");
        assertEqual(merged.widgetEntries[0].widget, "file:///a/A1.qml", "files become absolute file:// URLs");
        assertEqual(merged.widgetEntries[0].popupPanel, "file:///a/P.qml", "… the popup panel too");
        assertEqual(merged.widgetEntries[2].module, "zeta", "every entry names its module");
        assertEqual(merged.settingsPages[0].component, "file:///a/Page.qml", "a settings page's component URL");
        assertEqual(merged.settingEntries.length + "," + merged.factTypes.length, "1,1", "settings and facts merged");
        assertEqual(ModuleMergeRules.slotContributions(merged.slots, "network.vpn.row").map(entry => entry.module).join(","), "alpha,zeta",
                    "a slot's contributions, in module order");
        assertEqual(ModuleMergeRules.slotContributions(merged.slots, "constructor").length, 1, "a slot named like a prototype key is just a slot");
        assertEqual(ModuleMergeRules.slotContributions(merged.slots, "toString").length, 0, "a slot nobody fills: none (not the prototype's)");
        assertEqual(ModuleMergeRules.slotContributions(merged.slots, "hasOwnProperty").length, 0, "… none");
        assertEqual(ModuleMergeRules.slotContributions(null, "x").length, 0, "no slots: none");
        const again = ModuleMergeRules.merge([{ id: "alpha", directory: "/a", manifest: alpha }, { id: "zeta", directory: "/z", manifest: zeta }]);
        assertEqual(JSON.stringify(again.widgetEntries), JSON.stringify(merged.widgetEntries), "stable: the input order does not matter");
        assertEqual(ModuleMergeRules.merge(null).widgetEntries.length, 0, "nothing to merge: empty lists");

        _m2(rules, alpha, zeta);
        _api13(rules);
    }

    // API 1.3: Api.networks and Api.vpnsUp — the pure mappings, on realistic and hostile input
    function _api13(rules) {
        // Profiles as Nmcli.profiles reads them
        const profile = (uuid, name, kind, state, port) => ({ uuid: uuid, name: name, type: kind, kind: kind, device: "",
            autoconnect: true, priority: 0, lastUsed: 0, active: state !== "", port: port ?? "", state: state });
        const profiles = [
            profile("u-home", "Home", "wifi", ""),
            profile("u-hotspot", "Hotspot", "wifi", "activated"),
            profile("u-office", "Office LAN", "ethernet", "activated"),
            profile("u-wg", "wg0", "vpn", "activated"),
            profile("u-bridge", "br0", "bridge", "activated"),
            profile("u-port", "br0 port", "ethernet", "activated", "bridge"),
            profile("u-lo", "lo", "loopback", "activated"),
            profile("u-cafe", "Cafe", "wifi", "activated"),
            profile("u-train", "Train", "wifi", "activating")
        ];
        const wifi = { "u-home": { ssid: "home", mode: "infrastructure" }, "u-hotspot": { ssid: "mine", mode: "ap" },
                       "u-cafe": { ssid: "cafe", mode: "infrastructure" } };
        assertEqual(JSON.stringify(rules.apiNetworks(profiles, wifi)), JSON.stringify([
            { id: "u-office", name: "Office LAN", kind: "ethernet", active: true },
            { id: "u-cafe", name: "Cafe", kind: "wifi", active: true },
            { id: "u-home", name: "Home", kind: "wifi", active: false },
            { id: "u-train", name: "Train", kind: "wifi", active: false }]),
            "apiNetworks: Wi-Fi and Ethernet, active first (\"activated\" only), no hotspot, VPN, bridge, port or loopback");
        assertEqual(rules.apiNetworks([profile("u-unread", "New", "wifi", "")], {}).length, 1,
                    "apiNetworks: a Wi-Fi profile whose details are not read yet is kept");
        assertEqual(rules.apiNetworks([], {}).length, 0, "apiNetworks: no profiles, none");
        for (const bad of [null, undefined, "x", 3, {}, [null, 1, "x", [], {}, { uuid: "" }, { uuid: 5, kind: "wifi" }]])
            assertEqual(rules.apiNetworks(bad, null).length, 0, "apiNetworks: garbage skipped — " + JSON.stringify(bad));
        assertEqual(JSON.stringify(rules.apiNetworks([{ uuid: "u-bare", kind: "ethernet" }, { uuid: "constructor", kind: "wifi", name: 7 }], "junk")),
                    JSON.stringify([{ id: "u-bare", name: "", kind: "ethernet", active: false },
                                    { id: "constructor", name: "", kind: "wifi", active: false }]),
                    "apiNetworks: missing fields defaulted; a prototype-named UUID is just a UUID");

        // VPNs as VpnManager.activeVpns has them
        const vpns = [
            { uuid: "u-wg", name: "wg-home", type: "wireguard", active: true, state: "activated", device: "wg0" },
            { uuid: "tailscale:main", name: "Tailscale", type: "provider", provider: "tailscale", entryId: "main", state: "activated" },
            { uuid: "u-ovpn", name: "Work", type: "vpn", provider: "sneaky", state: "activated" }
        ];
        assertEqual(JSON.stringify(rules.apiVpnsUp(vpns)), JSON.stringify([
            { name: "wg-home", type: "wireguard", provider: "" },
            { name: "Tailscale", type: "provider", provider: "tailscale" },
            { name: "Work", type: "vpn", provider: "" }]),
            "apiVpnsUp: name, type, and the providerId only for a provider's VPN, in order");
        assertEqual(rules.apiVpnsUp([]).length, 0, "apiVpnsUp: none up, none");
        for (const bad of [null, undefined, "x", 3, {}, [null, 1, "x", []]])
            assertEqual(rules.apiVpnsUp(bad).length, 0, "apiVpnsUp: garbage skipped — " + JSON.stringify(bad));
        assertEqual(JSON.stringify(rules.apiVpnsUp([{ type: "provider", provider: 3 }, {}])),
                    JSON.stringify([{ name: "", type: "provider", provider: "" }, { name: "", type: "", provider: "" }]),
                    "apiVpnsUp: missing or wrong fields defaulted");

        // What Api hands out: frozen, the list and each entry
        const rows = rules.frozenRows(JSON.stringify([{ id: "a" }]));
        assert(Object.isFrozen(rows) && Object.isFrozen(rows[0]) && rows[0].id === "a", "frozenRows: the list and its entries frozen");
        for (const bad of ["", "{", "{}", "null", undefined])
            assertEqual(rules.frozenRows(bad).length, 0, "frozenRows: not a JSON list → [] — " + JSON.stringify(bad));
        assert(Array.isArray(Api.networks) && Object.isFrozen(Api.networks), "Api.networks: a frozen list");
        assert(Array.isArray(Api.vpnsUp) && Object.isFrozen(Api.vpnsUp), "Api.vpnsUp: a frozen list");
        assert(Api.networks.every(network => Object.isFrozen(network) && typeof network.id === "string"
                                  && (network.kind === "wifi" || network.kind === "ethernet")), "Api.networks: frozen entries of the shape");
    }

    // M2: the API version's home, presetDefaults, the slot table, the registries' merges, the
    // values a module hands over, the file check, the start guard
    function _m2(rules, alpha, zeta) {
        assertEqual(rules.apiVersion, Api.version, "Api.version is ModuleRules.apiVersion");

        // presetDefaults
        const presets = ModuleManifestRules.parseManifest(_manifest({ widgets: [
            { type: "tailscale", name: "T", widget: "W.qml", presetDefaults: { showIp: true, hosts: ["a"] } },
            { type: "tailscale.b", name: "B", widget: "W.qml", presetDefaults: [] },
            { type: "tailscale.c", name: "C", widget: "W.qml", presetDefaults: { "bad key": 1 } },
            { type: "tailscale.d", name: "D", widget: "W.qml", presetDefaults: { big: "x".repeat(20000) } }] }));
        assertEqual(presets.widgets.map(widget => widget.type).join(","), "tailscale", "presetDefaults: only a small object of names kept");
        assertEqual(presets.widgets[0].presetDefaults.hosts[0], "a", "… its values kept");
        assertEqual(presets.warnings.length, 0, "… presetDefaults is a known field");

        // The slot table
        assert(rules.slotNames.length >= 3 && rules.slotTable.every(slot => slot.name && slot.where && slot.context && slot.since),
               "the slot table: each slot with where, context, since");
        assertEqual(ModuleMergeRules.unknownSlotWarnings({ slots: [{ slot: "network.popup.sections", component: "A.qml" },
                                                        { slot: "network.popup.nowhere", component: "B.qml" }] }).length, 1,
                    "a contribution to a slot not offered: one warning");
        for (const slot of rules.slotNames)
            assert(!/lock|screensaver/.test(slot), "no slot on the lock screen: " + slot);

        // Registries: no module → the core's list, unchanged
        const core = [{ type: "clock", popup: "calendar" }, { type: "tray" }];
        assert(ModuleMergeRules.mergeWidgetEntries(core, []) === core, "widgets, no module: the core's list itself");
        const widgets = ModuleMergeRules.mergeWidgetEntries(core, [{ type: "alpha", popup: "alpha", module: "alpha" },
            { type: "clock", module: "x" }, { type: "x2", popup: "calendar", module: "x" }, { type: "x3", popup: "tray-menu", module: "x" }]);
        assertEqual(widgets.map(entry => entry.type).join(","), "clock,tray,alpha", "widgets: the core's first; a module's type or popup the core has is dropped");
        const pageCore = [{ id: "general", tab: "behaviour" }, { id: "network", tab: "system", group: true },
                          { id: "network_vpn", tab: "system", parent: "network" }, { id: "themes", tab: "appearance" }];
        assert(ModuleMergeRules.mergeSettingsPages(pageCore, []).pages === pageCore, "pages, no module: the core's list itself");
        const pages = ModuleMergeRules.mergeSettingsPages(pageCore, [
            { id: "ts", label: "T", tab: "behaviour", component: "file:///t/P.qml", module: "ts", parent: "network" },
            { id: "ts.top", label: "Top", tab: "appearance", component: "file:///t/Q.qml", module: "ts" },
            { id: "ts.lost", label: "Lost", tab: "behaviour", component: "file:///t/R.qml", module: "ts", parent: "nowhere" },
            { id: "general", label: "Mine", tab: "behaviour", component: "file:///t/S.qml", module: "ts" }]);
        assertEqual(pages.pages.map(page => page.id + (page.parent ? "<" + page.parent : "")).join(","),
                    "general,network,network_vpn<network,ts<network,themes,ts.top,modules,ts.lost<modules",
                    "pages: under a core group after its pages (on its tab), at the end of their tab, the rest under Modules");
        assertEqual(pages.pages.find(page => page.id === "ts").tab, "system", "… a group's page takes the group's tab");
        assertEqual(pages.pages.find(page => page.id === "ts").url, "file:///t/P.qml", "… a module's page has a url");
        assertEqual(pages.problems.length, 2, "… the lost parent and the core's id: said");
        const settingCore = [{ key: "general.debug" }];
        assert(ModuleMergeRules.mergeSettingEntries(settingCore, []) === settingCore, "settings, no module: the core's list itself");
        assertEqual(ModuleMergeRules.mergeSettingEntries(settingCore, [{ key: "general.debug" }, { key: "mod.x.a" }]).length, 2, "settings: a core key dropped");
        const factCore = [{ fact: "power.onBattery" }];
        assert(ModuleMergeRules.mergeFactTypes(factCore, []) === factCore, "facts, no module: the core's list itself");
        assertEqual(JSON.stringify(ModuleMergeRules.mergePresetDefaults({ clock: { format: "x" } }, [{ type: "alpha", presetDefaults: { a: 1 } }, { type: "clock", presetDefaults: { format: "evil" } }])),
                    "{\"clock\":{\"format\":\"x\"},\"alpha\":{\"a\":1}}", "preset defaults: a module's added, never over the core's");

        // Facts a module sets
        assert(rules.factValue("bool", true).ok && !rules.factValue("bool", 1).ok, "a bool fact");
        assert(rules.factValue("percent", 100).ok && !rules.factValue("percent", 101).ok && !rules.factValue("percent", NaN).ok, "a percent fact");
        assert(rules.factValue("enum", "a", ["a"]).ok && !rules.factValue("enum", "b", ["a"]).ok, "an enum fact");
        assert(rules.factValue("number", -5.5).ok && !rules.factValue("number", "5").ok, "a number fact");
        assert(!rules.factValue("string", "x".repeat(201)).ok, "a string fact: at most 200");
        assertEqual(rules.factValue("bool", null).value, null, "null: not known");
        assert(!rules.factValue("color", "red").ok, "an unknown type: refused");
        for (const hostile of [{}, [], () => 1, { valueOf: () => { throw "x"; } }])
            assert(!rules.factValue("number", hostile).ok, "hostile values: refused, no throw");
        assertEqual(rules.ownFactName("ts", "up"), "ts.up", "ownFactName: <name>");
        assertEqual(rules.ownFactName("ts", "x.y"), "ts.x.y", "ownFactName: a dotted name is its own too");
        assertEqual(rules.ownFactName("ts", "") + rules.ownFactName("ts", 5), "", "ownFactName: nothing, not a name");
        assertEqual(rules.ownSettingKey("ts", "a"), "mod.ts.a", "ownSettingKey: <name>");
        assertEqual(rules.ownSettingKey("ts", "mod.other.a"), "", "ownSettingKey: not another's");
        const enumEntry = { type: "enum", options: [{ value: "a", label: "A" }] };
        assert(rules.settingValueProblem(enumEntry, "a") === "" && rules.settingValueProblem(enumEntry, "b") !== "", "a setting's value: enum");
        assert(rules.settingValueProblem({ type: "number", min: 0, max: 5 }, 6) !== "", "… a number out of range");
        assert(rules.settingValueProblem({ type: "stringList" }, ["a", 1]) !== "", "… a list with a number");
        assert(rules.settingValueProblem(null, 1) !== "", "… an undeclared key");

        // The store
        assertEqual(rules.storeText({ a: 1 }), "{\"a\":1}", "storeText");
        assertEqual(rules.storeText({ huge: "x".repeat(rules.maxStoreBytes) }), null, "storeText: too large");
        const cyclic = {};
        cyclic.self = cyclic;
        assertEqual(rules.storeText(cyclic), null, "storeText: not plain JSON");
        assertEqual(JSON.stringify(rules.parseStore("[1]")) + JSON.stringify(rules.parseStore("{")) + JSON.stringify(rules.parseStore(null)), "{}{}{}",
                    "parseStore: anything but an object is an empty store");

        // Contexts compared by value
        const object = Qt.createQmlObject("import QtQuick; QtObject {}", this);
        const close = () => 1;
        assert(rules.sameContext({ slot: "a", n: [1, { b: 2 }] }, { slot: "a", n: [1, { b: 2 }] }), "sameContext: equal plain data");
        assert(!rules.sameContext({ slot: "a" }, { slot: "b" }), "… a changed value");
        assert(!rules.sameContext({ slot: "a" }, { slot: "a", x: 1 }), "… a key more");
        assert(rules.sameContext({ provider: object, close: close }, { provider: object, close: close }), "… the same object and function");
        assert(!rules.sameContext({ close: close }, { close: () => 1 }), "… another function");
        assert(!rules.sameContext(null, {}) && rules.sameContext(null, null), "… null");
        object.destroy();
        assertEqual(ModuleMergeRules.contributionKey({ module: "a", component: "file:///x" }), "a|file:///x", "a contribution's identity");
        assertEqual(ModuleFileRules.directoryIndexOf(["/m/a", "/m/a/b"], "file:///m/a/b/c/X.qml"), 1, "directoryIndexOf: the deepest");
        assertEqual(ModuleFileRules.directoryIndexOf(["/m/a"], "file:///m/ab/X.qml"), -1, "… not a prefix of another name");
        assertEqual(ModuleFileRules.directoryIndexOf(["/m/a"], "file:///m/a/../b/X.qml"), -1, "… .. leaves it");
        assertEqual(ModuleFileRules.directoryIndexOf(["/m/a b"], "file:///m/a%20b/X.qml"), 0, "… escaped");

        // The file check
        const files = ModuleFileRules.filesToCheck(alpha, "singleton S 1.0 S.qml\n");
        assertEqual(files.map(entry => entry.file + ":" + entry.kind).join(","), "A1.qml:entry,P.qml:entry,A2.qml:entry,Page.qml:entry,Row.qml:entry,S.qml:qmldir",
                    "filesToCheck: every file named, each once, with its kind");
        assertEqual(JSON.stringify(ModuleFileRules.parseFileCheck(["0\tok", "1\tis not a regular file", "junk", "2\t"])),
                    "{\"0\":\"ok\",\"1\":\"is not a regular file\",\"2\":\"\"}", "parseFileCheck");
        const checked = ModuleFileRules.withoutBadFiles(alpha, { "P.qml": "is not a regular file", "Row.qml": "leaves the module directory through a link" }, "");
        assertEqual(checked.manifest.widgets.map(widget => widget.type).join(","), "alpha.two", "withoutBadFiles: a widget with a bad file dropped");
        assertEqual(checked.manifest.slots.length, 0, "… a slot with one dropped");
        assertEqual(checked.errors.length, 2, "… each said");
        assertEqual(checked.fatal, "", "… the module still loads");
        assertEqual(alpha.widgets.length, 2, "… the manifest given is not changed");
        assert(ModuleFileRules.withoutBadFiles({ main: "Main.qml" }, { "Main.qml": "x" }, "").fatal !== "", "a bad main: fatal");
        assert(ModuleFileRules.withoutBadFiles({}, { "S.qml": "x" }, "singleton S 1.0 S.qml").fatal !== "", "a bad qmldir file: fatal");

        // The start guard
        assertEqual(JSON.stringify(ModuleFileRules.startGuard("0 77:")), JSON.stringify({ safeMode: false, count: 0, identity: "77:", reason: "" }), "guard: a fresh process, 0");
        assert(!ModuleFileRules.startGuard("1 77:5").safeMode, "guard: one relaunch after a crash — not yet");
        assert(ModuleFileRules.startGuard("2 77:6").safeMode && ModuleFileRules.startGuard("17 77:9").safeMode, "guard: 2 or more in a row — safe mode");
        assertEqual(ModuleFileRules.startGuard("2 77:6").identity, "77:6", "… its identity, to clear it with");
        assert(ModuleFileRules.startGuard("refused 77:").reason !== "", "guard: a counter that is not a plain file — said, not counted");
        for (const junk of ["", "abc", "2", "-3 1:2", "99999 1:2", null, "refused", "1\n2", "2 x:y"])
            assert(!ModuleFileRules.startGuard(junk).safeMode, "guard: garbage counts as 0 — " + JSON.stringify(junk));
        assertEqual(ModuleFileRules.guardClearMs, 30000, "the guard's window is the launcher's quick-death window (30 s)");

        // What a root object declares (the initial properties the core gives it)
        const declared = ModuleSourceRules.rootProperties("import QtQuick\n// property var top\nItem {\n    property var module: null\n    readonly property int x: 1\n"
            + "    required property var context\n    Rectangle { property var inner }\n    property list<string> names\n    // property var commented\n"
            + "    /* property var blocked */ property string text: \"property var fake; {\"\n    default property alias content: c.data\n}\n");
        assertEqual(declared.join(","), "module,context,names,text,content", "rootProperties: the root's own, writable ones; not nested, commented or quoted");
        assertEqual(JSON.stringify(ModuleSourceRules.initialProperties(["module"], { module: 1, context: 2 })), "{\"module\":1}", "initialProperties: only the declared");
        assertEqual(ModuleSourceRules.rootProperties(null).length, 0, "rootProperties: no text, none");
        // A regex literal holding a brace does not throw the depth off
        assertEqual(ModuleSourceRules.rootProperties("Item {\n    function f(s) { return /[{]+/.test(s) && s.split(/{/).length > 0; }\n    property var module\n    property var context: x.replace(/\\{/g, \"\")\n}\n").join(","),
                    "module,context", "rootProperties: braces inside regex literals ignored");
        // Only `property var module` gets the handle; other spellings get a warning
        assertEqual(ModuleSourceRules.rootProperties("Item {\n    property int module\n    property var context\n}\n").join(","), "context", "rootProperties: `property int module` is not a module property");
        assertEqual(ModuleSourceRules.rootProperties("Item {\n    readonly property var module: null\n}\n").length, 0, "rootProperties: a readonly module is not one");
        assert(ModuleSourceRules.modulePropertyWarning("W.qml", "Item {\n    property int module\n}\n").includes("only `property var module`"), "modulePropertyWarning: property int module");
        assert(ModuleSourceRules.modulePropertyWarning("W.qml", "Item {\n    readonly property var module: null\n}\n").includes("readonly"), "modulePropertyWarning: readonly");
        assertEqual(ModuleSourceRules.modulePropertyWarning("W.qml", "Item {\n    property var module: null\n    Item { property int module }\n}\n"), "", "modulePropertyWarning: the right spelling (a nested object's is not the root's)");

        // The file check's texts (A1: read in the check's process, never on the GUI thread)
        const texts = ModuleFileRules.fileTexts(["0:{\"a\":", "0:1}", "0\tok", "1:half", "2\tis not a regular file", "3:", "3\tok", "4:x", "4:", "4\tok"]);
        assertEqual(JSON.stringify(texts), "{\"0\":\"{\\\"a\\\":\\n1}\",\"3\":\"\",\"4\":\"x\\n\"}",
                    "fileTexts: the lines of each answered file joined; a text without its ok (cut short) dropped; the last line break kept");

        // A2: Api.openUrl's rule
        for (const good of ["https://login.tailscale.com/a/1", "http://example.org", "mailto:me@example.org", "HTTPS://X"])
            assertEqual(rules.openUrlProblem(good), "", "openUrl: " + good + " is opened");
        for (const bad of ["", "/etc/passwd", "file:///etc/passwd", "x.desktop", "/usr/share/applications/evil.desktop", "-help", "--version",
                           "javascript:alert(1)", "ftp://x", "smb://host/share", "steam://run/1", "https://a\nb", "https://" + "a".repeat(5000), "www.example.org"])
            assert(rules.openUrlProblem(bad) !== "", "openUrl refuses " + JSON.stringify(bad.slice(0, 40)) + ": " + rules.openUrlProblem(bad));
        assertEqual(rules.openUrlProblem("file:///home/me/x.txt", { allowFile: true }), "", "openUrl: file: with { allowFile: true }");
        assert(rules.openUrlProblem("/home/me/x.txt", { allowFile: true }) !== "", "… but never a bare path");
        assert(rules.openUrlProblem("smb://x", { allowFile: true }) !== "", "… and allowFile allows file: only");
        assert(rules.openUrlProblem("file:///x", { allowFile: "yes" }) !== "", "… exactly true");
        assertEqual(Api.openUrl("file:///etc/passwd"), false, "Api.openUrl refuses (nothing run)");
        assertEqual(Api.openUrl("/etc/passwd"), false, "Api.openUrl refuses a bare path");

        // A4: notify-send's argv — every option, then "--", then summary and body
        const argv = Notifier.command("-a evil", { body: "--action=x=y", urgency: "low", actions: [{ id: "ok", label: "OK" }] });
        const dash = argv.indexOf("--");
        assert(dash > 0 && argv[dash + 1] === "-a evil" && argv[dash + 2] === "--action=x=y" && argv.length === dash + 3,
               "Notifier.command: summary and body after \"--\": " + JSON.stringify(argv));
        assert(argv.indexOf("--wait") > 0 && argv.indexOf("--wait") < dash && argv.indexOf("--action=ok=OK") < dash, "… options (--wait, --action) before it");
        assertEqual(JSON.stringify(Notifier.command("Hi")), "[\"notify-send\",\"--app-name=H2S Shell\",\"--\",\"Hi\"]", "Notifier.command: the plain case");

        // Popup modes of module widget types: never core entries (a new config's Full must
        // not freeze a module's default)
        assert(!SettingsSchema.coreEntries.some(entry => entry.module !== undefined || !WidgetRegistry.coreEntries.some(widget => entry.key === "widgets." + widget.type + ".popupMode") && entry.group === "popupMode"),
               "SettingsSchema.coreEntries: only the core widget types' popup modes");

        // The import check: qs.tests only in a module's tests
        assertEqual(ModuleSourceRules.importWarnings("tests/T.qml", "import qs.tests\nItem {}", true).length, 0, "a test suite may import qs.tests");
        assertEqual(ModuleSourceRules.importWarnings("tests/T.qml", "import \"..\"\nItem {}", true).length, 0, "a suite in tests/ importing \"..\": the module's own directory");
        assertEqual(ModuleSourceRules.importWarnings("tests/T.qml", "import \"../..\"\nItem {}", true).length, 1, "… \"../..\" leaves it");
        assertEqual(ModuleSourceRules.importWarnings("Main.qml", "import qs.tests\nItem {}", false).length, 1, "… a module's own file may not (the shell has no qs.tests)");

        // Reserved ids: every core IPC target and settings page id shaped like a module id
        for (const target of ["tablet", "locktest", "shelltest", "lockscreen", "settings", "modules", "profiles", "fakevpn",
                              "authentication", "wallpaper", "popups", "controls", "tray-menu"])
            assert(rules.reservedIds.includes(target), "reserved: " + target);
    }
}
