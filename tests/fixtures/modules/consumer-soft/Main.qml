import QtQuick
import qs.api

// The soft consumer's main: module.uses.provider is the provider's object when it is there,
// null when not; it greets through it while built and says goodbye through it as it goes
QtObject {
    property var module: null
    // module.uses as it was in Component.onCompleted
    property var usesAtStart: null
    property string answer: ""

    Component.onCompleted: {
        usesAtStart = module.uses;
        answer = module.uses.provider ? module.uses.provider.hello("soft up") : "no provider";
    }
    Component.onDestruction: {
        if (module.uses.provider)
            module.uses.provider.hello("soft gone: " + (module.uses === usesAtStart ? "same uses" : "other uses"));
    }
}
