# shellcheck shell=bash
# The test tree's seams.sh: copied over scripts/seams.sh (whose values are constants) when a
# test tree is assembled (tests/lock/run.sh). It sets the same names, from the environment
# the tests give the shell; a variable that is not set leaves the production value. Sourced
# by scripts/lock-auth-methods.sh, scripts/pam-files.sh and scripts/launch.sh (tests/lock/README.md, "The test
# tree"; TestSeamsShapeTest checks both files set the same names).

# H2S_LOCK_SYSTEM_PAM_DIR: the test's own "system-wide" configs, so that the password
# fallback is never the system's real PAM stack
seam_system_pam_dir=${H2S_LOCK_SYSTEM_PAM_DIR:-/etc/pam.d}
# H2S_LOCK_SYSTEM_PAM_DIR, then H2S_LOCK_VENDOR_PAM_DIR (the test's own vendor directory):
# the PAM directories pam-files.sh names, in place of the distribution's. With only
# H2S_LOCK_SYSTEM_PAM_DIR set there is no vendor one, so that no PAM file of the machine is
# read; H2S_LOCK_VENDOR_PAM_DIR counts only with it
seam_pam_dirs=
[ -z "${H2S_LOCK_SYSTEM_PAM_DIR:-}" ] || seam_pam_dirs=$H2S_LOCK_SYSTEM_PAM_DIR${H2S_LOCK_VENDOR_PAM_DIR:+:$H2S_LOCK_VENDOR_PAM_DIR}
# H2S_LOCK_FAILLOCK_CONF: the test's own faillock.conf (pam-files.sh); with only
# H2S_LOCK_SYSTEM_PAM_DIR set, none is read
seam_faillock_conf=${H2S_LOCK_FAILLOCK_CONF:-/etc/security/faillock.conf}
[ -z "${H2S_LOCK_SYSTEM_PAM_DIR:-}" ] || [ -n "${H2S_LOCK_FAILLOCK_CONF:-}" ] || seam_faillock_conf=
# H2S_LOCK_U2F_CONF: the test's own pam_u2f.conf (pam-files.sh); with only
# H2S_LOCK_SYSTEM_PAM_DIR set, none is read (its place not said: not known)
seam_u2f_conf=${H2S_LOCK_U2F_CONF:-/etc/security/pam_u2f.conf}
[ -z "${H2S_LOCK_SYSTEM_PAM_DIR:-}" ] || [ -n "${H2S_LOCK_U2F_CONF:-}" ] || seam_u2f_conf=
# H2S_DISTRIBUTION: the distribution by its id (nixos, arch, generic), counted only together
# with H2S_LOCK_SYSTEM_PAM_DIR, so that a faked system never chooses among the machine's
# real PAM configs: both systems' answers are tested on every machine
seam_distribution=${H2S_LOCK_SYSTEM_PAM_DIR:+${H2S_DISTRIBUTION:-}}
# H2S_LOCK_AUTH_METHODS: a script of the test's that lists its test PAM stacks
seam_auth_methods=${H2S_LOCK_AUTH_METHODS:-}
# H2S_LOCK_TOOLS: a directory whose gdbus stands in (a stand-in fprintd behind it)
seam_gdbus=${H2S_LOCK_TOOLS:+$H2S_LOCK_TOOLS/gdbus}
seam_gdbus=${seam_gdbus:-gdbus}
# H2S_LAUNCHER_TEST_TIMINGS: the launcher's pauses, shortened ("first=0.1 lockwait=3 stopwait=1 ipccall=1",
# seconds), and "discoveryhang=S", a module search that takes S seconds
seam_launcher_timings=${H2S_LAUNCHER_TEST_TIMINGS:-}
# H2S_LAUNCHER_TEST_HANG_WHILE: a file the module search hangs only while it exists
# ("discoveryhang=S"), so a test can let one search through
seam_discovery_hang_while=${H2S_LAUNCHER_TEST_HANG_WHILE:-}
