# shellcheck shell=bash
# The test seams of the shell's scripts, as the shell has them: none. Sourced by
# scripts/lock-auth-methods.sh, scripts/pam-files.sh and scripts/launch.sh; every value is
# a constant, so the PAM directories, the lock's methods and its gdbus, and the launcher's
# pauses, are the real ones whatever the environment holds.
#
# A test tree — the lock bed's copy of the checkout (tests/lock/run.sh) — has
# tests/lock/seams/seams.sh in this file's place, which sets the same names from the
# environment (tests/lock/README.md, "The test tree"). TestSeamsShapeTest checks the two
# set the same names, that this one expands nothing, and that no script reads a seam
# itself. A new seam is added to both.

# Where the system-wide h2s-shell-* PAM configs are looked for (lock-auth-methods.sh)
seam_system_pam_dir=/etc/pam.d
# Where libpam looks for a service, in order, joined with ":" (pam-files.sh); empty: the
# distribution's own (its facts' pamDirectories, scripts/distribution.sh)
seam_pam_dirs=
# pam_faillock's default settings file (pam-files.sh); empty: not read
seam_faillock_conf=/etc/security/faillock.conf
# pam_u2f's default settings file, where it is outside the package (pam-files.sh); empty:
# not said (the shell takes its settings as not known)
seam_u2f_conf=/etc/security/pam_u2f.conf
# The distribution the scripts take themselves to be on, by its id (nixos, arch, generic);
# empty: they detect it (scripts/distribution.sh; lock-auth-methods.sh, launch.sh)
seam_distribution=
# An executable that answers for the methods script; empty: none (lock-auth-methods.sh)
seam_auth_methods=
# The gdbus the methods script asks fprintd with (lock-auth-methods.sh)
seam_gdbus=gdbus
# The launcher's pauses, "first=S lockwait=S stopwait=S ipccall=S discoveryhang=S"; empty: its own
# (launch.sh)
seam_launcher_timings=
# A file the module search hangs only while it exists ("discoveryhang=S"); empty: it always
# does (launch.sh)
seam_discovery_hang_while=
