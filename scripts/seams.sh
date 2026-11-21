# shellcheck shell=bash
# The test seams of the shell's scripts, as the shell has them: none. Sourced by
# scripts/lock-auth-methods.sh and scripts/launch.sh; every value is a constant, so the
# lock's PAM directory, its methods and its gdbus, and the launcher's pauses, are the real
# ones whatever the environment holds.
#
# A test tree — the lock bed's copy of the checkout (tests/lock/run.sh) — has
# tests/lock/seams/seams.sh in this file's place, which sets the same names from the
# environment (tests/lock/README.md, "The test tree"). TestSeamsShapeTest checks the two
# set the same names, that this one expands nothing, and that no script reads a seam
# itself. A new seam is added to both.

# Where the system-wide h2s-shell-* PAM configs are looked for (lock-auth-methods.sh)
seam_system_pam_dir=/etc/pam.d
# The system the methods script takes itself to be on, nixos or other; empty: it asks the
# machine (lock-auth-methods.sh)
seam_system=
# An executable that answers for the methods script; empty: none (lock-auth-methods.sh)
seam_auth_methods=
# The gdbus the methods script asks fprintd with (lock-auth-methods.sh)
seam_gdbus=gdbus
# The launcher's pauses, "first=S lockwait=S discoveryhang=S"; empty: its own
# (launch.sh)
seam_launcher_timings=
