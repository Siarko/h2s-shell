pragma Singleton

import Quickshell

// A VPN with a network — pure, tested in tests/VpnProvidersTest.qml and tests/NetworkTest.qml:
// which VPNs VpnManager brings up and takes down with the networks they are linked to, and
// the connection editor's list of linked VPNs.
Singleton {
    id: root

    // What the shell does when the profiles or the mapping
    // change (NetworkManager's connection.secondaries takes no WireGuard, and takes the
    // network down when the VPN fails). A VPN is wanted while some network it is linked to
    // in `mapping` ({ networkUuid: [vpnUuid…] }) is up; wanted and down, it is brought up,
    // unless taken down by hand; wanted by none, and brought up by the shell, it is taken
    // down once its networks are fully down (while one is still deactivating NetworkManager
    // takes a plugin VPN down itself). `memory` ({ broughtUp: { vpn: true }, pending: { vpn:
    // ms }, heldDown: { vpn: key } }) is kept between calls and across restarts:
    //   pending  — asked to connect at that time, not seen up yet: still down then is not
    //              "by hand" (the list can be read before NetworkManager says activating);
    //              still down 90 s later, it failed — held down, not retried in a loop
    //   heldDown — went down while wanted, not by the shell: left down until the networks
    //              wanting it change (`key`, the ones up then)
    // `now` the time in ms.
    // `providerVpns` (optional): the VPNs of providers (VpnManager, "<provider>:<id>"), in
    // the same shape ({ uuid, state, attention }) — considered only once the profiles are
    // read (with none, nothing is known of the networks: a VPN would look unwanted and be
    // taken down). A VPN that needs the user (`attention` set: log in, approve…) is never
    // asked to connect; one that went there after being asked (or after being brought up) is
    // held down like a failure, so it is not retried in a loop — tried again only when the
    // networks change. Attention within vpnAttentionGraceMs of being asked is waited out
    // (still pending): a provider passing through it on its way up (activating → attention
    // → activated) is not held down; one still needing the user after that is. (Attention
    // reached from up — brought up, then down with attention — is held down at once; a
    // provider must not use attention for transient states.) One that needed the user
    // before it was ever asked is asked once the attention is gone. A VPN of a provider that
    // is not there (a module disabled, not loaded yet) is left alone, its memory kept while
    // the mapping still names it (pending and held-down memory of an id neither known nor in
    // the mapping is dropped).
    // → { connect [], disconnect [], memory }
    function vpnWithNetworkPlan(profiles, mapping, memory, now, providerVpns) {
        const states = {};
        const attention = {};
        const known = (profiles ?? []).length > 0 ? (profiles ?? []).concat(providerVpns ?? []) : [];
        for (const profile of known) {
            states[profile.uuid] = profile.state ?? "";
            attention[profile.uuid] = !!profile.attention;
        }
        const broughtUp = Object.assign({}, memory?.broughtUp ?? {});
        const pending = Object.assign({}, memory?.pending ?? {});
        const heldDown = Object.assign({}, memory?.heldDown ?? {});
        const vpns = [];
        for (const network in mapping ?? {})
            for (const vpn of mapping[network] ?? [])
                if (!vpns.includes(vpn))
                    vpns.push(vpn);
        for (const vpn of Object.keys(broughtUp))
            if (!vpns.includes(vpn))
                vpns.push(vpn);
        const connect = [];
        const disconnect = [];
        // Memory of what is neither known nor wanted any more: nothing would ever settle it
        // (and the 30 s re-check would run for it for ever)
        for (const vpn of Object.keys(pending).concat(Object.keys(heldDown)))
            if (!(vpn in states) && !vpns.includes(vpn)) {
                delete pending[vpn];
                delete heldDown[vpn];
            }
        for (const vpn of vpns) {
            if (!(vpn in states))
                continue;
            const linked = Object.keys(mapping ?? {}).filter(network => (mapping[network] ?? []).includes(vpn));
            const upNetworks = linked.filter(network => states[network] === "activated").sort();
            const settling = linked.some(network => states[network] === "deactivating" || states[network] === "activating");
            const key = upNetworks.join(" ");
            const state = states[vpn];
            const vpnUp = state === "activated" || state === "activating";
            if (vpnUp)
                delete pending[vpn];
            if (vpn in heldDown && heldDown[vpn] !== key)
                delete heldDown[vpn];
            if (upNetworks.length > 0) {
                if (state !== "")
                    continue;
                if (attention[vpn]) {
                    // Asked moments ago: perhaps passing through on its way up — waited out
                    if (vpn in pending && now - pending[vpn] < vpnAttentionGraceMs)
                        continue;
                    // Asked to connect and now waiting for the user: a failure, held down
                    if (vpn in pending || broughtUp[vpn]) {
                        delete pending[vpn];
                        delete broughtUp[vpn];
                        heldDown[vpn] = key;
                    }
                    continue;
                }
                if (vpn in pending) {
                    if (now - pending[vpn] > 90000) {
                        delete pending[vpn];
                        delete broughtUp[vpn];
                        heldDown[vpn] = key;
                    }
                    continue;
                }
                if (broughtUp[vpn]) {
                    // Brought up, seen up, now down without the shell: by hand
                    delete broughtUp[vpn];
                    heldDown[vpn] = key;
                    continue;
                }
                if (vpn in heldDown)
                    continue;
                connect.push(vpn);
                broughtUp[vpn] = true;
                pending[vpn] = now;
            } else {
                delete pending[vpn];
                if (!broughtUp[vpn])
                    continue;
                if (state === "")
                    delete broughtUp[vpn];
                else if (state === "activated" && !settling) {
                    disconnect.push(vpn);
                    delete broughtUp[vpn];
                }
            }
        }
        return { connect: connect, disconnect: disconnect, memory: { broughtUp: broughtUp, pending: pending, heldDown: heldDown } };
    }

    // How long attention right after being asked is taken as passing (vpnWithNetworkPlan)
    readonly property int vpnAttentionGraceMs: 20000

    // The mapping without profiles that are gone; `profiles` empty (not read yet): as it is.
    // A provider's VPN ("<provider>:<id>") is NEVER removed here, whatever its provider says
    // and whether it is there at all: a provider logged out, stopped, unreadable for one
    // read, ready too early or renaming an entry must not make the shell delete the user's
    // setting. One its provider does not report now is "not available" (unavailableVpnIds):
    // kept, shown as such in the network's editor, removed only by the user there.
    // An id that can be neither a UUID nor a provider's (vpnIdParts) is removed.
    function prunedVpnMapping(mapping, profiles) {
        if ((profiles ?? []).length === 0)
            return mapping ?? {};
        const uuids = profiles.map(profile => profile.uuid);
        const keeps = vpn => {
            const parts = VpnProviderRules.vpnIdParts(vpn);
            return parts !== null && (parts.provider !== "" || uuids.includes(vpn));
        };
        const pruned = {};
        for (const network in mapping ?? {}) {
            if (!uuids.includes(network))
                continue;
            const vpns = (mapping[network] ?? []).filter(keeps);
            if (vpns.length > 0)
                pruned[network] = vpns;
        }
        return pruned;
    }

    function _vpnIdsOf(vpns) {
        return (vpns ?? []).map(vpn => typeof vpn === "string" ? vpn : vpn?.uuid);
    }

    // The one definition of "not available": the provider VPNs among `ids` (a list, or a
    // mapping { network: [id…] }) that are not among `vpns` now (VpnManager.vpns, or their
    // ids) — whatever the reason: provider not registered, not ready, logged out, the entry
    // missing from one read. [id…], each once, in their order.
    function unavailableVpnIds(ids, vpns) {
        const all = Array.isArray(ids) ? ids
            : Object.keys(ids ?? {}).reduce((list, network) => list.concat(ids[network] ?? []), []);
        const present = _vpnIdsOf(vpns);
        const found = [];
        for (const vpn of all) {
            const parts = VpnProviderRules.vpnIdParts(vpn);
            if (parts !== null && parts.provider !== "" && !present.includes(vpn) && !found.includes(vpn))
                found.push(vpn);
        }
        return found;
    }

    // The network editor's starting list for "VPN with a network", from the stored one:
    // NetworkManager's VPNs still there (one deleted would stay picked, unseen and
    // unremovable) and EVERY provider VPN, available or not (the editor shows the not
    // available ones as removable pills)
    function editorVpnIds(stored, vpns) {
        const present = _vpnIdsOf(vpns);
        const kept = [];
        for (const vpn of stored ?? []) {
            const parts = VpnProviderRules.vpnIdParts(vpn);
            if (parts !== null && (parts.provider !== "" || present.includes(vpn)) && !kept.includes(vpn))
                kept.push(vpn);
        }
        return kept;
    }

    // What the network editor writes for "VPN with a network": the user's picks (`edited`),
    // plus every provider VPN of the value stored now (`stored`) that the user did not take
    // out — taken out: in the list the editor started from (`original`), not in `edited`. A
    // provider id the editor did not show is never lost.
    function vpnsToWrite(stored, original, edited) {
        const picks = edited ?? [];
        const result = picks.filter((vpn, index) => picks.indexOf(vpn) === index);
        const removed = (original ?? []).filter(vpn => !picks.includes(vpn));
        for (const vpn of stored ?? []) {
            const parts = VpnProviderRules.vpnIdParts(vpn);
            if (parts !== null && parts.provider !== "" && !removed.includes(vpn) && !result.includes(vpn))
                result.push(vpn);
        }
        return result;
    }
}
