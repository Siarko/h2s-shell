import QtQuick
import qs.components
import qs.singletons.polling

TestCase {
    suiteName: "Polling"

    property var _chart: HistoryChart {}

    function _points(times, dt) {
        return times.map(t => ({ t: t, v: 1, dt: dt }));
    }

    function _runLengths(points) {
        return JSON.stringify(_chart._runs(points).map(run => run.length));
    }

    function run() {
        // --- History.append ---
        const hour = History.maxAgeMs;
        let history = History.append([], 5, 2000, 1000);
        assertEqual(JSON.stringify(history), JSON.stringify([{ t: 1000, v: 5, dt: 2000 }]), "a sample records its interval");
        const original = history;
        history = History.append(history, 6, 2000, 3000);
        assertEqual(original.length, 1, "append returns a new array, so bindings see the change");
        history = History.append(history, 7, 2000, 1000 + hour + 1);
        assertEqual(history.length, 2, "samples older than an hour are dropped");
        assertEqual(history[0].t, 3000, "the oldest kept sample is within the hour");

        // --- HistoryChart._runs ---
        assertEqual(_runLengths(_points([0, 2000, 4000, 6000], 2000)), "[4]", "steady sampling is one run");
        assertEqual(_runLengths(_points([0, 2000, 60000, 62000], 2000)), "[2,2]", "a pause breaks the run");
        const slowedDown = _points([0, 2000], 2000).concat(_points([12000, 22000], 10000));
        assertEqual(_runLengths(slowedDown), "[4]", "a slower rate is not a gap");
        const spedUp = _points([0, 10000], 10000).concat(_points([15000, 17000], 2000));
        assertEqual(_runLengths(spedUp), "[4]", "a faster rate after a slow one is not a gap either");
        assertEqual(_runLengths([{ t: 0, v: 1 }, { t: 99999, v: 1 }]), "[2]", "samples without dt are never split");
        assertEqual(_runLengths([]), "[]", "no samples");
    }
}
