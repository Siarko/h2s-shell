#!/usr/bin/env python3
"""One sample for the battery popup's use per app (docs/plans/battery-popup.md, stage 3).

Prints JSON: {"busy": ticks, "total": ticks, "processes": [[pid, app, cpu ticks,
gpu cycles], ...]} — the CPU time and GPU cycles each process has used so far, and the
app it belongs to. The shell (singletons/EnergyUsage.qml) runs it every so often on
battery and splits the energy drawn between apps by what they used in between
(EnergyRules). Standard library only; needs no root: /proc/<pid>/stat is everyone's, the
GPU's per-client cycles (/proc/<pid>/fdinfo, drm-cycles-*, the xe and amdgpu drivers) only
for the user's own processes — others count as none.

An app is: a systemd unit (pipewire, oskbd; a terminal's per-tab scopes, kitty-*.scope,
go to the terminal); else the process Hyprland started, named by its window class if it
has a window; init and kernel threads are "Kernel".
"""

import glob
import json
import os
import re
import subprocess


# Shells, as the top of a chain: a launcher script, not the app
SHELLS = {"bash", "sh", "zsh", "fish", "dash"}


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as file:
            return file.read()
    except OSError:
        return None


def window_classes():
    """pid → window class, from Hyprland (empty elsewhere)"""
    try:
        clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True,
                                            text=True, timeout=2).stdout)
        return {client["pid"]: client["class"] for client in clients if client.get("pid", 0) > 0}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


def gpu_cycles(pid):
    total = 0
    for fdinfo in glob.glob(f"/proc/{pid}/fdinfo/*"):
        text = read(fdinfo)
        if text and "drm-driver" in text:
            total += sum(int(value) for value in re.findall(r"drm-cycles-\w+:\s+(\d+)", text))
    return total


def program_name(pid, comm):
    """The program's name: its path's last part (the kernel cuts `comm` at 15 characters),
    without Nix's wrapper (.Hyprland-wrapped → Hyprland)"""
    cmdline = read(f"/proc/{pid}/cmdline") or ""
    # A program that rewrote its title ("sshd-session: h2s [postauth]"): its first word
    argv0 = cmdline.split("\0", 1)[0].split(" ", 1)[0].rstrip(":")
    name = os.path.basename(argv0) if argv0 else comm
    name = re.sub(r"^\.(.*)-wrapped$", r"\1", name)
    return name or comm


def unit_of(cgroup):
    """A systemd unit's name from /proc/<pid>/cgroup, or None for a session's processes"""
    match = re.search(r"/([^/]+)\.(service|scope)$", cgroup.strip())
    if not match:
        return None
    name, kind = match.groups()
    if kind == "scope":
        # A terminal's tab (kitty-1549-0.scope): the terminal's; a session's scope: none
        if name.startswith("session-") or name.startswith("app-hyprland"):
            return None
        name = re.sub(r"-\d+(-\d+)*$", "", name)
    else:
        name = re.sub(r"@.*$", "", name)
    # An app launched as a unit (app-org.chromium.Chromium-1234.scope): its id's last part
    if name.startswith("app-"):
        name = name[len("app-"):].rsplit(".", 1)[-1]
    return name


def main():
    processes = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        stat = read(f"/proc/{entry}/stat")
        if not stat:
            continue
        name = stat[stat.index("(") + 1:stat.rindex(")")]
        fields = stat[stat.rindex(")") + 2:].split()
        processes[int(entry)] = {"name": name, "ppid": int(fields[1]),
                                 "cpu": int(fields[11]) + int(fields[12]),
                                 "cgroup": read(f"/proc/{entry}/cgroup") or ""}

    hyprland = next((pid for pid, process in processes.items()
                     if process["name"] in ("Hyprland", ".Hyprland-wrapp")), None)
    classes = window_classes()

    def app_of(pid):
        process = processes[pid]
        if pid in (1, 2) or process["ppid"] == 2:
            return "Kernel"
        unit = unit_of(process["cgroup"])
        if unit:
            return unit
        # Up to the topmost ancestor short of what starts programs — Hyprland, init, the user's
        # systemd (a program Hyprland runs is often handed to it) — which, or whose window,
        # names the app: so a helper (the shell's own sampler) counts to what ran it
        chain, current = [], pid
        while current in processes and current not in chain and current != hyprland:
            chain.append(current)
            parent = processes[current]["ppid"]
            if parent == hyprland or parent <= 1 or processes.get(parent, {}).get("name") == "systemd":
                break
            current = parent
        if not chain:
            return program_name(pid, process["name"])
        # A launcher script (steam is a bash script): the program it ran names the app
        while len(chain) > 1 and processes[chain[-1]]["name"] in SHELLS and chain[-1] not in classes:
            chain.pop()
        top = chain[-1]
        return classes.get(top) or program_name(top, processes[top]["name"])

    rows = [[pid, app_of(pid), process["cpu"], gpu_cycles(pid)] for pid, process in processes.items()]
    fields = [int(value) for value in read("/proc/stat").splitlines()[0].split()[1:]]
    total = sum(fields)
    print(json.dumps({"busy": total - fields[3] - fields[4], "total": total, "processes": rows}))


if __name__ == "__main__":
    main()
