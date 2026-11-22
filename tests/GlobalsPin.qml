import QtQuick
import qs.singletons

// Settings a suite pins as globals for a while, and puts back: only the keys it pinned, each
// as it was before (or gone, when it was not there), merged into what Config.globals holds
// then — never the whole text saved at the start, which would also take back what another
// suite changed meanwhile (SharedState's check would then miss that suite's leak).
//
//   use(change)      the keys pinned so far put back, then `change` ({ key: value }) pinned
//   remember(keys)   keys the shell's code will pin (a save writing globals), to put back too
//   restore()        every key pinned or remembered put back; nothing pinned any more
QtObject {
    // key → { present, value }: as it was before this suite first touched it
    property var _before: ({})

    function _parse(text) {
        try {
            const value = JSON.parse(text || "{}");
            return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {};
        } catch (error) {
            return {};
        }
    }

    function remember(keys) {
        const now = _parse(Config.globals);
        for (const key of keys) {
            if (!Object.prototype.hasOwnProperty.call(_before, key))
                _before[key] = { present: Object.prototype.hasOwnProperty.call(now, key), value: now[key] };
        }
    }

    function _putBack(now) {
        for (const key of Object.keys(_before)) {
            if (_before[key].present)
                now[key] = _before[key].value;
            else
                delete now[key];
        }
        return now;
    }

    function use(change) {
        remember(Object.keys(change));
        Config.globals = JSON.stringify(Object.assign(_putBack(_parse(Config.globals)), change));
    }

    function restore() {
        const text = JSON.stringify(_putBack(_parse(Config.globals)));
        _before = {};
        if (text !== JSON.stringify(_parse(Config.globals)))
            Config.globals = text;
    }
}
