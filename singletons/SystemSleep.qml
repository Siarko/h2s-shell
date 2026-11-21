pragma Singleton

import Quickshell

// The machine's sleep, as plain signals for whoever cares beyond the lock screen:
// goingToSleep() when it is about to sleep (logind's PrepareForSleep(true)), resumed() once
// each time it wakes (PrepareForSleep(false)). Lockscreen, which follows logind for its own
// reasons (singletons/lock/LogindMonitor.qml), reports them here; Idle follows both, and the
// module host forwards resumed() to every active module's handle (module API 1.2,
// `module.resumed()`). Neutral on purpose: it knows nothing of the lock screen, idleness or
// modules, so none depends on another through it.
Singleton {
    signal goingToSleep()
    signal resumed()
    // When it last woke (ms since the epoch; 0 before)
    property double lastResumed: 0

    function reportGoingToSleep() {
        goingToSleep();
    }

    function reportResumed() {
        lastResumed = Date.now();
        resumed();
    }
}
