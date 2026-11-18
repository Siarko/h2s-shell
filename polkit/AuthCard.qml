import QtQuick
import qs.singletons

// The password prompt's card: the lock screen card's look, but opaque — what a window
// behind it shows must not read through the prompt's lines
Rectangle {
    radius: Theme.lock.cardRadius
    color: Theme.overlayOpaque
    border.color: Theme.glassBorder
    border.width: Theme.border.width
}
