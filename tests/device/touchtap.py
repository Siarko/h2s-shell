#!/usr/bin/env python3
"""A virtual touchscreen for tests: taps where it is told, through the whole stack
(uinput → libinput → Hyprland → client), as a finger would.

  touchtap.py "tap 800 40" "sleep 1500" "tap 700 200" "swipe 100 500 600 500 300"

Needs write access to /dev/uinput (tests/device/README.md).

Coordinates are logical pixels of the (only) monitor; `scale` turns them into the
device's range, which Hyprland maps onto the whole output.
"""
import sys
import time

from evdev import UInput, ecodes as e, AbsInfo

WIDTH, HEIGHT = 1920, 1200   # the output in physical pixels
SCALE = 1.2                  # Hyprland's scale for eDP-1

capabilities = {
    e.EV_KEY: [e.BTN_TOUCH, e.BTN_TOOL_FINGER],
    e.EV_ABS: [
        (e.ABS_X, AbsInfo(0, 0, WIDTH - 1, 0, 0, 10)),
        (e.ABS_Y, AbsInfo(0, 0, HEIGHT - 1, 0, 0, 10)),
        (e.ABS_MT_SLOT, AbsInfo(0, 0, 9, 0, 0, 0)),
        (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
        (e.ABS_MT_POSITION_X, AbsInfo(0, 0, WIDTH - 1, 0, 0, 10)),
        (e.ABS_MT_POSITION_Y, AbsInfo(0, 0, HEIGHT - 1, 0, 0, 10)),
    ],
}

tracking = 100


def log(message):
    print(f"{time.strftime('%H:%M:%S')}.{int(time.time() * 1000) % 1000:03d} {message}", flush=True)


def down(device, x, y):
    global tracking
    tracking += 1
    px, py = int(x * SCALE), int(y * SCALE)
    device.write(e.EV_ABS, e.ABS_MT_SLOT, 0)
    device.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, tracking)
    device.write(e.EV_ABS, e.ABS_MT_POSITION_X, px)
    device.write(e.EV_ABS, e.ABS_MT_POSITION_Y, py)
    device.write(e.EV_KEY, e.BTN_TOUCH, 1)
    device.write(e.EV_KEY, e.BTN_TOOL_FINGER, 1)
    device.write(e.EV_ABS, e.ABS_X, px)
    device.write(e.EV_ABS, e.ABS_Y, py)
    device.syn()


def move(device, x, y):
    px, py = int(x * SCALE), int(y * SCALE)
    device.write(e.EV_ABS, e.ABS_MT_POSITION_X, px)
    device.write(e.EV_ABS, e.ABS_MT_POSITION_Y, py)
    device.write(e.EV_ABS, e.ABS_X, px)
    device.write(e.EV_ABS, e.ABS_Y, py)
    device.syn()


def up(device):
    device.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
    device.write(e.EV_KEY, e.BTN_TOUCH, 0)
    device.write(e.EV_KEY, e.BTN_TOOL_FINGER, 0)
    device.syn()


def main(commands):
    with UInput(capabilities, name="h2s-test-touchscreen", input_props=[e.INPUT_PROP_DIRECT]) as device:
        time.sleep(1.5)  # libinput and Hyprland pick the new device up
        for command in commands:
            words = command.split()
            name, numbers = words[0], [float(word) for word in words[1:]]
            if name == "tap":
                log(f"tap {numbers[0]:.0f},{numbers[1]:.0f}")
                down(device, numbers[0], numbers[1])
                time.sleep(0.08)
                up(device)
            elif name == "hold":
                log(f"hold {numbers[0]:.0f},{numbers[1]:.0f} {numbers[2]:.0f} ms")
                down(device, numbers[0], numbers[1])
                time.sleep(numbers[2] / 1000)
                up(device)
            elif name == "swipe":
                x1, y1, x2, y2, duration = numbers
                log(f"swipe {x1:.0f},{y1:.0f} → {x2:.0f},{y2:.0f}")
                down(device, x1, y1)
                steps = max(2, int(duration / 16))
                for step in range(1, steps + 1):
                    time.sleep(duration / 1000 / steps)
                    move(device, x1 + (x2 - x1) * step / steps, y1 + (y2 - y1) * step / steps)
                up(device)
            elif name == "sleep":
                time.sleep(numbers[0] / 1000)
            else:
                raise SystemExit(f"unknown command: {command}")
        time.sleep(0.3)


if __name__ == "__main__":
    main(sys.argv[1:])
