import QtQuick

// The Appearance tab's Widgets page: the theme's shapes for these elements (ShapeSettings)
ShapeSettings {
    title: "Widgets"
    hint: "The widgets on the bar: their cells, and the workspaces' pills. The bar itself is on the Bar page."
    sections: [
        { title: "Cells", group: "capsule", hint: "Each widget's cell on the bar" },
        { title: "Workspace pills", group: "workspace" },
        { title: "Tray icons", group: "tray" }
    ]
}
