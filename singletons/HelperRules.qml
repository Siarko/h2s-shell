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
    readonly property int protocol: 3

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

    // ---- `h2s-helper screensaver` (singletons/helper/ScreenSaverClient.qml) ----

    // How long an app's name and its reason may be where the shell shows them
    readonly property int maxAppLength: 64
    readonly property int maxReasonLength: 128
    readonly property int maxOwnerLength: 40
    // Holders kept from one list (the helper allows 64)
    readonly property int maxHolders: 64

    // Text from outside on one line, capped (shown as plain text by every view)
    function plainLine(text, length) {
        return String(text ?? "").replace(/[\s\u0000-\u001f\u007f]+/g, " ").trim().slice(0, length);
    }

    // One line from the helper → the message, its text from apps made plain and capped; null
    // for a line that is not one of the protocol's:
    //   { event: "ready", protocol }       { event: "name", owned, owner, released }
    //       (released: true after the shell's { own: false }, owned then false)
    //   { event: "inhibitors", list: [{ app, reason, cookie, caller }] }   (sorted by
    //       cookie; caller: the app's unique bus name, "" when not one)
    //   { event: "activity" }   { event: "setActive", id }   { event: "askIdle", id }
    //   { event: "error", message }
    function readServiceLine(line) {
        let message = null;
        try {
            message = JSON.parse(String(line ?? ""));
        } catch (error) {
            return null;
        }
        if (message === null || typeof message !== "object" || Array.isArray(message))
            return null;
        switch (message.event) {
        case "ready":
            return Number.isInteger(message.protocol) ? { event: "ready", protocol: message.protocol } : null;
        case "name":
            if (message.released === true)
                return { event: "name", owned: false, owner: "", released: true };
            if (message.owned === true)
                return { event: "name", owned: true, owner: "", released: false };
            if (message.owned === false)
                return { event: "name", owned: false, owner: plainLine(message.owner, maxOwnerLength), released: false };
            return null;
        case "inhibitors": {
            if (!Array.isArray(message.list))
                return null;
            const list = message.list
                .filter(entry => entry !== null && typeof entry === "object" && Number.isInteger(entry.cookie) && entry.cookie > 0)
                .map(entry => ({ app: plainLine(entry.app, maxAppLength), reason: plainLine(entry.reason, maxReasonLength), cookie: entry.cookie,
                                 caller: typeof entry.caller === "string" && /^:[0-9]+\.[0-9]+$/.test(entry.caller) ? entry.caller : "" }))
                .sort((first, second) => first.cookie - second.cookie)
                .slice(0, maxHolders);
            return { event: "inhibitors", list: list };
        }
        case "activity":
            return { event: "activity" };
        case "askIdle":
        case "setActive":
            return Number.isInteger(message.id) && message.id > 0 ? { event: message.event, id: message.id } : null;
        case "error":
            return { event: "error", message: plainLine(message.message, 200) };
        default:
            return null;
        }
    }

    // Whether the shell asks for org.freedesktop.ScreenSaver: only while one of its idle
    // stages runs — the screensaver, screens off, the idle lock or the sleep, as
    // IdleRules.config resolves them (`saverAfter`, `screenOffAfter`, `lockAfter`,
    // `sleepAfter`: 0 off; a monitor's own
    // times in `times`; a screen-off without power control is the screensaver there, still
    // a stage) — since apps' requests hold only those. With none the name is left free, so an idle daemon doing idle instead
    // (hypridle) can own it and hear the apps. The lock screen's own screen-off does not
    // count: requests are ignored while locked
    function wantsScreenSaverName(config) {
        if (config === null || typeof config !== "object")
            return false;
        const on = seconds => typeof seconds === "number" && seconds > 0;
        const monitors = config.times !== null && typeof config.times === "object" ? Object.values(config.times) : [];
        return on(config.saverAfter) || on(config.screenOffAfter) || on(config.lockAfter) || on(config.sleepAfter)
            || monitors.some(times => on(times?.saverAfter) || on(times?.screenOffAfter));
    }

    // The shell's word on the name, for the helper
    function ownMessage(own) {
        return { own: own === true };
    }

    // The screensaver's state for the helper: { active, since (epoch s, 0 when inactive) }
    function activeMessage(active, sinceMs) {
        const since = active === true && typeof sinceMs === "number" && isFinite(sinceMs) && sinceMs > 0 ? Math.floor(sinceMs / 1000) : 0;
        return { active: active === true, since: since };
    }

    // The answer to askIdle `id`: whole seconds without input, never negative
    function idleMessage(id, seconds) {
        const value = Number(seconds);
        return { answer: id, idleSeconds: isFinite(value) && value > 0 ? Math.floor(value) : 0 };
    }

    // The answer to setActive `id` (an app's SetActive(true)): whether it took
    function setActiveMessage(id, taken) {
        return { answer: id, taken: taken === true };
    }

    // The holders of a helper that ended, handed to the next one to take over (those with a
    // caller; the helper keeps the ones whose caller is still on the bus); null for none
    function adoptMessage(holders) {
        const list = (Array.isArray(holders) ? holders : [])
            .filter(holder => holder?.caller && Number.isInteger(holder.cookie) && holder.cookie > 0)
            .map(holder => ({ caller: holder.caller, app: holder.app, reason: holder.reason, cookie: holder.cookie }));
        return list.length > 0 ? { adopt: list } : null;
    }

    // The screensaver interface as the Screensaver page tells it → { state, line }:
    //   "notBuilt"   no helper (the line: "Not built")
    //   "outdated"   a helper of another protocol, "failed" one that does not answer or
    //                keeps ending
    //   "starting"   started, the bus name not known yet
    //   "answering"  the shell owns org.freedesktop.ScreenSaver
    //   "taken"      another program owns it (the line names it); the shell gets it when
    //                that program lets go
    //   "released"   the shell leaves it free: none of its idle jobs is on
    // `helperState` is Helper.state, `clientState` ScreenSaverClient.state, `name` its name.
    function serviceStatus(helperState, clientState, name) {
        if (helperState === "missing")
            return { state: "notBuilt", line: "Not built" };
        if (helperState === "outdated" || clientState === "outdated")
            return { state: "outdated", line: "The helper is out of date" };
        if (helperState === "failed" || clientState === "failed")
            return { state: "failed", line: "The helper does not answer" };
        if (clientState === "running" && name?.released === true)
            return { state: "released", line: "Left to other programs while idle is off" };
        if (clientState === "running" && name?.owned === true)
            return { state: "answering", line: "" };
        if (clientState === "running" && name?.owned === false)
            return { state: "taken", line: nameTakenLine(name.owner) };
        return { state: "starting", line: "" };
    }

    function nameTakenLine(owner) {
        const who = plainLine(owner, maxOwnerLength);
        return (who !== "" ? who : "Another program") + " answers apps that ask to keep the screen on. Stop it to let the shell do it.";
    }
}
