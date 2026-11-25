pragma Singleton

import Quickshell

// A process of the shell's tree that must not reach the session it runs in: set by an entry
// file before anything else loads (mockup.qml), and never unset. Then no module loads (the
// module host in module test mode, H2S_SHELL_MODULES not read), no notification server is
// registered on the session bus, Notifier records instead of sending, and the helper the
// launcher found (H2S_SHELL_HELPER) is not run — whatever environment the process inherited.
Singleton {
    property bool active: false
    // false: what holds the keyboard while shown (FocusTrap's holdsFocus) no longer takes it
    // back when it moves out. Set only by the mockups' kit, while it shows every state at once:
    // several open modals side by side would take the keyboard from each other without end
    property bool keyboardHeld: true
}
