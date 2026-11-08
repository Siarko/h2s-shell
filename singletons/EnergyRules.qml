pragma Singleton

import Quickshell
import QtQuick

// How the battery popup estimates use per app (docs/plans/battery-popup.md, stage 3) —
// pure, so tests/EnergyRulesTest.qml checks it. Nothing on Linux measures energy per app
// without root (the CPU's energy counters are root's on purpose), so, as Android does, it
// is estimated from what each app used:
//
// - the energy drawn in an interval is the battery's power times its length;
// - a baseline — a low percentile of the recent power, what the laptop draws with nothing
//   to do: the screen, Wi-Fi, idle — goes to "System and screen";
// - the rest is split between apps by their share of the CPU time and the GPU cycles used
//   in the interval (scripts/energy-sample.py gives both per process).
Singleton {
    id: root

    // How the CPU and the GPU weigh in an app's share, when the GPU was used at all
    readonly property real cpuWeight: 0.75
    // The recent power's percentile taken as the baseline
    readonly property real baselinePercentile: 0.2

    // What each app used between two samples ([[pid, app, cpu, gpu], …]): per process
    // the difference — a process new in the second one started in between, so all of it
    // counts — summed per app; a process gone in the second is lost for its last interval
    function usage(previous, current): var {
        const before = {};
        for (const row of previous ?? [])
            before[row[0]] = row;
        const apps = {};
        let cpuTotal = 0;
        let gpuTotal = 0;
        for (const row of current ?? []) {
            const old = before[row[0]];
            // The same pid for another app is a reused pid: a new process
            const fresh = !old || old[1] !== row[1];
            const cpu = Math.max(0, row[2] - (fresh ? 0 : old[2]));
            const gpu = Math.max(0, row[3] - (fresh ? 0 : old[3]));
            if (cpu === 0 && gpu === 0)
                continue;
            const app = apps[row[1]] ?? (apps[row[1]] = { cpu: 0, gpu: 0 });
            app.cpu += cpu;
            app.gpu += gpu;
            cpuTotal += cpu;
            gpuTotal += gpu;
        }
        return { apps: apps, cpuTotal: cpuTotal, gpuTotal: gpuTotal };
    }

    // The baseline from recent power readings, in watts (0 with none)
    function baseline(powers): real {
        const sorted = (powers ?? []).filter(power => power > 0).sort((a, b) => a - b);
        if (sorted.length === 0)
            return 0;
        return sorted[Math.floor((sorted.length - 1) * root.baselinePercentile)];
    }

    // One interval: `watts` drawn for `seconds`, the apps' `usage`, the `baselineWatts`.
    // → { system: Wh, apps: { app: Wh } }. With no app using anything, all of it is the
    // system's.
    function attribute(watts: real, seconds: real, used, baselineWatts: real): var {
        const energy = Math.max(0, watts) * seconds / 3600;
        const base = Math.min(Math.max(0, watts), Math.max(0, baselineWatts)) * seconds / 3600;
        const active = energy - base;
        const result = { system: base, apps: {} };
        const cpuTotal = used?.cpuTotal ?? 0;
        const gpuTotal = used?.gpuTotal ?? 0;
        if (active <= 0 || (cpuTotal === 0 && gpuTotal === 0)) {
            result.system = energy;
            return result;
        }
        const cpuWeight = gpuTotal > 0 && cpuTotal > 0 ? root.cpuWeight : gpuTotal > 0 ? 0 : 1;
        for (const app in used.apps) {
            const share = cpuWeight * (cpuTotal > 0 ? used.apps[app].cpu / cpuTotal : 0)
                + (1 - cpuWeight) * (gpuTotal > 0 ? used.apps[app].gpu / gpuTotal : 0);
            if (share > 0)
                result.apps[app] = active * share;
        }
        return result;
    }

    // ---- Over time: five-minute buckets ----
    // Use per app is kept in buckets { t (the bucket's start, seconds), system (Wh),
    // apps: { app: Wh } }, so any span of time can be summed — since the last full charge,
    // or a stretch picked on the graph.
    readonly property int bucketSeconds: 300

    function bucketStart(seconds: real): real {
        return Math.floor(seconds / root.bucketSeconds) * root.bucketSeconds;
    }

    // Adds an interval's part ({ system, apps }) to a bucket, new or not → the bucket
    function addToBucket(bucket, part): var {
        const result = { t: bucket.t, system: (bucket.system ?? 0) + part.system, apps: Object.assign({}, bucket.apps) };
        for (const app in part.apps)
            result.apps[app] = (result.apps[app] ?? 0) + part.apps[app];
        return result;
    }

    // What the buckets that start within [from, to) add up to → { system, apps, count }
    function sumBuckets(buckets, from: real, to: real): var {
        const sum = { system: 0, apps: {}, count: 0 };
        for (const bucket of buckets ?? []) {
            if (bucket.t < from || bucket.t >= to)
                continue;
            sum.count++;
            sum.system += bucket.system ?? 0;
            for (const app in bucket.apps ?? {})
                sum.apps[app] = (sum.apps[app] ?? 0) + bucket.apps[app];
        }
        return sum;
    }

    // The buckets no older than `oldest` (seconds)
    function keepBuckets(buckets, oldest: real): var {
        return (buckets ?? []).filter(bucket => bucket.t >= oldest);
    }

    // Unplugged with the battery full or nearly: a new "since full charge" begins.
    // UPower's states: 1 charging, 2 discharging, 4 fully charged, 5 pending charge.
    function startsNewCharge(previousState: int, state: int, percent: real): bool {
        const wasCharging = previousState === 1 || previousState === 4 || previousState === 5;
        return wasCharging && state === 2 && percent >= 95;
    }

    // The apps by energy, most first, the smallest folded into "Other" (last) beyond
    // `count` → [{ name, wh, other }]
    function ranked(totals, count: int): var {
        const rows = Object.keys(totals ?? {}).map(name => ({ name: name, wh: totals[name] }))
            .filter(row => row.wh > 0).sort((a, b) => b.wh - a.wh);
        if (rows.length <= count)
            return rows;
        const rest = rows.slice(count - 1).reduce((sum, row) => sum + row.wh, 0);
        return rows.slice(0, count - 1).concat([{ name: "Other", wh: rest, other: true }]);
    }
}
