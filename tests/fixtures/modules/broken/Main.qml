import QtQuick

// A syntax error on purpose (tests/fixtures/modules): the host must contain it
QtObject {
    property int value: = 3
}
