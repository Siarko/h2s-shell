import QtQuick

// The lock screen's notification detail changed its default from "full" to "app" (2.1.0).
// Seeding spells every default out in the profile named Full, so a config seeded before then
// holds "full" there as if the user had chosen it: Full holding "full" loses it, so the new
// default applies. Any other value there, and every other profile's or the globals', is the
// user's and stays. (Someone who had picked "full" in Full by hand gets the new default once —
// the safer one.) Marked with "default:lockscreen.lockNotificationDetail" in migratedKeys, as
// older versions did, so that an older shell does not do it again.
QtObject {
    readonly property string migrationId: "2.1.0-lock-notification-detail-default"
    readonly property string since: "2.1.0"
    readonly property string summary: "The lock screen's notification detail is at its new default"
    readonly property var scope: ["setting:lockscreen.lockNotificationDetail"]

    readonly property string _key: "lockscreen.lockNotificationDetail"
    readonly property string _marker: "default:lockscreen.lockNotificationDetail"
    readonly property string _formerDefault: "full"

    function ownsRecord(entry) {
        return entry === _marker;
    }

    function appliedBefore(config) {
        return Array.isArray(config.migratedKeys) && config.migratedKeys.includes(_marker);
    }

    function migrate(document, context) {
        if (document.records.includes(_marker))
            return document;
        document.records.push(_marker);
        const full = document.profiles.find(profile => profile.name === "Full");
        if (full && full.set && Object.prototype.hasOwnProperty.call(full.set, _key)
                && JSON.stringify(full.set[_key]) === JSON.stringify(_formerDefault))
            delete full.set[_key];
        return document;
    }
}
