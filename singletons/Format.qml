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
}
