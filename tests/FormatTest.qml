import QtQuick
import qs.singletons

TestCase {
    suiteName: "Format"

    function run() {
        // --- sizes: what the RAM, disk and VRAM subtitles showed before ---
        assertEqual(Format.bytes(31.2 * 1073741824), "31.2 GB", "gigabytes to one decimal");
        const now = 1731400000;
        assertEqual(Format.ago(0, now), "never", "ago: never");
        assertEqual(Format.ago(now - 30, now), "just now", "ago: seconds");
        assertEqual(Format.ago(now - 300, now), "5 min ago", "ago: minutes");
        assertEqual(Format.ago(now - 3 * 3600, now), "3 h ago", "ago: hours");
        assertEqual(Format.ago(now - 30 * 3600, now), "yesterday", "ago: a day");
        assertEqual(Format.ago(now - 4 * 86400, now), "4 days ago", "ago: days");
        assertEqual(Format.ago(now - 90 * 86400, now), "3 months ago", "ago: months");
        assertEqual(Format.bytes(1073741824), "1.0 GB", "exactly a gigabyte");
        assertEqual(Format.bytes(742 * 1048576 + 300000), "742 MB", "whole megabytes");
        assertEqual(Format.bytes(1048576), "1 MB", "exactly a megabyte");
        assertEqual(Format.bytes(2048), "2 KB", "below a megabyte: kilobytes");
        assertEqual(Format.bytes(512), "512 B", "bytes");
        assertEqual(Format.bytes(0), "0 B", "nothing");

        // --- rates: what the network speeds showed before ---
        assertEqual(Format.rate(3.44 * 1048576), "3.4 MB/s", "megabytes per second to one decimal");
        assertEqual(Format.rate(12.4 * 1024), "12 KB/s", "whole kilobytes per second");
        assertEqual(Format.rate(1023.6), "1024 B/s", "bytes per second, rounded");
        assertEqual(Format.rate(0), "0 B/s", "idle");

        // --- terabytes, and what is not a number ---
        assertEqual(Format.bytes(2 * 1099511627776), "2.0 TB", "terabytes to one decimal");
        assertEqual(Format.bytes(1023 * 1073741824), "1023.0 GB", "just below a terabyte: gigabytes");
        assertEqual(Format.rate(1.5 * 1099511627776), "1.5 TB/s", "a rate in terabytes");
        assertEqual(Format.bytes("x") + "|" + Format.bytes(NaN) + "|" + Format.bytes(undefined) + "|" + Format.rate(Infinity), "0 B|0 B|0 B|0 B/s",
                    "not a number: nothing");

        // --- agoMs: the same words, in milliseconds (Api.format.ago) ---
        const nowMs = now * 1000;
        assertEqual(Format.agoMs(0, nowMs), "never", "agoMs: never");
        assertEqual(Format.agoMs(nowMs - 30000, nowMs), "just now", "agoMs: seconds");
        assertEqual(Format.agoMs(nowMs - 59999, nowMs), "just now", "agoMs: just under a minute");
        assertEqual(Format.agoMs(nowMs - 60000, nowMs), "1 min ago", "agoMs: a minute");
        assertEqual(Format.agoMs(nowMs - 5 * 60000, nowMs), "5 min ago", "agoMs: minutes");
        assertEqual(Format.agoMs(nowMs - 3 * 3600000, nowMs), "3 h ago", "agoMs: hours");
        assertEqual(Format.agoMs(nowMs - 30 * 3600000, nowMs), "yesterday", "agoMs: a day");
        assertEqual(Format.agoMs(nowMs - 4 * 86400000, nowMs), "4 days ago", "agoMs: days");
        assertEqual(Format.agoMs(nowMs - 90 * 86400000, nowMs), "3 months ago", "agoMs: months");
        assertEqual(Format.agoMs(nowMs + 60000, nowMs), "just now", "agoMs: a moment after now");
        assertEqual(Format.agoMs("x", nowMs) + "|" + Format.agoMs(NaN, nowMs) + "|" + Format.agoMs(-5, nowMs), "never|never|never", "agoMs: not a moment");
        assertEqual(Format.agoMs(Date.now() - 120000), "2 min ago", "agoMs: now not given");
        assertEqual(Format.ago(String(now - 300), now), "5 min ago", "ago: seconds given as a numeric text, as before");

        // Passed around as a function (LinkSpeedRow's graph peak), not called on Format
        const detached = Format.rate;
        assertEqual(detached(2048), "2 KB/s", "works detached from Format");
    }
}
