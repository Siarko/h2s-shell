pragma Singleton

import Quickshell

// The machine's sleep, as a plain signal for whoever cares beyond the lock screen: resumed()
// once each time it wakes (logind's PrepareForSleep(false)). Lockscreen, which follows logind
// for its own reasons (singletons/lock/LogindMonitor.qml), reports it here; the module host
// forwards it to every active module's handle (module API 1.2, `module.resumed()`). Neutral
// on purpose: it knows nothing of the lock screen or of modules, so neither depends on the
// other through it.
Singleton {
    signal resumed()
    // When it last woke (ms since the epoch; 0 before)
    property double lastResumed: 0

    function reportResumed() {
        lastResumed = Date.now();
        resumed();
    }
}
