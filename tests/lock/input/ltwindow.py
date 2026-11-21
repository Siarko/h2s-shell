#!/usr/bin/env python3
"""A stand-in desktop window for the lock test bed: one xdg toplevel, solid magenta.

Usage: ltwindow.py <protocol-dir>

Something visible behind the lock screen, in a colour nothing of the shell uses, so that a
screenshot shows at once whether any of the desktop is visible through the lock (a lock
surface fades in from transparent). Hyprland tiles it over the whole output. It redraws at
whatever size it is configured to, and runs until it is killed.

Every pointer press it receives is printed as "press <x> <y>" (surface coordinates, where the
pointer last was): a test sees from window.log whether a click went past the shell's
surfaces to the window beneath (their input masks). Every key press it receives is printed
as "key <code>" (the evdev code): a test sees whether a key reached the desktop past a
shell surface that should take the keyboard (the screensaver).
"""
import mmap
import os
import sys

sys.path.insert(0, sys.argv[1])

from pywayland.client import Display  # noqa: E402
from ltproto.wayland import WlCompositor, WlSeat, WlShm  # noqa: E402
from ltproto.xdg_shell import XdgWmBase  # noqa: E402

MAGENTA = bytes((255, 0, 255, 255))  # B, G, R, A of WL_SHM_FORMAT_ARGB8888 (little endian)


def main():
    display = Display(os.environ.get("WAYLAND_DISPLAY"))
    display.connect()
    found = {}

    def on_global(registry, name, interface, version):
        if interface == "wl_compositor":
            found["compositor"] = registry.bind(name, WlCompositor, 4)
        elif interface == "wl_shm":
            found["shm"] = registry.bind(name, WlShm, 1)
        elif interface == "xdg_wm_base":
            found["wm_base"] = registry.bind(name, XdgWmBase, 1)
        elif interface == "wl_seat" and "seat" not in found:
            found["seat"] = registry.bind(name, WlSeat, 1)

    registry = display.get_registry()
    registry.dispatcher["global"] = on_global
    display.roundtrip()
    for name in ("compositor", "shm", "wm_base"):
        if name not in found:
            print("missing global", name, file=sys.stderr)
            sys.exit(2)

    wm_base = found["wm_base"]
    wm_base.dispatcher["ping"] = lambda base, serial: base.pong(serial)
    surface = found["compositor"].create_surface()
    xdg_surface = wm_base.get_xdg_surface(surface)
    toplevel = xdg_surface.get_toplevel()
    toplevel.set_title("locktest stand-in")
    size = {"width": 640, "height": 480}
    buffers = []

    def on_toplevel_configure(toplevel, width, height, states):
        if width > 0 and height > 0:
            size["width"], size["height"] = width, height

    def draw():
        width, height = size["width"], size["height"]
        stride = width * 4
        length = stride * height
        fd = os.memfd_create("ltwindow")
        os.ftruncate(fd, length)
        data = mmap.mmap(fd, length)
        data.write(MAGENTA * (width * height))
        pool = found["shm"].create_pool(fd, length)
        buffer = pool.create_buffer(0, width, height, stride, WlShm.format.argb8888.value)
        pool.destroy()
        os.close(fd)
        buffers.append((buffer, data))  # kept: the compositor may read it at any time
        del buffers[:-2]
        surface.attach(buffer, 0, 0)
        surface.damage(0, 0, width, height)
        surface.commit()

    def on_surface_configure(xdg_surface, serial):
        xdg_surface.ack_configure(serial)
        draw()

    pointer_at = {"x": 0.0, "y": 0.0}
    pointers = []
    keyboards = []

    def on_seat_capabilities(seat, capabilities):
        if capabilities & WlSeat.capability.pointer.value and not pointers:
            pointer = seat.get_pointer()

            def on_enter(pointer, serial, surface, x, y):
                pointer_at["x"], pointer_at["y"] = x, y

            def on_motion(pointer, time, x, y):
                pointer_at["x"], pointer_at["y"] = x, y

            def on_button(pointer, serial, time, button, state):
                if state == 1:
                    print("press %d %d" % (pointer_at["x"], pointer_at["y"]), flush=True)

            pointer.dispatcher["enter"] = on_enter
            pointer.dispatcher["motion"] = on_motion
            pointer.dispatcher["button"] = on_button
            pointers.append(pointer)
        if capabilities & WlSeat.capability.keyboard.value and not keyboards:
            keyboard = seat.get_keyboard()

            def on_keymap(keyboard, format, fd, size):
                os.close(fd)

            def on_key(keyboard, serial, time, key, state):
                if state == 1:
                    print("key %d" % key, flush=True)

            keyboard.dispatcher["keymap"] = on_keymap
            keyboard.dispatcher["key"] = on_key
            keyboards.append(keyboard)

    if "seat" in found:
        found["seat"].dispatcher["capabilities"] = on_seat_capabilities

    toplevel.dispatcher["configure"] = on_toplevel_configure
    toplevel.dispatcher["close"] = lambda toplevel: None
    xdg_surface.dispatcher["configure"] = on_surface_configure
    surface.commit()
    display.roundtrip()
    print("ltwindow ready", flush=True)
    while display.dispatch(block=True) != -1:
        pass


if __name__ == "__main__":
    main()
