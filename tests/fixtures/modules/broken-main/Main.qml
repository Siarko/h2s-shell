import QtQuick

// Throws in Component.onCompleted on purpose (tests/fixtures/modules): the engine catches
// and prints it; the host and the other modules carry on
QtObject {
    Component.onCompleted: {
        throw new Error("broken-main fixture: thrown on purpose in Component.onCompleted");
    }
}
