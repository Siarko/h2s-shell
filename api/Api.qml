pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io as Io
import qs.singletons.network

// The module API (notes/plans/modules.md, "Module API 1.0", 1.1, 1.2 and 1.3; notes/plans/api-next.md from 1.4): everything a
// module may use of the shell. A module imports `qs.api` and reaches:
//
//   Api.version            "1.25" — this shell's module API, "major.minor". A module's manifest
//                          asks for one ("api"); it loads when the major is the same, this
//                          minor is at least the one asked for, and the one asked for is not
//                          below the shell's floor (ModuleRules.apiFloor: the oldest version
//                          whose modules still run unchanged). Every change bumps the minor
//                          and has its "- 1.x:" line under "Module API" in CHANGELOG.md.
//                          Until the first release announced as open to module authors a
//                          minor may also remove things: the old way keeps working while it
//                          is listed in the module's status (`deprecations`, in `modules
//                          list`), then goes in a change that raises the floor — a module
//                          below it does not load, and says why. From that release on a
//                          removal needs a major version, after at least one release that
//                          listed the thing as deprecated.
//   Api.theme              the theme's tokens, read-only (api/ThemeTokens.qml)
//   Api.slots              the slots the core offers: [{ name, where, context, since }]. Once
//                          a slot's view is built from anchor blocks, a manifest's `slots`
//                          entry for it is read as its anchor (ModuleRules.slotAliases: the
//                          element's context also carries `slot`) and listed in the
//                          module's deprecations
//   Api.anchors            (1.20) the places in the shell's views a module may put elements
//                          at, frozen [{ path, kind, placements, takes, marks, context, scope,
//                          since, where, view }] (ModuleRules.anchorTable, the reference). A path is
//                          <surface>.<view>[.<block>]…[.<region>]: surface "settings" or
//                          "popup" (the bar has none, nor the lock screen); view a settings
//                          page's id or a popup's key; block a block's name, what it holds
//                          (a block repeated per item named by its kind, card or row: the item
//                          is in the context); region a card's "actions" or "settings". A
//                          module names a path, a placement and its file in its manifest:
//                            "anchors": [{ "at": "settings.general", "place": "append",
//                                          "component": "GeneralRow.qml" }]
//                          `before` and `after` put the element next to the block, outside it;
//                          `prepend` and `append` inside, first and last of its content (under
//                          its heading or title). The element gets its handle as `module` and
//                          `context` ({ anchor: the path, placement, …what the row's context
//                          names }), again only when that changes by value, and `shown` (1.2)
//                          when it declares them. Several modules at one place: by module id,
//                          a module's in its manifest's order. A path this shell does not offer
//                          or a placement it does not take is an error in the module's status;
//                          the rest of the module loads. A row of scope "own-provider" (on
//                          the card or row of a VPN provider's item) shows only the elements
//                          of the module that is that item's provider. A slot read as its
//                          anchor keeps its context: the converted block gives the keys the
//                          slot gave (ModuleRules.slotAliases' `needs`). The places so far,
//                          the shell's views getting them one by one:
//                            settings.general (1.21)  Settings → Behaviour → General: append,
//                                                     at the end of the page; context
//                                                     { editIndex: the profile being edited }.
//                                                     The slot settings.general.bottom is read
//                                                     as it
//                            popup.network.connections (1.22)  the network popup, under the
//                                                     VPN, Ethernet and Wi-Fi parts, above the
//                                                     divider over the network list: append;
//                                                     context { wifiEnabled, wifiConnected,
//                                                     ethernetConnected }. The slot
//                                                     network.popup.sections is read as it
//                            popup.notifications (1.22)  the notifications popup, under its
//                                                     header, above the list: prepend; context
//                                                     { count: the notifications in the list }.
//                                                     The slot notifications.popup.top is read
//                                                     as it
//                            popup.network.connections.vpn.row (1.23)  under the row of each
//                                                     VPN of the module's provider in the
//                                                     network popup: after; own-provider;
//                                                     context { vpnId, entryId, vpn, provider:
//                                                     the provider object, otherVpnsUp,
//                                                     otherVpns }. The slot network.vpn.row is
//                                                     read as it
//                            settings.network_vpn.vpns.card.settings (1.23)  in the opened card
//                                                     of each VPN of the module's provider on
//                                                     Settings → System → Network → VPN, above
//                                                     the card's own rows, while the card is
//                                                     open: prepend; own-provider; context as
//                                                     the row's. The slot network.vpn.card is
//                                                     read as it (its context adds open: true)
//                            settings.network_wifi.saved.card.settings (1.24)  in the opened
//                                                     card of each saved network on Settings →
//                                                     System → Network → Wi-Fi, under the
//                                                     page's rows (the password), while the
//                                                     card is open: append; context { networkId:
//                                                     the profile's UUID (Api.networks' id),
//                                                     name, kind: "wifi", active: fully up }.
//                                                     Not on a hotspot's card
//                            settings.network_ethernet.profiles.card.settings (1.24)  the same
//                                                     in the opened card of each wired profile
//                                                     on Settings → System → Network →
//                                                     Ethernet, under the card's rows: append;
//                                                     context as the Wi-Fi network's (kind
//                                                     "ethernet")
//                            settings.network_vpn.vpns.card.actions,
//                            settings.network_wifi.saved.card.actions,
//                            settings.network_ethernet.profiles.card.actions (1.25)  the
//                                                     buttons of the same opened cards: append,
//                                                     under the card's own ("Settings…", "Edit
//                                                     connection…"), above "Forget" / "Delete",
//                                                     which stays last; context as the card's
//                                                     settings (the VPN's own-provider). These
//                                                     take a SmallButton only (`takes`): another
//                                                     element is built once (its startup code
//                                                     runs), then destroyed, not shown; an error
//                                                     in the module's status says so. A button
//                                                     with `visible: false` takes no room. Each
//                                                     button at its
//                                                     own width on the stack's right edge, at
//                                                     most a third of the card wide (a longer
//                                                     label is cut), in size "m" whatever it
//                                                     asks for; any kind, with or without
//                                                     confirm
//                          A saved Wi-Fi network's card is a place only once its details are
//                          read (until then Api.networks leaves it out: it could be a hotspot)
//   Api.module(id)         a module's handle (api/ModuleHandle.qml), or null. Deprecated
//                          (1.19): a module keeps to its own handle — another module is
//                          Api.moduleStatus(id) and its exports (`uses`, below). A module whose
//                          code calls it has it listed in its `deprecations`; it goes with the
//                          shell's next tightening
//   Api.moduleStatus(id)   (1.19) another module's plain state, frozen { id, name, version,
//                          state (as in `modules list`: "loaded", "disabled", "missing-module",
//                          …), active (true while it is enabled and loaded) }, or null for an
//                          id no module has. Nothing else of it: no handle, no directory, no
//                          errors. It follows the module in a binding
//   Api.moduleAt(url)      the handle of the module whose directory holds `url` — in any file
//                          of a module: Api.moduleAt(Qt.resolvedUrl("."))
//   module.main            (1.15, on its handle) the object made from the manifest's `main`
//                          while the module is active, read-only, and it notifies: null while
//                          the module is off, while the main itself is being built and for a
//                          module without one. The shell sets it right after making the main,
//                          before any of the module's widgets, popup panels or pages are
//                          built, and clears it before destroying the main; turned on again,
//                          it is a new object. What the module's views share (a client, its
//                          state) lives on the main and is read through it, allowing null:
//                          `module.main?.client`
//   Api.notify(summary, options)   a notification (options: Notifier's — body, urgency, icon,
//                          actions…); a module's own handle's notify() names the module.
//                          (1.12) options.format "plain": the summary and body are plain
//                          text — use it for any text from outside (a command's output, a
//                          peer's or a file's name): each on one line (line breaks and tabs
//                          become spaces), other control and format characters (a
//                          right-to-left override, a zero-width joiner) dropped, the summary cut
//                          at 200 characters and the body at 1000 with "…"; "&", "<" and ">"
//                          in the body shown as written, never read as markup. A text that
//                          starts with "-" is safe either way. Without it the body is markup,
//                          as the notification spec has it. A category of the shell's own
//                          ("x-qs-…", its toast's "x-qs-shell"), as an option or a hint, is
//                          dropped: a module's notification never looks like the shell's
//   Api.openUrl(url, options)  opens a link in the user's programs (xdg-open, no shell): only
//                          http:, https:, mailto: — file: with { allowFile: true }; anything
//                          else (no scheme, a bare path, another scheme) refused, logged, false
//                          In module test mode it opens nothing: the link is recorded
//                          (ModuleTestKit.opened) and true returned, as for one opened
//   Api.testMode           (1.10) true in module test mode — under tests/run-modules.sh and
//                          in a test tree — read-only; below
//   Api.format             (1.12) sizes, rates and moments as text, pure:
//                            bytes(n)   "742 MB", "15.6 GB", "1.8 TB" (1 KB = 1024 B; whole
//                                       megabytes, larger to one decimal; not a number: "0 B")
//                            rate(n)    bytes per second: "12 KB/s", "3.4 MB/s"
//                            ago(ms, nowMs)   "just now", "5 min ago", "3 h ago", "yesterday",
//                                       "4 days ago", "2 months ago"; "never" for 0 or not a
//                                       number; both in milliseconds since 1970 (nowMs not
//                                       given: now; a moment after it: "just now")
//   Api.address            (1.12) IP addresses and networks, pure (singletons/AddressRules.qml):
//                            isIpv4(text), isIpv6(text), isIp(text)   IPv4 without leading
//                                       zeros, IPv6 without a zone, at most 45 characters
//                            parseCidr(text)   "address/prefix" or a bare address (a /32 or
//                                       /128) → frozen { family (4 | 6), bits, bytes (host
//                                       bits cleared), address and network ("<address>/<bits>",
//                                       written canonically: IPv6 lower case, the longest run
//                                       of zeros "::"), canonical (false: host bits were set) }
//                                       or null
//                            contains(network, inner)   `inner` (an address or a network)
//                                       lies wholly in `network`
//                            overlap(a, b)   two networks share addresses
//                                       (each argument a text or parseCidr's result; anything
//                                       else, or two families: false)
//                            redact(text)   every address in a text (with a prefix too)
//                                       replaced by "[address]", what is around it kept
//                                       ("[address]:443", "[[address]]:41641",
//                                       "peer:[address]"); version numbers, times and names
//                                       with "::" in code ("std::string") stay; the first
//                                       2000 characters read
//   Api.minuteNow          (1.12) the time, in milliseconds since 1970, at the start of the
//                          current minute: changes once a minute, on the minute — bind to it
//                          for "5 min ago" and grace periods instead of a clock of the
//                          module's own. In module test mode ModuleTestKit.setNow(ms) sets it
//                          (to the start of that minute)
//   module.log(level, text, key)   (1.12, on its handle) a line in the shell's log, "[<id>]
//                          <text>": level "debug" (only with the shell's debug setting),
//                          "info", "warn", "error" (another word: "info"); the text on one
//                          line, cut at 1000 characters. With `key` written only when the
//                          level or text differs from the one last written for that key;
//                          → true when written (a debug line with the setting off is not,
//                          and is not remembered)
//   Api.system             (1.13) what the shell read of the system, frozen; a new object
//                          only when something in it changed:
//                            ready              the user name and the download folder have
//                                               been read (the rest is there from the start)
//                            userName           the user's name (`id -un`: the user database,
//                                               a network account too)
//                            uid                the user's id, a number (/proc/self/status)
//                            hostName           the machine's name (/proc/sys/kernel/hostname)
//                            home               HOME
//                            configHome         XDG_CONFIG_HOME, else <home>/.config
//                            dataHome           XDG_DATA_HOME, else <home>/.local/share
//                            runtimeDirectory   XDG_RUNTIME_DIR (no default)
//                            downloadDirectory  XDG_DOWNLOAD_DIR from <configHome>/user-dirs.dirs
//                                               (read as text, never run: only "$HOME/…" or an
//                                               absolute path in double quotes counts), else
//                                               <home>/Downloads
//                            readIpForwarding() → frozen { ipv4, ipv6 }: /proc's two switches
//                                               read now, each true, false, or null when it
//                                               could not be read
//                            refresh()          reads the name, the host name and
//                                               user-dirs.dirs again; the facts stay as they
//                                               were until the new answers come
//                          Every path is absolute, without a trailing "/". A fact that could
//                          not be read, or reads as something unexpected (a relative path, a
//                          line break), is unknown — "" for a text, null for `uid` — never a
//                          guess; an XDG_* variable that is not an absolute path is ignored,
//                          as the XDG specification says. The same on NixOS and on Arch (a
//                          home-manager user-dirs.dirs on NixOS is read like xdg-user-dirs'
//                          on Arch; with none, <home>/Downloads). In module test mode the
//                          facts are the test kit's (ModuleTestKit.setSystem): made up, the
//                          same on every machine, nothing read
//   module.dataDirectory   (1.13, on its handle) the module's own directory for its files
//                          (certificates, caches): "<dataHome>/h2s-shell/module-data/<id>".
//                          The shell makes it before the module loads (at each load of the
//                          modules, and when the module is turned on), mode 700, after
//                          checking every folder from the data home down: owned by the user
//                          (or root, above the data root), writable by no one else, and no
//                          link below the data home. A data root or module directory that
//                          others could write before is refused, not closed. When that
//                          fails the module loads all the same with dataDirectory "" and a
//                          warning in its status (`modules list`): a module that needs it
//                          checks for "". It is apart from the module's own directory,
//                          which installing and removing the module owns; the shell never
//                          removes it. Nothing in the data directory may be run as root —
//                          the user can write there. In module test mode it lies in a private
//                          temporary directory the shell made, never in the user's data home,
//                          and setSystem does not move it
//   Api.copy(text)         puts text on the clipboard
//   Api.openSettings(page) the settings window on a page, by id (a core page's or a module's)
//   Api.networks           (1.3) the saved networks this computer joins, frozen:
//                          [{ id (the NetworkManager profile UUID, system.vpnWithNetworks' key),
//                          name, kind ("wifi" | "ethernet"), active (bool, fully up) }] — no
//                          hotspots, VPNs, bridges or their ports; active ones first, then
//                          NetworkProfiles' order; empty until the profiles are read. A new
//                          array only when something in it changed
//                          (1.16) A Wi-Fi network only once its details are read (until
//                          then it could be a hotspot)
//   Api.networksReady      (1.16) the profiles and the Wi-Fi details of every Wi-Fi profile
//                          have been read: an empty Api.networks then means none. False while
//                          not, and when the last reading of either failed (no nmcli,
//                          NetworkManager not running) — Api.networks is then not known
//                          whole, never "no network". While false Api.networks may still
//                          list some (the Ethernet ones before the Wi-Fi details are read)
//   Api.vpnsUp             (1.3) the VPNs up now, frozen: [{ name, type ("wireguard", "vpn"…
//                          or "provider"), provider (a provider's providerId, else "") }];
//                          a new array only when something in it changed. (1.16) Each row
//                          also says what the VPN does with the traffic, null where that is
//                          not known (never false for "not read"):
//                            fullTunnel  true | false | null — true: it takes all traffic of
//                                        IPv4 or of IPv6 (or both) that no more specific
//                                        route sends elsewhere (that family's default route,
//                                        or "all" as its two halves, 0.0.0.0/1 + 128.0.0.0/1,
//                                        ::/1 + 8000::/1); false: of neither family
//                            setsDns     true | false | null — it brings DNS servers of its
//                                        own while up; null until read while it is fully up
//                            routes      [networks] | null — what it carries, canonical
//                                        ("10.0.0.0/8"; "0.0.0.0/0", "::/0" for all), frozen;
//                                        null when not known, and when there would be more
//                                        than 256 (the shell logs that)
//                          NetworkManager's WireGuard: from its profile — its peers'
//                          allowed-ips (not the IPv6 ones while its IPv6 is disabled), a /0
//                          all of its family unless never-default is on for it; with
//                          peer-routes off the routes are null and fullTunnel null unless
//                          never-default rules it out. A plugin VPN: what NetworkManager set
//                          up, read while it is "activated" (a gateway, a /0 or the two
//                          halves is a full tunnel); all three null while it is still
//                          activating. A provider's VPN: what its entry reports (VpnProvider,
//                          below), null where it reports nothing
//   Api.localNetworks      (1.16) the networks this computer is on, frozen: [{ device (the
//                          interface the address is on — a modem's wwan0, not its control
//                          device), kind ("wifi" | "ethernet" | "bridge" | "modem" |
//                          "other"), family (4 | 6), address (this computer's, canonical, no
//                          prefix), network (the one it lies in, "192.168.1.0/24"; null for a
//                          /32 or /128 address, whose network is not said with it — DHCPv6's) }]
//                          — global addresses only (no loopback, link-local or multicast), of
//                          IPv6 no deprecated privacy address (the current one stays; when
//                          `ip` cannot tell the flags, every address stays); none on a VPN's
//                          device (loopback, tun, WireGuard, an IP tunnel, an interface of
//                          NetworkManager's VPNs or a provider's), except a Wi-Fi or Ethernet
//                          device a VPN runs on (IPsec), which stays less the VPNs' own
//                          addresses; from NetworkManager's devices, read again when the
//                          networks change; at most 64. A new array only when something in
//                          it changed
//   Api.localNetworksReady (1.16) the devices' addresses were read; false (and
//                          Api.localNetworks empty) while not, and when the last reading
//                          failed — unknown, never "no network"
//                          These show every installed module the saved network names, the
//                          VPN names and the addresses: modules are trusted and run in the
//                          shell's process. In module test mode they are the test kit's
//                          (ModuleTestKit.setNetworks), nothing read
//
// And these types (files beside this one):
//   SettingEditor, SectionTitle, Heading, Hint, DetailRow, SwitchRow — the settings window's
//                          building blocks, so a module's page looks like the core's
//   CommandRunner (1.8) — running commands: any number at once, each with a time limit,
//                          its output as it comes, one answer (below)
//   CommandAction, CommandQuery, PrivilegedAction — running commands the shell's way
//   SmallButton (1.4), Dropdown, InputField, Pill, Checkbox, ToggleSwitch, PrivilegedMark
//                          (1.5), SettingsRow, ExpandingRow, Notice (1.6) — the public
//                          elements (below)
//   PopupWidget, BarText, BarRow, PointerArea, VpnProvider (1.7) — the base types (below)
//   ThemeTokens, ModuleHandle, ModuleStore — what Api.theme, a handle and its store are
//
// Public elements (1.4): types made for the API, which hold the shell's internal component
// inside and show only their own properties; the shell changes its insides freely. On one
// a module picks a meaning, never a colour, a radius or a number of pixels: `kind` (what
// the element is about) and `size` ("xs", "s", "m" — the default —, "l"; an element takes
// the ones it has). Both lists are open: a word an element does not know shows as its
// default and is logged once per element type and word. Every text is shown as written
// (plain text). A label, a button's question, a pill's text and a dropdown's option
// labels and placeholder are one line: line breaks become spaces, and past 80 characters
// the text is cut with "…" (ApiElementRules.oneLine). An element's properties and signals are pinned by tests/ApiElementsTest.qml;
// a change to them is a version change.
//   SmallButton            label, available, checked, tooltip;
//                          kind: "primary" (performs the action) | "secondary" (the default:
//                          a step in between, opens something, "Cancel") | "danger" (stops
//                          or removes) | "warning" (goes on, but think) | "success" (a good
//                          outcome to take); size: "xs" | "s" | "m";
//                          confirm (false; true: the first click only turns the button into
//                          the question, with a "×" that takes it back, the second acts),
//                          confirmLabel (the question; the label and "?" unless given),
//                          cancelTip (the "×"'s tooltip), asking (the first click was made;
//                          set it false when what the button acts on changes);
//                          clicked() — do it: the click, or with confirm the second one;
//                          asked() — the first click of a button that asks. A danger button
//                          without confirm acts on the first click. A button that asks
//                          shows no `checked` and keeps its own width in a layout, or less
//                          when given less (1.25: its label or question cut);
//                          apiElement (1.25, read-only) "SmallButton" — the mark a place
//                          that takes only a button reads.
//                          `checked` shows only on a secondary button: a primary,
//                          danger, warning or success one looks the same either way.
//   Dropdown               (1.5) options ([{ value, label }]; other fields of an option
//                          are dropped), value (the owner sets it),
//                          placeholder (shown while the value is none of the options);
//                          size: "xs" | "s" | "m"; picked(value) — the choice made
//   InputField             (1.5) text, placeholder, problem (the value is wrong now),
//                          password (hidden, with an eye), revealed (the eye flips it);
//                          size: "xs" | "s" | "m"; accepted(), textEdited(),
//                          editingFinished(), revealToggled()
//   Pill                   (1.5) label, picked (the owner sets it), tooltip;
//                          size: "s" | "m" | "l" — the theme's three pill heights;
//                          clicked()
//   Checkbox               (1.5) label, checked (the owner flips it); toggled()
//   ToggleSwitch           (1.5) checked (the owner changes it), and every item's
//                          `enabled`; toggled()
//   PrivilegedMark         (1.5) need — polkit's answer for what the control beside it
//                          does: "auth" (the default: the lock), "no" (not allowed), "yes"
//                          or "" (nothing to mark: hidden, no room taken). An answer it
//                          does not know shows the lock. Where a module sets `visible`
//                          itself, an element with nothing to mark is empty and without
//                          size, but a layout keeps its spacing around it.
//   SettingsRow            (1.6) label, hint (a short line under the label), value (a
//                          text on the right); its children, written inside it, are the
//                          controls on the right, in a row (`controls` is where they go,
//                          nothing to set). Fills the width a layout gives it.
//   ExpandingRow           (1.6) label, hint, open (a click on its line flips it; the
//                          owner may set it); its one child, written inside it, is what it
//                          opens (`content`, a Component): built when the row opens,
//                          destroyed when it closes, as wide as the row. Fills the width.
//   Notice                 (1.6) text — a small line that wraps, as the line on a
//                          network's card; kind: "warning" (the default) | "danger" |
//                          "success". Fills the width.
//                          The settings blocks above (SectionTitle, Heading, Hint,
//                          SwitchRow, a SettingEditor's label, hint and unit) and a
//                          module's page name in the settings window show their texts as
//                          written from 1.6: markup in them is no longer read.
//                          qs.components has types of these names too (other properties:
//                          a fontSize, other kinds): in a file that imports both, the
//                          import written last gives the name.
//
// Base types (1.7): what a module's own object extends where the shell needs the object
// itself — the bar its widget, VpnManager a provider. Each is the shell's internal type,
// not a wrapper: the names below are pinned (tests/ApiElementsTest.qml), what else the
// type has is not promised.
//   PopupWidget            a bar widget that opens the popup its manifest names:
//                          widgetType, popup (set by the bar), popupOpen, interactive;
//                          clicked, hover(status), scrolled(delta), scrollNotch(direction),
//                          middleClicked; its children are the cell's content. A widget that
//                          declares `property string preset` is given its bar entry's preset
//                          by the bar, and its popup panel is told it (`opener`, below)
//   BarText                text on the bar, turned or stacked on a bar at a side: text,
//                          font, color, alignment, elide, length, leadingGap
//   BarRow                 items along the bar, a row or a column: vertical (read-only),
//                          spacing
//   PointerArea            the MouseArea of a module's own control: lit (its hover look,
//                          a tap included), centred, reach, and a MouseArea's own
//   VpnProvider            a VPN provider (the contract is API 1.1's, written in
//                          components/VpnProvider.qml): providerId (the module's id),
//                          kind, typeName, glyph, entries, ready, busy, canChange,
//                          lockdownNote, settingsPage (an entry may set fullTunnel, setsDns
//                          and routes, 1.16: Api.vpnsUp's; absent is null, unknown);
//                          connect(entryId, request),
//                          disconnect(entryId, request), attend(entryId);
//                          failed(entryId, what, reason). Its module's elements under its
//                          VPNs' rows and in their cards are the own-provider places
//                          popup.network.connections.vpn.row and
//                          settings.network_vpn.vpns.card.settings (1.23; the old slots
//                          network.vpn.row and .card are read as them); its framed page the
//                          slot network.vpn.page. Their context's `otherVpns` (1.16): the
//                          other VPNs up as Api.vpnsUp's rows, beside `otherVpnsUp` (their
//                          names).
//
// A module's popup panel (the manifest's `popupPanel`, 1.15): built when its popup opens and
// destroyed when it closes; it gets its module's handle as `module` (`property var module`)
// and, each only when its root object declares the property:
//   opener                 `property var opener` — the bar widget that opened it, frozen
//                          { widgetType, preset (its bar entry's: "" when the widget declares
//                          no `preset`), edge (the bar's: "top", "bottom", "left", "right"),
//                          byTouch (opened by a tap) }; set before the panel's
//                          Component.onCompleted. Two entries of the widget on different
//                          presets each open it with their own. While the panel stays open
//                          and is opened again from another entry (by hover), it is given
//                          the new opener; an unchanged one is not set again. Only a
//                          `property var opener` of the root itself is given it: not a
//                          readonly one or one of another type (its status warns), nor one
//                          inherited from a base type
//   availableHeight        `property real availableHeight` — the most height the panel may
//                          take before it must scroll (to a gap short of the screen's edge,
//                          or along a bar at a side); kept current
//   fitsShownHeight        `readonly property bool fitsShownHeight: true` — declared by the
//                          panel: it is then given, as its height, the height shown while the
//                          popup opens and resizes, so what it holds to its edges stays in
//                          sight instead of being cut (its implicitHeight still sizes the
//                          popup)
//   popupAnimating         `property bool popupAnimating` — true while the popup opens,
//                          closes, moves or resizes (a panel may leave out costly parts
//                          meanwhile)
//
// CommandRunner (1.8): runs commands for a module. It is written under the module's main
// object or one of its views; when that is destroyed (the module turned off) its runs are
// ended at once and nothing is called any more.
//   environment            { NAME: value }, added to every run's environment
//   running                how many runs are started and not answered yet
//   start(argv, options)   starts one → a handle { running (bool), cancel() }.
//                          `argv`: a non-empty list of strings, started as it is — no
//                          shell reads it. options, all optional:
//                            timeoutMs       30000; 0: no limit. Past it the command gets
//                                            TERM, and KILL killAfterMs later
//                            killAfterMs     3000
//                            environment     { NAME: value } for this run, on top of the
//                                            runner's: the way to hand over a secret
//                            onLine(line, stream)   each line, of "stdout" and "stderr"
//                            onStdout(text), onStderr(text)   each line of that stream,
//                                            with its line break. Output is read in whole
//                                            lines: what is written without ending the
//                                            line comes when the line, or the stream, ends
//                            keepOutput      true: the result holds both streams, the
//                                            lines joined by line breaks, none after the
//                                            last
//                            maxOutputBytes  1048576: where each kept stream, and a single
//                                            line, is cut (counted in characters)
//                            done(result)    called once, after start() has returned
//                          result, frozen: { ok (exit 0 and none of the rest), code (the
//                          exit status; -1 without one), stdout, stderr, timedOut,
//                          cancelled, failedToStart, truncated, durationMs, error }.
//                          `failedToStart`: the program is not there or cannot run — where
//                          the run has a limit that is read from `timeout`'s exit status,
//                          126 or 127, so a command that exits with one of them itself
//                          reads the same. `error`: "" — or why nothing was run (argv or an
//                          option of the wrong kind); the result is the only place it shows
//   cancel()               TERM, KILL after killAfterMs; no output is handed over from
//                          that moment; done comes with `cancelled: true` when the process
//                          is gone. A run that waits to be started is answered at once
//   cancelAll()            cancel() for every run
//                          The limit is kept by coreutils' `timeout` around the command
//                          (with util-linux's `setpriv`, so that the command dies with
//                          it), both taken from PATH, and only where only root can change
//                          them (as a handle's `programs` judge it) — so a run ends even
//                          when the shell is gone — and by the shell's own timer where one
//                          of the two is missing. What a command prints is text from
//                          outside: show it as plain text, never put it on a command line
//                          unquoted. A callback that throws is logged; the run goes on.
//                          CommandAction and CommandQuery are run by it, without a limit.
//
// A module's programs (1.9), on its handle (api/ModuleHandle.qml). The manifest names them:
// `requires.programs` (without one the module is not loaded) and `optionalPrograms` (a
// missing one does not stop it). The shell looks each up on PATH before the module loads.
//   module.programs        frozen { <name>: { path, trusted, reason } } — `path` absolute,
//                          "" when not found; `trusted`: only root can change what runs (the
//                          path walked as the kernel resolves it — every directory passed,
//                          the directory holding each link met, and the real file root's
//                          and writable by no one else; a Nix store that is root's and that
//                          the user cannot write to counts as root's); a read that failed,
//                          or a name with a line break or a tab, is untrusted;
//                          `reason` says why, in a few words. A new object only when
//                          something in it changed
//   module.programsReady   every program it names has a verdict
//   module.recheckPrograms()  looks them up again (installed or changed since); at most once
//                          every 2 s, a call sooner is done when they are over; the verdicts
//                          stay until the new ones come. The shell does it after the
//                          machine wakes, before `resumed()`
//                          Run a program by its `path`, never by its name; hand one to
//                          anything that runs as root only when `trusted`.
//
// Module test mode (1.10): set only by the shell's test entry points — tests-modules.qml
// (tests/run-modules.sh) in process, a test tree (the lock bed's copy) by its own test seam
// file — never by a variable alone, and never by a module: it is fixed before modules load
// and read-only after; Api.testMode tells it. Then:
//   - a module whose manifest names `testPrograms` (a directory inside the module) gets
//     every program it names from there: module.programs[name] is { path:
//     "<directory>/<testPrograms>/<name>", trusted: true, reason: "test stand-in" }, or
//     path "" when the directory has no such executable file, or when it or the directory
//     leads out of the module through a link — never a program on PATH. Without test mode
//     `testPrograms` is ignored;
//   - Api.openUrl and Notifier's notifications (Api.notify, module.notify) are recorded,
//     not opened or sent; the module's suites read them from ModuleTestKit (qs.tests);
//   - no command a module starts (CommandRunner, CommandAction, CommandQuery,
//     PrivilegedAction) holds a pkexec — as the program or any later word, as handed to
//     env, timeout or setsid — other than a module's `<testPrograms>/pkexec` (pkexec named
//     among its programs): it is answered with an error and nothing runs.
//     PrivilegedAction's `elevate` must be that stand-in. A guard against mistakes, not a
//     sandbox: a shell handed "pkexec" inside a script is not read;
//   - until slice Z, a module written for an API below 1.10 may put a stand-in that lies
//     anywhere into PrivilegedAction's `elevate` (its absolute path): it runs unless a check
//     finds the system's pkexec or a setuid file there, and a check that fails counts as
//     that. Listed in the module's `deprecations`; it will be removed.
//
// Running as administrator (1.11), on a module's handle (api/ModuleHandle.qml). The shell
// knows which module asks from the handle the run is started on.
//   module.privileged.available   a trusted pkexec, setuid root, and a trusted `timeout`
//                          (coreutils) were found
//   module.privileged.unavailableReason   why not, in a few words ("" when available)
//   module.privileged.start(argv, options)   runs a command as root through pkexec →
//                          a handle { running (bool), cancel() }.
//                          `argv`: a real array of strings (not a QML list, not an object
//                          that looks like one), read once when start() is called — the
//                          copy is what is judged and what runs; `argv[0]`: an absolute
//                          path (root's PATH is never searched), normally one of its
//                          programs, `module.programs[name].path`. start() does not check
//                          `trusted`: the module itself must pass only a program whose
//                          `module.programs[name].trusted` is true — a program in a place
//                          the user can write, run as root, lets any user process become
//                          root.
//                          The options are read once too. options:
//                            what            needed: a few words saying what the run does
//                                            ("Send a file", "Connect"), never a sentence;
//                                            control and format characters dropped, white
//                                            space folded, at most 200 characters
//                            timeoutMs       needed: the run's time limit, 1000 to 3600000.
//                                            It starts when the command starts as root,
//                                            after the password: a prompt left open is not
//                                            bounded by it, and holds the queue meanwhile
//                            onLine(line, stream), onStdout(text), onStderr(text)   as
//                                            CommandRunner's: whole lines, as they come
//                            notifyFailures  true: a run that ran and failed, timed out, or
//                                            whose program was not there is notified as
//                                            "<what> failed" under the module's name
//                            done(result)    called once, after start() has returned —
//                                            never while the module is off
//                            environment     (1.14) TEST MODE ONLY: variables for the
//                                            stand-in pkexec and the command it runs, as
//                                            CommandRunner's ({ NAME: "value" }, null
//                                            takes one away; read once into a copy) — so
//                                            a module's suites can give each scenario its
//                                            own stand-in state. Outside module test mode
//                                            a run given one is refused (`error`), nothing
//                                            run: a real privileged run never takes an
//                                            environment its module chose
//                          result, frozen: { ok (exit 0), code (-1 without one), stdout,
//                          stderr, dismissed (pkexec's 126: the prompt dismissed or the
//                          password not accepted — nothing is shown; also a run refused for
//                          the lock), refused (127: not authorised, or no agent answered —
//                          the shell says so once), notFound, timedOut, cancelled, blocked,
//                          error }. A command that itself exits 124, 126, 127 or 137 reads
//                          as the shell's or pkexec's own (both pass its status through),
//                          and so does `timeout`'s own 125 (it failed), 126 (the command
//                          could not be run) or 127 (not found once started): 126 reads as
//                          `dismissed`, 127 as `refused`. The words pkexec ran are the same
//                          either way, so nothing tells them apart; the program is checked
//                          to be there just before, which makes `timeout`'s 127 rare.
//                          Refused before pkexec runs, nothing started. These checks catch
//                          mistakes and keep the command printable as it is; they do not
//                          stop a hostile module, which runs in the shell's process. Against
//                          a module that is not the project's, the user's protection is
//                          knowing what they install. The shell's own prompt shows "Module"
//                          (the manifest's name and id), "Authorization" (`what`) and the
//                          command handed to pkexec one click away, attached when pkexec's
//                          message names that command; past 80 bytes pkexec names only its
//                          first 38 and last 37 bytes, so another command with the same ends
//                          gets the same lines. Another agent's prompt shows polkit's message
//                          alone; then the shell sends a notification just before pkexec
//                          starts, "Module: <name>" and "Authorization: <what>". The refusals:
//                            blocked "unprintable"  a word holds a control or format character
//                                            or a line or paragraph separator (a line
//                                            break, a right-to-left override, U+2028): the
//                                            command could not be shown as it is
//                            blocked "no-purpose"   `what` empty once cleaned
//                            blocked "locked"       the session is locked (dismissed too: the
//                                            user clicks again once unlocked)
//                            notFound        argv[0] is "" (the path of a program not
//                                            found), or not an absolute path, or — checked
//                                            when the run's turn comes — not an executable
//                                            file
//                            error           options of the wrong kind, timeoutMs missing or
//                                            out of range, an environment outside test
//                                            mode, argv not an array of strings, not
//                                            available (the reason)
//                          The words pkexec gets: `<pkexec> <timeout> -k 3 <limit> <argv…>`.
//                          The shell's own `timeout` runs inside pkexec, as root, and ends the
//                          command at its limit (TERM, KILL 3 s later) even when the shell is
//                          gone. Nothing is put around pkexec: once the command runs as root
//                          the shell cannot signal it, and the kernel drops `setpriv
//                          --pdeathsig` at the exec of a setuid program.
//                          cancel(): a run still waiting is answered at once; a started one
//                          gets TERM (which ends pkexec while it asks), no output is handed
//                          over from then, and done comes with `cancelled: true` when it has
//                          exited or 3 s later — run as root it ends at its limit.
//                          One queue for the whole shell: one password question at a time. A
//                          run keeps the next waiting while its question can still come —
//                          with the shell's own prompt until its own request was seen and no
//                          request is open, or 2 s with none (not counted while another
//                          program's request is open); another program's open request holds
//                          it at most 2 minutes, its own as long as it is open; with another agent
//                          until it ends, at most 2 minutes;
//                          a cancelled one until it has exited, or 3 s. A long run does not
//                          hold the others otherwise. The session locked: nothing starts,
//                          the runs waiting end `dismissed`, `blocked: "locked"`; the open
//                          prompt is cancelled, so a run whose pkexec asked ends `dismissed`. The module
//                          turned off: its waiting runs leave, its started ones are
//                          cancelled, nothing is called. One log line per run started, with
//                          the module's id and `what`.
//                          In module test mode the pkexec is the module's own
//                          `<testPrograms>/pkexec` (pkexec named among its programs) and
//                          nothing else: without one `available` is false. The polkit agent
//                          and the lock are then the test kit's (ModuleTestKit).
//   PrivilegedAction keeps working and runs through the same queue: one run at a time per
//                          object, no time limit, no `what` the prompt can show. Its
//                          command is read once. Its default `elevate: ["pkexec"]` (pkexec by
//                          its bare name) is the shell's trusted, setuid pkexec, the one
//                          `module.privileged` uses — never one found first on PATH; none
//                          found: the run fails, not available. An `elevate` set to a path
//                          outside test mode runs as given, unjudged — that ends in slice Z,
//                          with the type.
//
// The file chooser (1.17), on a module's handle (api/ModuleHandle.qml; singletons/FileChooser.qml).
//   module.chooseFiles(options, done)   asks the user for files or a folder → a handle
//                          { open (bool), cancel() }. options, all optional (read once):
//                            mode            "open" (the default: one file) | "openMany"
//                                            (several files) | "folder"
//                            title           plain text: one line, control and format
//                                            characters and "<", ">", "&" dropped, at
//                                            most 60 characters
//                            startDirectory  an absolute path; none or "": the home
//                                            directory (Api.system.home)
//                            done(result)    called once, after chooseFiles has returned —
//                                            never while the module is off
//                          result, frozen: { paths (absolute paths, never URLs; frozen),
//                          cancelled (the user closed it, cancel() was called, or the
//                          session locked while it was open), blocked ("" | "locked": the
//                          session is locked, nothing opened | "busy": a chooser is open
//                          already — one at a time for the whole shell, any module's),
//                          error (options of the wrong kind; the dialog could not be opened
//                          or returned something that is not a local file — never half a
//                          choice) }.
//                          The dialog is the system's: Qt's file dialog, which the user's Qt
//                          platform theme makes the portal's or GTK's, else Qt Quick's own.
//                          Qt Quick's own returns one file even for "openMany"; take
//                          `paths` as one or more. Its folder dialog selects the first
//                          sub-folder as it opens, as if the user had picked it: Open with
//                          nothing else picked gives that sub-folder, and the folder shown
//                          only when it has none (Qt tells the two apart in no way the shell
//                          can see). It is hosted by the shell, not by the
//                          caller's window: a popup can ask and close. The module turned
//                          off: the dialog closes and done is not called. A portal's dialog
//                          is another program's window: the shell cannot close it (on a lock,
//                          the module turned off), and what is chosen in it then is dropped.
//                          The shell reloading closes the dialog; done is not called.
//                          In module test mode no dialog opens: the call is recorded and the
//                          module's suite answers it (ModuleTestKit.chooserCalls,
//                          answerChooser(moduleId, paths), cancelChooser(moduleId)); the
//                          lock is the test kit's (setSessionLocked, or setChooserLocked for
//                          the chooser alone).
//
// A module's API for other modules (1.18; the manifest's fields: singletons/ModuleManifestRules.qml,
// the plan: ModuleMergeRules.dependencyPlan).
//   "exports": { "version": "1.0" }   in the provider's module.json: it offers other modules an
//                          object of its own, its main's `exports` property — a plain QtObject
//                          (`readonly property QtObject exports: QtObject { … }`), read once
//                          when the main is made. Not the main, nothing with a `parent` (an
//                          Item), not its handle (or any of the shell's objects): a dependent
//                          must not be able to climb to the main or act as the provider. What
//                          the object's own properties hand out (a handle put in one, a
//                          function) is the provider's choice, and its responsibility. The version
//                          is the provider's own API's, "major.minor"; what a minor of it may
//                          change is the provider's rule. Declared and not given (no main, no
//                          such property, the wrong kind): an error in the provider's status,
//                          the provider still loads, and its dependents count it as missing.
//   "uses": { "<id>": "1.0" }   in a dependent's module.json: the modules whose exports it
//                          needs, each with the least version: the same major, the provider's
//                          minor at least the one asked for. All are required. A dependent's
//                          main is made after its providers' and destroyed before them.
//   module.uses            (on its handle) frozen { <id>: that module's exports object } — the
//                          object, nothing else of the provider. Set just before the module is
//                          turned on (before its main is made and its views built) and kept,
//                          the same object, until it is turned on again: other modules coming
//                          and going do not touch it, and while the module is off it still
//                          holds what its last main had. Empty for a module never turned on. A
//                          provider turned off, failing or reloaded turns its dependents off
//                          first (state missing-module), and they come back after it; its main
//                          is destroyed only once theirs are gone, so a dependent's main and
//                          views can read module.uses — in bindings, in Component.onDestruction
//                          — for as long as they live. A module turned off and on again
//                          before its old main is gone (in one turn of the event loop) is
//                          pending until it is, so its old main reads its own module.uses to
//                          the end. The shell waits for a dependent's main, not for its views:
//                          a dependent without a main has its views taken down as it goes off,
//                          before the provider's main goes, but not held for. The shell
//                          reloading: every main's Component.onDestruction runs newest first,
//                          so dependents' before their providers'. A dependent listens to the object
//                          from what lives under its main (a `Connections` there goes with
//                          it) and hands it no function to call later: the shell cannot see a
//                          function held by the provider, which could then call into a module
//                          that is off.
//   state "missing-module" a module it uses is not there or not usable, one reason per module
//                          in its errors: "needs module tailscale 1.0: not installed" /
//                          "turned off" / "failed" / "exports no API" / "has 0.9" / "gives no
//                          exports object". Waiting for one: "pending". A cycle of `uses`
//                          (a module using itself too): each module in it fails, the cycle
//                          named ("uses form a cycle: a → b → a", "uses itself").
//
// Reaching into another module or the shell (1.19): a module uses its own handle, qs.api,
// Api.moduleStatus(id) and the exports it `uses`. `Api.module(id)` and the handle's `host`
// still work and are listed in the module's `deprecations` where its code uses them (read
// from its QML and JavaScript files, comments and strings left out: `Api.module(`, and
// `.host` on `module`
// or straight on Api.moduleAt(…) — a handle kept under another name is not found, QML cannot
// notice a property read); both go with the shell's next tightening (`host` then becomes
// `_host`). Importing the shell's singletons (`qs.singletons` and below) or a directory
// outside the module's own is an error in its status, in a JavaScript file's `.import` too;
// the module still loads.
//
// `import qs.components` is deprecated (1.7): with the base types here, qs.api has
// everything a module took from the shell's internal components, which may change in any
// release. A module that still imports it loads as before, and the import is listed in
// its status (`deprecations`, in `modules list`); it becomes an error with the change
// that raises the floor. The imports are read from every QML and JavaScript file under the
// module's directory — in subdirectories too, and ones only a Loader builds — up to 100
// files, 8 directories deep, hidden directories, links and other file systems skipped; a
// file the module does not name (main, its entries' files, tests, qmldir) is read in its
// first 64 KB only, for its imports and the old ways above alike; any other
// import outside what modules may import is a warning in the status (at most 5 per file, 50 per
// module, the rest counted). Files the scan left out or could not read are one warning
// ("imports not checked in N files"), never a silent "no warnings".
Singleton {
    id: root

    readonly property string version: ModuleRules.apiVersion

    // (1.10) Module test mode (above)
    readonly property bool testMode: Modules.host.testMode

    readonly property ThemeTokens theme: ThemeTokens {}

    // (1.12) Helpers (above): plain functions, so a module can pass one around
    readonly property var format: Object.freeze({
        bytes: value => Format.bytes(value),
        rate: value => Format.rate(value),
        ago: (ms, nowMs) => Format.agoMs(ms, nowMs)
    })
    readonly property var address: Object.freeze({
        isIpv4: text => AddressRules.isIpv4(text),
        isIpv6: text => AddressRules.isIpv6(text),
        isIp: text => AddressRules.isIp(text),
        parseCidr: text => AddressRules.parseCidr(text),
        contains: (network, inner) => AddressRules.contains(network, inner),
        overlap: (a, b) => AddressRules.overlap(a, b),
        redact: text => AddressRules.redact(text)
    })

    // (1.12) The start of the current minute, in ms; in test mode the test kit's
    readonly property real minuteNow: ModuleRules.minuteStart(testMode && _testNow > 0 ? _testNow : _minuteClock.date.getTime())
    property SystemClock _minuteClock: SystemClock {
        precision: SystemClock.Minutes
    }
    // Set by ModuleTestKit.setNow in test mode (0: the real clock)
    property real _testNow: 0

    // (1.13) System facts (above): the shell's reading, or in test mode the test kit's
    readonly property var system: testMode ? _systemObject(_testSystemFacts, true) : _systemObject(SystemFacts.facts, false)
    // Set by ModuleTestKit.setSystem in test mode (null: the made-up defaults)
    property var _testSystemGiven: null
    readonly property var _testSystemFacts: SystemFactsRules.testFacts(_testSystemGiven, SystemFactsRules.testDefaults(Modules.host.testHome)).facts

    function _systemObject(facts, test) {
        const forwarding = test ? Object.freeze({ ipv4: facts.ipForwarding?.ipv4 ?? null, ipv6: facts.ipForwarding?.ipv6 ?? null }) : null;
        return Object.freeze({
            ready: facts.ready === true,
            userName: String(facts.userName ?? ""),
            uid: typeof facts.uid === "number" ? facts.uid : null,
            hostName: String(facts.hostName ?? ""),
            home: String(facts.home ?? ""),
            configHome: String(facts.configHome ?? ""),
            dataHome: String(facts.dataHome ?? ""),
            runtimeDirectory: String(facts.runtimeDirectory ?? ""),
            downloadDirectory: String(facts.downloadDirectory ?? ""),
            readIpForwarding: () => test ? forwarding : SystemFacts.readIpForwarding(),
            refresh: () => {
                if (!test)
                    SystemFacts.refresh();
            }
        });
    }

    // The slots the core offers in this API version (ModuleRules.slotTable, the reference)
    readonly property var slots: Object.freeze(ModuleRules.slotTable.map(entry => Object.freeze(Object.assign({}, entry))))

    // (1.20) The anchors the core offers (ModuleRules.anchorTable, the reference), frozen
    readonly property var anchors: Object.freeze(ModuleRules.anchorTable.map(row =>
        Object.freeze(Object.assign({}, row, { placements: Object.freeze((row.placements ?? []).slice()) }))))

    // (1.3, 1.16) Network facts (above). Through a JSON text: a string property notifies only
    // when its value changes, so a module reacting to these is not woken by every re-read of
    // the profiles. In module test mode the test kit's (ModuleTestKit.setNetworks), and the
    // shell's network singletons are not touched
    readonly property string _networksText: testMode ? JSON.stringify(_testNetworkFacts.networks)
        : NetworkProfiles.listRead ? JSON.stringify(ModuleRules.apiNetworks(NetworkProfiles.profiles, NetworkProfiles.wifi)) : "[]"
    readonly property var networks: ModuleRules.frozenRows(_networksText)
    readonly property bool networksReady: testMode ? _testNetworkFacts.networksReady
        : ModuleRules.apiNetworksReady(NetworkProfiles.listRead && NetworkProfiles.listOk, NetworkProfiles.profiles, NetworkProfiles.wifi)

    readonly property string _vpnsUpText: testMode ? JSON.stringify(_testNetworkFacts.vpnsUp)
        : JSON.stringify(ModuleRules.apiVpnsUp(VpnManager.activeVpns, VpnManager.details))
    readonly property var vpnsUp: ModuleRules.frozenRows(_vpnsUpText)

    readonly property bool localNetworksReady: testMode ? _testNetworkFacts.localNetworksReady : IpManager.devicesRead
    readonly property string _localNetworksText: testMode ? JSON.stringify(_testNetworkFacts.localNetworks)
        : IpManager.devicesRead ? JSON.stringify(ModuleRules.apiLocalNetworks(IpManager.devices, VpnManager.vpnInterfaces,
                                                                                  VpnManager.vpnAddresses, IpManager.ipv6Flags)) : "[]"
    readonly property var localNetworks: ModuleRules.frozenRows(_localNetworksText)

    // Set by ModuleTestKit.setNetworks in test mode (null: the defaults — read, none)
    property var _testNetworkGiven: null
    readonly property var _testNetworkFacts: ModuleRules.testNetworkFacts(_testNetworkGiven).facts

    // Deprecated (1.19): listed in the calling module's `deprecations` (found in its code),
    // removed with the shell's next tightening
    function module(id) {
        return Modules.handle(id);
    }

    // (1.19) Another module's plain state (above)
    function moduleStatus(id) {
        return ModuleMergeRules.moduleStatusFacts(typeof id === "string" ? Modules.status(id) : null, Modules.activeIds);
    }

    function moduleAt(url) {
        return Modules.handleAt(url);
    }

    function notify(summary, options) {
        Notifier.send(String(summary), ModuleRules.moduleNotifyOptions(options));
    }

    // A link, given to xdg-open as one argument (no shell). Only with a scheme, and only
    // http:, https: and mailto: — file: too with { allowFile: true }; anything else (a bare
    // path, a .desktop file, another scheme a program is registered for, text starting with
    // "-", control characters, more than 4096 characters) is refused, logged, → false
    // (ModuleRules.openUrlProblem).
    function openUrl(url, options) {
        const text = String(url ?? "");
        const problem = ModuleRules.openUrlProblem(text, options);
        if (problem !== "") {
            console.warn("[Modules] Api.openUrl refused " + JSON.stringify(text.slice(0, 200)) + ": " + problem);
            return false;
        }
        // Test mode: recorded, nothing opened
        if (testMode) {
            _opened = _opened.concat([Object.freeze({ url: text, allowFile: options?.allowFile === true })]).slice(-200);
            return true;
        }
        // No time limit: where xdg-open starts the program itself it lasts as long as it
        _opener.start(["xdg-open", text], {
            timeoutMs: 0,
            maxOutputBytes: 4096,
            done: result => {
                if (!result.ok)
                    console.warn("[Modules] xdg-open " + JSON.stringify(text.slice(0, 200)) + " failed:",
                                 result.stderr.trim().slice(0, 300) || (result.failedToStart ? "it could not be started" : result.code));
            }
        });
        return true;
    }

    function copy(text) {
        Quickshell.clipboardText = String(text ?? "");
    }

    function openSettings(page) {
        Shell.openSettings(String(page ?? ""));
    }

    property Io.CommandRunner _opener: Io.CommandRunner {}
    // What openUrl was asked in test mode, oldest first: frozen { url, allowFile } (read by
    // tests/ModuleTestKit.qml)
    property var _opened: []
}
