pragma Singleton

import Quickshell
import QtQuick

// The settings a profile can override, with their types and defaults. The defaults
// together are the read-only system profile (see docs/plans/adaptive-polling.md): what
// applies to a key that no active profile sets.
//
// Entry fields:
//   key      — dotted name, as stored in a profile's `set`
//   label    — shown in settings
//   group    — settings section the key is edited in
//   type     — "interval" (ms, 0 = paused), "number", "enum", "bool"
//   default  — value of the system profile
//   min/max  — for interval and number
//   options  — for enum: [{ value, label }]
Singleton {
    id: root

    readonly property var entries: [
        { key: "polling.hardware.interval", label: "Hardware", group: "performance",
          type: "interval", min: 0, max: 600000, default: 2000 },
        { key: "polling.hardware.gpuSampling", label: "GPU load sampling", group: "performance",
          type: "enum", default: "averaged", options: [
              { value: "averaged", label: "Averaged (5 samples/s)" },
              { value: "single", label: "One sample per update" }
          ] },
        { key: "polling.temperatures.interval", label: "Temperatures", group: "performance",
          type: "interval", min: 0, max: 600000, default: 2000 },
        { key: "polling.disk.interval", label: "Disk", group: "performance",
          type: "interval", min: 0, max: 600000, default: 10000 },
        { key: "polling.network.interval", label: "Network throughput", group: "performance",
          type: "interval", min: 0, max: 600000, default: 2000 },
        // A brief wave across every history graph when it takes a sample
        { key: "graphs.heartbeat", label: "Graph heartbeat", group: "performance",
          type: "bool", default: true },
        // Applied by Profiles while a profile sets it (step 6 of the plan); "unchanged"
        // leaves the system's own choice alone
        { key: "system.powerProfile", label: "System power profile", group: "power",
          type: "enum", default: "unchanged", options: [
              { value: "unchanged", label: "Leave unchanged" },
              { value: "power-saver", label: "Power saver" },
              { value: "balanced", label: "Balanced" },
              { value: "performance", label: "Performance" }
          ] }
    ]

    readonly property var _byKey: {
        let map = {};
        for (const entry of entries)
            map[entry.key] = entry;
        return map;
    }

    readonly property var defaults: {
        let values = {};
        for (const entry of entries)
            values[entry.key] = entry.default;
        return values;
    }

    function entry(key) {
        return _byKey[key] ?? null;
    }

    function keysInGroup(group) {
        return entries.filter(entry => entry.group === group).map(entry => entry.key);
    }
}
