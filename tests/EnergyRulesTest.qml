import QtQuick
import qs.singletons

TestCase {
    suiteName: "EnergyRules"

    function _near(actual, expected, message) {
        assert(Math.abs(actual - expected) < 1e-9, message + " — expected " + expected + ", got " + actual);
    }

    function run() {
        // --- what each app used between two samples ---
        const before = [[10, "kitty", 100, 0], [11, "kitty", 50, 1000], [20, "brave", 300, 5000], [30, "gone", 10, 0]];
        const after = [[10, "kitty", 160, 0], [11, "kitty", 70, 1500], [20, "brave", 330, 9000], [40, "new", 5, 0], [41, "idle", 0, 0]];
        const used = EnergyRules.usage(before, after);
        assertEqual(used.apps["kitty"].cpu, 80, "an app's processes summed: 60 + 20");
        assertEqual(used.apps["kitty"].gpu, 500, "and their GPU cycles");
        assertEqual(used.apps["brave"].cpu, 30, "the difference, not the total");
        assertEqual(used.apps["new"].cpu, 5, "a process started in between: all of its time");
        assert(used.apps["gone"] === undefined, "a process gone: nothing");
        assert(used.apps["idle"] === undefined, "an app that used nothing is left out");
        assertEqual(used.cpuTotal, 115, "the CPU total: 80 + 30 + 5");
        assertEqual(used.gpuTotal, 4500, "the GPU total: 500 + 4000");
        const reused = EnergyRules.usage([[50, "old", 900, 0]], [[50, "other", 30, 0]]);
        assertEqual(reused.apps["other"].cpu, 30, "a pid reused by another app is a new process");
        assertEqual(EnergyRules.usage([[1, "a", 50, 0]], [[1, "a", 40, 0]]).cpuTotal, 0, "a counter going back counts as none");

        // --- the baseline ---
        _near(EnergyRules.baseline([5, 3, 9, 4, 3.5, 8, 10, 6, 7, 3.2]), 3.2, "the 20th percentile of ten readings: the second lowest");
        _near(EnergyRules.baseline([4]), 4, "one reading: itself");
        _near(EnergyRules.baseline([]), 0, "none: 0");
        _near(EnergyRules.baseline([0, -1, 5]), 5, "zero and negative readings left out");

        // --- splitting an interval ---
        // 6 W for an hour: 6 Wh; baseline 2 W → 2 Wh to the system, 4 Wh to the apps
        const split = EnergyRules.attribute(6, 3600, { apps: { a: { cpu: 30, gpu: 0 }, b: { cpu: 10, gpu: 0 } }, cpuTotal: 40, gpuTotal: 0 }, 2);
        _near(split.system, 2, "the baseline is the system's");
        _near(split.apps.a, 3, "no GPU used: by CPU share alone, 3/4 of 4 Wh");
        _near(split.apps.b, 1, "and 1/4");
        const withGpu = EnergyRules.attribute(6, 3600, { apps: { a: { cpu: 10, gpu: 0 }, b: { cpu: 0, gpu: 10 } }, cpuTotal: 10, gpuTotal: 10 }, 2);
        _near(withGpu.apps.a, 3, "CPU weighs 0.75: all the CPU, 3 of 4 Wh");
        _near(withGpu.apps.b, 1, "GPU weighs 0.25: all the GPU, 1 Wh");
        const idle = EnergyRules.attribute(3, 3600, { apps: {}, cpuTotal: 0, gpuTotal: 0 }, 2);
        _near(idle.system, 3, "no app used anything: all of it the system's");
        const under = EnergyRules.attribute(1.5, 3600, { apps: { a: { cpu: 5, gpu: 0 } }, cpuTotal: 5, gpuTotal: 0 }, 2);
        _near(under.system, 1.5, "drawing less than the baseline: all of it the system's");
        assert(under.apps.a === undefined, "and nothing to the apps");
        let sum = withGpu.system;
        for (const app in withGpu.apps)
            sum += withGpu.apps[app];
        _near(sum, 6, "the parts add up to what was drawn");

        // --- buckets over time ---
        assertEqual(EnergyRules.bucketStart(1000), 900, "five minutes: 1000 s is in the bucket from 900");
        assertEqual(EnergyRules.bucketStart(1200), 1200, "a bucket's own start");
        let bucket = { t: 900, system: 0, apps: {} };
        bucket = EnergyRules.addToBucket(bucket, { system: 1, apps: { a: 2 } });
        bucket = EnergyRules.addToBucket(bucket, { system: 0.5, apps: { a: 1, b: 3 } });
        _near(bucket.system, 1.5, "a bucket adds the system's parts");
        _near(bucket.apps.a, 3, "and each app's");
        _near(bucket.apps.b, 3, "a new app in it");
        const buckets = [{ t: 0, system: 1, apps: { a: 1 } }, { t: 300, system: 2, apps: { a: 2, b: 5 } }, { t: 600, system: 4, apps: { b: 1 } }];
        const middle = EnergyRules.sumBuckets(buckets, 300, 600);
        _near(middle.system, 2, "a span holds the buckets starting in it: only 300");
        _near(middle.apps.b, 5, "its apps");
        assertEqual(middle.count, 1, "and says how many");
        const all = EnergyRules.sumBuckets(buckets, 0, 900);
        _near(all.system, 7, "the whole span: 1 + 2 + 4");
        _near(all.apps.a, 3, "a: 1 + 2");
        assertEqual(EnergyRules.sumBuckets(buckets, 1000, 2000).count, 0, "a span with no buckets: none");
        assertEqual(EnergyRules.keepBuckets(buckets, 300).length, 2, "older buckets dropped");

        // --- a new charge ---
        assert(EnergyRules.startsNewCharge(4, 2, 100), "unplugged when full");
        assert(EnergyRules.startsNewCharge(1, 2, 96), "unplugged while charging, at 96 %");
        assert(!EnergyRules.startsNewCharge(1, 2, 80), "unplugged at 80 %: the same charge goes on");
        assert(!EnergyRules.startsNewCharge(2, 2, 100), "still discharging: nothing new");
        assert(!EnergyRules.startsNewCharge(2, 1, 100), "plugged in: nothing new yet");

        // --- the list ---
        const ranked = EnergyRules.ranked({ a: 1, b: 5, c: 3, d: 0.5, e: 0.25, z: 0 }, 3);
        assertEqual(ranked.map(row => row.name).join(","), "b,c,Other", "most first, the rest as Other beyond the count");
        _near(ranked[2].wh, 1.75, "Other sums the rest: 1 + 0.5 + 0.25");
        assert(ranked[2].other === true, "and is marked, to stay last");
        assertEqual(EnergyRules.ranked({ a: 1, b: 2 }, 5).map(row => row.name).join(","), "b,a", "fewer than the count: all, no Other");
        assertEqual(EnergyRules.ranked({}, 5).length, 0, "nothing: empty");
    }
}
