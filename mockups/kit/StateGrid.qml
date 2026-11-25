import QtQuick
import qs.singletons

// The cells of a component's or a view's states, laid out by the kit's layout (the
// MockupWindow sets `mockup` when it starts, and from then on the content's size, the subject
// and the place of every cell follow the grid):
//   shot  every cell at its place in rows of cellsPerRow (stacked: all at the corner, only the
//         current one shown), the parking strip under them: the shooter crops to the current
//         cell
//   all   on screen, every cell under its label (the state's name and description), in rows
//         that fit the window (stacked: one under another); a pointer state's label says how
//         to see it, as one pointer cannot light every cell at once
//   one   on screen, the current cell alone under its label, at its size
// The mockup gives each state a StateCell (a Repeater over `names` as a rule), its items
// inside; a cell is cellWidth x cellHeight unless the mockup sizes it otherwise (the
// subject is the cell). The pointer rests on `parking`, off every cell, when no cell is to be
// under it: nothing is shown or hidden under the pointer as the states go by.
Item {
    id: grid

    readonly property bool isStateGrid: true

    property int cellWidth: 100
    property int cellHeight: 100
    // While shooting: the cells in a row
    property int cellsPerRow: 1
    // Cells too large to lie side by side: on one another while shooting, one under
    // another on screen
    property bool stacked: false
    // The height of the strip the pointer rests on, under the cells
    property int parkingHeight: 0
    property alias parking: _parking

    // Set by the kit when it starts; until then no cell is shown
    property QtObject mockup: null
    // On screen, the width the cells flow in (the window's)
    property real availableWidth: 0

    readonly property string layout: mockup ? mockup.layout : ""
    readonly property var _names: mockup ? Array.prototype.slice.call(mockup.names) : []
    readonly property int _count: _names.length

    // On screen: the room round the cells and between them, and a label's least width
    readonly property int _gap: 16
    readonly property int _labelMinWidth: 240
    readonly property int _slotWidth: Math.max(cellWidth, _labelMinWidth)

    readonly property int _shotColumns: stacked ? 1 : Math.max(1, cellsPerRow)
    readonly property int _shotGridHeight: stacked ? cellHeight : Math.ceil(_count / _shotColumns) * cellHeight
    readonly property int _flowColumns: stacked ? 1
        : Math.max(1, Math.min(_count, Math.floor((availableWidth - _gap) / (_slotWidth + _gap))))
    readonly property int _preferredColumns: stacked ? 1 : Math.max(1, Math.min(_count, cellsPerRow))

    // The cells in their states, in the order of the names
    readonly property var cells: {
        const found = [];
        for (const child of children)
            if (child.isStateCell)
                found.push(child);
        const names = _names;
        return found.sort((a, b) => names.indexOf(a.name) - names.indexOf(b.name));
    }
    readonly property Item currentCell: {
        const name = mockup ? mockup.current : "";
        for (const cell of cells)
            if (cell.name === name)
                return cell;
        return null;
    }

    // A label's text: the state's name and description, and for a pointer state in the
    // all-states layout how to see it
    function labelText(name) {
        const index = _names.indexOf(name);
        const description = index >= 0 && mockup ? mockup.descriptions[index] ?? "" : "";
        return name + " — " + description + (layout === "all" && mockup ? mockup.hintFor(name) : "");
    }

    function _labelHeight(name) {
        const label = _labels.itemAt(_names.indexOf(name));
        return label ? label.implicitHeight : 0;
    }

    // The places of the labels and the cells and the size they take, for `columns` columns
    function _flow(columns) {
        const labels = {}, cellsAt = {};
        let y = _gap, width = _gap + columns * (_slotWidth + _gap);
        for (let first = 0; first < _count; first += columns) {
            let labelHeight = 0, cellHeight = 0;
            const row = _names.slice(first, first + columns);
            for (const name of row) {
                labelHeight = Math.max(labelHeight, _labelHeight(name));
                const cell = cells.find(c => c.name === name);
                cellHeight = Math.max(cellHeight, cell ? cell.height : grid.cellHeight);
            }
            row.forEach((name, i) => {
                const x = _gap + i * (_slotWidth + _gap);
                labels[name] = Qt.point(x, y);
                cellsAt[name] = Qt.point(x, y + labelHeight + 4);
            });
            y += labelHeight + 4 + cellHeight + _gap;
        }
        return { labels: labels, cells: cellsAt, width: width, height: y };
    }

    readonly property var _places: {
        // The labels' heights are read through the Repeater: laid out again as they come
        void _labels.count;
        if (layout === "all")
            return _flow(_flowColumns);
        if (layout === "one") {
            const name = mockup.current;
            const labelHeight = _labelHeight(name);
            const cell = currentCell;
            const labels = {}, cellsAt = {};
            labels[name] = Qt.point(_gap, _gap);
            cellsAt[name] = Qt.point(_gap, _gap + labelHeight + 4);
            return { labels: labels, cells: cellsAt, width: _gap + Math.max(_slotWidth, cell ? cell.width : 0) + _gap,
                     height: _gap + labelHeight + 4 + (cell ? cell.height : cellHeight) + _gap };
        }
        return { labels: {}, cells: {}, width: _shotColumns * cellWidth, height: _shotGridHeight };
    }

    // The size the content takes as laid out, and the size the window opens at
    readonly property int laidWidth: _places.width
    readonly property int laidHeight: _places.height + parkingHeight
    readonly property int preferredWidth: layout === "all" ? _gap + _preferredColumns * (_slotWidth + _gap) : laidWidth
    readonly property int preferredHeight: {
        void _labels.count;
        return layout === "all" ? _flow(_preferredColumns).height + parkingHeight : laidHeight;
    }

    function cellPlace(name) {
        if (layout === "shot") {
            const index = _names.indexOf(name);
            return stacked ? Qt.point(0, 0)
                : Qt.point((index % _shotColumns) * cellWidth, Math.floor(index / _shotColumns) * cellHeight);
        }
        return _places.cells[name] ?? Qt.point(0, 0);
    }

    function cellShown(name) {
        if (layout === "shot")
            return !stacked || name === mockup.current;
        if (layout === "all")
            return true;
        if (layout === "one")
            return name === mockup.current;
        return false;
    }

    width: laidWidth
    height: laidHeight

    // Where the pointer rests off every cell
    Item {
        id: _parking
        y: grid._places.height
        width: grid.laidWidth
        height: grid.parkingHeight
    }

    // The labels, on screen only: nothing of them is drawn while shooting
    Repeater {
        id: _labels
        model: grid.layout === "all" || grid.layout === "one" ? grid._count : 0
        Column {
            required property int index
            readonly property string name: grid._names[index] ?? ""
            readonly property point place: grid._places.labels[name] ?? Qt.point(0, 0)
            readonly property string text: grid.labelText(name)
            x: place.x
            y: place.y
            width: grid._slotWidth
            visible: grid.cellShown(name)
            spacing: 2

            Text {
                width: parent.width
                text: parent.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: Theme.textPrimary
            }
            Text {
                width: parent.width
                text: parent.text.slice(parent.name.length + 3)
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }
        }
    }

    // The labels shown and the cells they name, for the kit's `cells` answer
    function labelItem(name) {
        return _labels.itemAt(_names.indexOf(name));
    }
}
