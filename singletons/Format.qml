pragma Singleton

import QtQuick

// Sizes, rates, lengths of time and moments as text, sizes in binary units (1 KB = 1024 B). Pure functions,
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

    // A length of time in whole seconds, as a time setting's choice reads: "30 s", "5 min",
    // "1 h", "1 h 30 min", "2 min 5 s"; 0 is `zeroLabel` ("0 s" when not given). Not a
    // number, or below 0: ""
    function duration(seconds, zeroLabel) {
        const total = typeof seconds === "number" && Number.isFinite(seconds) ? Math.round(seconds) : -1;
        if (total < 0)
            return "";
        if (total === 0)
            return typeof zeroLabel === "string" && zeroLabel !== "" ? zeroLabel : "0 s";
        const parts = [];
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor(total % 3600 / 60);
        const rest = total % 60;
        if (hours > 0)
            parts.push(hours + " h");
        if (minutes > 0)
            parts.push(minutes + " min");
        if (rest > 0)
            parts.push(rest + " s");
        return parts.join(" ");
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
