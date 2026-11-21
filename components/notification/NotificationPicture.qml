import QtQuick
import Quickshell

// A notification card's pictures (NotificationCard). A notification carries up to two: the
// app's icon (app_icon, or the icon of its desktop entry — Quickshell fills that in) and an
// image (image-data or image-path: an avatar, album art, a screenshot — or, from many apps,
// their logo). The icon sits in the header; a square image is a thumbnail beside the text,
// anything else a preview across the card.
//
// Itself the image, loaded at its own size and never shown, only to learn its shape.
Image {
    id: root

    // The notification's app icon and image, as it gives them
    property string appIcon: ""
    property string image: ""

    readonly property string appIconSource: pictureSource(appIcon)
    // The same picture as the icon is shown once, in the header
    readonly property string imageSource: {
        const source = pictureSource(image);
        return source === appIconSource ? "" : source;
    }
    // "thumbnail", "preview", or "" — known once the image has loaded and its shape is known
    readonly property string imageKind: {
        if (imageSource === "" || status !== Image.Ready)
            return "";
        const width = sourceSize.width, height = sourceSize.height;
        if (width <= 0 || height <= 0)
            return "";
        const aspect = width / height;
        return aspect >= 0.8 && aspect <= 1.25 ? "thumbnail" : "preview";
    }

    // An icon name the theme lacks still loads, as Quickshell's purple checkerboard, so
    // names are looked up first and a missing one shows nothing. A path given as a name
    // (image-path without "file:") becomes a file URL.
    function pictureSource(picture) {
        const value = (picture ?? "").toString();
        if (value === "")
            return "";
        const iconPrefix = "image://icon/";
        const name = value.startsWith(iconPrefix) ? value.slice(iconPrefix.length) : value;
        if (name.startsWith("/"))
            return "file://" + name;
        if (value.startsWith(iconPrefix) || !/^[a-z]+:/.test(value))
            return Quickshell.iconPath(name, true);
        return value;
    }

    visible: false
    source: imageSource
    asynchronous: true
}
