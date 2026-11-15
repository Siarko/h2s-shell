import qs.singletons
import qs.panels.settings as Settings

// The editor of one of the module's own settings (module API 1.0): the control its type
// calls for (a switch, pills, a field, a slider, a list of texts), where the shown value comes
// from, the pin that makes it global — the core's SchemaSettingEditor, for a key declared in
// the module's manifest (mod.<id>.<name>).
//
//   SettingEditor { key: "mod.example.greeting" }                 the profile in effect
//   SettingEditor { key: "mod.example.greeting"; editIndex: page.editIndex }
//
// `editIndex`: the profile being edited — a page on the Behaviour tab declares
// `property int editIndex` and the settings window keeps it current; elsewhere (System tab,
// a popup) the default is the profile a change from the shell lands in (Full, else the first).
Settings.SchemaSettingEditor {
    editIndex: {
        const full = Profiles.profiles.findIndex(profile => profile.name === "Full");
        return full >= 0 ? full : 0;
    }
}
