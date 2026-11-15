pragma Singleton

import QtQuick

// Sizes and rates as text, in binary units (1 KB = 1024 B). Pure functions, used by the
// hardware sources (RAM, disk, VRAM) and the network speeds.
QtObject {
    readonly property var _units: ["B", "KB", "MB", "GB"]

    // A size: whole megabytes, gigabytes to one decimal — "742 MB", "15.6 GB"
    function bytes(value) {
        return _scaled(value, "", [0, 0, 0, 1]);
    }

    // A rate: megabytes per second get a decimal, being the ones that change — "12 KB/s",
    // "3.4 MB/s"
    function rate(bytesPerSecond) {
        return _scaled(bytesPerSecond, "/s", [0, 0, 1, 1]);
    }

    // The largest unit the value reaches, with that unit's decimals
    function _scaled(value, suffix, decimals) {
        let unit = 0;
        while (unit < _units.length - 1 && Math.abs(value) >= Math.pow(1024, unit + 1))
            unit++;
        return (value / Math.pow(1024, unit)).toFixed(decimals[unit]) + " " + _units[unit] + suffix;
    }

    // How long ago a moment was, as a person says it: "just now", "5 min ago", "3 h ago",
    // "yesterday", "4 days ago", "2 months ago"; "never" for 0 (callers say "Never used"
    // rather than "Last used never"). Both in seconds since 1970.
    function ago(seconds, nowSeconds) {
        if (!(seconds > 0))
            return "never";
        const elapsed = Math.max(0, (nowSeconds ?? Date.now() / 1000) - seconds);
        if (elapsed < 60)
            return "just now";
        if (elapsed < 3600)
            return Math.floor(elapsed / 60) + " min ago";
        if (elapsed < 86400)
            return Math.floor(elapsed / 3600) + " h ago";
        const days = Math.floor(elapsed / 86400);
        if (days === 1)
            return "yesterday";
        if (days < 60)
            return days + " days ago";
        return Math.floor(days / 30) + " months ago";
    }
}
