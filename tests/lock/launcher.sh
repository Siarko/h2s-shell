#!/usr/bin/env bash
# The lock test bed's launcher for a machine without an `h2s-shell` command: what the
# packaged launcher (nix/package.nix) does when H2S_SHELL_DIR names a checkout — it runs
# that checkout's scripts/launch.sh with the arguments it was given. So the supervisor, the
# restart, `ipc` and the module search under test are launch.sh's own, as with the package.
#
#   H2S_SHELL_DIR=<a copy of the checkout> tests/lock/launcher.sh [launch.sh's arguments]
#
# What it does not do: put the programs the shell calls on PATH. The package does (its own
# Quickshell first); here they are the ones already on PATH, as where the shell is started
# from a checkout by scripts/launch.sh. And it has no shell of its own to fall back to:
# without H2S_SHELL_DIR it starts nothing (status 2).
#
# tests/lock/resolve.sh takes it when there is neither LOCKTEST_LAUNCHER nor an h2s-shell on
# PATH, and a run says so.
if [ -z "${H2S_SHELL_DIR:-}" ]; then
    echo "launcher.sh: H2S_SHELL_DIR is not set: this launcher only runs the checkout it is pointed at" >&2
    exit 2
fi
exec "$H2S_SHELL_DIR/scripts/launch.sh" "$@"
