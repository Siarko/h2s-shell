import QtQuick

// The Appearance tab's Controls page: the theme's shapes for these elements (ShapeSettings)
ShapeSettings {
    title: "Controls"
    hint: "Buttons, choices and fields everywhere: popups, settings, the calendar."
    sections: [
        { title: "Buttons", group: "button", hint: "Every button's padding and height; general buttons' corners" },
        { title: "Save buttons", group: "saveButton" },
        { title: "Cancel buttons", group: "cancelButton" },
        { title: "Delete buttons", group: "deleteButton" },
        { title: "Icon buttons", group: "iconButton" },
        { title: "Pills", group: "pill" },
        { title: "Text fields", group: "field" },
        { title: "Check boxes", group: "checkbox" },
        { title: "Tooltips", group: "tooltip" },
        { title: "Outlines", group: "border" },
        { title: "Targets", group: "target", hint: "How far around a control a click or a tap still reaches it" }
    ]
}
