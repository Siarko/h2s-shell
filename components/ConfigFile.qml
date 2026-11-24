import QtQuick
import Quickshell.Io
import qs.singletons

// config.json read and written (Config holds one; a suite one on a scratch file): what the
// file says about itself once read — whether it could be read, whether it held the
// acknowledgements, the version that wrote it, and whether that was a newer shell
// (MigrationRules.newerConfig, newerNotice) —, and a save that stamps this version and keeps
// the keys this version does not declare (JsonConfigFile). `adapter` is a ConfigAdapter.
JsonConfigFile {
    id: root

    // The file is there but could not be read or is not a JSON object
    // (ProfileRules.configReadFailed)
    property bool loadFailed: false
    // Whether the file held acknowledgedModules, and the version that wrote it ("" for none)
    property bool acknowledgedModulesInFile: false
    property string writtenByAtLoad: ""
    // Why the file could not be read ("" when it was, or is missing)
    property string readError: ""
    // Written by a newer shell: the banner's and the log line's text (MigrationRules.newerNotice)
    property var newerNotice: MigrationRules.newerNotice(null, Version.number)
    // The version stamped on each save (a suite gives another)
    property string version: Version.number

    // The file was read (or found missing, or unreadable) and the properties above say what
    // it holds
    signal read

    onLoaded: {
        const content = text();
        loadFailed = ProfileRules.configReadFailed("", content);
        readError = "";
        let data = null;
        try {
            data = JSON.parse(content);
        } catch (error) {
            data = null;
        }
        acknowledgedModulesInFile = data !== null && typeof data === "object" && Object.prototype.hasOwnProperty.call(data, "acknowledgedModules");
        writtenByAtLoad = typeof data?.writtenBy === "string" ? data.writtenBy : "";
        newerNotice = MigrationRules.newerNotice(MigrationRules.newerConfig(data?.writtenBy, data?.migratedKeys, version, Migrations.all()), version);
        read();
    }
    onLoadFailed: error => {
        loadFailed = ProfileRules.configReadFailed(error === FileViewError.FileNotFound ? "missing" : "error", "");
        readError = loadFailed ? FileViewError.toString(error) : "";
        acknowledgedModulesInFile = false;
        writtenByAtLoad = "";
        newerNotice = MigrationRules.newerNotice(null, version);
        read();
    }

    // Writes the adapter's content, stamped with this version
    function saveStamped() {
        adapter.writtenBy = version;
        save();
    }
}
