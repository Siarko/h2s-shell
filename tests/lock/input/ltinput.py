#!/usr/bin/env python3
"""A persistent virtual keyboard and pointer for the lock test bed's compositor.

Both devices stay alive for the client's whole lifetime, so the compositor's seat keeps
advertising a keyboard and a pointer and the shell keeps its wl_keyboard/wl_pointer.
One-shot tools (wtype, wlrctl) create and destroy a device per call; on a seat with no
other devices that toggles the seat's capabilities, and the first events are lost
(observed: the first key dropped, every pointer motion dropped). For the same reason
this client must be running before the lock client binds its seat.

Usage: ltinput.py <protocol-dir> <keymap-file> <fifo>

<protocol-dir> holds the generated `ltproto` bindings (the tool set's share/). The keyboard
sends <keymap-file> (an XKB keymap, the tool set holds a few) and works out from it, with
`xkbcli how-to-type`, which key and which modifiers type a character or a keysym — so a test
can type with any layout, and a character the layout cannot type directly is fatal: the
client ends with an error before anything of the command is typed, so a typed password is
always exactly the one asked for. Commands, one per line, are written to <fifo>:

  type <text>          type the text: each character by the key and modifiers (Shift,
                       AltGr) that give it directly in this layout. Refused while Caps Lock
                       is on (the text typed would not be the text asked for): use `keys`
  keys <text>          press the keys that type <text> with Caps Lock off, whatever the
                       locks are now (with Caps Lock on, "abc" gives "ABC")
  key <keysym>         one key by its keysym name, with the modifiers it needs: Return,
                       BackSpace, Escape, Tab, space, dead_acute, Multi_key, KP_1 (needs Num
                       Lock on), KP_Enter, … Caps_Lock and Num_Lock toggle the lock
  hold <keysym> <s>    one key held down for <s> seconds, then released: the compositor's
                       key repeat (Qt repeats on the client side) has its chance
  move <dx> <dy>       relative motion
  abs <x> <y> <w> <h>  absolute motion in a w*h extent
  click [left|right|middle]
  press [left|right|middle]    held down (a drag: press, moves, release)
  release [left|right|middle]
  sleep <seconds>
  quit

A key needing Num Lock while it is off (or the like) is fatal too: the client never sends
another key in its place.

Each command, once the compositor has received it (a roundtrip), is acknowledged by a
line "done <n> <command>" appended to <fifo>.ack: the caller waits for it, so a test
never races its own input into the compositor. The acknowledgement says nothing about
the shell: whether the shell has received and handled the input is for the test to
observe (through the shell's state).
"""
import os
import re
import shutil
import subprocess
import sys
import time

protocol_dir, keymap_path, fifo_path = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, protocol_dir)

from pywayland.client import Display  # noqa: E402
from ltproto.wayland import WlSeat  # noqa: E402
from ltproto.wlr_virtual_pointer_unstable_v1 import ZwlrVirtualPointerManagerV1  # noqa: E402
from ltproto.virtual_keyboard_unstable_v1 import ZwpVirtualKeyboardManagerV1  # noqa: E402

BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112}
KEYMAP_FORMAT_XKB_V1 = 1
# The real modifiers' masks: their order is fixed in every keymap xkbcommon compiles
MASKS = {"Shift": 1, "Lock": 2, "Control": 4, "Mod1": 8, "Mod2": 16, "Mod3": 32, "Mod4": 64, "Mod5": 128}
# The virtual modifiers how-to-type names beside the real ones they map to
ALIASES = {"LevelThree": "Mod5", "NumLock": "Mod2", "Alt": "Mod1", "Super": "Mod4"}
# The modifiers a key may need here: held (Shift, AltGr) or locked (Num Lock). Never
# Lock: Caps Lock is the test's to set, never a way to reach a character
HELD = {"Shift": "Shift_L", "Mod5": "ISO_Level3_Shift"}
LOCKED = {"Mod2": "Num_Lock"}
LOCK_KEYSYMS = {"Caps_Lock": "Lock", "Num_Lock": "Mod2"}


