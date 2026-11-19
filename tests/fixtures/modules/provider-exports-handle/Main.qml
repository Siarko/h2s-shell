import QtQuick

// Offers its own module handle as its exports: refused (a dependent would get the
// provider's powers), so its dependents count it as missing ("gives no exports object")
QtObject {
    property var module: null
    readonly property QtObject exports: module
}
