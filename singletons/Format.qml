pragma Singleton

import QtQuick

// Sizes, rates and moments as text, sizes in binary units (1 KB = 1024 B). Pure functions,
// used by the hardware sources (RAM, disk, VRAM), the network speeds and the saved networks'
// "Last used"; modules reach them as Api.format.
QtObject {
    readonly property var _units: ["B", "KB", "MB", "GB", "TB"]

    // A size: whole megabytes, gigabytes and terabytes to one decimal — "742 MB", "15.6 GB",
    // "1.8 TB". Not a number: "0 B"
    function bytes(value) {
        return _scaled(value, "", [0, 0, 0, 1, 1]);
    }

    // A rate: megabytes per second get a decimal, being the ones that change — "12 KB/s",
    // "3.4 MB/s". Not a number: "0 B/s"
    function rate(bytesPerSecond) {
        return _scaled(bytesPerSecond, "/s", [0, 0, 1, 1, 1]);
    }

    // The largest unit the value reaches, with that unit's decimals
    function _scaled(given, suffix, decimals) {
        const value = typeof given === "number" && Number.isFinite(given) ? given : 0;
        let unit = 0;
        while (unit < _units.length - 1 && Math.abs(value) >= Math.pow(1024, unit + 1))
            unit++;
        return (value / Math.pow(1024, unit)).toFixed(decimals[unit]) + " " + _units[unit] + suffix;
    }

    // How long ago a moment was, as a person says it: "just now", "5 min ago", "3 h ago",
    // "yesterday", "4 days ago", "2 months ago"; "never" for 0 (callers say "Never used"
    // rather than "Last used never"). Both in seconds since 1970 (NetworkManager's
    // timestamps); agoMs below in milliseconds.
    function ago(seconds, nowSeconds) {
        const at = Number(seconds);
        if (!(at > 0))
            return "never";
        const now = nowSeconds === undefined || nowSeconds === null ? Date.now() / 1000 : Number(nowSeconds);
        return agoMs(at * 1000, now * 1000);
    }

    // ago() with both moments in milliseconds since 1970 (Date.now()'s; Api.format.ago). A
    // moment after `nowMs` is "just now"; `nowMs` not given: now
    function agoMs(ms, nowMs) {
        if (typeof ms !== "number" || !(ms > 0) || !Number.isFinite(ms))
            return "never";
        const now = typeof nowMs === "number" && Number.isFinite(nowMs) ? nowMs : Date.now();
        const elapsed = Math.max(0, now - ms) / 1000;
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
