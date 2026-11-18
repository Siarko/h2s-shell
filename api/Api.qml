pragma Singleton

import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.io as Io
import qs.singletons.network

// The module API (notes/plans/modules.md, "Module API 1.0", 1.1, 1.2 and 1.3; notes/plans/api-next.md from 1.4): everything a
// module may use of the shell. A module imports `qs.api` and reaches:
//
//   Api.version            "1.11" — this shell's module API, "major.minor". A module's manifest
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
//   Api.slots              the slots the core offers: [{ name, where, context, since }]
//   Api.module(id)         a module's handle (api/ModuleHandle.qml), or null
//   Api.moduleAt(url)      the handle of the module whose directory holds `url` — in any file
//                          of a module: Api.moduleAt(Qt.resolvedUrl("."))
//   Api.notify(summary, options)   a notification (options: Notifier's — body, urgency, icon,
//                          actions…); a module's own handle's notify() names the module
//   Api.openUrl(url, options)  opens a link in the user's programs (xdg-open, no shell): only
//                          http:, https:, mailto: — file: with { allowFile: true }; anything
//                          else (no scheme, a bare path, another scheme) refused, logged, false
//                          In module test mode it opens nothing: the link is recorded
//                          (ModuleTestKit.opened) and true returned, as for one opened
//   Api.testMode           (1.10) true in module test mode — under tests/run-modules.sh and
//                          in a test tree — read-only; below
//   Api.copy(text)         puts text on the clipboard
//   Api.openSettings(page) the settings window on a page, by id (a core page's or a module's)
//   Api.networks           (1.3) the saved networks this computer joins, frozen:
//                          [{ id (the NetworkManager profile UUID, system.vpnWithNetworks' key),
//                          name, kind ("wifi" | "ethernet"), active (bool, fully up) }] — no
//                          hotspots, VPNs, bridges or their ports; active ones first, then
//                          NetworkProfiles' order; empty until the profiles are read. A new
//                          array only when something in it changed
//   Api.vpnsUp             (1.3) the VPNs up now, frozen: [{ name, type ("wireguard", "vpn"…
//                          or "provider"), provider (a provider's providerId, else "") }];
//                          a new array only when something in it changed.
//                          Both show every installed module the saved network names and the
//                          VPN names: modules are trusted and run in the shell's process
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
//                          shows no `checked` and keeps its own width in a layout.
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
//                          middleClicked; its children are the cell's content
//   BarText                text on the bar, turned or stacked on a bar at a side: text,
//                          font, color, alignment, elide, length, leadingGap
//   BarRow                 items along the bar, a row or a column: vertical (read-only),
//                          spacing
//   PointerArea            the MouseArea of a module's own control: lit (its hover look,
//                          a tap included), centred, reach, and a MouseArea's own
//   VpnProvider            a VPN provider (the contract is API 1.1's, written in
//                          components/VpnProvider.qml): providerId (the module's id),
//                          kind, typeName, glyph, entries, ready, busy, canChange,
//                          lockdownNote, settingsPage; connect(entryId, request),
//                          disconnect(entryId, request), attend(entryId);
//                          failed(entryId, what, reason). Its three VPN slots
//                          (network.vpn.row, .card, .page) are manifest `slots`
//                          contributions like any other (Api.slots).
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
//                          alone:
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
//                                            out of range, argv not an array of strings,
//                                            not available (the reason)
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
// `import qs.components` is deprecated (1.7): with the base types here, qs.api has
// everything a module took from the shell's internal components, which may change in any
// release. A module that still imports it loads as before, and the import is listed in
// its status (`deprecations`, in `modules list`); it becomes an error with the change
// that raises the floor.
Singleton {
    id: root

    readonly property string version: ModuleRules.apiVersion

    // (1.10) Module test mode (above)
    readonly property bool testMode: Modules.host.testMode

    readonly property ThemeTokens theme: ThemeTokens {}

    // The slots the core offers in this API version (ModuleRules.slotTable, the reference)
    readonly property var slots: Object.freeze(ModuleRules.slotTable.map(entry => Object.freeze(Object.assign({}, entry))))

    // (1.3) Through a JSON text: a string property notifies only when its value changes, so
    // a module reacting to these is not woken by every re-read of the profiles
    readonly property string _networksText: NetworkProfiles.listRead
        ? JSON.stringify(ModuleRules.apiNetworks(NetworkProfiles.profiles, NetworkProfiles.wifi)) : "[]"
    readonly property var networks: ModuleRules.frozenRows(_networksText)

    readonly property string _vpnsUpText: JSON.stringify(ModuleRules.apiVpnsUp(VpnManager.activeVpns))
    readonly property var vpnsUp: ModuleRules.frozenRows(_vpnsUpText)

    function module(id) {
        return Modules.handle(id);
    }

    function moduleAt(url) {
        return Modules.handleAt(url);
    }

    function notify(summary, options) {
        Notifier.send(String(summary), options ?? {});
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
