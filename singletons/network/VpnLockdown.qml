pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io
import Quickshell.Io
import qs.singletons.network

// Only through the VPN (a kill switch): the nftables
// table built by scripts/h2s-vpn-lockdown, switched on while the blocking is wanted —
// always, or while a network it is set for is up — and off when it is not. Only the
// installed script runs, through pkexec: a copy root owns (checked before each start of the
// check: scripts/vpn-lockdown-check.sh), with a polkit rule letting this user run it without
// a password. Installing it is the distribution's ("network.vpnLockdown": Arch installs it,
// one password at the user's click, with Undo; NixOS gives a module to import). Never the
// shell's own copy in its tree, which the user can write.
//   - installed with its rule: its `status` is asked at the start, after network events and
//     every 5 minutes, so a firewall reload that dropped the table is mended; switched by
//     itself as the blocking is wanted, without a password;
//   - not installed, or installed but a password was asked for (its rule does not apply):
//     nothing runs and nothing asks by itself ("missing"); the page says so. A click on
//     "Apply again" may run the installed script and its password question; a prompt that
//     opens for a run started by itself is closed at once.
// Switched again only when its arguments change (a VPN's interface or server, the local
// network), a moment after the last change. A refused switch is not tried again by itself:
// the page offers "Apply again". What was switched on, in which boot, is remembered in Config.
// Started with the shell (shell.qml).
//
// Per network, the blocking comes a moment after the network is up: until then nothing is
// blocked. "Always" has no such gap.
Singleton {
    id: root

    readonly property bool always: Profiles.value("system.vpnLockdownAlways") ?? false
    readonly property bool allowLan: Profiles.value("system.vpnLockdownLan") ?? false
    // Servers of VPNs outside NetworkManager (wg-quick's…), by address: let through too
    readonly property string _extraText: JSON.stringify(Profiles.value("system.vpnLockdownServers") ?? [])
    readonly property var extraServers: JSON.parse(_extraText).filter(address => VpnLockdownRules.isLockdownAddress(address))
    // Through its text: Profiles.value is a new object on every profile fact (battery…)
    readonly property string _networksText: JSON.stringify(Profiles.value("system.vpnLockdownNetworks") ?? [])
    readonly property var networks: JSON.parse(_networksText)

    readonly property bool wanted: VpnLockdownRules.lockdownWanted(NetworkProfiles.profiles, always, networks)

    // Blocking is on, or about to be: what the provider VPNs' note goes by
    readonly property bool blocking: wanted || state === "on"
    // The blocking's rules are loaded, as last reported or remembered for this boot
    readonly property bool loaded: _status.startsWith("on")

    // What to say on a provider VPN's row and card while blocking: the blocking does not let
    // it through (VpnProviderRules.lockdownProviderNote; the provider's own lockdownNote if it
    // has one). "" for NetworkManager's VPNs, and when there is nothing to say. The popup's
    // row: while the VPN is up or coming up; the VPN page's card (`whateverState` true):
    // whenever blocking is on, connected or not — the page states the limit.
    function noteFor(vpn, whateverState): string {
        if (vpn?.type !== "provider")
            return "";
        return VpnProviderRules.lockdownProviderNote(blocking, vpn, VpnProviders.providerOf(vpn)?.lockdownNote ?? "", whateverState === true);
    }

    // ── The script ──
    readonly property string kind: "network.vpnLockdown"
    // How this system installs it, and its places (the integration's facts for the kind):
    // the installed script, its rule (Arch), the folder rules granting it are looked for in,
    // and nft's places. Nothing known (a distribution without an integration): nothing runs.
    readonly property var capability: Distribution.capability(kind)
    readonly property string mode: capability.mode
    readonly property var _facts: Distribution.details(kind).facts
    readonly property string installedAt: String(_facts.scriptPath ?? "")
    readonly property string rulePath: String(_facts.rulePath ?? "")
    readonly property string ruleDirectory: String(_facts.ruleDirectory ?? "")
    readonly property var nftPaths: Array.isArray(_facts.nftPaths) ? _facts.nftPaths.map(path => String(path)) : []
    // The shell's own copy: shown on the page, and what Install puts in place — never run
    readonly property string scriptPath: Quickshell.shellDir + "/scripts/h2s-vpn-lockdown"
    // The user the rule is for, as the system names this process's user (`id -un`), not the
    // environment's USER, which anyone may set; "" until read
    property string user: ""
    readonly property string scriptText: _scriptFile.text()
    // The rule as Install would write it (Arch), and NixOS's module (the integration's plan)
    readonly property string polkitRule: VpnLockdownInstallRules.ruleText(user, installedAt)
    readonly property var _modulePlan: mode === "copy" ? Distribution.plan(kind, { op: "install", user: user, script: scriptText }) : null
    readonly property string nixosModule: _modulePlan?.preview?.snippet ?? ""
    readonly property string moduleHint: _modulePlan?.preview?.hint ?? ""
    readonly property string moduleFile: _modulePlan?.preview?.option ?? ""
    FileView {
        id: _scriptFile
        path: root.scriptPath
        watchChanges: true
        onFileChanged: reload()
    }

    // The version of the shell's copy, and of the one installed (0 none); whether one is there
    // that root owns alone (the only one run), or one that is not (`unsafeFound`, never run);
    // whether a polkit rule for this user names it
    property int scriptVersion: 0
    property int installedVersion: 0
    property bool installedFound: false
    property bool unsafeFound: false
    property bool folderFound: false
    property bool ruleInstalled: false
    property bool nftFound: false
    property bool checked: false
    // A password was asked for while running the installed script: its rule does not apply
    property bool installedAsks: false

    // "none", "folder" (an older install's layout: a folder at the script's place), "unsafe"
    // (a file there not root's alone), "norule", "asks", "outdated" (runs,
    // but older than the shell's), "ready"
    readonly property string helperState: folderFound ? "folder" : unsafeFound ? "unsafe" : !installedFound ? "none" : !ruleInstalled ? "norule"
        : installedAsks ? "asks" : installedVersion < scriptVersion ? "outdated" : "ready"
    readonly property bool passwordFree: installedFound && ruleInstalled && !installedAsks

    // Arch: the two files as read (each a text, undefined for none, null not read), and what
    // they are against what Install would write (VpnLockdownInstallRules.states)
    property var current: ({ script: null, rule: null })
    readonly property var installState: VpnLockdownInstallRules.states({ user: user, script: scriptText, current: current }, { script: installedAt })

    // ── The blocking ──
    // "off", "on", "asking" (the password is being asked for, after a click), "working",
    // "failed", "missing" (a switch is due, but nothing may run by itself)
    property string state: "off"
    property string failure: ""

    // The interfaces let through as VPNs, besides tun*, wg* and the like: the WireGuard
    // profiles' own — as set, not as up, so a VPN connecting changes nothing. NetworkManager's
    // VPNs only: the blocking does not support provider VPNs (Tailscale; the owner's decision)
    // — what a provider reports never reaches the script.
    readonly property var vpnInterfaces: VpnManager.nmInterfaceNames.slice().sort()
    // The VPN servers' names and addresses as set (every peer's, every remote) — of
    // NetworkManager's VPNs only, as above
    readonly property var _hostList: Array.from(new Set(Object.values(VpnManager.nmDetails)
        .reduce((all, detail) => all.concat(detail.servers ?? []), []).map(server => VpnLockdownRules.serverHost(server))
        .filter(host => host !== ""))).sort()
    readonly property string _hosts: _hostList.join(" ")
    // { host: [addresses] } as last found; a host not found again keeps its addresses
    property var _serverMap: ({})
    readonly property var servers: Array.from(new Set(_hostList.reduce((all, host) =>
        all.concat(NetworkRules.isIpAddress(host) ? [host] : (_serverMap[host] ?? [])), []).concat(extraServers))).sort()

    // The script's arguments as they would be now, and the status it would report
    // (not "arguments": inside a function that name is the function's own)
    readonly property var switchArguments: VpnLockdownRules.lockdownArguments({ vpnInterfaces: vpnInterfaces, servers: servers, allowLan: allowLan })
    readonly property string expectedStatus: VpnLockdownRules.lockdownStatusOf(switchArguments)

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
    // version 4); rules older than the installed script are switched on again
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
    // Once the distribution is known (its places); the page asks again when shown
    function checkScript(): void {
        // Looked at afresh: a question seen before is not held against the script any more
        installedAsks = false;
        Distribution.whenReady(() => _userRead.request());
    }

    CommandQuery {
        id: _userRead
        command: ["id", "-un"]
        onDone: lines => {
            const name = String(lines[0] ?? "").trim();
            if (name !== root.user)
                root.user = name;
            _scriptCheck.request();
            if (root.mode === "apply")
                root._readFiles();
        }
    }

    CommandQuery {
        id: _scriptCheck
        command: [Quickshell.shellDir + "/scripts/vpn-lockdown-check.sh", "0", root.scriptPath, root.installedAt, root.ruleDirectory, root.user]
            .concat(root.nftPaths)
        onDone: lines => {
            const found = VpnLockdownRules.checkReply(lines);
            const changed = found.installed !== root.installedVersion || found.installedFound !== root.installedFound;
            root.scriptVersion = found.script;
            root.installedVersion = found.installed;
            root.installedFound = found.installedFound;
            root.unsafeFound = found.unsafe;
            root.folderFound = found.folder;
            root.ruleInstalled = found.rule;
            root.nftFound = found.nft;
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

    // As the user: what is at the install's two places now; an answer from before a later
    // reading was asked is not taken
    property int _reads: 0
    function _readFiles() {
        const number = ++_reads;
        const asked = [installedAt, rulePath];
        const lines = [];
        _filesRunner.start([Quickshell.shellDir + "/scripts/pam-files.sh"].concat(asked), {
            timeoutMs: 6000,
            killAfterMs: 1000,
            maxOutputBytes: 1048576,
            keepOutput: false,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                if (number !== root._reads)
                    return;
                const answers = PamStackRules.filesAnswer(lines, result, asked).answers;
                root.current = VpnLockdownRules.filesRead(answers[asked[0]], answers[asked[1]]);
            }
        });
    }
    property CommandRunner _filesRunner: CommandRunner {}

    // A password asked for while the installed script runs: its rule does not apply. The
    // question that is this run's (PolkitRules.announces: pkexec's, quoting its command) is
    // closed at once when the run started by itself — nothing asks without a click — and
    // nothing runs by itself after that until the script is checked again (the page shown,
    // "Check again", an install) or a run on a click goes through without a question.
    // Another polkit agent's question cannot be seen or closed from here: a run by itself that
    // pkexec ends refused or unanswered counts the same (VpnLockdownRules.asksAfter).
    Connections {
        target: Authentication
        function onFlowChanged() {
            const answer = VpnLockdownRules.promptAnswer(Authentication.flow, root._running, root._runningByItself);
            if (answer === "")
                return;
            root.installedAsks = true;
            root._promptSeen = true;
            if (answer === "close") {
                console.warn("[VpnLockdown] the installed script asked for a password: its polkit rule does not apply; the question is closed");
                Authentication.flow.cancelAuthenticationRequest();
            }
        }
    }
    // The words handed to pkexec by the run under way ([] none), and whether it started by
    // itself (not the user's click)
    property var _running: []
    property bool _runningByItself: false
    // A question was seen during the run under way
    property bool _promptSeen: false

    // A refusal is for the moment it was given: wanted or not again, it is asked afresh
    onWantedChanged: {
        _refused = "";
        _toldMissing = false;
        _schedule();
    }
    onExpectedStatusChanged: _schedule()
    on_HostsChanged: _schedule()
    // A password refused for switching on is no reason to hold back once none is needed (the
    // script installed): its status is asked, and changed rules switched on again. A refused
    // switch-off stays refused: installing never takes the blocking down by itself.
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
        Profiles.setGlobal("system.vpnLockdownServers", addresses.filter(address => VpnLockdownRules.isLockdownAddress(address)));
    }

    // More servers' addresses than the script takes: the rest left out (said on the page)
    readonly property bool tooManyServers: servers.filter(address => VpnLockdownRules.isLockdownAddress(address)).length > VpnLockdownRules.lockdownMostAddresses

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

    // A moment's wait after the last change, so changes in a row switch once
    Timer {
        id: _settle
        interval: 800
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
        _runScript(["status"], VpnLockdownRules.runByItself("status", false), result => {
            if (result.ok) {
                const reply = VpnLockdownRules.lockdownStatusReply(result.lines);
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

    // The decision is VpnLockdownRules.lockdownNextStep's, from the state as it is now: nothing
    // is used up by a call that has to wait (busy, not ready) — the next one decides again
    function _follow(force) {
        // The VPNs' interfaces and servers read first: arguments made without them would
        // differ from the ones switched on, and switch again at every start
        const ready = Config.ready && checked && _bootId !== "" && VpnManager.detailsRead;
        const busy = _action.busy || _resolve.running;
        if (ready && !busy && !_memoryRead)
            _readMemory();
        const step = VpnLockdownRules.lockdownNextStep({
            ready: ready, busy: busy, installed: installedFound, passwordFree: passwordFree, askedAtStart: _askedAtStart, force: force === true,
            wanted: wanted, nftFound: nftFound, status: _status, rulesVersion: _rulesVersion,
            expectedStatus: expectedStatus, scriptVersion: installedVersion, refused: _refused, hosts: _hosts
        });
        if (step === "ask") {
            _askedAtStart = true;
            _askStatus();
        } else if (step === "missing") {
            // Nothing may run by itself: said on the page, nothing asked; told once while
            // wanted, so the blocking never fails open unnoticed
            state = "missing";
            failure = "";
            if (wanted && !_toldMissing) {
                _toldMissing = true;
                const notice = VpnLockdownRules.missingNotice(helperState);
                Notifier.send(notice.summary, { body: notice.body });
            }
        } else if (step === "keep") {
            if (state === "missing")
                state = loaded ? "on" : "off";
        } else if (step === "no-nft") {
            state = "failed";
            failure = "nftables is not installed: the blocking needs it.";
        } else if (step === "refused") {
            state = "failed";
        } else if (step === "on") {
            _findServersThenSwitchOn(VpnLockdownRules.runByItself("on", force === true));
        } else if (step === "off") {
            _switchOff(VpnLockdownRules.runByItself("off", force === true));
        } else if (step === "idle") {
            // Nothing to do: a refusal from before is not carried to the next time
            _refused = "";
            state = "off";
            failure = "";
        }
    }

    // Told that the blocking is wanted but nothing may switch it (once per wanted)
    property bool _toldMissing: false

    // A switch is under way (the page's "Apply again" waits for it)
    readonly property bool switching: state === "asking" || state === "working" || _resolve.running || _action.busy

    // Whether what is loaded differs from what is wanted (the page offers "Apply again")
    readonly property bool mismatched: checked && state !== "asking" && state !== "working"
        && (state === "failed" || state === "missing" || wanted !== _status.startsWith("on"))

    // The servers by their names, each found through the system's resolver; those not
    // found keep their last addresses
    // `byItself` decided with the switch (VpnLockdownRules.runByItself) and carried through
    // the lookup: a decision made meanwhile does not change whose run it is
    property bool _resolveByItself: true
    function _findServersThenSwitchOn(byItself) {
        const names = _hostList.filter(host => !NetworkRules.isIpAddress(host));
        if (names.length === 0) {
            _switchOn(byItself);
            return;
        }
        _resolveByItself = byItself;
        _resolve.command = ["sh", "-c", 'for host in "$@"; do getent ahosts "$host" | while read -r address rest; do echo "$host $address"; done; done; true',
            "sh"].concat(names);
        _resolve.request();
    }

    CommandQuery {
        id: _resolve
        onDone: lines => {
            const map = Object.assign({}, root._serverMap, VpnLockdownRules.addressesByHost(lines));
            if (JSON.stringify(map) !== JSON.stringify(root._serverMap))
                root._serverMap = map;
            const byItself = root._resolveByItself;
            Qt.callLater(() => root._switchOn(byItself));
        }
    }

    CommandAction {
        id: _action
    }

    // The installed script — never the shell's own copy. `byItself`: not the user's click,
    // so a password question this run raises is closed at once
    function _runScript(scriptArguments, byItself, done) {
        const command = ["pkexec", installedAt].concat(scriptArguments);
        _running = command.slice(1);
        _runningByItself = byItself;
        _promptSeen = false;
        _action.run(command, result => {
            const promptSeen = root._promptSeen;
            root._running = [];
            root._runningByItself = false;
            root._promptSeen = false;
            // A run on a click that went through without a question: the rule applies again,
            // and the blocking switches by itself again
            if (!byItself && result.ok && !promptSeen && root.installedAsks) {
                console.log("[VpnLockdown] the installed script ran without a password again: it switches by itself again");
                root.installedAsks = false;
            }
            // A question this shell could not see (another agent's): nothing more by itself
            if (VpnLockdownRules.asksAfter(result, byItself) && !root.installedAsks) {
                console.warn("[VpnLockdown] the installed script asked for a password (pkexec " + result.code + "): nothing runs by itself until it is checked again");
                root.installedAsks = true;
            }
            done(result);
        });
    }

    function _switchOn(byItself) {
        if (_action.busy)
            return;
        const scriptArguments = switchArguments.slice();
        const status = expectedStatus;
        const hosts = _hosts;
        const version = installedVersion;
        state = passwordFree ? "working" : "asking";
        _runScript(scriptArguments, byItself, result => {
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

    function _switchOff(byItself) {
        state = passwordFree ? "working" : "asking";
        _runScript(["off"], byItself, result => {
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

    // ── Installing and removing the script ── through the distribution's integration
    // ("network.vpnLockdown"), each the user's click: on Arch one password, the files written
    // as root with a backup Undo puts back; elsewhere nothing to install from here (NixOS: the
    // module, `nixosModule`). What Install acts on is what the page last read (`current`); a
    // file there not written by the shell is replaced only with `replace` naming it.
    readonly property string installBusy: _change.busy
    readonly property bool undoable: _change.undoable
    property string installFailure: ""

    function install(replace): void {
        _start(_change.apply({ op: "install", user: user, script: scriptText, current: current, replace: replace ?? {} }));
    }

    function uninstall(): void {
        _start(_change.apply({ op: "remove", user: user, script: scriptText, current: current, replace: {} }));
    }

    function undoInstall(): void {
        _start(_change.undo());
    }

    function _start(started) {
        installFailure = started.started ? "" : (started.refusal?.text ?? "");
    }

    property IntegrationChange _change: IntegrationChange {
        kind: root.kind
        onFinished: (mode, outcome) => {
            root.installFailure = outcome?.ok === true || outcome?.quiet === true ? "" : String(outcome?.error ?? "");
            root.installedAsks = false;
            root.checkScript();
        }
    }
}
