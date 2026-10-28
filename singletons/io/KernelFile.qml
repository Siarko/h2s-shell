import Quickshell.Io

// A small kernel file (procfs, sysfs) re-read on every poll, without a subprocess.
//
// Reads are synchronous: these files are generated in memory by the kernel and take
// microseconds, and a synchronous read means values read together in one tick really
// do come from the same moment. A missing or unreadable file reads as "".
FileView {
    blockAllReads: true
    printErrors: false

    function read() {
        reload();
        return text();
    }
}
