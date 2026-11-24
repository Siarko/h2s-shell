pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io as Io
import qs.singletons.network

// The module API: everything a
// module may use of the shell. A module imports `qs.api` and reaches:
//
//   Api.version            "1.40" — this shell's module API, "major.minor". A module's manifest
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
//                          at, frozen [{ path, kind, placements, takes, context, scope, since,
//                          where, view }] (ModuleRules.anchorTable, the reference; 1.28: no
//                          `marks` any more).
//                          A path is <surface>.<view>[.<block>]…[.<region>]: surface "settings" or
//                          "popup" (the bar has none, nor the lock screen); view a settings
//                          page's id or a popup's key; block a block's name, what it holds
//                          (a block repeated per item named by its kind, card or row: the item
//                          is in the context); region a card's "actions", "settings" or
//                          (1.28) "title". A
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
//                                                     name, kind: "wifi", active: fully up,
//                                                     (1.32) ssid: the network's SSID, plain,
//                                                     on one line }. Not on a hotspot's card
//                            settings.network_ethernet.profiles.card.settings (1.24)  the same
//                                                     in the opened card of each wired profile
//                                                     on Settings → System → Network →
//                                                     Ethernet, under the card's rows: append;
//                                                     context as the Wi-Fi network's (kind
//                                                     "ethernet", no ssid)
//                            settings.network_vpn.vpns.card.actions,
//                            settings.network_wifi.saved.card.actions,
//                            settings.network_ethernet.profiles.card.actions (1.25)  the
//                                                     buttons of the same cards: append, (1.29)
//                                                     closed and open — built while the card is
//                                                     closed too, as long as the card is (1.25:
//                                                     only while it was open) —, in the row of
//                                                     buttons on the name's line (or under the
//                                                     name, see below), after the card's own
//                                                     ("Settings…", "Edit"), before "Forget" /
//                                                     "Delete", which stays last; context as
//                                                     the card's settings (the VPN's
//                                                     own-provider). These take a SmallButton
//                                                     only (`takes`): another element is built
//                                                     once (its startup code runs), then
//                                                     destroyed, not shown; an error in the
//                                                     module's status says so. A button with
//                                                     `visible: false` takes no room. Each
//                                                     button at its own width, 6 apart, centred
//                                                     on the line, at most a third of the card
//                                                     wide (a longer label is cut), in the size
//                                                     it sets (1.28; "m", the card's own
//                                                     buttons' size, when it sets none); any
//                                                     kind, with or without confirm. The row
//                                                     stays on the name's line while it fits
//                                                     beside a few characters of the name and
//                                                     the name line's elements; else it stands
//                                                     on a line of its own under the name,
//                                                     right-aligned (wider than the card: the
//                                                     main button alone on that line, the rest
//                                                     under it). The card's own buttons keep
//                                                     their room; the modules' buttons beyond
//                                                     a line's room are cut on the right
//                            settings.network_wifi.saved.card.title,
//                            settings.network_ethernet.profiles.card.title (1.28),
//                            settings.network_vpn.vpns.card.title (1.29)  the name's
//                                                     line of the same cards, closed and open
//                                                     (the VPN's: every VPN's card, whatever
//                                                     its provider — not own-provider):
//                                                     append, after the name; context as the
//                                                     card's settings. For what a module adds
//                                                     to that network (an exit node, a mark of
//                                                     its own): any element — public elements
//                                                     or its own, on theme tokens. Each is as
//                                                     tall as the name's line (given that
//                                                     height, cut to it) and at its own width;
//                                                     all of them, side by side 4 apart in
//                                                     module id order, at most a quarter of the
//                                                     card wide (cut on the right). The name is
//                                                     cut first: the elements keep their place,
//                                                     right after the name, and never cover the
//                                                     card's own parts. An element with
//                                                     `visible: false` takes no room. (1.29)
//                                                     An element made with no implicitWidth and
//                                                     a width of its own (a `Rectangle { width:
//                                                     16 }`) keeps that width; any other follows
//                                                     its implicitWidth, down to none. The
//                                                     elements leave the name less room, so the
//                                                     card's buttons move under the name sooner.
//                                                     A click
//                                                     on an element that takes none opens or
//                                                     closes the card, as on the name
//                            popup.network.wifi.row.title,
//                            popup.network.connections.wired.row.title (1.32)  the name's
//                                                     line of the network popup's rows: each
//                                                     Wi-Fi network in range's, closed and open,
//                                                     and the wired row's — append, after the
//                                                     name, the same rules as the cards' (as
//                                                     tall as the line, a quarter of the row at
//                                                     most, the name cut first; a click on an
//                                                     element that takes none opens or closes
//                                                     the Wi-Fi row). Context as the cards':
//                                                     { networkId, name, kind, active, ssid } —
//                                                     a Wi-Fi network saved: its profile's (of
//                                                     several, the one fully up, else the one
//                                                     coming up, else the one last used); not
//                                                     saved: networkId "" and its SSID as name.
//                                                     ssid: the SSID scanned, saved or not —
//                                                     to tell networks not saved apart and to
//                                                     match saved ones by SSID. Saved as the row
//                                                     has it (it offers Forget then): a hotspot
//                                                     profile is none, and a profile just saved
//                                                     is one a moment later, once its details
//                                                     are read. The wired row (no ssid): the
//                                                     wired profile up on the device; none up:
//                                                     networkId and name "". A long list builds
//                                                     only the rows in view: a row scrolled out
//                                                     goes with its elements and comes back
//                                                     anew, so an element keeps no state of its
//                                                     own there (its module keeps it, by the
//                                                     context). Not in Settings → Wi-Fi's own
//                                                     list of networks in range
//                          A saved Wi-Fi network's card is a place only once its details are
//                          read (until then Api.networks leaves it out: it could be a hotspot)
//   Api.module(id)         the calling module's own handle (api/ModuleHandle.qml) when `id`
//                          is its id, or null. Deprecated (1.19): a module keeps to its own
//                          handle — another module is Api.moduleStatus(id) and its exports
//                          (`uses`, below). (1.36) Another module's id, or a call that does
//                          not come from exactly one module's code: null. A module whose
//                          code calls it has it listed in its `deprecations`; it goes with the
//                          shell's next tightening
//   Api.moduleStatus(id)   (1.19) another module's plain state, frozen { id, name, version,
//                          state (as in `modules list`: "loaded", "disabled", "missing-module",
//                          …), active (true while it is enabled and loaded) }, or null for an
//                          id no module has. Nothing else of it: no handle, no directory, no
//                          errors. It follows the module in a binding
//   Api.moduleAt(url)      the handle of the module whose directory holds `url` — in any file
//                          of a module: Api.moduleAt(Qt.resolvedUrl(".")). (1.36) Only for the
//                          caller's own directory: a `url` of another module, or a call that
//                          does not come from exactly that module's code, gives null
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
//                          peer's or a file's name): the summary on one line (line breaks
//                          and tabs become spaces); (1.28) the body keeps its line breaks
//                          (CR and CRLF as one, tabs as spaces), at most 20 lines, the last
//                          kept one ending in "…"; other control and format characters (a
//                          right-to-left override, a zero-width joiner) dropped, the summary cut
//                          at 200 characters and the body at 1000 with "…"; "&", "<" and ">"
//                          in the body shown as written, never read as markup. A text that
//                          starts with "-" is safe either way. Without it the body is markup,
//                          as the notification spec has it. A category of the shell's own
//                          ("x-qs-…", its toast's "x-qs-shell"), as an option or a hint, is
//                          dropped: a module's notification never looks like the shell's;
//                          (1.33) so is every hint whose key starts with "x-qs-" (case and
//                          white space in front ignored, judged as the server receives it).
//                          → null, or, (1.33) with options.progress on module.notify, a
//                          handle (below); Api.notify refuses a progress (null, nothing
//                          shown, a warning in the log): it has no module to close it when
//                          the module goes.
//                          (1.33) options.expireTime (ms; 0 stays until closed; absent: the
//                          user's time) is followed by the shell's toasts, unless the user
//                          turned that off (Settings → Notifications, "Apps choose how long")
//                          — how long the toast shows; the entry stays in the notification
//                          panel until dismissed, as every notification's does.
//                          Progress (1.33): options.progress, a number 0–100 (-1: a run of
//                          unknown length; anything not a finite number: a plain
//                          notification, null), on the module's own handle, makes a
//                          notification with a bar, and module.notify returns its handle, a
//                          frozen plain object of these four and nothing else:
//                            open      bool: shown or being shown, not closed
//                            state     "starting" (until the server answered) | "running" |
//                                      "done" | "failed" | "cancelled" | "closed" | "unknown"
//                                      (the shell's own notification server does not hold
//                                      it — another daemon owns the name, or it stopped
//                                      answering: nothing more is known, no callbacks)
//                            update({ summary?, body?, progress?, actions?, state?, announce? })
//                                      → true when taken. The texts follow the first call's
//                                      format; state "running", or "done" | "failed" |
//                                      "cancelled", which end the job: after an end state only
//                                      close() is taken. announce: true brings its toast back
//                                      once (or, on screen, starts its time again) — for a
//                                      change of status the user should see (started,
//                                      stalled, done); not with toasts off, no toast screen,
//                                      or the notification panel open. Updates are coalesced:
//                                      a progress-only change at most once a second, the
//                                      newest content wins, an end state always goes
//                            close()   takes it away (an ended job's entry stays until then,
//                                      or until the user dismisses it); no onDismissed
//                          options.toast "brief" (the default; anything else is "brief"): the
//                          toast shows for the user's time, the entry stays with its moving
//                          bar; "whileRunning": the toast stays on screen while the job runs,
//                          and from the update that ends it shows for the user's time. Taken
//                          away by the user, it comes back only by an announce.
//                          options.actions stay after a click (the notification is resident);
//                          options.onDismissed runs once when the user closes it (the job
//                          goes on; send no more updates: none would be shown). Its own
//                          expireTime and x-qs- hints are not used; urgency "critical" is
//                          taken as "normal"; it carries the module's name whatever
//                          options.appName says (a plain notification takes options.appName,
//                          as before). The module's handle keeps its open handles and closes
//                          them when the module is turned off; while it is off a progress
//                          notify shows nothing and returns null. Example:
//                            let job = module.notify("Sending photo.jpg", { body: "to laptop",
//                                format: "plain", progress: 0, toast: "whileRunning",
//                                actions: [{ id: "cancel", label: "Cancel", onTriggered: cancelSend }],
//                                onDismissed: () => job = null });
//                            job.update({ progress: 40 });
//                            job.update({ state: "done", summary: "Sent photo.jpg", actions: [],
//                                         announce: true });
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
//                            distribution       (1.40) which distribution the shell runs on,
//                                               frozen { ready, id, label, facts }: ready
//                                               once the shell's detection has answered; id
//                                               "nixos" | "arch" | "generic" (a system the
//                                               shell has no integration for) and label
//                                               ("NixOS") — "" while not answered, or when
//                                               it could not be told; facts the
//                                               distribution's static facts, a frozen copy
//                                               (lists too), or null with id "": etcManaged
//                                               (/etc is generated from the system's
//                                               configuration), programDirectories,
//                                               setuidWrapperDirectory, pamDirectories,
//                                               pamModuleDirectories,
//                                               networkManagerVpnDirectories,
//                                               polkitRulesDirectory, polkitRulesInstallable,
//                                               helper and builtinModules ("package": the
//                                               system's package ships them), matches and
//                                               markers (how it is detected); the keys and
//                                               kinds are distributions/<id>/
//                                               distribution.json's (DistributionRules
//                                               .manifest). Read-only facts: nothing that
//                                               changes the system is reached through it.
//                                               A module that differs by system reads this,
//                                               never /etc/NIXOS or os-release itself. In
//                                               module test mode the test kit's
//                                               (ModuleTestKit.setDistribution): not
//                                               answered until a suite names one
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
//                          (1.37) Before the module moves to another version, and before a
//                          restore, the shell backs up its configuration: its settings
//                          (mod.<id>.* in every profile and the pinned globals) and its store
//                          — never this directory, only the paths inside it that module.json's
//                          "backup" names (["notes.db", "accounts"]: relative, no ".."). A
//                          named path whose resolved place is outside the directory is left
//                          out; a link inside a named folder is kept as a link. A restore
//                          turns the module off, writes those back and turns it on again.
//   module.icon            (1.26, on its handle) the module's icon as the shell draws it,
//                          frozen: { kind: "glyph" | "svg" | "image", glyph, url (its file's
//                          file:// URL, "" for a glyph), colors: "theme" | "own" }, or null.
//                          Declared once in the manifest ("icon", the format in
//                          ModuleManifestRules.qml): a glyph of the shell's icon font, drawn
//                          in its place's text colour; an SVG file, painted in that colour (a
//                          one-colour drawing follows the theme) or in its own colours with
//                          "colors": "own"; a PNG or WebP picture, in its own colours. A glyph
//                          is a private-use character (U+E000–U+F8FF, U+F0000–U+FFFFD,
//                          U+100000–U+10FFFD) — no emoji, letter, combining mark or
//                          variation selector — and none of the shell's status marks or the
//                          font's other locks and no-entry signs. A file lies inside the
//                          module's directory and passes the file check like every file the
//                          manifest names (links not followed out of it; at most 64 KiB for an
//                          SVG, 256 KiB for a picture). Its content is read only to refuse
//                          external references: an SVG with an <image>, an href or url( not
//                          starting with "#", a <!DOCTYPE>/<!ENTITY>, a style sheet
//                          (<?xml-stylesheet>, @import), a <script> or <foreignObject>, or in
//                          another encoding than UTF-8 is refused; so is a picture whose first
//                          bytes are not its name's type (PNG, WebP). It is drawn, never run. The shell draws it itself
//                          (components/ModuleIcon.qml): a square as tall as a line of body
//                          text, the picture fitted inside. A wrong icon, or a file that
//                          cannot be drawn, is an error in the module's status and null here;
//                          with none the shell shows the first letter of the module's name
//                          (1.28) The icon is the module's face in the list of modules
//                          (Settings → Modules); the shell puts it on no card — a module
//                          shows what it adds to a network in that card's title place
//                          (above). module.setMark / clearMark (1.27) are gone: removed
//                          before any release
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
//                          building blocks, so a module's page looks like the core's.
//                          SectionTitle, Heading (1.34): the children written inside are
//                          controls at the right end of the title's line (a switch for the
//                          section, its buttons); the title then fills the width a layout
//                          gives it. Without children, as before. SectionTitle (1.38): a
//                          line above it across the column, the look of the core's sections;
//                          `divider: false` leaves it out (the first section under a heading)
//   CommandRunner (1.8) — running commands: any number at once, each with a time limit,
//                          its output as it comes, one answer (below)
//   CommandAction, CommandQuery, PrivilegedAction — running commands the shell's way
//   SmallButton (1.4), Dropdown, InputField, Pill, Checkbox, ToggleSwitch, PrivilegedMark
//                          (1.5), SettingsRow, ExpandingRow, Notice (1.6), ProgressBar,
//                          HoverTip (1.31), SidePanel (1.34), StatusPill (1.35) — the public
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
//                          outcome to take); size: "xs" | "s" | "m"; (1.28) defaultSize —
//                          the size of a button that sets no `size`: "m", or what its place
//                          gives (a card's actions: "m"); a module sets `size`, which stays;
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
//                          (1.32) textSize: "small" (the default) | "body" — the theme's
//                          type sizes, never pixels; clicked()
//   Checkbox               (1.5) label, checked (the owner flips it); toggled()
//   ToggleSwitch           (1.5) checked (the owner changes it), and every item's
//                          `enabled`; toggled()
//   PrivilegedMark         (1.5) need — polkit's answer for what the control beside it
//                          does: "auth" (the default: the lock), "no" (not allowed), "yes"
//                          or "" (nothing to mark: hidden, no room taken). An answer it
//                          does not know shows the lock. (1.39) remembered — the module's
//                          `module.privileged.remembered`, for a control that runs through
//                          module.privileged.start: while it is kept, a mark whose need is
//                          "auth" shows an open lock, dimmed, its tooltip the time left ("No
//                          password needed for 4 min"); anything else, or nothing (the
//                          default, null), leaves the mark as `need` says. SwitchRow takes
//                          the same `remembered` for its mark. Where a module sets `visible`
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
//   ProgressBar            (1.31) value — how much is done, 0 to 1 (beyond, the nearer end;
//                          not a number, nothing); below 0, a run of unknown length: a piece
//                          of the fill slides along the track; kind: "normal" (the default,
//                          the accent) | "success" | "warning" | "danger". As thick as the
//                          theme's progress.thickness, its ends progress.radius (at most half
//                          the thickness). Fills the width. (1.35) wave (false by default):
//                          the owner says the bar moves now — bands of light pass through
//                          the filled part, a new one every Theme duration "progressWave",
//                          each crossing in "progressWaveTravel"; none while
//                          full, of unknown length, hidden, or with reduced motion. The bar
//                          does not judge it: a stalled job sets it false.
//   HoverTip               (1.31) text, target (an Item; the item it is written inside unless
//                          given) — a tooltip over the target after a moment's hover: plain
//                          text, wrapped at the tooltip's width, line breaks as spaces, cut
//                          with "…" past 200 characters; empty, nothing shows. It takes no
//                          room (in a layout, none) and leaves the target its clicks and hover.
//   SidePanel              (1.34) a panel from the right over a module's settings page, the
//                          page dimmed beside it: open (the owner sets true; the panel sets
//                          it false when it closes itself), title (one line, plain), size:
//                          "s" | "m" (the default) | "l" — the theme's widths, never wider
//                          than 90 % of the page area; closed(reason) — "close" (its Close
//                          button), "outside" (a click on the dimmed page), "escape" (Escape
//                          closes a dropdown's list open inside it first, the panel at the
//                          next), "replaced" (another SidePanel opened), "page" (the page
//                          changed, the window closed, the module went away), "lock" (the
//                          session locked). The owner setting open false closes it without
//                          a reason. closed("page") for the page or the module going runs
//                          while the page is torn down: other items of the page may already
//                          be gone, so its handler sets only the module's own state. Its one child is its content (`content`, a Component):
//                          built when it opens, destroyed when it has closed, laid out at
//                          the panel's inner width; the panel scrolls it below a fixed
//                          title line — the content must not scroll itself. One open per
//                          page. Anywhere in a module's page tree; elsewhere (a popup
//                          panel, an anchor, the bar) it does not open: `open` goes back to
//                          false, logged once; while the session is locked neither. Takes
//                          no room where written. In module test mode the test kit's page
//                          frame hosts it (ModuleTestKit.pageFrame); setSessionLocked
//                          closes it.
//                          SidePanel { id: files; title: "Files"; size: "l"; ColumnLayout { … } }
//                          SmallButton { label: "Files…"; onClicked: files.open = true }
//   StatusPill             (1.35) a pill that sums up a state: icon (a glyph of the shell's
//                          icon font; "" none), label (one line), kind: "normal" (the
//                          default: icon accent, label text) | "muted" | "success" |
//                          "warning" | "danger" — the icon's and label's colour; parts:
//                          [{ icon, text, kind, tip, line }] — after the label, each an
//                          icon and a short text (a count) in its kind's colour, its tip
//                          over it on hover (HoverTip's rules); expanded (the owner may set
//                          it; a click flips it while there are parts): the parts one per
//                          line under a rule — icon and `line` ("" → the tip, or the text
//                          without one) in the part's colour; toggled(expanded);
//                          expandable (1.36, default true) — false: a click neither expands
//                          it nor reaches what it stands on, tips on hover still. Texts
//                          plain, one line, cut past 80 (oneLine); unknown kinds →
//                          "normal", logged once; past 12 parts the rest dropped, logged
//                          once. Fills no width.
//                          StatusPill { icon: ""; label: "Sending 1/6"
//                                       parts: [{ icon: ""; text: "3"; kind: "muted";
//                                                 tip: "3 queued" }] }
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
//                          widgetType, popup (set by the bar), popupOpen (its popup shows,
//                          opened from this entry — not from another entry of the type; an
//                          entry built in the place of the one that opened it, same type
//                          and preset, takes it over), interactive;
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
//                          failed(entryId, what, reason) — (1.28) the shell sends `what` and
//                          `reason` as a plain notification (one-line title, the reason's
//                          line breaks kept, never read as markup). Its module's elements under its
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
//                            outputAfterCancel  false (1.33); true: cancel() does not
//                                            stop the output — the lines the command
//                                            still prints until it is gone are handed
//                                            over and kept, as before the cancel (for a
//                                            run whose last words matter even when
//                                            stopped)
//                            endWithShell    false (1.33); true: the command ends with
//                                            the shell (a crash, a restart) even without
//                                            a limit — started behind util-linux's
//                                            `setpriv --pdeathsig KILL` where that was
//                                            found, after the shell's look-up of it. What
//                                            the command starts itself does not end with
//                                            it. Without it a run with no limit is
//                                            started as it is, at once, and outlives the
//                                            shell (a program a launcher opens)
//                            maxOutputBytes  1048576: where each kept stream, and a single
//                                            line, is cut (counted in characters). A cut
//                                            sets `truncated` and leaves `ok` alone: a
//                                            reader of the output checks `truncated`
//                            done(result)    called once, after start() has returned
//                          result, frozen: { ok (exit 0, and not timedOut, cancelled or
//                          failedToStart; `truncated` does not change it), code (the
//                          exit status; -1 without one), stdout, stderr, timedOut,
//                          cancelled, failedToStart, truncated, durationMs, error }.
//                          `failedToStart`: the program is not there or cannot run — where
//                          the run has a limit that is read from `timeout`'s exit status,
//                          126 or 127, so a command that exits with one of them itself
//                          reads the same. `error`: "" — or why nothing was run (argv or an
//                          option of the wrong kind); the result is the only place it shows
//   cancel()               TERM, KILL after killAfterMs; no output is handed over from
//                          that moment (with `outputAfterCancel` it still is, and kept);
//                          done comes with `cancelled: true` when the process is gone. A run that waits to be started is answered at once;
//                          one already over whose answer is not handed over yet (refused,
//                          or unable to start) is answered with `cancelled: true` too
//   cancelAll()            cancel() for every run
//                          The limit is kept by coreutils' `timeout` around the command
//                          (with util-linux's `setpriv`, so that the command dies with
//                          it), both taken from PATH, and only where only root can change
//                          them (as a handle's `programs` judge it) — so a run ends even
//                          when the shell is gone — and by the shell's own timer where one
//                          of the two is missing. A run with `endWithShell` and no limit
//                          (or no `timeout`) is started behind `setpriv` alone: a program
//                          that cannot run is then `failedToStart` when it exits 126 or
//                          127 with setpriv's own message last on stderr ("setpriv: …"),
//                          which is in `stderr` and the callbacks too. Runs with a limit
//                          or `endWithShell` wait for the look-up of the two (once, as the
//                          shell starts). What a command prints is text from
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
//     not opened or sent; the module's suites read them from ModuleTestKit (qs.tests).
//     (1.33) A progress notification's handle acts as if the server answered at once, each
//     show, update and close is recorded, and a suite dismisses it or presses one of its
//     actions through ModuleTestKit (dismissNotification, pressNotificationAction);
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
//   (1.36) The declaration: a module that runs anything as administrator says so in its
//   module.json (singletons/ModuleManifestRules.qml has the format):
//     "privileged": { "why": "Connect, change Tailscale's settings", "programs": ["tailscale"] }
//   `why`: a few words for the user, plain text on one line, at most 200 characters;
//   `programs`: names among its requires.programs and optionalPrograms. A malformed block
//   fails the module. The shell refuses module.privileged.start — before any prompt,
//   nothing run, `blocked: "undeclared"`, the reason in `error` and among the module's
//   status errors (logged once per text) — when the module has no such block, when the user
//   has not approved it, or when `argv[0]` is not the path `module.programs` has for one of
//   the declared programs that is `trusted`. PrivilegedAction is refused the same way
//   (command[0] for argv[0]), and also when the shell cannot trace the call to a module's
//   code.
//   Only the module's own code may ask: a call whose stack names another module's directory
//   too, or none, is refused the same way (a handle handed to another module cannot be used
//   for it). Code a module builds with Qt.createQmlObject under another module's URL looks
//   like that module's to the shell: outside what this guard can see.
//   This holds whatever API the manifest asks for. `"author"` (plain text on one line, at most
//   100 characters) names who wrote the module; a new author asks the user again.
//   What it is and what it is not: a guard against a module's mistakes and a statement for
//   the user — an honest module cannot start asking for a password without saying so, and an
//   update that starts asking stops at a question. It is not a sandbox: a module runs in the
//   shell's process and can start programs, pkexec among them, by other means. Against a module that is not the project's, the user's protection is
//   knowing what they install.
//   module.privileged.available   a trusted pkexec, setuid root, and a trusted `timeout`
//                          (coreutils) were found
//   module.privileged.unavailableReason   why not, in a few words ("" when available)
//   module.privileged.remembered   (1.39) what polkit keeps for the shell's process, frozen
//                          { kept, untilMs }: while `kept`, a run through start() asks for no
//                          password until `untilMs` (ms since the epoch; 0 when not kept) —
//                          the shell's remembered administrator authorization. A new object
//                          only when it changes, and when it runs out (kept false then);
//                          forgotten at lock and on the user's "Forget now". A list the
//                          shell could not read is not kept. Hand it to PrivilegedMark's
//                          `remembered` beside a control that runs through start(); a control
//                          that asks through anything else (PrivilegedAction's own program,
//                          another daemon's polkit action) is not covered by it. In module
//                          test mode the test kit's (ModuleTestKit.setRemembered)
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
//                            blocked "undeclared"   (1.36) not declared, not approved, or
//                                            argv[0] not among the declared, trusted programs (the
//                                            declaration, above); in the module's status too
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
//                          found: the run fails, not available. (1.36) Any other `elevate`
//                          outside test mode, and more than one word anywhere, is refused
//                          before anything runs (`error`, the reason in the module's status):
//                          extra words would run a program of their own as root.
//
// The file chooser (1.17), on a module's handle (api/ModuleHandle.qml; singletons/FileChooser.qml).
//   module.chooseFiles(options, done)   asks the user for files or a folder → a handle
//                          { open (bool), cancel() }. options, all optional (read once):
//                            mode            "open" (the default: one file) | "openMany"
//                                            (several files) | "folder"
//                            title           plain text: one line, control and format
//                                            characters and "<", ">", "&" dropped, at
//                                            most 60 characters; none or "": the
//                                            module's name (1.30)
//                            startDirectory  an absolute path; none or "": the home
//                                            directory (Api.system.home)
//                            done(result)    called once, after chooseFiles has returned —
//                                            never while the module is off
//                          result, frozen: { paths (absolute paths, never URLs; frozen),
//                          cancelled (the user closed it, or cancel() was called), blocked
//                          ("" | "locked": the session is locked — nothing opened, or (1.30)
//                          the lock closed the open dialog | "busy": a chooser is open
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
//                          minor at least the one asked for. A version alone is required
//                          (hard). A dependent's main is made after its providers' and
//                          destroyed before them.
//   "uses": { "<id>": { "version": "1.2", "optional": true } }   (1.30) a soft use: the module
//                          loads with or without that provider. When it is there and fits, the
//                          module is made after it and module.uses.<id> is its exports object;
//                          when not (not installed, off, failed, an older or another major,
//                          no exports object), module.uses.<id> is null and the module loads
//                          all the same — a provider that is there and does not fit is a
//                          warning in its status ("can use module x 1.2: has 2.0"). The
//                          provider coming or going while the module is on turns the module's
//                          main off and on again (pending meanwhile; its views are rebuilt when
//                          they read module.uses): module.uses never holds a provider that is
//                          gone, and a main reads one module.uses for its whole life. Each
//                          time, the main starts from nothing: whatever it held in memory is
//                          lost (keep what must last in its data directory or settings). The
//                          mains that use it, hard or soft, restart with it, going before it
//                          (only those given its object: one left out keeps its main).
//                          A soft dependent without a main (views only) is not turned off when
//                          the provider comes or goes: module.uses is replaced by a new object
//                          under its live views, so a binding on module.uses.<id> follows it
//                          (null once the provider has gone) and a view must not keep the old
//                          object; while the provider is pending (restarting, starting) it is
//                          pending too, its views gone until the provider is back. A provider
//                          pending whose manifest does not fit is not waited for. Soft uses
//                          never make a cycle an error: one that would close a cycle is left
//                          out (by dependent id, then provider id), null, and warned about
//                          ("left out, a cycle of uses"). { "version": "1.2" } alone is hard.
//                          One object form for both, so a use is one entry under one id.
//                          (1.36) "source": "<repository address>#<ref>" in the object form:
//                          where to get the provider when it is missing, offered when the
//                          module is installed. Not such an address: an error in the module's
//                          status, the entry kept without a source.
//   module.uses            (on its handle) frozen { <id>: that module's exports object } — the
//                          object, nothing else of the provider. Set just before the module is
//                          turned on (before its main is made and its views built) and kept,
//                          the same object, until it is turned on again: other modules coming
//                          and going do not touch it, and while the module is off it still
//                          holds what its last main had. Empty for a module never turned on. A
//                          provider turned off, failing or reloaded turns its dependents off
//                          first (state missing-module; a soft dependent is turned off and on
//                          again without it), and they come back after it; its main
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
//   state "missing-module" a module it uses (hard) is not there or not usable, one reason per module
//                          in its errors: "needs module tailscale 1.0: not installed" /
//                          "turned off" / "failed" / "exports no API" / "has 0.9" / "gives no
//                          exports object". Waiting for one: "pending". A cycle of `uses`
//                          (a module using itself too): each module in it fails, the cycle
//                          named ("uses form a cycle: a → b → a", "uses itself").
//
// Reaching into another module or the shell (1.19): a module uses its own handle, qs.api,
// Api.moduleStatus(id) and the exports it `uses`. `Api.module(id)` still works for the
// module's own id and is listed in the module's `deprecations` where its code uses it (read
// from its QML and JavaScript files, comments and strings left out: `Api.module(`); it goes
// with the shell's next tightening. (1.36) The handle's `host` is gone (undefined); a module
// whose code still reads `.host` on `module` or straight on Api.moduleAt(…) has that listed
// too — a handle kept under another name is not found, QML cannot notice a property read. Importing the shell's singletons (`qs.singletons` and below) or a directory
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
    // (1.39) module.privileged.remembered in test mode, set by ModuleTestKit.setRemembered
    property var _testRemembered: RememberRules.remembered(null, 5, 0)

    // (1.13) System facts (above): the shell's reading, or in test mode the test kit's
    readonly property var system: testMode ? _systemObject(_testSystemFacts, true, _distribution) : _systemObject(SystemFacts.facts, false, _distribution)
    // Set by ModuleTestKit.setSystem in test mode (null: the made-up defaults)
    property var _testSystemGiven: null
    readonly property var _testSystemFacts: SystemFactsRules.testFacts(_testSystemGiven, SystemFactsRules.testDefaults(Modules.host.testHome)).facts

    // (1.40) Api.system.distribution: a frozen copy of Distribution's answer, never the
    // singleton or its integration; in test mode the one ModuleTestKit.setDistribution named
    readonly property var _distribution: ModuleRules.apiDistribution(testMode
        ? ModuleRules.testDistribution(_testDistributionName, Distribution.detection) : Distribution.detection)
    // Set by ModuleTestKit.setDistribution in test mode (null: not answered)
    property var _testDistributionName: null

    function _systemObject(facts, test, distribution) {
        const forwarding = test ? Object.freeze({ ipv4: facts.ipForwarding?.ipv4 ?? null, ipv6: facts.ipForwarding?.ipv6 ?? null }) : null;
        return Object.freeze({
            ready: facts.ready === true,
            distribution: distribution,
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
        // (1.36) Only the caller's own handle: the stack names its directory alone
        const callers = ModuleRules.stackDirectories(new Error().stack, Modules.host.directories);
        const handle = Modules.handle(id);
        return handle && PrivilegedRules.callerProblem(callers, handle.directory) === "" ? handle : null;
    }

    // (1.19) Another module's plain state (above)
    function moduleStatus(id) {
        return ModuleMergeRules.moduleStatusFacts(typeof id === "string" ? Modules.status(id) : null, Modules.activeIds);
    }

    function moduleAt(url) {
        // (1.36) Only for the caller's own directory
        const callers = ModuleRules.stackDirectories(new Error().stack, Modules.host.directories);
        const handle = Modules.handleAt(url);
        return handle && PrivilegedRules.callerProblem(callers, handle.directory) === "" ? handle : null;
    }

    function notify(summary, options) {
        const checked = ModuleRules.moduleNotifyOptions(options);
        if (checked.progress !== undefined) {
            // A progress notification needs an owner that closes it when the module goes:
            // the module's own handle (module.notify)
            if (!_progressRefusedLogged) {
                _progressRefusedLogged = true;
                console.warn("[Api] notify with a progress is module.notify's: refused, nothing shown");
            }
            return null;
        }
        Notifier.send(String(summary), checked);
        return null;
    }

    property bool _progressRefusedLogged: false

    // What a module gets of Notifier's progress handle (io/NotificationHandle.qml): a frozen
    // plain object whose getters and functions close over the handle — open, state,
    // update(), close() and nothing else, so nothing of how it is sent (the handle, its
    // runner, the server, the run token) is reachable from it. The getters read the
    // handle's properties, so a binding on `job.state` follows it. null for null
    function _notification(handle) {
        if (!handle)
            return null;
        return Object.freeze({
            get open() {
                return handle.open === true;
            },
            get state() {
                return String(handle.state);
            },
            update: changes => handle.update(changes) === true,
            close: () => {
                handle.close();
            }
        });
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
