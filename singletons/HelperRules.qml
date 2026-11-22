pragma Singleton

import Quickshell
import QtQuick

// What the shell makes of its helper's answers (helper/, h2s-helper) — pure, so
// tests/HelperTest.qml checks every case without the program. `Helper` (I/O) runs
// `h2s-helper --version` once and hands the answer here.
Singleton {
    id: root

    // The line protocol this shell speaks with the helper (helper/src/main.cpp's
    // `protocol`): a helper with another number is out of date, its features off
    readonly property int protocol: 1

    // `h2s-helper --version`'s run (CommandRunner's result: { ok, code, stdout, timedOut,
    // failedToStart, truncated }) → { state, version, problem }:
    //   "ready"     the helper answers and speaks this protocol
    //   "outdated"  it answers with another protocol (an old build: rebuilt at the next
    //               start, or by scripts/build-helper.sh)
    //   "failed"    no readable answer (could not start, failed, said something else)
    // `version` is the shell version it was built for ("" when unknown), plain text, capped.
    function readVersion(result) {
        const failed = problem => ({ state: "failed", version: "", problem: problem });
        if (result === null || typeof result !== "object")
            return failed("no answer");
        if (result.failedToStart === true)
            return failed("could not be started");
        if (result.timedOut === true)
            return failed("did not answer");
        if (result.truncated === true)
            return failed("answered too much");
        if (result.ok !== true)
            return failed("failed (" + result.code + ")");
        const lines = String(result.stdout ?? "").split("\n").map(line => line.trim()).filter(line => line !== "");
        let answer = null;
        try {
            answer = lines.length === 1 ? JSON.parse(lines[0]) : null;
        } catch (error) {
            answer = null;
        }
        if (answer === null || typeof answer !== "object" || Array.isArray(answer)
                || typeof answer.version !== "string" || !Number.isInteger(answer.protocol))
            return failed("gave no readable answer");
        const version = answer.version.replace(/[\s]+/g, " ").trim().slice(0, 40);
        if (answer.protocol !== protocol)
            return { state: "outdated", version: version, problem: "speaks protocol " + answer.protocol + ", the shell " + protocol };
        return { state: "ready", version: version, problem: "" };
    }

    // The log line for a reading's outcome; "" when there is nothing to say (ready; or no
    // helper, which the launcher has said already)
    function logLine(path, reading) {
        if (path === "" || reading.state === "ready" || reading.state === "missing")
            return "";
        if (reading.state === "outdated")
            return path + " is out of date (" + reading.problem + "): its features are off until it is rebuilt";
        return path + " " + reading.problem + ": its features are off";
    }
}