def fatal(message):
    print("fatal:", message, file=sys.stderr, flush=True)
    os._exit(3)  # sys.exit crashes in pywayland's teardown


class Layout:
    """What the keymap says types a character or a keysym, asked of xkbcli how-to-type"""

    def __init__(self, path):
        self.path = path
        self.xkbcli = shutil.which("xkbcli")
        if not self.xkbcli:
            fatal("xkbcli is not on PATH (the tool set provides it)")
        self.cache = {}

    def _ask(self, argument, keysym):
        command = [self.xkbcli, "how-to-type", "--disable-compose", "--keymap=" + self.path]
        # A character as its code point: "1" alone could be read as the code point 1, a
        # leading "-" as an option
        command += ["--keysym", argument] if keysym else ["U+%04X" % ord(argument)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        entries = []
        section = ""
        for line in result.stdout.splitlines():
            if line.startswith("==="):
                section = line
                continue
            if "Direct access" not in section:
                continue
            match = re.match(r"^\s*(\d+)\s+(\S+)\s.*\[(.*)\]\s*$", line)
            if not match:
                continue
            keycode, name = int(match.group(1)), match.group(2)
            modifiers = {ALIASES.get(word, word) for word in match.group(3).split()}
            entries.append((keycode, name, modifiers))
        return entries

    def resolve(self, argument, keysym=False):
        """(evdev code, held modifiers, locked modifiers needed) for the gentlest way to type it"""
        key = (argument, keysym)
        if key in self.cache:
            return self.cache[key]
        candidates = []
        for keycode, name, modifiers in self._ask(argument, keysym):
            # Keys past the usual range (xkb 256+) exist only in the keymap's tables
            if keycode > 255 or not modifiers <= set(HELD) | set(LOCKED):
                continue
            held = sorted(modifiers & set(HELD))
            locked = sorted(modifiers & set(LOCKED))
            # Fewest modifiers first; among modifier keys the usual right Alt for AltGr
            candidates.append((len(modifiers), name != "RALT", keycode - 8, held, locked))
        if not candidates:
            self.cache[key] = None
            return None
        candidates.sort()
        _, _, code, held, locked = candidates[0]
        self.cache[key] = (code, held, locked)
        return self.cache[key]


def main():
    acknowledgement_path = fifo_path + ".ack"
    layout = Layout(keymap_path)
    display = Display(os.environ.get("WAYLAND_DISPLAY"))
    display.connect()
    registry = display.get_registry()
    globals_found = {}

    def on_global(registry, name, interface, version):
        if interface == "wl_seat":
            globals_found["seat"] = registry.bind(name, WlSeat, 1)
        elif interface == "zwlr_virtual_pointer_manager_v1":
            globals_found["pointer_manager"] = registry.bind(name, ZwlrVirtualPointerManagerV1, 1)
        elif interface == "zwp_virtual_keyboard_manager_v1":
            globals_found["keyboard_manager"] = registry.bind(name, ZwpVirtualKeyboardManagerV1, 1)

    registry.dispatcher["global"] = on_global
    display.roundtrip()
    missing = [key for key in ("seat", "pointer_manager", "keyboard_manager") if key not in globals_found]
    if missing:
        print("missing globals:", missing, file=sys.stderr)
        sys.exit(2)

    pointer = globals_found["pointer_manager"].create_virtual_pointer(globals_found["seat"])
    keyboard = globals_found["keyboard_manager"].create_virtual_keyboard(globals_found["seat"])
    with open(keymap_path, "rb") as keymap_file:
        keymap = keymap_file.read() + b"\0"
    keymap_fd = os.memfd_create("ltkeymap")
    os.write(keymap_fd, keymap)
    os.lseek(keymap_fd, 0, 0)
    keyboard.keymap(KEYMAP_FORMAT_XKB_V1, keymap_fd, len(keymap))
    display.roundtrip()
    os.close(keymap_fd)

    # The keys of the modifiers, found once in this layout
    modifier_codes = {}
    for modifier, keysym in list(HELD.items()) + list(LOCKED.items()) + [("Lock", "Caps_Lock")]:
        found = layout.resolve(keysym, keysym=True)
        if found and not found[1] and not found[2]:
            modifier_codes[modifier] = found[0]

    started = time.monotonic()
    locked_mask = 0

    def milliseconds():
        return int((time.monotonic() - started) * 1000) & 0xFFFFFFFF

    def send_modifiers(depressed):
        keyboard.modifiers(depressed, 0, locked_mask, 0)

    def press(code, held=(), seconds=0.01):
        depressed = 0
        for modifier in held:
            keyboard.key(milliseconds(), modifier_codes[modifier], 1)
            depressed |= MASKS[modifier]
        if held:
            send_modifiers(depressed)
        keyboard.key(milliseconds(), code, 1)
        display.flush()
        time.sleep(seconds)
        keyboard.key(milliseconds(), code, 0)
        for modifier in reversed(held):
            keyboard.key(milliseconds(), modifier_codes[modifier], 0)
        if held:
            send_modifiers(0)
        display.roundtrip()
        time.sleep(0.01)

    def plan(argument, keysym):
        """The key presses for one character or keysym, or a fatal error"""
        found = layout.resolve(argument, keysym)
        what = ("keysym " if keysym else "character ") + repr(argument)
        if found is None:
            fatal(f"cannot type {what}: no key gives it directly in {os.path.basename(keymap_path)}")
        code, held, locked = found
        for modifier in held:
            if modifier not in modifier_codes:
                fatal(f"cannot type {what}: the layout has no key for {modifier}")
        for modifier in locked:
            if not locked_mask & MASKS[modifier]:
                fatal(f"cannot type {what}: it needs {LOCKED[modifier]} on")
        return code, held

    print("ltinput ready", flush=True)
    count = 0
    while True:
        with open(fifo_path) as fifo:  # blocks until a writer opens the FIFO
            for line in fifo:
                line = line.rstrip("\n")
                if not line:
                    continue
                command, _, argument = line.partition(" ")
                if command in ("type", "keys"):
                    if command == "type" and locked_mask & MASKS["Lock"]:
                        fatal("`type` with Caps Lock on would not type the text asked for: use `keys`")
                    presses = [plan(character, False) for character in argument]
                    for code, held in presses:
                        press(code, held)
                elif command == "key":
                    code, held = plan(argument, True)
                    press(code, held)
                    if argument in LOCK_KEYSYMS:
                        locked_mask ^= MASKS[LOCK_KEYSYMS[argument]]
                        send_modifiers(0)
                elif command == "hold":
                    name, _, seconds = argument.partition(" ")
                    if name in LOCK_KEYSYMS:
                        fatal("hold a lock key? use `key`")
                    code, held = plan(name, True)
                    press(code, held, float(seconds))
                elif command == "move":
                    delta_x, delta_y = (float(value) for value in argument.split())
                    pointer.motion(milliseconds(), delta_x, delta_y)
                    pointer.frame()
                elif command == "abs":
                    x, y, width, height = (int(value) for value in argument.split())
                    pointer.motion_absolute(milliseconds(), x, y, width, height)
                    pointer.frame()
                elif command == "click":
                    button = BUTTONS[argument or "left"]
                    pointer.button(milliseconds(), button, 1)
                    pointer.frame()
                    display.roundtrip()
                    time.sleep(0.02)
                    pointer.button(milliseconds(), button, 0)
                    pointer.frame()
                elif command in ("press", "release"):
                    pointer.button(milliseconds(), BUTTONS[argument or "left"], 1 if command == "press" else 0)
                    pointer.frame()
                elif command == "sleep":
                    time.sleep(float(argument))
                elif command == "quit":
                    display.roundtrip()
                    display.disconnect()
                    return
                else:
                    fatal(f"unknown command {command!r}")
                display.roundtrip()
                count += 1
                with open(acknowledgement_path, "a") as acknowledgements:
                    acknowledgements.write(f"done {count} {command}\n")


if __name__ == "__main__":
    main()
