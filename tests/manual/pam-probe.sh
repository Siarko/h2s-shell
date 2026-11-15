#!/usr/bin/env bash
# Runs pam-probe.qml once: asks for the password without echo, hands it over through a
# FIFO in a private directory (never an argument, the environment or a log), prints
# Success / Failed / Error. See README.md here. NOT run by any suite.
#
#   tests/manual/pam-probe.sh [config]     (default: password, the shipped pam/password)
set -euo pipefail

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
repo=$(cd "$here/../.." && pwd)
qs=${PAM_PROBE_QS:-$(command -v qs || command -v quickshell)}

work=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pam-probe.XXXXXX")
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT
mkfifo -m 600 "$work/password"

IFS= read -rs -p "Password for $(id -un) (one attempt): " password
echo

# No window, nothing on screen (offscreen platform); the password goes into the FIFO only
H2S_PAM_PROBE_DIR="$repo/pam" H2S_PAM_PROBE_CONFIG="${1:-password}" H2S_PAM_PROBE_FIFO="$work/password" \
    QT_QPA_PLATFORM=offscreen "$qs" -p "$here/pam-probe.qml" 2>&1 | grep --line-buffered 'pam-probe:' &
probe=$!
printf '%s\n' "$password" > "$work/password"
unset password
wait "$probe"
