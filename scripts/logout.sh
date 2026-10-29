#!/bin/bash
# Hyprland with a Lua config (hyprland.lua, 0.5x): dispatch takes a Lua expression through
# the hl.dsp.* API. A classic hyprland.conf setup would need `hyprctl dispatch exit`.
hyprctl dispatch 'hl.dsp.exit()'
