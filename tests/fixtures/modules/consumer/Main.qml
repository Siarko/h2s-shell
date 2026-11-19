import QtQuick
import qs.api

// The consumer's main: it reads module.uses while it is built, binds to the provider's
// exported property, and says goodbye through module.uses when it is destroyed — all
// without guarding: module.uses must hold the provider's object for as long as this lives
QtObject {
    id: main

    property var module: null
    // module.uses as it was in Component.onCompleted, and the provider's object from it
    property var usesAtStart: null
    property var provider: null
    property string answer: ""
    // Bound, unguarded: a module.uses that emptied under it would throw here
    readonly property string greeting: module.uses.provider.greeting

    Component.onCompleted: {
        usesAtStart = module.uses;
        provider = module.uses.provider ?? null;
        answer = provider ? provider.hello("consumer up") : "no provider";
    }
    Component.onDestruction: {
        module.uses.provider.hello("consumer gone: " + (module.uses === usesAtStart ? "same uses" : "other uses") + ", " + greeting);
    }
}
