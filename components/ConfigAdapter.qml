import Quickshell.Io

// What config.json holds (Config, ConfigFile): data that is not a preference, plus the
// profiles, globals and preset library as JSON text. A key here is declared; JsonConfigFile
// keeps the keys a file holds that are not.
JsonAdapter {
    id: root
    property string widgetPresets: ""
    property string profiles: ""
    property string globals: "{}"
    property list<string> migratedKeys: []
    property list<string> disabledModules: []
    property list<string> enabledModules: []
    // ModuleInstallRules.parseAcknowledgements' text: "" until first written
    property string acknowledgedModules: ""
    property string sleepLockNotice: ""
    property string moduleUpdates: ""
    property list<string> screensOff: []
    // The shell version that last wrote this file — for reference, and for
    // migrations that need to know what wrote it
    property string writtenBy: ""
    // Remembered per app by the volume sliders, not a preference
    property JsonObject audio: JsonObject {
        id: _audio
        property string appVolumes: "{}"
    }

    // Whether Bluetooth was left on, remembered by BluetoothPower, not a preference:
    // "" until it is first seen switched, then "on" or "off"
    property JsonObject bluetooth: JsonObject {
        id: _bluetooth
        property string powered: ""
    }

    // Which VPNs the shell brought up with a network, and which were taken down by
    // hand (VpnManager), so a restart keeps them — remembered, not a preference
    property JsonObject network: JsonObject {
        id: _network
        property string vpnMemory: "{}"
        // The blocking rules last loaded and the boot they were loaded in
        // (VpnLockdown: root's to read back, so remembered), and the VPN servers'
        // addresses last found
        property string lockdown: "{}"
    }

    // The NixOS configuration chosen with "Select directory" (an absolute folder, "" for the
    // usual places) and the flake's host chosen with it ("" for /etc/hostname's), and
    // the real paths of configurations outside root's folders whose one-time warning
    // the user took
    property JsonObject nixos: JsonObject {
        id: _nixos
        property string folder: ""
        property string host: ""
        property list<string> homeWarningAcknowledged: []
    }

    // The Google account, its tokens and the calendars picked — data, not settings
    property JsonObject gcal: JsonObject {
        id: _gcal
        property string viewMode: "day"
        property string clientId: ""
        property string clientSecret: ""
        property string accessToken: ""
        property string refreshToken: ""
        property real tokenExpiry: 0
        property list<string> enabledCalendarIds: []
    }
}
