import QtQuick
import qs.api

// Reaches another module and the host the old ways (deprecations, API 1.19). The same words
// in comments and strings do not count: Api.module("x"), module.host
Item {
    property var module: null
    readonly property var other: Api.module("good")
    readonly property bool testing: module?.host?.testMode ?? false
    readonly property string said: "Api.module(\"good\") and module.host"
}
