pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io
import qs.singletons.network

// NetworkManager's saved connection profiles, by UUID (Nmcli.profiles), and each Wi-Fi
// profile's SSID — names are the user's: they may repeat, or differ from the network they
// are for, so nothing is matched by name. Re-read when NetworkEvents reports a change.
Singleton {
    id: root

    // [{ uuid, name, type, kind, device, autoconnect, priority, lastUsed, active, port, state }]
    property var profiles: []
    // The list read at least once — empty, too (no NetworkManager profile at all); a failed
    // reading counts too, with `profiles` empty, so the views do not wait for ever
    property bool listRead: false
    // The last reading of the list worked: false while not read and after a failure (no
    // nmcli, NetworkManager not running) — the empty list is then unknown, never "none"
    // (Api.networksReady)
    property bool listOk: false
    property string _listProblem: ""
    // { uuid: { ssid, security, hidden, mode, band } } for the Wi-Fi profiles
    // (Nmcli.wifiDetails); mode "ap" is a hotspot
    property var wifi: ({})
    // { uuid: ssid } of the networks joined — not the hotspots, which are this computer's
    readonly property var ssids: {
        const map = {};
        for (const uuid in wifi)
            if (wifi[uuid].mode !== "ap")
                map[uuid] = wifi[uuid].ssid;
        return map;
    }

    function isHotspot(uuid: string): bool {
        return wifi[uuid]?.mode === "ap";
    }

    // The saved hotspots, each with its Wi-Fi details ({ uuid, name, active, …, ssid,
    // security, band, hidden }): the one on first, then the most recently used
    readonly property var hotspots: profiles.filter(profile => profile.kind === "wifi" && isHotspot(profile.uuid))
        .map(profile => Object.assign({}, profile, wifi[profile.uuid]))
        .sort((a, b) => (b.active - a.active) || (b.lastUsed - a.lastUsed))

    // The hotspot on now, or null — the Wi-Fi then serves it and joins no network (the
    // popup, the bar, the summary say so)
    readonly property var activeHotspot: hotspots.find(hotspot => hotspot.active) ?? null

    // The SSIDs some saved Wi-Fi network is for — the profiles listed now whose details are
    // read and are no hotspot (ModuleRules.savedWifiSsids: the rule the network popup's rows'
    // context keeps too)
    readonly property var savedSsids: ModuleRules.savedWifiSsids(profiles, wifi)

    // The profiles saved for the network named `ssid`
    function profilesForSsid(ssid: string): var {
        return profiles.filter(profile => profile.kind === "wifi" && ssids[profile.uuid] === ssid);
    }

    function refresh(): void {
        _list.request();
    }

    // A request while it runs drops that run's answer and runs again (LatestQuery): the
    // list kept is from after the last change reported
    LatestQuery {
        id: _list
        command: ["nmcli", "-t", "-f", "UUID,NAME,TYPE,DEVICE,AUTOCONNECT,AUTOCONNECT-PRIORITY,TIMESTAMP,ACTIVE,SLAVE,STATE", "connection", "show"]
        onAnswered: (lines, result) => {
            const problem = NetworkRules.readProblem(result, "nmcli");
            if (problem !== root._listProblem)
                console.warn("NetworkProfiles: the profiles " + (problem === "" ? "are read again" : "could not be read: " + problem));
            root._listProblem = problem;
            root.profiles = Nmcli.profiles(lines);
            root._awaitingList = false;
            root.listOk = problem === "";
            root.listRead = true;
            const wifi = root.profiles.filter(profile => profile.kind === "wifi");
            if (wifi.length === 0) {
                root.wifi = {};
                return;
            }
            const command = ["nmcli", "-t", "-f",
                "connection.uuid,802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless.hidden,802-11-wireless.mode,802-11-wireless.band", "connection", "show"];
            for (const profile of wifi)
                command.push("uuid", profile.uuid);
            _ssidQuery.command = command;
            _ssidQuery.request();
        }
    }

    CommandQuery {
        id: _ssidQuery
        onDone: lines => root.wifi = Nmcli.wifiDetails(lines)
    }

    // ── Changing a profile ── one command after another (CommandAction); a refusal for
    // want of rights goes to Authentication (the polkit prompt), another failure to a
    // notification naming the change. Connecting has a queue of its own: it waits for the
    // connection, up to 90 s, and must not hold up the rest. `busy` lasts until the list
    // is read again, so a second click at once (priority) does not start from the old value.
    readonly property bool busy: _action.busy || _awaitingList
    readonly property bool connecting: _connectAction.busy
    property bool _awaitingList: false

    CommandAction {
        id: _action
    }

    CommandAction {
        id: _connectAction
    }

    // A secret's read, apart from both queues: shown at once, whatever runs
    CommandAction {
        id: _secretAction
    }

    function _report(what, result) {
        if (result.ok)
            return;
        if (Nmcli.errorKind(result.error) === "auth")
            Authentication.reportDenied(what);
        else
            Notifier.send(what + " failed", { body: Nmcli.errorMessage(result.error) || ("Exit code " + result.code) });
    }

    function _change(what, command, done, queue, environment) {
        (queue ?? _action).run(command, result => {
            root._report(what, result);
            if (done)
                done(result.ok);
            if ((queue ?? _action) === _action)
                root._awaitingList = true;
            root.refresh();
        }, environment);
    }

    function nameOf(uuid) {
        const profile = profiles.find(entry => entry.uuid === uuid);
        return wifi[uuid]?.ssid || profile?.name || uuid;
    }

    // On `device` when given, so the device the page offers is the one used — NetworkManager
    // could otherwise pick another
    function activate(uuid: string, device: string): void {
        const command = ["nmcli", "connection", "up", "uuid", uuid];
        if (device)
            command.push("ifname", device);
        _change("Connecting to " + nameOf(uuid), command, null, _connectAction);
    }

    // Disconnects the device, not just the profile: `connection down` blocks only that
    // profile, and NetworkManager brings up another one that connects automatically on the
    // same device at once (a second wired profile, another saved network in range); the
    // device stays down until something is connected on it by hand
    function disconnectDevice(device: string, what: string): void {
        if (device === "")
            return;
        _change(what, ["nmcli", "device", "disconnect", device], null, _connectAction);
    }

    function setAutoconnect(uuid: string, on: bool): void {
        _change("Changing " + nameOf(uuid), ["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect", on ? "yes" : "no"]);
    }

    // Higher wins when several saved networks are in range; NetworkManager takes -999 to 999
    function setPriority(uuid: string, priority: int): void {
        const value = Math.max(-999, Math.min(999, priority));
        _change("Changing " + nameOf(uuid), ["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect-priority", String(value)]);
    }

    function setWifiPassword(uuid: string, password: string, done): void {
        const write = NetworkRules.modifyCommand(uuid, [["802-11-wireless-security.psk", password]]);
        _change("Changing the password of " + nameOf(uuid), write.command, done, null, write.environment);
    }

    // A saved secret ("802-11-wireless-security.psk"), handed to `done(value, ok)` — ""
    // when there is none or it cannot be read (ok false). Never logged. `--escape no`: in
    // -g form nmcli puts a backslash before ':' and '\', and "pass:word" read as "pass\:word".
    function readSecret(uuid: string, field: string, done): void {
        _secretAction.run(["nmcli", "--escape", "no", "-s", "-g", field, "connection", "show", "uuid", uuid],
            result => done(result.ok ? (result.lines[0] ?? "") : "", result.ok));
    }

    // A profile's settings for the editor (NetworkRules.settingsFrom), handed to `done`;
    // null when it cannot be read. A hotspot's password too, which the editor shows — read
    // as readSecret does, so a ':' or a space at its ends comes through as it is
    function readSettings(uuid: string, done): void {
        _secretAction.run(["nmcli", "-t", "-f", NetworkRules.editorFields.join(","), "connection", "show", "uuid", uuid], result => {
            const block = result.ok ? Nmcli.records(result.lines, "connection.id")[0] : null;
            const settings = block ? NetworkRules.settingsFrom(block) : null;
            if (settings?.wireguard) {
                root._readWireguardSecrets(uuid, settings, done);
                return;
            }
            if (!NetworkRules.isHotspot(settings) || settings.wifi.security === "") {
                done(settings);
                return;
            }
            // A secured hotspot always has one: "" means it could not be read — null, kept
            // as it is unless a new one is typed
            root.readSecret(uuid, "802-11-wireless-security.psk", password => {
                settings.wifi.password = password === "" ? null : password;
                done(settings);
            });
        });
    }

    // WireGuard's private key and peers (their preshared keys are secrets): null when they
    // could not be read — kept as they are then, and not editable (a save would lose the
    // preshared keys). A key read as "" is a profile with none: "", which the editor asks for.
    function _readWireguardSecrets(uuid, settings, done) {
        readSecret(uuid, "wireguard.private-key", (key, keyRead) => {
            settings.wireguard.privateKey = keyRead ? key : null;
            root.readSecret(uuid, "wireguard.peers", (peers, peersRead) => {
                settings.wireguard.peers = peersRead ? NetworkRules.wireguardPeers(peers) : null;
                done(settings);
            });
        });
    }

    // A new profile from the editor's settings (NetworkRules.createCommand); `created(token,
    // uuid)` follows, uuid "" when it failed — nmcli answers "Connection 'X' (<uuid>)
    // successfully added.". A signal, not a callback: the editor may be gone by then.
    signal created(int token, string uuid)
    property int _nextToken: 1

    function create(settings, what: string): int {
        const token = _nextToken++;
        const write = NetworkRules.createCommand(settings, Quickshell.env("USER") ?? "");
        _action.run(write.command, result => {
            root._report(what, result);
            const match = /\(([0-9a-f-]{36})\)/.exec(result.lines.join(" "));
            root.created(token, result.ok && match ? match[1] : "");
            root._awaitingList = true;
            root.refresh();
        }, write.environment);
        return token;
    }

    // ── Saving from the editor ── `saved(uuid, ok)` once a profile's settings were written
    // (or put back), ok false when that failed: the editor reads them again — or, after a
    // failure, keeps what was typed. Signals, not callbacks, here too.
    signal saved(string uuid, bool ok)

    function save(uuid: string, changes, what: string): void {
        modify(uuid, changes, what, ok => root.saved(uuid, ok));
    }

    // "Save and reconnect": the changes, the profile up again, then "Keep these settings?"
    // for 20 s — without an answer the old ones come back, so a wrong address on the only
    // link does not leave the computer cut off. Kept here, not in the editor: leaving the
    // page during the countdown must not drop the way back. The undo comes from the
    // settings read after the change against `previous` (what the editor had read), so it
    // writes back what really changed (a manual profile's addresses, say).
    // { uuid, name, changes } while the countdown runs, else null
    property var pendingUndo: null
    property int undoSecondsLeft: 0

    function saveAndReconnect(uuid: string, changes, previous, what: string): void {
        modify(uuid, changes, what, ok => {
            if (!ok) {
                root.saved(uuid, false);
                return;
            }
            root.reconnect(uuid, () => root.readSettings(uuid, current => {
                const undo = current ? NetworkRules.editorChanges(current, previous, Quickshell.env("USER") ?? "") : [];
                if (undo.length > 0) {
                    root.pendingUndo = { uuid: uuid, name: previous.name, changes: undo };
                    root.undoSecondsLeft = 20;
                    _undoCountdown.restart();
                }
                root.saved(uuid, true);
            }));
        });
    }

    function keepChanges(): void {
        _undoCountdown.stop();
        pendingUndo = null;
    }

    function revertChanges(): void {
        _undoCountdown.stop();
        const undo = pendingUndo;
        pendingUndo = null;
        if (!undo)
            return;
        modify(undo.uuid, undo.changes, "Going back to the old settings of " + undo.name, ok => {
            if (ok)
                root.reconnect(undo.uuid, () => root.saved(undo.uuid, true));
            else
                root.saved(undo.uuid, false);
        });
    }

    Timer {
        id: _undoCountdown
        interval: 1000
        repeat: true
        onTriggered: {
            if (--root.undoSecondsLeft <= 0)
                root.revertChanges();
        }
    }

    // A VPN's file made a profile: a WireGuard .conf ("wireguard"), or a plugin's (its name).
    // A WireGuard one is imported from a copy in a fresh folder of its own (mktemp -d, in
    // $XDG_RUNTIME_DIR when there is one: mode 700, removed at once — never a fixed name in
    // /tmp another user could have planted first) named for a valid interface; NetworkManager would bring it up at once
    // (autoconnect), a whole-traffic tunnel taking the internet over unasked — so it is
    // made manual, named after the file, and taken down if it came up. The key stays in
    // files, never on a command line others could read in `ps`.
    function importFile(path: string, type: string): void {
        const fileName = path.split("/").pop();
        if (type !== "wireguard") {
            _change("Importing " + fileName, ["nmcli", "connection", "import", "type", type, "file", path]);
            return;
        }
        const names = NetworkRules.wireguardImportNames(path);
        const script = 'umask 077; folder=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/h2s-vpn.XXXXXXXX") || exit 1; '
            + 'cp -- "$1" "$folder/$2.conf" || { rm -rf "$folder"; exit 1; }; '
            + 'out=$(nmcli connection import type wireguard file "$folder/$2.conf"); status=$?; rm -rf "$folder"; '
            + '[ $status -eq 0 ] || exit $status; '
            + 'uuid=$(printf "%s" "$out" | grep -oE "[0-9a-f-]{36}" | head -n1); '
            + 'nmcli connection modify uuid "$uuid" connection.autoconnect no connection.id "$3" || exit 1; '
            + 'nmcli connection down uuid "$uuid" >/dev/null 2>&1; printf "%s\\n" "$out"';
        _change("Importing " + fileName, ["sh", "-c", script, "sh", path, names.iface, names.name]);
    }

    // Takes a hotspot down by its profile: `device disconnect` would keep the Wi-Fi off
    // until something is connected by hand, and the saved network should come back
    function deactivate(uuid: string, what: string): void {
        _change(what, ["nmcli", "connection", "down", "uuid", uuid], null, _connectAction);
    }

    // Changes ([[property, value], …], NetworkRules.editorChanges) in one `nmcli connection
    // modify` — the secrets right after it, off the command line (NetworkRules
    // .modifyCommand); `done(ok)`
    function modify(uuid: string, changes, what: string, done): void {
        if (changes.length === 0) {
            if (done)
                done(true);
            return;
        }
        const write = NetworkRules.modifyCommand(uuid, changes);
        _change(what, write.command, done, null, write.environment);
    }

    // Brings a profile up again, so its changed settings apply; `done(ok)`
    function reconnect(uuid: string, done): void {
        _change("Reconnecting " + nameOf(uuid), ["nmcli", "connection", "up", "uuid", uuid], done, _connectAction);
    }

    function forget(uuids, what: string): void {
        if (uuids.length === 0)
            return;
        const command = ["nmcli", "connection", "delete"];
        for (const uuid of uuids)
            command.push("uuid", uuid);
        _change(what, command);
    }

    Connections {
        target: NetworkEvents
        function onChanged() {
            root.refresh();
        }
    }

    // The fallback for changes nmcli monitor does not print
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
