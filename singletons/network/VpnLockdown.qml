pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io
import Quickshell.Io
import qs.singletons.network

// Only through the VPN (a kill switch; docs/plans/network.md, VPN stage 7): the nftables
// table built by scripts/h2s-vpn-lockdown, switched on while the blocking is wanted —
// always, or while a network it is set for is up — and off when it is not. The script runs
// as root through pkexec:
//   - installed (a copy root owns, and a polkit rule letting this user run it without a
//     password — "Password-free blocking" on the VPN page): no password, and its `status`
//     is asked at the start, after network events and every 5 minutes, so a firewall
//     reload that dropped the table is mended;
//   - not installed: the shell's own copy, asking for the password at each switch; what
//     was switched on, in which boot, is remembered in Config (root's to read back).
// Switched again only when its arguments change (a VPN's interface or server, the local
// network), a moment after the last change. Rules loaded by a script older than the
// shell's copy (the script records its VERSION with them; `status` reports it) are switched
// on again by themselves only when no password is needed; otherwise they stay, and the page
// says so (staleRules) until the user applies them again or installs the script. A
// refused password is not asked again by itself: the page offers "Apply again"; installing
// the script, so that none is needed, lifts a refusal to switch on (never one to switch
// off). Started with the shell (shell.qml).
//
// Per network, the blocking comes a moment after the network is up (and, without the
// installed script, after the password): until then nothing is blocked. "Always" has no
// such gap.
Singleton {
    id: root

    readonly property bool always: Profiles.value("system.vpnLockdownAlways") ?? false
    readonly property bool allowLan: Profiles.value("system.vpnLockdownLan") ?? false
    // Servers of VPNs outside NetworkManager (wg-quick's…), by address: let through too
    readonly property string _extraText: JSON.stringify(Profiles.value("system.vpnLockdownServers") ?? [])
    readonly property var extraServers: JSON.parse(_extraText).filter(address => NetworkRules.isLockdownAddress(address))
    // Through its text: Profiles.value is a new object on every profile fact (battery…)
    readonly property string _networksText: JSON.stringify(Profiles.value("system.vpnLockdownNetworks") ?? [])
    readonly property var networks: JSON.parse(_networksText)

    readonly property bool wanted: NetworkRules.lockdownWanted(NetworkProfiles.profiles, always, networks)

    // Blocking is on, or about to be: what the provider VPNs' note goes by
    readonly property bool blocking: wanted || state === "on"

    // What to say on a provider VPN's row and card while blocking: the blocking does not let
    // it through (NetworkRules.lockdownProviderNote; the provider's own lockdownNote if it
    // has one). "" for NetworkManager's VPNs, and when there is nothing to say. The popup's
    // row: while the VPN is up or coming up; the VPN page's card (`whateverState` true):
    // whenever blocking is on, connected or not — the page states the limit (tailscale.md §8).
    function noteFor(vpn, whateverState): string {
        if (vpn?.type !== "provider")
            return "";
        return NetworkRules.lockdownProviderNote(blocking, vpn, VpnManager.providerOf(vpn)?.lockdownNote ?? "", whateverState === true);
    }

    // ── The script ──
    // The shell's own copy (shown on the page; run with a password when not installed)
    readonly property string scriptPath: Quickshell.shellDir + "/scripts/h2s-vpn-lockdown"
    // Where "Install" puts it (root's, with a copy of its polkit rule beside it to read),
    // and where a NixOS module puts it
    readonly property string installFolder: "/usr/local/libexec/h2s-vpn-lockdown"
    readonly property string installedPath: installFolder + "/h2s-vpn-lockdown"
    readonly property string polkitRulePath: "/etc/polkit-1/rules.d/49-h2s-vpn-lockdown.rules"
    readonly property string nixosPath: "/run/current-system/sw/bin/h2s-vpn-lockdown"
    readonly property string user: Quickshell.env("USER") ?? ""
    // Its text, shown in full on the page, and NixOS's module made from it
    readonly property string scriptText: _scriptFile.text()
    readonly property string nixosModule: NetworkRules.lockdownNixosModule(scriptText, user)
    FileView {
        id: _scriptFile
        path: root.scriptPath
        watchChanges: true
        onFileChanged: reload()
    }

    // The version of the shell's copy, and of the one installed (0 none); where that is;
    // whether its polkit rule is there for this user (as installed: the rules' folder is
    // root's to read on most systems, NixOS's is open); NixOS
    property int scriptVersion: 0
    property int installedVersion: 0
    property string installedAt: ""
    property bool ruleInstalled: false
    property bool isNixos: false
    property bool nftFound: false
    property bool checked: false
    // A password was asked for while running the installed script: its rule does not apply
    property bool installedAsks: false

    // "none", "outdated", "asks", "ready"
    readonly property string helperState: installedVersion === 0 || !ruleInstalled ? "none"
        : installedVersion < scriptVersion ? "outdated"
        : installedAsks ? "asks" : "ready"
    readonly property bool passwordFree: helperState === "ready"

    // ── The blocking ──
    // "off", "on", "asking" (the password is being asked for), "working", "failed"
    property string state: "off"
    property string failure: ""

    // The interfaces let through as VPNs, besides tun*, wg* and the like: the WireGuard
    // profiles' own — as set, not as up, so a VPN connecting changes nothing. NetworkManager's
    // VPNs only: the blocking does not support provider VPNs (Tailscale; the owner's decision,
    // docs/plans/tailscale.md §8) — what a provider reports never reaches the script.
    readonly property var vpnInterfaces: VpnManager.nmInterfaceNames.slice().sort()
    // The VPN servers' names and addresses as set (every peer's, every remote) — of
    // NetworkManager's VPNs only, as above
    readonly property var _hostList: Array.from(new Set(Object.values(VpnManager.nmDetails)
        .reduce((all, detail) => all.concat(detail.servers ?? []), []).map(server => NetworkRules.serverHost(server))
        .filter(host => host !== ""))).sort()
    readonly property string _hosts: _hostList.join(" ")
    // { host: [addresses] } as last found; a host not found again keeps its addresses
    property var _serverMap: ({})
    readonly property var servers: Array.from(new Set(_hostList.reduce((all, host) =>
        all.concat(NetworkRules.isIpAddress(host) ? [host] : (_serverMap[host] ?? [])), []).concat(extraServers))).sort()

    // The script's arguments as they would be now, and the status it would report
    // (not "arguments": inside a function that name is the function's own)
    readonly property var switchArguments: NetworkRules.lockdownArguments({ vpnInterfaces: vpnInterfaces, servers: servers, allowLan: allowLan })
    readonly property string expectedStatus: NetworkRules.lockdownStatusOf(switchArguments)

    property string _bootId: ""
    // The memory read once Config has loaded and the boot is known (read before, it would
    // be the empty default: blocking loaded, shown as off)
    property bool _memoryRead: false

    function _readMemory() {
        const memory = _memory();
        _serverMap = memory.serverMap ?? {};
        // Switched on in this boot: on. In an earlier one: gone with the reboot.
        _status = memory.status && memory.bootId === _bootId ? memory.status : "off";
        _rulesVersion = _status.startsWith("on") ? (parseInt(memory.rules) || 0) : 0;
        state = _status.startsWith("on") ? "on" : "off";
        _memoryRead = true;
    }
    // The status the script last reported, or the one remembered for this boot
    property string _status: ""
    // The version of the script that switched the loaded rules on (0 unknown: from before
    // version 4); rules older than the shell's copy are switched on again by themselves only
    // when the script is password-free, otherwise kept until the user asks (staleRules)
    property int _rulesVersion: 0
    // A refused or failed switch (its status, or "off"): not tried again by itself until
    // something changes, or "Apply again"
    property string _refused: ""

    function _memory() {
        try {
            return JSON.parse(Config.network.lockdown || "{}");
        } catch (error) {
            return {};
        }
    }

    function _remember(memory) {
        Config.network.lockdown = JSON.stringify(memory);
    }

    function start(): void {
        checkScript();
        _bootIdRead.request();
    }

    // ── Looking at the script ──
    function checkScript(): void {
        _scriptCheck.request();
    }

    CommandQuery {
        id: _scriptCheck
        command: ["sh", "-c",
            'version() { sed -n "s/^VERSION=\\([0-9]*\\).*/\\1/p" "$1" 2>/dev/null | head -n1; }; '
            + 'echo "script $(version "$1")"; '
            + 'if [ -x "$2" ]; then echo "installed $(version "$2") $2"; elif [ -x "$4" ]; then echo "installed $(version "$4") $4"; fi; '
            + 'if grep -qs "h2s-vpn-lockdown" "$3" && grep -qs "subject.user == \\"$5\\"" "$3"; then echo "rule yes"; '
            + 'elif cat /etc/static/polkit-1/rules.d/*.rules 2>/dev/null | grep -q "h2s-vpn-lockdown"; then '
            + '  if cat /etc/static/polkit-1/rules.d/*.rules | grep -q "subject.user == \\"$5\\""; then echo "rule yes"; fi; fi; '
            + '[ -e /etc/NIXOS ] && echo "nixos"; '
            + 'for place in /usr/sbin/nft /usr/bin/nft /sbin/nft /bin/nft /run/current-system/sw/bin/nft; do [ -x "$place" ] && echo "nft" && break; done; true',
            "sh", root.scriptPath, root.installedPath, root.installFolder + "/polkit.rules", root.nixosPath, root.user]
        onDone: lines => {
            let script = 0, installed = 0, at = "", rule = false, nixos = false, nft = false;
            for (const line of lines) {
                const parts = line.trim().split(" ");
                if (parts[0] === "script")
                    script = parseInt(parts[1]) || 0;
                else if (parts[0] === "installed") {
                    installed = parseInt(parts[1]) || 0;
                    at = parts[2] ?? "";
                } else if (parts[0] === "rule")
                    rule = true;
                else if (parts[0] === "nixos")
                    nixos = true;
                else if (parts[0] === "nft")
                    nft = true;
            }
            const changed = installed !== root.installedVersion || at !== root.installedAt;
            root.scriptVersion = script;
            root.installedVersion = installed;
            root.installedAt = at;
            root.ruleInstalled = rule;
            root.isNixos = nixos;
            root.nftFound = nft;
            root.checked = true;
            if (changed)
                root.installedAsks = false;
            root._schedule();
        }
    }

    CommandQuery {
        id: _bootIdRead
        command: ["cat", "/proc/sys/kernel/random/boot_id"]
        onDone: lines => {
            root._bootId = (lines[0] ?? "").trim();
            root._schedule();
        }
    }

    // A password asked for while the installed script runs: its rule does not apply
    Connections {
        target: Authentication
        function onFlowChanged() {
            // Only pkexec's own question, while the installed script switches (not its
            // status check, which another program's prompt could fall on)
            if (Authentication.flow !== null && root._switchingInstalled
                    && (Authentication.flow.actionId ?? "") === "org.freedesktop.policykit.exec")
                root.installedAsks = true;
        }
    }
    property bool _runningInstalled: false
    property bool _switchingInstalled: false

    // A refusal is for the moment it was given: wanted or not again, it is asked afresh
    onWantedChanged: {
        _refused = "";
        _schedule();
    }
    onExpectedStatusChanged: _schedule()
    on_HostsChanged: _schedule()
    // A password refused for switching on is no reason to hold back once none is needed (the
    // script installed): its status is asked, and stale or changed rules switched on again. A
    // refused switch-off stays refused: installing never takes the blocking down by itself.
    onPasswordFreeChanged: {
        if (passwordFree) {
            if (_refused !== "off")
                _refused = "";
            _askedAtStart = false;
        }
        _schedule();
    }
    Connections {
        target: VpnManager
        function onDetailsReadChanged() {
            root._schedule();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root._schedule();
        }
    }
    // Networks that are gone leave the setting (none read yet: nothing is pruned)
    Connections {
        target: NetworkProfiles
        function onProfilesChanged() {
            const profiles = NetworkProfiles.profiles;
            if (profiles.length === 0 || !Config.ready)
                return;
            const kept = root.networks.filter(uuid => profiles.some(profile => profile.uuid === uuid));
            if (kept.length !== root.networks.length)
                Profiles.setGlobal("system.vpnLockdownNetworks", kept);
        }
    }

    function setExtraServers(addresses): void {
        Profiles.setGlobal("system.vpnLockdownServers", addresses.filter(address => NetworkRules.isLockdownAddress(address)));
    }

    // More servers' addresses than the script takes: the rest left out (said on the page)
    readonly property bool tooManyServers: servers.filter(address => NetworkRules.isLockdownAddress(address)).length > NetworkRules.lockdownMostAddresses

    function isSetFor(networkUuid: string): bool {
        return networks.includes(networkUuid);
    }

    function setFor(networkUuid: string, on: bool): void {
        const others = networks.filter(uuid => uuid !== networkUuid);
        Profiles.setGlobal("system.vpnLockdownNetworks", on ? others.concat([networkUuid]) : others);
    }

    function _schedule() {
        _settle.restart();
    }

    // A moment's wait after the last change, so changes in a row switch once: longer when
    // each switch asks for the password
    Timer {
        id: _settle
        interval: root.passwordFree ? 800 : 3000
        onTriggered: root._follow(false)
    }

    // With the installed script, its status asked: once at the start (a table the memory
    // missed), after network events (a firewall reload — nixos-rebuild with nftables,
    // `systemctl restart nftables` — may have dropped it), and every 5 minutes besides;
    // each run is a pkexec line in the journal, so not more often
    Timer {
        interval: 300000
        repeat: true
        running: root.passwordFree && (root.wanted || root._status.startsWith("on"))
        onTriggered: root._askStatus()
    }
    Timer {
        id: _statusSoon
        interval: 5000
        onTriggered: root._askStatus()
    }
    Connections {
        target: NetworkEvents
        function onChanged() {
            if (root.passwordFree && (root.wanted || root._status.startsWith("on")))
                _statusSoon.restart();
        }
    }
    property bool _askedAtStart: false

    function _askStatus() {
        if (_action.busy || !passwordFree)
            return;
        _runScript(["status"], result => {
            if (result.ok) {
                const reply = NetworkRules.lockdownStatusReply(result.lines);
                root._status = reply.status;
                root._rulesVersion = reply.rules;
                root.state = root._status.startsWith("on") ? "on" : "off";
            }
            root._schedule();
        });
    }

    // Asked again after a refusal, the servers' addresses found anew
    function apply(): void {
        _refused = "";
        _follow(true);
    }

    // The decision is NetworkRules.lockdownNextStep's, from the state as it is now: nothing
    // is used up by a call that has to wait (busy, not ready) — the next one decides again
    function _follow(force) {
        // The VPNs' interfaces and servers read first: arguments made without them would
        // differ from the ones switched on, and switch again at every start
        const ready = Config.ready && checked && _bootId !== "" && VpnManager.detailsRead;
        const busy = _action.busy || _resolve.running;
        if (ready && !busy && !_memoryRead)
            _readMemory();
        const step = NetworkRules.lockdownNextStep({
            ready: ready, busy: busy, passwordFree: passwordFree, askedAtStart: _askedAtStart, force: force === true,
            wanted: wanted, nftFound: nftFound, status: _status, rulesVersion: _rulesVersion,
            expectedStatus: expectedStatus, scriptVersion: scriptVersion, refused: _refused, hosts: _hosts
        });
        if (step === "ask") {
            _askedAtStart = true;
            _askStatus();
        } else if (step === "no-nft") {
            state = "failed";
            failure = "nftables is not installed: the blocking needs it.";
        } else if (step === "refused") {
            state = "failed";
        } else if (step === "on") {
            _findServersThenSwitchOn();
        } else if (step === "off") {
            _switchOff();
        } else if (step === "idle") {
            // Nothing to do: a refusal from before is not carried to the next time
            _refused = "";
            state = "off";
            failure = "";
        }
    }

    // Rules loaded by a script older than the shell's copy: switched on again by themselves
    // only when no password is needed; else kept, and said on the page until the user
    // applies them again or installs the script
    readonly property bool staleRules: checked && _status.startsWith("on") && _rulesVersion < scriptVersion

    // Whether what is loaded differs from what is wanted (the page offers "Apply again"):
    // stale rules included
    readonly property bool mismatched: checked && state !== "asking" && state !== "working"
        && (state === "failed" || wanted !== _status.startsWith("on") || (wanted && staleRules))

    // The servers by their names, each found through the system's resolver; those not
    // found keep their last addresses
    function _findServersThenSwitchOn() {
        const names = _hostList.filter(host => !NetworkRules.isIpAddress(host));
        if (names.length === 0) {
            _switchOn();
            return;
        }
        _resolve.command = ["sh", "-c", 'for host in "$@"; do getent ahosts "$host" | while read -r address rest; do echo "$host $address"; done; done; true',
            "sh"].concat(names);
        _resolve.request();
    }

    CommandQuery {
        id: _resolve
        onDone: lines => {
            const map = Object.assign({}, root._serverMap, NetworkRules.addressesByHost(lines));
            if (JSON.stringify(map) !== JSON.stringify(root._serverMap))
                root._serverMap = map;
            Qt.callLater(root._switchOn);
        }
    }

    CommandAction {
        id: _action
    }

    // The installed script without a password; else the shell's own copy, through sh,
    // with one
    function _runScript(scriptArguments, done) {
        const installed = passwordFree;
        const command = installed ? ["pkexec", installedAt].concat(scriptArguments)
            : ["pkexec", "sh", scriptPath].concat(scriptArguments);
        _runningInstalled = installed;
        _switchingInstalled = installed && scriptArguments[0] !== "status";
        _action.run(command, result => {
            root._runningInstalled = false;
            root._switchingInstalled = false;
            done(result);
        });
    }

    function _switchOn() {
        if (_action.busy)
            return;
        const scriptArguments = switchArguments.slice();
        const status = expectedStatus;
        const hosts = _hosts;
        // The script that runs: the installed one without a password, else the shell's copy
        const version = passwordFree ? installedVersion : scriptVersion;
        state = passwordFree ? "working" : "asking";
        _runScript(scriptArguments, result => {
            if (result.ok) {
                root._status = status;
                root._rulesVersion = version;
                root.state = "on";
                root.failure = "";
                root._refused = "";
                root._remember({ status: status, rules: version, bootId: root._bootId, serverMap: root._serverMap });
            } else {
                root._fail(status + hosts, result, "Blocking traffic outside the VPN");
            }
            root._schedule();
        });
    }

    function _switchOff() {
        state = passwordFree ? "working" : "asking";
        _runScript(["off"], result => {
            if (result.ok) {
                root._status = "off";
                root._rulesVersion = 0;
                root.state = "off";
                root.failure = "";
                root._refused = "";
                root._remember({ serverMap: root._serverMap });
            } else {
                root._fail("off", result, "Letting traffic outside the VPN through");
            }
            root._schedule();
        });
    }

    // pkexec: 126 cancelled or refused, 127 no agent answered
    function _fail(refused, result, what) {
        _refused = refused;
        state = _status.startsWith("on") ? "on" : "failed";
        failure = result.code === 126 ? "Not done: the password was not given."
            : result.code === 127 ? "Not done: no authentication agent answered."
            : (result.error || ("Exit code " + result.code));
        if (result.code === 127)
            Authentication.reportDenied(what);
        else if (result.code !== 126)
            Notifier.send(what + " failed", { body: failure });
    }

    // ── Installing and removing the script ── each once, with the password: the script
    // copied where root owns it, its polkit rule into polkit's rules (and a copy beside the
    // script, which anyone may read). NixOS keeps /etc itself: its module is shown instead.
    readonly property string polkitRule: NetworkRules.lockdownPolkitRule(user, ['"' + installedPath + '"'])
    property string installFailure: ""

    function install(): void {
        installFailure = "";
        _install.run(["pkexec", "sh", "-c",
            'set -e; install -d -m 0755 -o root -g root "$2"; install -m 0755 -o root -g root "$1" "$2/h2s-vpn-lockdown"; '
            + 'printf "%s" "$3" > "$2/polkit.rules"; chmod 0644 "$2/polkit.rules"; '
            // polkit's rules folder kept as it is (root's to read on Arch: 0750 root:polkitd)
            + '[ -d "$(dirname "$4")" ] || install -d -m 0750 "$(dirname "$4")"; install -m 0644 -o root -g root "$2/polkit.rules" "$4"',
            "sh", scriptPath, installFolder, polkitRule, polkitRulePath], result => root._installed(result, "Installing the blocking script"));
    }

    function uninstall(): void {
        installFailure = "";
        _install.run(["pkexec", "sh", "-c", 'rm -f "$2"; rm -rf "$1"', "sh", installFolder, polkitRulePath],
            result => root._installed(result, "Removing the blocking script"));
    }

    function _installed(result, what) {
        if (!result.ok)
            installFailure = result.code === 126 ? "Not done: the password was not given." : (result.error || ("Exit code " + result.code));
        if (!result.ok && result.code !== 126)
            Notifier.send(what + " failed", { body: installFailure });
        installedAsks = false;
        checkScript();
    }

    CommandAction {
        id: _install
    }
}
