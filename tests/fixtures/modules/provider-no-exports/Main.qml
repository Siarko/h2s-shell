import QtQuick

// Declares exports in its manifest and has no `exports` property: its dependents count it
// as missing ("gives no exports object") — known only once this main is made
QtObject {
    property var module: null
}
