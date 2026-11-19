import QtQuick
import qs.api

// The consumer's main: it reads module.uses while it is built, and keeps the provider's
// object to say goodbye through it when it is destroyed
QtObject {
    id: main

    property var module: null
    // module.uses as it was in Component.onCompleted, and the provider's object from it
    property var usesAtStart: null
    property var provider: null
    property string answer: ""

    Component.onCompleted: {
        usesAtStart = module.uses;
        provider = module.uses.provider ?? null;
        answer = provider ? provider.hello("consumer up") : "no provider";
    }
    Component.onDestruction: {
        if (provider)
            provider.hello("consumer gone");
    }
}
