import QtQuick

// Its suite runs its stand-ins as administrator (tests/PrivilegedRunsTest.qml);
// tests/ModulesTest.qml asks through tryStart, the module's own code
QtObject {
    property var module: null

    function tryStart(argv, options) {
        return module.privileged.start(argv, options);
    }
}
