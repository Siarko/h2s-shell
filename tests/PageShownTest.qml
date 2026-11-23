import QtQuick
import Quickshell
import qs.components
import qs.singletons

// PageShown (components/PageShown.qml) in a window built as the Settings window is: a page
// loader that keeps its page while the window is hidden and builds a new page on a switch
// (sourceComponent null, then the next). A page reads once when built on screen, once each
// time the window shows again, never while hidden, and not when built in a hidden window
// until that window shows; a page whose own place is hidden is not shown.
//
// Opens a small window for a moment in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "PageShown"
    asynchronous: true
    // Its window takes the keyboard when shown, as other suites' do
    ownProcess: true

    property var _window: FloatingWindow {
        title: "h2s-tests page shown"
        visible: false
        implicitWidth: 300
        implicitHeight: 200
        color: Theme.popupBackground

        Loader {
            id: pageLoader
            anchors.fill: parent
        }

        WindowDriver {
            id: driver
            name: "PageShownDriver"
        }
    }

    // A page that reads when shown, counting its reads
    property Component _pageComp: Component {
        Item {
            property int reads: 0
            readonly property bool shown: _watch.shown
            readonly property alias inner: _inner
            PageShown {
                id: _watch
                onBecameShown: parent.reads++
            }
            // A section inside, in a place that can be hidden
            Item {
                id: _inner
                property int reads: 0
                PageShown {
                    onBecameShown: parent.reads++
                }
            }
        }
    }
    // Another page, as a switch to another sidebar entry
    property Component _otherComp: Component {
        Item {
            property int reads: 0
            PageShown {
                onBecameShown: parent.reads++
            }
        }
    }

    function _until(condition, limitMs = 8000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    // As SettingsWindow._showPage: the page going first, then the page coming
    function _showPage(component) {
        pageLoader.sourceComponent = null;
        pageLoader.sourceComponent = component;
        return pageLoader.item;
    }

    function _show(visible) {
        _window.visible = visible;
        return _until(() => (pageLoader.Window.window?.visible ?? false) === visible);
    }

    function runAsync() {
        try {
            _run();
        } finally {
            pageLoader.sourceComponent = null;
            _window.visible = false;
        }
        finish();
    }

    function _run() {
        // Built while the window is hidden (a page picked before the window opens): no read
        let page = _showPage(_pageComp);
        driver.wait(20);
        assertEqual(page.reads, 0, "built in a hidden window: not read");
        assert(_show(true) && _until(() => page.reads === 1), "the window shown: read once");
        assertEqual(page.inner.reads, 1, "… a section inside too");
        driver.wait(50);
        assertEqual(page.reads, 1, "… once, not again");

        // Hidden and shown again: the page kept, read again
        assert(_show(false), "the window hidden");
        assert(!page.shown, "… the page not shown");
        driver.wait(50);
        assertEqual(page.reads, 1, "… not read while hidden");
        assert(pageLoader.item === page, "… the page kept");
        assert(_show(true) && _until(() => page.reads === 2), "shown again: read again");
        assertEqual(page.inner.reads, 2, "… the section inside too");
        driver.wait(50);
        assertEqual(page.reads, 2, "… once for the showing");

        // A switch to another page and back: each built on screen, read once
        const other = _showPage(_otherComp);
        assert(_until(() => other.reads === 1), "another page: read when built on screen");
        driver.wait(50);
        assertEqual(other.reads, 1, "… once");
        page = _showPage(_pageComp);
        assert(_until(() => page.reads === 1), "back: the page built again, read");
        driver.wait(50);
        assertEqual(page.reads, 1, "… once, not twice at creation");

        // A section in a hidden place: not shown, read when its place shows
        page.inner.visible = false;
        assert(_until(() => page.reads === 1 && page.inner.visible === false), "(the section's place hidden)");
        assert(_show(false) && _show(true) && _until(() => page.reads === 2), "the window shown again: the page read");
        assertEqual(page.inner.reads, 1, "… the hidden section not");
        page.inner.visible = true;
        assert(_until(() => page.inner.reads === 2), "its place shown: read");
    }
}
