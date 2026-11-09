pragma Singleton

import Quickshell
import QtQuick

// The battery widget's rules — which icon a charge shows, which colour the thresholds
// give it. Pure, so tests/BatteryRulesTest.qml checks them.
Singleton {
    id: root

    // Nerd Font (Material Design) battery icons, checked against the font's glyph names:
    // the charge in tens, empty, and charging alike
    readonly property var _discharging: ({
        0: 0xf008e,   // md-battery_outline
        10: 0xf007a, 20: 0xf007b, 30: 0xf007c, 40: 0xf007d, 50: 0xf007e,
        60: 0xf007f, 70: 0xf0080, 80: 0xf0081, 90: 0xf0082,
        100: 0xf0079  // md-battery
    })
    readonly property var _charging: ({
        0: 0xf089f,   // md-battery_charging_outline
        10: 0xf089c, 20: 0xf0086, 30: 0xf0087, 40: 0xf0088, 50: 0xf089d,
        60: 0xf0089, 70: 0xf089e, 80: 0xf008a, 90: 0xf008b,
        100: 0xf0085  // md-battery_charging_100
    })
    readonly property int _noBattery: 0xf125e  // md-battery_off_outline

    // The charge in tens, 0–100, from a percentage
    function step(percent: real): int {
        return Math.max(0, Math.min(100, Math.round(percent / 10) * 10));
    }

    // The icon: no battery (absent, or not read yet), else the charge, charging or not
    function icon(present: bool, percent: real, charging: bool): string {
        if (!present)
            return String.fromCodePoint(root._noBattery);
        return String.fromCodePoint((charging ? root._charging : root._discharging)[root.step(percent)]);
    }

    // UPower's device states (org.freedesktop.UPower.Device.State) on the charger:
    // charging, fully charged, pending charge
    function isCharging(state: int): bool {
        return state === 1 || state === 4 || state === 5;
    }

    // The laptop's battery among UPower's devices — EnumerateDevices through
    // `busctl --json=short`: {"type":"ao","data":[[path, …]]}. Its path names the kernel's
    // battery (battery_BAT0, battery_BAT1); another battery (a stylus's, a mouse's) only if
    // there is no such one. "" when there is none.
    function laptopBatteryPath(text: string): string {
        let paths = [];
        try {
            paths = JSON.parse(text).data?.[0] ?? [];
        } catch (error) {
            return "";
        }
        return paths.find(path => /\/battery_BAT\d+$/.test(path))
            ?? paths.find(path => /\/battery_/.test(path)) ?? "";
    }

    // A history from UPower — GetHistory through `busctl --json=short`:
    // {"type":"a(udu)","data":[[[time, value, state], …]]}, newest first — as
    // [{ t (seconds), v, state }] oldest first, without the entries of unknown state
    // (UPower marks a restart with a zero of state 0)
    function parseHistory(text: string): var {
        let rows = [];
        try {
            rows = JSON.parse(text).data?.[0] ?? [];
        } catch (error) {
            return [];
        }
        return rows.filter(row => Array.isArray(row) && row.length === 3 && row[2] !== 0)
            .map(row => ({ t: row[0], v: row[1], state: row[2] }))
            .sort((a, b) => a.t - b.t);
    }

    function isHexColor(text: string): bool {
        return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(text);
    }

    // The colour for a charge: each threshold { value, color } colours a charge at or
    // below its value, the tightest winning — so with 15 → red and 30 → orange, 10 % is
    // red, 25 % orange, 50 % `fallback`. Their order does not matter; a threshold with no
    // number or no valid hex colour is left out.
    function color(percent: real, thresholds, fallback: color): color {
        let best = null;
        for (const threshold of thresholds ?? []) {
            const value = Number(threshold?.value);
            if (threshold?.value === "" || !isFinite(value) || !root.isHexColor(String(threshold?.color ?? "")))
                continue;
            if (percent <= value && (best === null || value < best.value))
                best = { value: value, color: threshold.color };
        }
        return best !== null ? best.color : fallback;
    }

    // The widget's colour: plugged in (`charging`) with a valid `chargingColor`, that;
    // otherwise the thresholds' (color())
    function widgetColor(percent: real, thresholds, charging: bool, chargingColor, fallback: color): color {
        if (charging && root.isHexColor(String(chargingColor ?? "")))
            return chargingColor;
        return root.color(percent, thresholds, fallback);
    }
}
