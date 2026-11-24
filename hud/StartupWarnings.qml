import QtQuick
import Quickshell
import qs.singletons

// The banners under the bar, stacked, about how the shell was started or set up
// (StartupWarning; Hud.qml places them): the safe-mode banner (SafeModeBanner), started
// without scripts/launch.sh, no Nerd Font, settings outside their range, settings written by a
// newer version. Only those that apply show; with none the column
// is empty (height 0).
Column {
    id: root

    // The modules (Modules: its host, and the safe-mode banner's dismissal for this run; a
    // suite gives a stand-in)
    property var modules: Modules
    // Opens a settings page by its id (a suite gives a stand-in: the real one reaches every
    // listener of Shell.openSettings)
    property var openSettings: pageId => Shell.openSettings(pageId)
    // The distribution's facts, for how this system gets a missing package (a suite gives
    // stand-ins; null while not known: the neutral hint)
    property var distributionFacts: Distribution.facts
    // What the window's input mask takes: the column while a banner shows, else nothing. A
    // Region takes its item's geometry whether the item is shown or not, and the banners stay
    // where they are, hidden — in the mask while hidden, the launch warning took every click
    // in a 640 px band under the bar's middle, over the popups there (the calendar's top half).
    readonly property Item maskItem: height > 0 ? root : null
    readonly property alias safeModeBanner: safeModeBanner
    readonly property alias fontWarning: fontWarning
    readonly property alias rangeWarning: rangeWarning
    readonly property alias newerWarning: newerWarning
    // The config written by a newer shell (Config; a suite gives stand-ins)
    property var newerNotice: Config.newerNotice
    // Number settings the shell uses other than stored (Profiles; a suite gives stand-ins)
    property var rangeCorrections: Profiles.rangeCorrections
    readonly property var _rangeNotice: ProfileRules.rangeNotice(rangeCorrections)

    spacing: Theme.osdToast.screenGap

    // Started without modules (safe mode): why, and the modules loaded again from here.
    // Not while the session is locked — the lock screen shows nothing of the modules
    SafeModeBanner {
        id: safeModeBanner
        width: parent.width
        host: root.modules?.host ?? null
        visible: (host?.safeMode ?? false) && !(host?.locked ?? false) && !(root.modules?.safeModeBannerDismissed ?? false)
        onDismissed: root.modules.safeModeBannerDismissed = true
        onOpenRequested: root.openSettings("modules")
    }

    // Started without scripts/launch.sh: the icon theme setting cannot apply
    StartupWarning {
        width: parent.width
        visible: !IconThemes.launchedByScript && !IconThemes.launchWarningDismissed
        icon: "󰀦"
        title: "The shell was started without scripts/launch.sh"
        body: "Quickshell reads the icon theme only when it starts, from QS_ICON_THEME, and the script "
            + "sets that from Settings → General → Icon theme. Started directly (qs, qs -c default), "
            + "the shell has no icon theme: the setting does nothing and icons such as warnings may be "
            + "missing. Start it with " + Quickshell.shellDir + "/scripts/launch.sh — Hyprland's autostart "
            + "does — or restart it with launch.sh --restart."
        onDismissed: IconThemes.launchWarningDismissed = true
    }

    // No Nerd Font: the bar's icons are its glyphs. The package is named as this system gets
    // it (DistributionRules.packageHint), never as a command
    StartupWarning {
        id: fontWarning
        width: parent.width
        visible: !Theme.nerdFontInstalled && !Theme.nerdFontWarningDismissed
        title: "No Nerd Font installed: icons show as empty boxes"
        body: "The shell's icons are Nerd Font glyphs, and no font on this system has them. Install "
            + "JetBrainsMono Nerd Font (any Nerd Font works), then restart the shell.\n"
            + DistributionRules.packageHint(root.distributionFacts, "nerdFont").text
        onDismissed: Theme.nerdFontWarningDismissed = true
    }

    // Number settings in the config file outside their range, or not numbers: the shell uses
    // others, and says so here as well as in the log and on their Settings rows
    StartupWarning {
        id: rangeWarning
        width: parent.width
        visible: root._rangeNotice.shown && Profiles.rangeNoticeDismissed !== root._rangeNotice.key
        title: root._rangeNotice.title
        body: root._rangeNotice.body
        onDismissed: Profiles.rangeNoticeDismissed = root._rangeNotice.key
    }

    // The config was written by a newer shell: what this one does not know is kept, unused
    // (Config keeps the keys it does not declare); nothing is refused
    StartupWarning {
        id: newerWarning
        width: parent.width
        visible: (root.newerNotice?.shown ?? false) && !Config.newerNoticeDismissed
        title: root.newerNotice?.title ?? ""
        body: root.newerNotice?.body ?? ""
        onDismissed: Config.newerNoticeDismissed = true
    }
}
