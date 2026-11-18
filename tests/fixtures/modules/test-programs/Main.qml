import QtQuick

// Its required program exists only as a stand-in (stand-ins/, its testPrograms): it loads in
// module test mode alone, and there takes every program it names from stand-ins/ — sh too,
// which is not there (tests/ModulesTest.qml, tests/lock/tests/modules.sh)
QtObject {
    property var module: null
}
