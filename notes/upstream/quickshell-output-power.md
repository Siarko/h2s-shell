# Draft: Quickshell feature request — output power from QML (not filed)

Against **Quickshell 0.3.2**. Not checked against master and the upstream tracker was not
searched; do both before filing. If the answer is "a contribution is welcome", h2s-shell
offers one (`notes/plans/idle-lock-flow.md` §9 is what it would replace: the Hyprland and
`wlopm` backends of `singletons/ScreenPower.qml`).

---

## Summary

Expose **`wlr-output-power-management-v1`** in the Wayland module: per output, read whether
it is powered and turn it off or on, from QML. Today a shell that wants to turn monitors off
when idle has to run a compositor's own command (`hyprctl dispatch dpms off <output>`) or an
external tool (`wlopm`) as a process, and parse their output to know the state.

## Why

Quickshell already gives a shell everything else an idle daemon needs: `IdleMonitor`
(ext-idle-notify, with and without respecting inhibitors), `IdleInhibitor`, the session
lock (`WlSessionLock`) and layer-shell surfaces for a screensaver. The one missing piece is
cutting a monitor's power, which is what hypridle and swayidle are mostly kept for
(`dpms off` listeners). A black surface is not a substitute: OLED monitors start their own
protection mode on a black picture, and a laptop panel's backlight still draws power.

The protocol is implemented by sway, labwc, river, Hyprland and other wlroots-based
compositors; GNOME and KDE blank by themselves and do not offer it, so a shell needs to know
whether it is there.

## A possible shape

```qml
import Quickshell.Wayland

// One per output the compositor advertises; null where the protocol is missing
OutputPower {
    screen: modelData                    // a ShellScreen (Quickshell.screens)
    readonly property bool available     // the compositor offers the protocol
    readonly property int mode           // OutputPower.On | OutputPower.Off | OutputPower.Unknown
    function setMode(mode)               // asks; `mode` follows the compositor's event
    signal failed()                      // the compositor said the output's power cannot be set
}
```

What matters more than the names:

1. the mode as the compositor reports it (the protocol's `mode` event), not as asked — an
   output turned on again by the compositor at input (Hyprland's `*_enables_dpms`) must show
   as on;
2. a way to know the protocol is absent, without errors in the log;
3. the `failed` event surfaced, and the object usable again after the output is unplugged and
   plugged in (the protocol's object for it is then dead).

Stable identity for outputs would help too: `ShellScreen.serialNumber` is empty on Wayland
in 0.3.2 and there is no make, so a setting per monitor has to read them from the compositor
(`hyprctl -j monitors`) or fall back to the connector name.

## What we do meanwhile

`ScreenPower` runs `hyprctl` under Hyprland (dispatch per connector, `dpmsStatus` from
`hyprctl -j monitors`) and `wlopm` elsewhere (`wlopm --json`, `--off`/`--on <output>`), and
without either offers no screen-off. Each needs care: Hyprland's dispatcher turns *every*
monitor off for a connector name it does not know, so only names from the last reading are
ever sent.
