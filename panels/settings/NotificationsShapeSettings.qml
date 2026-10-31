import QtQuick

// The Appearance tab's Notifications page: the theme's shapes for these elements (ShapeSettings)
ShapeSettings {
    title: "Notifications"
    hint: "Notifications on screen and in the panel, the volume OSD and the shell's messages. Borders' colours are on the Colors page."
    sections: [
        { title: "Toasts", group: "osdToast" },
        { title: "In the panel", group: "notificationCard" },
        { title: "Volume OSD", group: "osdVolume" },
        { title: "Shell messages", group: "osdMessage" }
    ]
}
