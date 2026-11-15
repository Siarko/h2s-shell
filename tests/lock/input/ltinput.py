#!/usr/bin/env python3
"""A persistent virtual keyboard and pointer for the lock test bed's compositor.

Both devices stay alive for the client's whole lifetime, so the compositor's seat keeps
advertising a keyboard and a pointer and the shell keeps its wl_keyboard/wl_pointer.
One-shot tools (wtype, wlrctl) create and destroy a device per call; on a seat with no
other devices that toggles the seat's capabilities, and the first events are lost
(observed: the first key dropped, every pointer motion dropped). For the same reason
this client must be running before the lock client binds its seat.

Usage: ltinput.py <protocol-dir> <keymap-file> <fifo>

<protocol-dir> holds the generated `ltproto` bindings (tools.nix builds them). Commands,
one per line, are written to <fifo>:

  type <text>          type ASCII text (US layout); a character the table below lacks
                       ends the client with an error before anything is typed, so a
                       typed password is always exactly the one asked for
  key <Name>           Return | BackSpace | Escape | Tab | space
  move <dx> <dy>       relative motion
  abs <x> <y> <w> <h>  absolute motion in a w*h extent
  click [left|right|middle]
  sleep <seconds>
  quit

Each command, once the compositor has received it (a roundtrip), is acknowledged by a
line "done <n> <command>" appended to <fifo>.ack: the caller waits for it, so a test
never races its own input into the compositor. The acknowledgement says nothing about
the shell: whether the shell has received and handled the input is for the test to
observe (through the shell's state).
"""
import os
import sys
import time

protocol_dir, keymap_path, fifo_path = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, protocol_dir)

from pywayland.client import Display  # noqa: E402
from ltproto.wayland import WlSeat  # noqa: E402
from ltproto.wlr_virtual_pointer_unstable_v1 import ZwlrVirtualPointerManagerV1  # noqa: E402
from ltproto.virtual_keyboard_unstable_v1 import ZwpVirtualKeyboardManagerV1  # noqa: E402

# Linux evdev key codes of a US layout: (code, needs shift)
KEYS = {}
for index, character in enumerate("1234567890"):
    KEYS[character] = (2 + index, False)
for row, first_code in (("qwertyuiop", 16), ("asdfghjkl", 30), ("zxcvbnm", 44)):
    for index, character in enumerate(row):
        KEYS[character] = (first_code + index, False)
        KEYS[character.upper()] = (first_code + index, True)
for character, code, shift in (("-", 12, False), ("_", 12, True), ("=", 13, False), ("+", 13, True),
                               (" ", 57, False), (".", 52, False), (",", 51, False), ("/", 53, False),
                               ("!", 2, True), ("@", 3, True), ("#", 4, True), ("$", 5, True),
                               ("%", 6, True), (";", 39, False), (":", 39, True)):
    KEYS[character] = (code, shift)
NAMED_KEYS = {"Return": 28, "BackSpace": 14, "Escape": 1, "Tab": 15, "space": 57}
BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112}
SHIFT = 42
KEYMAP_FORMAT_XKB_V1 = 1


def main():
    acknowledgement_path = fifo_path + ".ack"
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

    started = time.monotonic()

    def milliseconds():
        return int((time.monotonic() - started) * 1000) & 0xFFFFFFFF

    def press(code, shift=False):
        if shift:
            keyboard.key(milliseconds(), SHIFT, 1)
            keyboard.modifiers(1, 0, 0, 0)
        keyboard.key(milliseconds(), code, 1)
        display.flush()
        time.sleep(0.01)
        keyboard.key(milliseconds(), code, 0)
        if shift:
            keyboard.key(milliseconds(), SHIFT, 0)
            keyboard.modifiers(0, 0, 0, 0)
        display.roundtrip()
        time.sleep(0.01)

    print("ltinput ready", flush=True)
    count = 0
    while True:
        with open(fifo_path) as fifo:  # blocks until a writer opens the FIFO
            for line in fifo:
                line = line.rstrip("\n")
                if not line:
                    continue
                command, _, argument = line.partition(" ")
                if command == "type":
                    unmapped = sorted({character for character in argument if character not in KEYS})
                    if unmapped:
                        print("fatal: cannot type", unmapped, "(not in ltinput.py's key table)",
                              file=sys.stderr, flush=True)
                        os._exit(3)  # sys.exit crashes in pywayland's teardown
                    for character in argument:
                        press(*KEYS[character])
                elif command == "key":
                    press(NAMED_KEYS[argument])
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
                elif command == "sleep":
                    time.sleep(float(argument))
                elif command == "quit":
                    display.roundtrip()
                    display.disconnect()
                    return
                display.roundtrip()
                count += 1
                with open(acknowledgement_path, "a") as acknowledgements:
                    acknowledgements.write(f"done {count} {command}\n")


if __name__ == "__main__":
    main()
