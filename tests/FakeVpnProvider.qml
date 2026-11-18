import QtQuick
import Quickshell.Io
import qs.components

// A stand-in VPN provider (components/VpnProvider.qml) for the tests — never part of the
// shell's UI. Scriptable: entries, states, attention, failures, slow operations, busy,
// canChange, the kill switch's note, extras for the slots. Used by tests/VpnProvidersTest
// .qml; and, by hand, in a shell started from a test tree with H2S_FAKE_VPN_PROVIDER=1
// (tests/test-tree.sh; tests/lock/README.md, "The test tree", says how to start one):
// VpnManager loads it then, with `ipc` on — `qs ipc call fakevpn <function> …`, see the
// IpcHandler below. The installed shell and a checkout never load it.
VpnProvider {
    id: root

    providerId: "fake"
    kind: "vpn"
    typeName: "Fake VPN"
    glyph: "󰖂"
    ready: true
    entries: []

    // Operations take this long (busy meanwhile, the entry activating / deactivating); 0 at once
    property int slowMs: 0
    // The next connect fails with this reason ("" none)
    property string failNext: ""
    // The next connect ends in this attention ({ reason, action }) instead of connecting
    property var attentionOnConnect: null
    // attend() clears the attention (the user did what was asked)
    property bool attendClears: true
    // What the core called: [[action, entryId, origin], …] (origin "" for attend, which has
    // no request)
    property var calls: []
    // Connecting needs a password (pkexec): asked by the user, the fake "prompts" (logged in
    // `prompts`) and connects; asked by a network, it must not — it sets attention instead
    property bool needsPrompt: false
    property var prompts: []

    // The extras for the slots, when wanted: plain text items that show their context
    property bool withExtras: false
    rowExtras: withExtras ? _rowExtras : null
    cardExtras: withExtras ? _cardExtras : null
    property Component _rowExtras: Component {
        Text {
            property var context: null
            text: "Fake row extras for " + (context?.entryId ?? "?")
            color: "gray"
        }
    }
    property Component _cardExtras: Component {
        Text {
            property var context: null
            text: "Fake card extras for " + (context?.entryId ?? "?") + (context?.open ? " (open)" : "")
            color: "gray"
        }
    }

    // A page of its own (slot network.vpn.page), when wanted
    property bool withPage: false
    pageUrl: withPage ? Qt.resolvedUrl("FakeVpnProviderPage.qml") : ""

    function _index(id) {
        return entries.findIndex(entry => entry.id === id);
    }

    function _change(id, fields) {
        const index = _index(id);
        if (index < 0)
            return;
        const list = entries.slice();
        list[index] = Object.assign({}, list[index], fields);
        entries = list;
    }

    function add(id, name) {
        if (_index(id) < 0)
            entries = entries.concat([{ id: id, name: name, state: "", attention: null,
                detail: { server: "relay.example.net", iface: "", addresses: [], dns: [] } }]);
    }

    function remove(id) {
        entries = entries.filter(entry => entry.id !== id);
    }

    function setState(id, state) {
        _change(id, { state: state, detail: Object.assign({}, entries[_index(id)]?.detail ?? {},
            { iface: state === "activated" ? "fake0" : "", addresses: state === "activated" ? ["100.64.0.2/32"] : [] }) });
    }

    function setAttention(id, reason, action) {
        _change(id, { attention: { reason: reason, action: action } });
    }

    function clearAttention(id) {
        _change(id, { attention: null });
    }

    function _nameOf(id) {
        return entries[_index(id)]?.name ?? id;
    }

    // The operation in progress: [entryId, the state it ends in]
    property var _pending: null

    function _finish() {
        busy = false;
        if (_pending !== null)
            setState(_pending[0], _pending[1]);
        _pending = null;
    }

    property Timer _timer: Timer {
        interval: Math.max(1, root.slowMs)
        onTriggered: root._finish()
    }

    function setStatus(id, text) {
        _change(id, { status: text });
    }

    function setBusy(id, on) {
        _change(id, { busy: on });
    }

    function connect(entryId, request) {
        const origin = request?.origin ?? "?";
        calls = calls.concat([["connect", entryId, origin]]);
        if (needsPrompt) {
            if (origin !== "user") {
                _change(entryId, { state: "", attention: { reason: "Connecting needs your password", action: "Connect" } });
                return;
            }
            prompts = prompts.concat([entryId]);
        }
        if (failNext !== "") {
            const reason = failNext;
            failNext = "";
            setState(entryId, "");
            root.failed(entryId, "Connecting " + _nameOf(entryId), reason);
            return;
        }
        if (attentionOnConnect !== null) {
            const attention = attentionOnConnect;
            attentionOnConnect = null;
            _change(entryId, { state: "", attention: attention });
            return;
        }
        if (slowMs > 0) {
            busy = true;
            _pending = [entryId, "activated"];
            setState(entryId, "activating");
            _timer.restart();
            return;
        }
        setState(entryId, "activated");
    }

    function disconnect(entryId, request) {
        calls = calls.concat([["disconnect", entryId, request?.origin ?? "?"]]);
        if (slowMs > 0) {
            busy = true;
            _pending = [entryId, ""];
            setState(entryId, "deactivating");
            _timer.restart();
            return;
        }
        setState(entryId, "");
    }

    function attend(entryId) {
        calls = calls.concat([["attend", entryId, ""]]);
        if (attendClears)
            clearAttention(entryId);
    }

    // ── By hand ── only in a test tree's shell started with H2S_FAKE_VPN_PROVIDER=1
    property bool ipc: false
    property IpcHandler _ipc: IpcHandler {
        target: "fakevpn"
        enabled: root.ipc

        function list(): string {
            return JSON.stringify(root.entries);
        }
        function add(id: string, name: string): void {
            root.add(id, name);
        }
        function remove(id: string): void {
            root.remove(id);
        }
        function state(id: string, state: string): void {
            root.setState(id, state);
        }
        function attention(id: string, reason: string, action: string): void {
            root.setAttention(id, reason, action);
        }
        function clear(id: string): void {
            root.clearAttention(id);
        }
        function failNext(reason: string): void {
            root.failNext = reason;
        }
        function slow(milliseconds: int): void {
            root.slowMs = milliseconds;
        }
        function canChange(on: bool): void {
            root.canChange = on;
        }
        function note(text: string): void {
            root.lockdownNote = text;
        }
        function extras(on: bool): void {
            root.withExtras = on;
        }
        function page(on: bool): void {
            root.withPage = on;
        }
        function status(id: string, text: string): void {
            root.setStatus(id, text);
        }
        function busy(id: string, on: bool): void {
            root.setBusy(id, on);
        }
        function needsPrompt(on: bool): void {
            root.needsPrompt = on;
        }
        // Garbage, to see that the views drop it: one entry of every wrong shape
        function garbage(): void {
            root.entries = root.entries.concat([null, 7, { id: "a:b", name: "colon", state: "" }, { id: "x", name: 5, state: "" },
                { id: "y", name: "bad state", state: "up" }]);
        }
    }
}
