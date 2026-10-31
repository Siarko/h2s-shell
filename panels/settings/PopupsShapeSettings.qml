import QtQuick

// The Appearance tab's Popups page: the theme's shapes for these elements (ShapeSettings)
ShapeSettings {
    title: "Popups"
    hint: "The popups opening from the bar, and what is in them. Their colours, and the border's, are on the Colors page."
    sections: [
        { title: "Popup", group: "popup" },
        { title: "Widths", group: "popupWidth",
          hint: "Popups grow with the theme's text; these widen or narrow them on top of that. Each one's width as it comes out is beside it." },
        { title: "Rows and cards", group: "row" },
        { title: "Menu and list items", group: "listItem" },
        { title: "Dropdowns", group: "dropdown" },
        { title: "Power menu", group: "powerMenu" }
    ]
}
