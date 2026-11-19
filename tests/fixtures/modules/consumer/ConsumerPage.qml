import QtQuick
import qs.api

// The consumer's settings page: bound to the provider's exported property through
// module.uses, unguarded, and saying goodbye through it when it goes
Item {
    property var module: null
    readonly property string greeting: module.uses.provider.greeting

    Component.onDestruction: module.uses.provider.hello("page gone: " + greeting)
}
