import QtQuick
import qs.singletons

TestCase {
    suiteName: "Format"

    function run() {
        // --- sizes: what the RAM, disk and VRAM subtitles showed before ---
        assertEqual(Format.bytes(31.2 * 1073741824), "31.2 GB", "gigabytes to one decimal");
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

        // Passed around as a function (LinkSpeedRow's graph peak), not called on Format
        const detached = Format.rate;
        assertEqual(detached(2048), "2 KB/s", "works detached from Format");
    }
}
