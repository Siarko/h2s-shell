# Draft: Quickshell feature request — D-Bus services from QML (not filed)

Against **Quickshell 0.3.2**. Not checked against master and the upstream tracker was not
searched; do both before filing. If the answer is "a contribution is welcome", h2s-shell
offers one (`notes/plans/idle-lock-flow.md` §18 is what it would replace).

---

## Summary

Let a shell **own a D-Bus name and export an object** from QML: methods answered by QML
functions, properties, and signals emitted from QML. Today a shell can only *consume* D-Bus
through the services Quickshell wraps (MPRIS, UPower, notifications, tray…) or by running
`gdbus`/`busctl` as processes; it cannot *provide* an interface.

## Why

Desktop shells are expected to provide several freedesktop interfaces that have no
Wayland equivalent:

- `org.freedesktop.ScreenSaver` (`Inhibit`/`UnInhibit`, `GetActive`, `ActiveChanged`):
  browsers and video players ask to keep the screen awake through it (Chromium's "Video Wake
  Lock", Firefox, mpv, VLC). A shell doing its own idle and screen-off cannot see these
  requests unless it owns the name. hypridle and swayidle provide it for that reason.
- Small local services a shell needs: a callback endpoint for an OAuth sign-in, a
  per-application interface for other programs to call (`org.<shell>.*`).

Quickshell already links QtDBus and implements servers internally (the notification server,
the StatusNotifierWatcher), so the machinery is there; it is not reachable from QML.

## A possible shape

```qml
import Quickshell.DBus

DBusService {
    bus: DBusService.Session
    name: "org.freedesktop.ScreenSaver"
    replace: false                    // queue behind a current owner instead of taking it
    readonly property bool owned      // true once the bus granted the name
    readonly property string currentOwner   // unique name of the owner while not ours

    DBusObject {
        path: "/org/freedesktop/ScreenSaver"
        interfaceName: "org.freedesktop.ScreenSaver"
        // Methods: name, D-Bus signature, a handler; the caller's unique name is passed so
        // per-client state can be kept and dropped when the client leaves
        DBusMethod { name: "Inhibit"; inSignature: "ss"; outSignature: "u"
                     handler: (caller, app, reason) => root.inhibit(caller, app, reason) }
        DBusMethod { name: "GetActive"; outSignature: "b"; handler: () => root.active }
        DBusSignal { id: activeChanged; name: "ActiveChanged"; signature: "b" }
    }
    // A client's unique name vanishing (NameOwnerChanged with an empty new owner)
    onPeerVanished: uniqueName => root.dropClient(uniqueName)
}
```

What matters more than the names:

1. owning a name with the bus's flags (allow replacement, replace, do not queue) and seeing
   whether it is owned and by whom;
2. methods answered synchronously from QML with typed arguments (basic types, arrays,
   dictionaries `a{sv}`) and a way to return a D-Bus error;
3. the caller's unique name in each call, and a signal when a peer disconnects;
4. emitting signals; exporting properties with `PropertiesChanged`;
5. introspection generated from the declarations.

Asynchronous replies (a handler returning a promise) would be a bonus, not a need.

## What we do meanwhile

A small C++/Qt helper process owns the name and talks to the shell over stdin/stdout lines.
It works, but it adds a build step to an otherwise interpreted configuration, and every
shell that wants these interfaces writes the same helper.
