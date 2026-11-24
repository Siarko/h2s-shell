import QtQuick
import qs.distributions.arch
import qs.distributions.generic
import qs.distributions.nixos
import qs.singletons

// The connectivity check's address (singletons/ConnectivityRules.qml): the address, the
// shell's file for it, NetworkManager's files merged in its order, which files it reads after
// the shell's, and what the address's row offers by each shipped distribution's capability
// (Arch saves, NixOS copies the line or writes anyway, generic says why not) and what is in
// force.
TestCase {
    id: suite
    suiteName: "ConnectivityRules"

    property Component _arch: Component {
        ArchIntegration {}
    }
    property Component _nixos: Component {
        NixosIntegration {}
    }
    property Component _generic: Component {
        GenericIntegration {}
    }

    function run() {
        const rules = ConnectivityRules;
        const json = value => JSON.stringify(value);
        const address = "http://nmcheck.gnome.org/check_network_status.txt";

        // ── the address and the shell's file ──
        assert(rules.isUri(address) && rules.isUri("https://example.com:8443/x"), "http and https, a port, a path");
        for (const wrong of ["ftp://x/y", "http://x/a b", "http://x/a\nuri=evil", "http://x/\"q", "http://x/a\\b", "http://", "http://x:/", ""])
            assert(!rules.isUri(wrong), "not an address: " + json(wrong));
        assert(!rules.isUri("http://x/a\u0001b") && !rules.isUri("http://x/a\u007fb"), "… nor one with a control character (the root step refuses it too)");
        assertEqual(rules.text(address), "# Written by h2s-shell (Settings > System > Network)\n[connectivity]\nuri=" + address + "\n",
                    "the shell's file, as it has always written it");
        assert(rules.shellText(rules.text(address)), "… is the shell's");
        for (const [why, text] of [["edited", rules.text(address).replace("[connectivity]", "[connectivity]\nenabled=false")],
                                   ["another address in it, not one", rules.text("http://x/ y")], ["no line break last", rules.text(address).trim()],
                                   ["another first line", rules.text(address).replace("Network)", "Net)")], ["nothing", null]])
            assert(!rules.shellText(text), "not the shell's: " + why);

        // ── read after the shell's file ──
        for (const [path, after] of [["/etc/NetworkManager/conf.d/99-mine.conf", true], ["/etc/NetworkManager/conf.d/91.conf", true],
                                     ["/etc/NetworkManager/conf.d/20-connectivity.conf", false], ["/etc/NetworkManager/conf.d/90-a.conf", false],
                                     ["/etc/NetworkManager/NetworkManager.conf", false], ["/run/NetworkManager/conf.d/99-x.conf", false],
                                     ["/usr/lib/NetworkManager/conf.d/99-x.conf", false], ["/somewhere/else.conf", true],
                                     [EtcFilesRules.files[rules.kind], false], ["/etc/NetworkManager/nm-system-settings.conf", false],
                                     ["/run/current-system/sw/lib/NetworkManager/conf.d/99-x.conf", false]])
            assertEqual(rules.readAfterOwn(path), after, "read after the shell's file: " + path + " → " + after);

        // ── NetworkManager's files merged ──
        const record = (path, lines) => "file\t" + path + "\ttext\n" + lines.map(line => "|" + line + "\n").join("") + "end\t" + path + "\n";
        const main = "/etc/NetworkManager/NetworkManager.conf";
        assertEqual(json(rules.setting(record(main, ["[main]", "dns=default"]) + "done\n")), json({ state: "default", value: null, from: "", shadowed: null }), "no file sets it: the default");
        assertEqual(json(rules.setting(record(main, ["  # uri=http://no/", "[connectivity]", " uri = http://a/ ", "[main]", "uri=http://not/", "[connectivity]", "uri=http://b/"]) + "done\n")),
                    json({ state: "set", value: "http://b/", from: main, shadowed: null }), "comments, blanks, other groups; a group repeated is the same group, its last value wins");
        assertEqual(json(rules.setting(record(main, ["[connectivity]", "uri=http://a/"]) + record("/etc/NetworkManager/conf.d/50.conf", ["[connectivity]", "enabled=false"]) + "done\n")),
                    json({ state: "set", value: "http://a/", from: main, shadowed: null }), "a later file without the address leaves it");
        assertEqual(rules.setting(record(main, ["[connectivity]", "uri=http://a/"]) + record("/etc/NetworkManager/conf.d/50.conf", ["[connectivity]", "uri="]) + "done\n").value,
                    "", "a later file empties it");
        assertEqual(json(rules.setting(record("/usr/lib/NetworkManager/conf.d/20-connectivity.conf", ["[connectivity]", "uri=http://ping.archlinux.org/nm-check.txt"]) + "done\n")),
                    json({ state: "default", value: null, from: "/usr/lib/NetworkManager/conf.d/20-connectivity.conf", shadowed: null }), "only the distribution's package: its default");
        const ours = EtcFilesRules.files[rules.kind];
        assertEqual(json(rules.setting(record(main, ["[connectivity]", "uri=http://mine/"]) + record(ours, ["[connectivity]", "uri=http://shell/"]) + "done\n")),
                    json({ state: "set", value: "http://shell/", from: ours, shadowed: { from: main, value: "http://mine/" } }),
                    "the shell's file in force: the user's address it overrides");
        assertEqual(rules.setting(record("/usr/lib/NetworkManager/conf.d/20-connectivity.conf", ["[connectivity]", "uri=http://pkg/"])
                                  + record(ours, ["[connectivity]", "uri=http://shell/"]) + "done\n").shadowed, null, "… only the package's default: nothing overridden to show");
        assertEqual(rules.setting(record(main, ["[connectivity]", "uri=http://mine/"]) + record(ours, ["[connectivity]", "uri=http://shell/"])
                                  + record("/etc/NetworkManager/conf.d/99.conf", ["[connectivity]", "uri=http://last/"]) + "done\n").shadowed, null, "… another file wins: none");
        assertEqual(rules.setting(record("/run/current-system/sw/lib/NetworkManager/conf.d/20.conf", ["[connectivity]", "uri=http://pkg/"]) + "done\n").state, "default",
                    "NixOS's packages' conf.d: the default too");
        for (const [enable, state] of [["false", "default"], ["No", "default"], ["0", "default"], ["true", "set"], ["yes", "set"], ["nm-version-min:1.2", "unknown"]])
            assertEqual(rules.setting(record("/etc/NetworkManager/conf.d/50.conf", ["[connectivity]", "uri=http://a/", "[.config]", "enable=" + enable]) + "done\n").state, state,
                        "a conf.d file with [.config] enable=" + enable + ": " + state);
        assertEqual(rules.setting(record(main, ["[connectivity]", "uri=http://a/", "[.config]", "enable=false"]) + "done\n").state, "set",
                    "… the main file is never skipped");
        assertEqual(rules.setting(record("/etc/NetworkManager/conf.d/50.conf", ["[main]", "enable=false", "[connectivity]", "uri=http://a/"]) + "done\n").state, "set",
                    "… `enable` in another group: not that");
        assertEqual(rules.setting(record("/etc/NetworkManager/conf.d/50.conf", ["[connectivity]", "uri=http://a/", "[.config]", "garbage", "enable=false"]) + "done\n").state,
                    "default", "… a line that is no key there passed over");
        for (const [why, output] of [["not finished", record(main, [])], ["a file unreadable", "file\t" + main + "\tunreadable\ndone\n"],
                                     ["a folder not listed", "unknown\t/etc/NetworkManager/conf.d cannot be listed\ndone\n"], ["a record not closed", "file\t" + main + "\ttext\n|x\ndone\n"],
                                     ["a line after the end", "done\nfile\t" + main + "\ttext\n"], ["an end of another file", "file\t" + main + "\ttext\nend\t/x\ndone\n"],
                                     ["a record of another kind", record(main, ["[connectivity]", "uri=http://a/"]).replace(/^file/, "other") + "done\n"],
                                     ["a path not absolute", record("etc/x.conf", ["[connectivity]", "uri=http://a/"]) + "done\n"],
                                     ["a record with a field more", record(main, ["[connectivity]", "uri=http://a/"]).replace("\ttext\n", "\ttext\tx\n") + "done\n"],
                                     ["nothing read", null], ["empty", ""]])
            assertEqual(rules.setting(output).state, "unknown", "unknown: " + why);

        _offers(rules, address);
    }

    // The row's offer, from the integrations' own capabilities
    function _offers(rules, address) {
        const kind = rules.kind;
        const json = value => JSON.stringify(value);
        const made = [_arch.createObject(suite), _nixos.createObject(suite), _generic.createObject(suite)];
        const [arch, nixos, generic] = made.map(integration => integration.capability(kind));
        const snippet = made[1].plan(kind, address).preview.snippet;
        made.forEach(integration => integration.destroy());
        const ours = "/etc/NetworkManager/conf.d/90-h2s-connectivity.conf";
        const absent = { state: "absent", text: null, sha256: "absent", ours: false };
        const shells = { state: "text", text: rules.text("http://old/"), sha256: "a".repeat(64), ours: true };
        const edited = { state: "text", text: "[connectivity]\nuri=http://old/\n", sha256: "b".repeat(64), ours: false };
        const read = (file, extra) => Object.assign({ state: "default", value: null, from: "", elsewhere: "", file, afterOwn: false }, extra ?? {});
        const offer = extra => rules.offer(Object.assign({ field: address, current: "", capability: arch, snippet: "", inForce: read(absent), busy: "", undoable: false }, extra));
        const base = "The address it fetches now and then; saved in " + ours + ".";

        // Arch
        let answer = offer({});
        assert(answer.save.shown && answer.save.button === "plain" && answer.save.label === "Save" && answer.save.available, "Arch: Save");
        assertEqual(json(answer.save.request), json({ uri: address, current: absent, replace: false, anyway: false }), "… its effect: the address, against the file as read");
        assert(!answer.copy.shown && !answer.anyway.shown && !answer.anyway.available && !answer.undo.shown, "… nothing to copy, nothing anyway, no Undo yet");
        assertEqual(answer.hint, base, "… the line: where it is saved");
        assert(!offer({ current: address }).save.available, "the address in use: nothing to save");
        assert(!offer({ busy: "apply" }).save.available, "a change running: not clickable");
        assert(!offer({ inForce: null }).save.available && offer({ inForce: null }).save.button === "plain", "what is in force not read yet: Save, not clickable");
        answer = offer({ inForce: read(null, { state: "unknown" }) });
        assert(answer.save.button === "none" && !answer.save.available, "not readable: no Save");
        assertEqual(answer.hint, base + " NetworkManager's configuration could not be read.", "… said");
        assertEqual(offer({ inForce: read(null, { state: "set", value: "http://x/", from: "/x" }) }).save.button, "none", "the shell's file not read: no Save");
        answer = offer({ undoable: true });
        assert(answer.undo.shown && answer.undo.label === "Undo" && answer.undo.available, "after a change: Undo");
        assert(!offer({ undoable: true, busy: "undo" }).undo.available, "… not while one runs");
        assert(!offer({ undoable: true, capability: nixos }).undo.shown, "… never where copied");
        // Default: the shell's file removed
        answer = offer({ field: "", current: "http://old/", inForce: read(shells, { state: "set", value: "http://old/", from: ours }) });
        assert(answer.save.label === "Default" && answer.save.button === "plain" && answer.save.available, "the field emptied: Default");
        assertEqual(answer.save.tooltip, "Back to the distribution's address (none on some)", "… explained");
        assertEqual(json(answer.save.request), json({ uri: "", current: shells, replace: false, anyway: false }), "… its effect: the file removed");
        assert(!offer({ field: "", current: "http://ping.archlinux.org/nm-check.txt" }).save.available, "no file of the shell's: nothing to remove");
        assertEqual(offer({ field: "" }).save.label, "Save", "nothing in use, nothing typed: Save, not clickable");
        // Set in a file read after the shell's: shown, not overridden
        const later = "/etc/NetworkManager/conf.d/99-mine.conf";
        answer = offer({ inForce: read(absent, { state: "set", value: "http://mine/", from: later, elsewhere: later, afterOwn: true }) });
        assert(answer.save.button === "none" && !answer.save.available, "set in a file read after the shell's: no Save");
        assertEqual(answer.hint, base + " Set in " + later + ": http://mine/; it is read after the shell's file.", "… named with its value");
        assertEqual(offer({ inForce: read(absent, { state: "set", value: "", from: later, elsewhere: later, afterOwn: true }) }).hint,
                    base + " Set in " + later + ": no address; it is read after the shell's file.", "… an empty one: no address");
        assertEqual(offer({ inForce: read(absent, { state: "set", value: "http://x/" + "y".repeat(200), from: later, elsewhere: later, afterOwn: true }) }).hint.length,
                    (base + " Set in " + later + ": ").length + rules.shownLength + 1 + "; it is read after the shell's file.".length, "… a long one cut");
        const exact = "http://x/" + "y".repeat(rules.shownLength - 9);
        assert(offer({ inForce: read(absent, { state: "set", value: exact, from: later, elsewhere: later, afterOwn: true }) }).hint.includes(": " + exact + ";"),
               "… one just short enough shown whole");
        answer = offer({ field: "", current: "http://mine/", inForce: read(shells, { state: "set", value: "http://mine/", from: later, elsewhere: later, afterOwn: true }) });
        assert(answer.save.button === "plain" && answer.save.available, "… removing the shell's own file all the same: Default");
        // Set in the user's own NetworkManager.conf, read before: warned, Save asks
        const main = "/etc/NetworkManager/NetworkManager.conf";
        answer = offer({ inForce: read(absent, { state: "set", value: "http://mine/", from: main, elsewhere: main }) });
        assert(answer.save.button === "ask" && answer.save.question === "Use the shell's value instead?" && answer.save.available, "set in NetworkManager.conf: Save asks first");
        assertEqual(answer.hint, base + " Set in " + main + ": http://mine/.", "… named with its value");
        assertEqual(json(answer.save.request), json({ uri: address, current: absent, replace: false, anyway: false }), "… its effect");
        assertEqual(offer({ field: "", current: "x", inForce: read(shells, { state: "set", value: "http://mine/", from: main, elsewhere: main }) }).save.button, "plain",
                    "… removing the shell's file asks nothing (the user's own setting then applies)");
        // The shell's own file changed outside it: replaced or removed only asked
        answer = offer({ inForce: read(edited, { state: "set", value: "http://old/", from: ours }) });
        assert(answer.save.button === "ask" && answer.save.question === "Replace?", "the shell's file edited by hand: Save asks first");
        assertEqual(answer.hint, base + " " + ours + " was changed outside the shell: Save replaces it.", "… said");
        assertEqual(json(answer.save.request), json({ uri: address, current: edited, replace: true, anyway: false }), "… its effect replaces it");
        answer = offer({ field: "", current: "http://old/", inForce: read(edited, { state: "set", value: "http://old/", from: ours }) });
        assert(answer.save.button === "ask" && answer.save.question === "Remove?" && answer.save.request.replace, "… Default asks too");
        assertEqual(answer.hint, base + " " + ours + " was changed outside the shell: Default removes it.", "… said");
        answer = offer({ inForce: read(edited, { state: "set", value: "http://mine/", from: main, elsewhere: main }) });
        assertEqual(answer.save.question, "Replace?", "both: the file's question");
        assertEqual(answer.hint, base + " Set in " + main + ": http://mine/. " + ours + " was changed outside the shell: Save replaces it.", "… both said");
        // The user's own setting the shell's file overrides: shown, Default puts it back
        const overridden = read(shells, { state: "set", value: "http://old/", from: ours, shadowed: { from: main, value: "http://mine/" } });
        answer = offer({ inForce: overridden });
        assertEqual(answer.hint, base + " Set in " + main + ": http://mine/; the shell's file overrides it.", "the shell's file over the user's: said");
        assert(answer.save.button === "plain", "… Save asks nothing (the shell's file wins already)");
        answer = offer({ field: "", current: "http://old/", inForce: overridden });
        assert(answer.save.label === "Default" && answer.save.available && answer.save.button === "plain", "… Default puts the user's back");
        assertEqual(offer({ inForce: read(shells, { state: "set", value: "http://old/", from: ours, shadowed: { from: main, value: null } }) }).hint,
                    base + " Set in " + main + ": the default; the shell's file overrides it.", "… a setting of the default: said so");
        assertEqual(answer.enter, "save", "Enter: a plain Save");
        assertEqual(offer({ inForce: read(absent, { state: "set", value: "http://mine/", from: main, elsewhere: main }) }).enter, "", "… never a question's first click");
        answer = offer({ field: "ftp://x" });
        assert(!answer.save.available, "not an address: nothing to save");
        assertEqual(answer.hint, "An http:// or https:// address, without spaces or quotes.", "… said what it takes");

        // NixOS: the line to copy, and the file written anyway
        answer = offer({ capability: nixos, snippet });
        assert(!answer.save.shown && !answer.save.available, "NixOS: no Save");
        assert(answer.copy.shown && answer.copy.label === "Copy for configuration.nix" && answer.copy.available, "… the line to copy");
        assertEqual(answer.copy.text, "networking.networkmanager.settings.connectivity.uri = \"" + address + "\";", "… the option set to the address");
        assert(!offer({ capability: nixos, field: "" }).copy.available && !offer({ capability: nixos, field: "x y" }).copy.available, "… nothing to copy for no address or a wrong one");
        assert(answer.anyway.shown && answer.anyway.label === "Write anyway" && answer.anyway.button === "plain" && answer.anyway.available, "… Write anyway");
        assertEqual(answer.anyway.hint, "Add the copied line to your configuration.nix and rebuild — or write NetworkManager's file here, outside the system's configuration:",
                    "… what it means");
        assertEqual(json(answer.anyway.request), json({ uri: address, current: absent, replace: false, anyway: true }), "… its effect: written anyway");
        assertEqual(answer.hint, "The address it fetches now and then.", "… the line under it");
        assertEqual(answer.enter, "copy", "… Enter copies the line, never writes");
        assertEqual(offer({ capability: nixos, current: "http://old/" }).anyway.label, "Write anyway", "… another address over one in use: Write anyway");
        answer = offer({ capability: nixos, field: "", current: "http://old/", inForce: read(shells, { state: "set", value: "http://old/", from: ours }) });
        assert(answer.anyway.label === "Default" && answer.anyway.available && answer.anyway.request.uri === "", "… the field emptied: Default, removing the shell's file");
        answer = offer({ capability: nixos, inForce: read(absent, { state: "set", value: "http://cfg/", from: main, elsewhere: main }) });
        assert(answer.anyway.button === "ask" && answer.anyway.question === "Use the shell's value instead?", "set in the system's configuration: Write anyway asks");
        assertEqual(answer.hint, "The address it fetches now and then. Set in " + main + ": http://cfg/.", "… named");
        answer = offer({ capability: nixos, inForce: read(edited, { state: "set", value: "http://old/", from: ours }) });
        assertEqual(answer.hint, "The address it fetches now and then. " + ours + " was changed outside the shell: Write anyway replaces it.", "the file edited: said");
        assert(!offer({ capability: nixos, current: address }).anyway.available, "… the address in use: nothing to write");
        const copyOnly = IntegrationRules.capability({ [kind]: { mode: "copy", option: "o" } }, kind);
        answer = offer({ capability: copyOnly, inForce: read(edited, { state: "set", value: "http://old/", from: main, elsewhere: main }) });
        assert(!answer.anyway.shown && !answer.anyway.available, "copied without writing anyway: no Write anyway");
        assertEqual(answer.hint, "The address it fetches now and then.", "… and nothing said of writing");

        // Generic, and the distribution not known
        answer = offer({ capability: generic });
        assert(!answer.save.shown && !answer.save.available && !answer.copy.shown && !answer.anyway.shown, "generic: nothing offered");
        assertEqual(answer.hint, "The address it fetches now and then. Not supported on this distribution.", "… and why");
        answer = offer({ capability: IntegrationRules.unknownCapability() });
        assert(!answer.save.shown && !answer.copy.shown, "not known: nothing offered");
        assertEqual(answer.hint, "The address it fetches now and then.", "… nothing promised");
        assertEqual(offer({ capability: generic }).enter, "", "… Enter does nothing");

        // After a change
        const what = "Setting the connectivity check's address";
        assertEqual(rules.notice(what, { ok: true, warnings: [] }), null, "done: nothing to say");
        assertEqual(json(rules.notice(what, { ok: true, warnings: ["no nmcli: NetworkManager did not read its configuration again"] })),
                    json({ title: "NetworkManager did not take the change", body: "no nmcli: NetworkManager did not read its configuration again\nIt takes it when it starts again." }),
                    "done, NetworkManager not told: said");
        assertEqual(json(rules.notice(what, { ok: false, quiet: false, error: "The file changed since it was read: read it again." })),
                    json({ title: what + " failed", body: "The file changed since it was read: read it again." }), "failed: said why");
        assertEqual(rules.notice(what, { ok: false, quiet: true, error: "" }), null, "the prompt dismissed: nothing");
        assertEqual(json([arch.mode, arch.undo, nixos.mode, nixos.anyway, generic.mode]), json(["apply", true, "copy", true, "unavailable"]),
                    "the integrations: Arch applies with Undo, NixOS copies or writes anyway, generic not");
    }
}
