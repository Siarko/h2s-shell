import qs.components as Components

// The base type of a VPN provider (module API 1.7; the contract is API 1.1's): VPNs that
// are not NetworkManager's, listed, shown and switched by the shell beside its own. A
// module declares one inside its main, with its module id as `providerId` (another id is
// refused); it registers itself when made and leaves when destroyed.
//
//   VpnProvider {
//       providerId: "example"; typeName: "Example"; glyph: "󰖂"; ready: true
//       entries: [{ id: "default", name: "Example", state: "activated", attention: null, detail: {} }]
//       function connect(entryId, request) { … }   function disconnect(entryId, request) { … }
//       function attend(entryId) { … }
//   }
//
// Pinned by name: `providerId`, `kind`, `typeName`, `glyph`, `entries`, `ready`, `busy`,
// `canChange`, `lockdownNote`, `settingsPage`; the functions the shell calls, `connect`,
// `disconnect`, `attend`; the signal `failed(entryId, what, reason)`. What each means, an
// entry's fields and what a provider must never do are written in
// components/VpnProvider.qml. A module's row, card and page for its VPN are its manifest's
// contributions, not properties of this type. VpnManager needs the object itself, so this
// is the internal provider, not a wrapper: what else it has is not promised.
Components.VpnProvider {}
