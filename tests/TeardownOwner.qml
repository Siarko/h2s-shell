import QtQuick

// An owner for TeardownTest: a type of its own file, so that an owner declared from it is a
// derived type. Made without a parent and destroyed while the collector runs, what is
// declared inside such an owner has lost its properties and functions by the time its
// Component.onDestruction runs (each reads undefined, 0, "" or false).
Item {
}
