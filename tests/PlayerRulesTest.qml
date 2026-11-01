import QtQuick
import qs.singletons

// Media players for the music panel: the proxy left out, hidden ones, their applications
TestCase {
    suiteName: "PlayerRules"

    readonly property var _apps: [
        { id: "spotify", name: "Spotify" },
        { id: "brave-browser", name: "Brave" },
        { id: "org.kde.kdeconnect.app", name: "KDE Connect" },
        { id: "vlc", name: "VLC media player" },
        { id: "mpv-extra", name: "Something else" }
    ]

    function run() {
        assert(PlayerRules.isProxy("org.mpris.MediaPlayer2.playerctld"), "playerctld is a proxy");
        assert(!PlayerRules.isProxy("org.mpris.MediaPlayer2.spotify"), "a player is not");

        assertEqual(PlayerRules.busApp("org.mpris.MediaPlayer2.brave.instance13097"), "brave", "busApp: the instance number dropped");
        assertEqual(PlayerRules.busApp("org.mpris.MediaPlayer2.spotify"), "spotify", "busApp: a plain name");
        assertEqual(PlayerRules.busApp(""), "", "busApp: nothing");

        assertEqual(PlayerRules.key(" Spotify - Pixel 10 Pro ", "org.mpris.MediaPlayer2.kdeconnect.mpris_1"), "Spotify - Pixel 10 Pro",
            "key: the name, trimmed");
        assertEqual(PlayerRules.key("", "org.mpris.MediaPlayer2.vlc.instance2"), "vlc", "key: no name, the bus's application");

        const hidden = ["Audioteka - Pixel 10 Pro"];
        assert(PlayerRules.isHidden("Audioteka - Pixel 10 Pro", "", hidden), "isHidden: by name");
        assert(!PlayerRules.isHidden("Spotify", "", hidden), "isHidden: another is not");
        assert(!PlayerRules.isHidden("Spotify", "", undefined), "isHidden: no list, none hidden");

        assertEqual(JSON.stringify(PlayerRules.withHidden(hidden, "Spotify", true)), JSON.stringify(["Audioteka - Pixel 10 Pro", "Spotify"]),
            "withHidden: added");
        assertEqual(JSON.stringify(PlayerRules.withHidden(hidden, "Audioteka - Pixel 10 Pro", true)), JSON.stringify(hidden),
            "withHidden: hidden twice, listed once");
        assertEqual(JSON.stringify(PlayerRules.withHidden(hidden, "Audioteka - Pixel 10 Pro", false)), "[]", "withHidden: taken out");
        assertEqual(JSON.stringify(hidden), JSON.stringify(["Audioteka - Pixel 10 Pro"]), "withHidden: the list given is not changed");

        assertEqual(PlayerRules.desktopEntryFor("spotify", "Spotify", "org.mpris.MediaPlayer2.spotify", _apps), "spotify",
            "desktopEntryFor: the entry it names");
        assertEqual(PlayerRules.desktopEntryFor("", "Brave", "org.mpris.MediaPlayer2.brave.instance1", _apps), "brave-browser",
            "desktopEntryFor: by the application's name");
        assertEqual(PlayerRules.desktopEntryFor("org.kde.kdeconnect.app", "Spotify - Pixel 10 Pro", "org.mpris.MediaPlayer2.kdeconnect.mpris_1", _apps),
            "org.kde.kdeconnect.app", "desktopEntryFor: a phone's player is KDE Connect's");
        assertEqual(PlayerRules.desktopEntryFor("missing", "VLC", "org.mpris.MediaPlayer2.vlc.instance7", _apps), "vlc",
            "desktopEntryFor: an entry not installed, then by bus name");
        assertEqual(PlayerRules.desktopEntryFor("", "Brave", "", [{ id: "brave-browser", name: "brave" }]), "brave-browser",
            "desktopEntryFor: names compared without case");
        assertEqual(PlayerRules.desktopEntryFor("", "mpv", "org.mpris.MediaPlayer2.mpv", _apps), "mpv-extra",
            "desktopEntryFor: an id starting with the bus's application");
        assertEqual(PlayerRules.desktopEntryFor("", "Unknown", "org.mpris.MediaPlayer2.unknown", _apps), "", "desktopEntryFor: none fits");
    }
}
