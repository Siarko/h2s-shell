pragma Singleton

import Quickshell

// What most settings migrations do, done one way: a key renamed, a value mapped or a key
// removed across every profile and the pinned globals and, where asked, the presets of the
// named widget types — so that no migration forgets a profile. Each takes the document a
// migration is handed (MigrationRules' shape) and returns a new one; the input is not
// modified. A rename never overwrites a target key that is already set (the user may have
// set it since): the old key is then only removed. Pure; checked by
// tests/MigrationRulesTest.qml.
//
// `where`: { settings: true (the profiles and globals; the default), presets: [type…] (the
// presets of those widget types, keys inside each preset) }
Singleton {
    id: root

    function _object(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function _own(object, key) {
        return _object(object) && Object.prototype.hasOwnProperty.call(object, key);
    }

    function _put(object, key, value) {
        Object.defineProperty(object, key, { value: value, enumerable: true, writable: true, configurable: true });
    }

    // Every place a setting can be in, on a copy: visit(values, place) for each profile's
    // set ("profile:<name>"), the globals ("globals") and each preset of the asked types
    // ("preset:<type>/<name>"); `values` may be changed in place. → the copy
    function forEachSetting(document, visit, where) {
        const result = JSON.parse(JSON.stringify(document));
        const settings = where?.settings !== false;
        const types = Array.isArray(where?.presets) ? where.presets : [];
        if (settings) {
            for (const profile of Array.isArray(result.profiles) ? result.profiles : [])
                if (_object(profile.set))
                    visit(profile.set, "profile:" + profile.name);
            if (_object(result.globals))
                visit(result.globals, "globals");
        }
        for (const type of types) {
            const presets = _own(result.presets, type) ? result.presets[type] : null;
            for (const name of Object.keys(_object(presets) ? presets : {}))
                if (_object(presets[name]))
                    visit(presets[name], "preset:" + type + "/" + name);
        }
        return result;
    }

    // `from` renamed to `to` wherever it is set; a `to` already set is kept and `from` only
    // removed
    function renameKey(document, from, to, where) {
        return forEachSetting(document, values => {
            if (!_own(values, from))
                return;
            if (!_own(values, to))
                _put(values, to, values[from]);
            delete values[from];
        }, where);
    }

    // `key`'s value replaced by map(value, place) wherever it is set; undefined from map
    // removes the key
    function mapValue(document, key, map, where) {
        return forEachSetting(document, (values, place) => {
            if (!_own(values, key))
                return;
            const mapped = map(values[key], place);
            if (mapped === undefined)
                delete values[key];
            else
                _put(values, key, mapped);
        }, where);
    }

    // `key` removed wherever it is set
    function removeKey(document, key, where) {
        return forEachSetting(document, values => {
            delete values[key];
        }, where);
    }
}
