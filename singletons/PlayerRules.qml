pragma Singleton

import Quickshell

// Rules about media players for the music panel's list (Music): which are listed, which
// hidden, and which application each belongs to. Pure functions on plain values — no
// MPRIS — so the test suite checks them.
Singleton {
    id: root

    // playerctld is no player of its own: it stands in for the last one used, so it would
    // show that one twice, and a pause sent to it reaches whichever player it follows
    function isProxy(dbusName) {
        return (dbusName ?? "") === "org.mpris.MediaPlayer2.playerctld";
    }

    // What a hidden player is remembered by: its name, which stays the same from one run
    // to the next (its bus name has a new instance number each time)
    function key(identity, dbusName) {
        const name = (identity ?? "").trim();
        return name !== "" ? name : busApp(dbusName);
    }

    function isHidden(identity, dbusName, hidden) {
        return (hidden ?? []).includes(key(identity, dbusName));
    }

    // `hidden` with the player's key added or taken out, as a new list
    function withHidden(hidden, playerKey, hide) {
        const list = (hidden ?? []).filter(name => name !== playerKey);
        if (hide)
            list.push(playerKey);
        return list;
    }

    // The application part of a player's bus name: "brave" of
    // "org.mpris.MediaPlayer2.brave.instance13097"
    function busApp(dbusName) {
        const name = (dbusName ?? "").replace(/^org\.mpris\.MediaPlayer2\./, "");
        return name.split(".")[0];
    }

    // The id of the application a player belongs to, from `apps` ([{ id, name }]): the
    // desktop entry it names, else the application of its name ("Brave" names none), else
    // one whose id starts with its bus name's application. "" when none fits.
    function desktopEntryFor(desktopEntry, identity, dbusName, apps) {
        const list = apps ?? [];
        const named = (desktopEntry ?? "").trim();
        if (named !== "" && list.some(app => app.id === named))
            return named;
        const name = (identity ?? "").trim().toLowerCase();
        if (name !== "") {
            const byName = list.find(app => (app.name ?? "").toLowerCase() === name);
            if (byName)
                return byName.id;
        }
        const application = busApp(dbusName).toLowerCase();
        if (application !== "") {
            const byBus = list.find(app => app.id.toLowerCase() === application)
                ?? list.find(app => app.id.toLowerCase().startsWith(application + "-") || app.id.toLowerCase().startsWith(application + "."));
            if (byBus)
                return byBus.id;
        }
        return "";
    }
}
