#!/usr/bin/env bash
# The ways the lock screen can check who is there, one per line:
#
#   <method> TAB <PAM config directory> TAB <PAM config name>
#
# Each method is a PAM conversation of its own, so that a fingerprint reader waiting for
# a finger never holds up a typed password. A system-wide /etc/pam.d/h2s-shell-<method>
# wins (the NixOS module writes them; elsewhere the administrator may), else the config
# shipped in pam/ is used — except for the passive methods on NixOS, where the shipped
# configs cannot load their modules (below).
#
#   password     always
#   u2f          when there is a config for it and the user has a key registered where
#                that config's pam_u2f looks for keys (u2f_authfile below)
#   fingerprint  when there is a config for it and fprintd, asked over D-Bus, has a
#                finger enrolled for the user on some reader
#
# Exit status: 0 when every question was answered — also when the answer is "not here"
# (no fprintd, no reader, no finger enrolled, no key registered): the shell then does not
# ask again at every wake of the prompt. Non-zero when a question could not be answered
# (fprintd timed out, gave an error or an answer that cannot be read, no system bus):
# the shell then goes on with what it knew and asks again later (notes/plans/lockscreen.md,
# section 7, "Asking the script again"). The lines that could be answered are printed
# first even then; the shell does not use them after a failure (it takes its password
# fallback, chosen the same way as the password line here), but they show what was known.
# Why it failed goes to stderr, which the shell logs.
#
# It finishes within about four seconds whatever fprintd does (the shell gives it five):
# D-Bus activation of fprintd can block for much longer around suspend and resume.
#
# `--fallback-facts` asks something else: what the shell's own password fallback depends
# on (LockIoRules.fallbackFacts), one word per line that holds — "readable" (the
# system-wide h2s-shell-password), "nixos" — and always "answered" as the last line: the
# shell takes an answer without it (nothing at all, a cut-off one) as no answer, never as
# "neither holds". The shell asks here so that which system this is gets decided in one
# place; when this gives no answer it asks the machine itself (singletons/Lockscreen.qml).
#
# H2S_LOCK_SYSTEM_PAM_DIR: the test bed's seam for where system-wide configs are looked
# for (the shell's password fallback honours it too, singletons/Lockscreen.qml).
system_dir=${H2S_LOCK_SYSTEM_PAM_DIR:-/etc/pam.d}

# Which system this is: NixOS (/etc/NIXOS) or any other. H2S_LOCK_SYSTEM=nixos|other is
# the test bed's seam for it, so that both answers are tested on every machine. It counts
# only together with H2S_LOCK_SYSTEM_PAM_DIR: without H2S_LOCK_SYSTEM_PAM_DIR the machine
# is always asked. It grants nothing either way: both answers name real PAM stacks (the
# worst a wrong one does is a config that cannot be started, which never unlocks), and
# whoever can set the shell's environment can already run anything as the user.
nixos=0
case "${H2S_LOCK_SYSTEM_PAM_DIR:+${H2S_LOCK_SYSTEM:-}}" in
    nixos) nixos=1 ;;
    other) ;;
    *) [ -e /etc/NIXOS ] && nixos=1 ;;
esac

if [ "${1:-}" = --fallback-facts ]; then
    [ -r "$system_dir/h2s-shell-password" ] && echo readable
    [ "$nixos" = 1 ] && echo nixos
    echo answered
    exit 0
fi

# H2S_LOCK_AUTH_METHODS, when set, names an executable that answers instead of this
# script, in the same format. The lock test bed (tests/lock/) uses it to run the real
# shell against PAM stacks of its own rather than the system's. It lives here, in the
# detection step, so that it holds whatever QML asks the question. It grants nothing:
# whoever can set the shell's environment can already run anything as the user.
if [ -n "${H2S_LOCK_AUTH_METHODS:-}" ]; then
    exec "$H2S_LOCK_AUTH_METHODS"
fi

set -u

shell_dir=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# H2S_LOCK_TOOLS: the test bed's seam for a stand-in gdbus (as for the logind monitor)
gdbus=gdbus
[ -n "${H2S_LOCK_TOOLS:-}" ] && gdbus=$H2S_LOCK_TOOLS/gdbus
user=$(id -un)
failed=0

# Says why a question could not be answered, and makes the exit status non-zero
cannot_tell() {
    local reason="$*"
    echo "lock-auth-methods: ${reason//$'\n'/ }" >&2
    failed=1
}

# config <method> → "<directory> TAB <name>" of the config to use, or nothing. On NixOS
# the shipped configs name modules without a path, which libpam looks for only in its own
# store directory: pam_unix is there, pam_fprintd and pam_u2f (other packages) are not
# ("PAM unable to dlopen(…/linux-pam-…/lib/security/pam_fprintd.so)" in the journal). So
# there a passive method needs the system-wide config the NixOS module writes.
config() {
    if [ -r "$system_dir/h2s-shell-$1" ]; then
        printf '%s\t%s' "$system_dir" "h2s-shell-$1"
    elif [ "$1" = password ] || [ "$nixos" = 0 ]; then
        printf '%s\t%s' "$shell_dir/pam" "$1"
    fi
}

# ---- password -------------------------------------------------------------------------
# NixOS without the module's h2s-shell-password: "login", as the shell's own password
# fallback does (LockIoRules.passwordFallback) — they must agree. login waits for a
# fingerprint first when fprintd is on. The shipped pam/password would most likely work
# there too (its pam_unix does reach /run/wrappers/bin/unix_chkpwd: see notes/plans/
# lockscreen.md, Stage 5), but that is not confirmed with a real password yet.
if [ "$nixos" = 1 ] && [ ! -r "$system_dir/h2s-shell-password" ]; then
    printf 'password\t%s\tlogin\n' "$system_dir"
else
    printf 'password\t%s\n' "$(config password)"
fi

# ---- u2f ------------------------------------------------------------------------------
# Where the pam_u2f of a config looks for the user's keys, as pam_u2f 1.4 resolves it
# (pam-u2f.c, resolve_authfile_path): `authfile=<path>` (%u and %h expanded with `expand`;
# a relative path is under the home directory), else $XDG_CONFIG_HOME/Yubico/u2f_keys
# when XDG_CONFIG_HOME is set (the PAM child inherits the shell's environment), else
# ~/.config/Yubico/u2f_keys; with `sshformat`, id_ecdsa_sk in place of Yubico/u2f_keys
# (and ~/.ssh in place of ~/.config). Printed as "<path> TAB <sshformat 0/1>"; nothing
# when the config has no pam_u2f line. `include`d or `substack`ed configs are not followed.
u2f_authfile() {
    local file=$1 line word words authfile="" expand=0 sshformat=0 home
    line=$(grep -E '^[[:space:]]*-?auth[[:space:]].*pam_u2f\.so' "$file" 2> /dev/null | head -n 1)
    [ -n "$line" ] || return 0
    # Split into words without pathname expansion: `[origin=…]`, `authfile=/x/*` are
    # the module's words, not patterns to match against files here
    read -ra words <<< "$line"
    for word in "${words[@]}"; do
        case "$word" in
            authfile=*) authfile=${word#authfile=} ;;
            expand) expand=1 ;;
            sshformat) sshformat=1 ;;
        esac
    done
    home=$(getent passwd "$user" 2> /dev/null | cut -d: -f6)
    home=${home:-$HOME}
    if [ -n "$authfile" ] && [ "$expand" = 1 ]; then
        authfile=${authfile//%u/$user}
        authfile=${authfile//%h/$home}
    fi
    if [ -z "$authfile" ]; then
        if [ -n "${XDG_CONFIG_HOME:-}" ]; then
            [ "$sshformat" = 1 ] && authfile=$XDG_CONFIG_HOME/id_ecdsa_sk || authfile=$XDG_CONFIG_HOME/Yubico/u2f_keys
        else
            [ "$sshformat" = 1 ] && authfile=$home/.ssh/id_ecdsa_sk || authfile=$home/.config/Yubico/u2f_keys
        fi
    elif [ "${authfile#/}" = "$authfile" ]; then
        authfile=$home/$authfile
    fi
    printf '%s\t%s' "$authfile" "$sshformat"
}

# Whether the user has a key in that file. pam_u2f's own format (pamu2fcfg's output, per
# user or one file for everybody) is one line per user, "<user>:<key>[:<key>…]"; an SSH
# key file is the key itself. The PAM conversation runs as the user, so a file the user
# cannot read (a root-only mapping file) cannot serve: not offered.
u2f_registered() {
    local authfile=$1 sshformat=$2 line
    [ -r "$authfile" ] || return 1
    if [ "$sshformat" = 1 ]; then
        [ -s "$authfile" ]
        return
    fi
    # The user name matched literally (not as a pattern: a name may hold a dot), at the
    # start of a line, followed by ":" and at least one character
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" == "$user:"?* ]] && return 0
    done < "$authfile"
    return 1
}

u2f_config=$(config u2f)
if [ -n "$u2f_config" ]; then
    u2f_where=$(u2f_authfile "${u2f_config%%$'\t'*}/${u2f_config#*$'\t'}")
    if [ -n "$u2f_where" ] && u2f_registered "${u2f_where%%$'\t'*}" "${u2f_where#*$'\t'}"; then
        printf 'u2f\t%s\n' "$u2f_config"
    fi
fi

# ---- fingerprint ----------------------------------------------------------------------
# fprintd over D-Bus (net.reactivated.Fprint), with gdbus (glib: a dependency of the
# shell already, and what its logind monitor uses). Read-only calls: Manager.GetDevices
# and Device.ListEnrolledFingers. The user name is passed as "" — fprintd then takes the
# caller; naming a user, even oneself, is not needed, and naming another would ask polkit
# for net.reactivated.fprint.device.setusername, which brings up an authentication dialog.
#
# Not free of polkit even so: fprintd checks EVERY ListEnrolledFingers against the polkit
# action net.reactivated.fprint.device.verify (fprintd 1.94, src/device.c: the call needs
# the verify permission, checked with user interaction allowed). Its default is
# allow_active=yes — the active session's user gets it without a dialog — and no for an
# inactive session (a PermissionDenied: a failure here, asked again later). A site policy
# that requires authentication for it would put a dialog on the screen at every detection;
# the same rule already applies to pam_fprintd's Claim of the reader at every fingerprint
# conversation, so such a machine has no usable fingerprint lock either way.
#
# The whole question has a deadline (4 s); each call gets what is left of it.
deadline=$(( ${EPOCHREALTIME//[.,]/} / 1000 + 4000 ))

# fprint <object path> <method> [argument] → the reply on stdout; the D-Bus error name
# on stdout as "error <name>" with status 1; status 2 for a time-out or a failure to ask.
# What it prints is one line. gdbus's stderr is kept apart from its reply (a file of its
# own, removed at once): a GLib warning on a call that succeeded must not make the reply
# unreadable, and an error of several lines is one line of reason.
fprint() {
    local left output errors status error_file
    left=$(( deadline - ${EPOCHREALTIME//[.,]/} / 1000 ))
    if [ "$left" -le 0 ]; then
        echo "timeout"
        return 2
    fi
    error_file=$(mktemp "${TMPDIR:-/tmp}/lock-auth-methods.XXXXXX") || { echo "failed: cannot create a temp file"; return 2; }
    output=$(timeout -k 1 "$((left / 1000)).$(printf '%03d' $((left % 1000)))" \
        "$gdbus" call --system --timeout $(((left + 999) / 1000)) --dest net.reactivated.Fprint \
        --object-path "$1" --method "net.reactivated.Fprint.$2" "${@:3}" 2> "$error_file" < /dev/null)
    status=$?
    errors=$(tr '\n' ' ' < "$error_file" 2> /dev/null)
    rm -f "$error_file"
    if [ "$status" = 0 ]; then
        printf '%s\n' "$output" | head -n 1
        return 0
    fi
    # timeout's own, or gdbus's (its --timeout ran out: "Error: Timeout was reached")
    if [ "$status" = 124 ] || [ "$status" = 137 ] || [[ "$errors" == *"Timeout was reached"* ]]; then
        echo "timeout"
        return 2
    fi
    # gdbus: "Error: GDBus.Error:<error name>: <message>"
    if [[ "$errors" =~ GDBus\.Error:([A-Za-z0-9_.]+): ]]; then
        echo "error ${BASH_REMATCH[1]}"
        return 1
    fi
    printf 'failed: %s\n' "$(printf '%s' "${errors:-status $status}" | cut -c 1-200)"
    return 2
}

# The answer: "yes", "no", or a reason it could not be told (printed, status 1)
fingerprint_enrolled() {
    local reply status devices device
    if [ ! -x "$gdbus" ] && ! command -v "$gdbus" > /dev/null; then
        echo "gdbus is not installed"
        return 1
    fi
    reply=$(fprint /net/reactivated/Fprint/Manager Manager.GetDevices)
    status=$?
    case "$status:$reply" in
        0:*) ;;
        # No fprintd on this machine (not installed, or no activation file): not a failure
        "1:error org.freedesktop.DBus.Error.ServiceUnknown" | "1:error org.freedesktop.DBus.Error.NameHasNoOwner")
            echo no
            return 0
            ;;
        *)
            echo "fprintd GetDevices: $reply"
            return 1
            ;;
    esac
    # (@ao [],) or ([objectpath '/net/reactivated/Fprint/Device/0', …],)
    if [[ "$reply" =~ ^\((@ao\ )?\[\],\)$ ]]; then
        echo no
        return 0
    fi
    if ! [[ "$reply" =~ ^\(\[objectpath\ \'/[A-Za-z0-9_/]+\'(,\ objectpath\ \'/[A-Za-z0-9_/]+\')*\],\)$ ]]; then
        echo "fprintd GetDevices: an answer that cannot be read: ${reply:0:200}"
        return 1
    fi
    devices=$(grep -o "'/[A-Za-z0-9_/]*'" <<< "$reply" | tr -d "'")
    for device in $devices; do
        reply=$(fprint "$device" Device.ListEnrolledFingers "")
        status=$?
        case "$status:$reply" in
            "0:"*) ;;
            "1:error net.reactivated.Fprint.Error.NoEnrolledPrints") continue ;;
            *)
                echo "fprintd ListEnrolledFingers ($device): $reply"
                return 1
                ;;
        esac
        # (['right-index-finger', …],), or (@as [],)
        if [[ "$reply" =~ ^\((@as\ )?\[\],\)$ ]]; then
            continue
        fi
        if [[ "$reply" =~ ^\(\[\'[a-z-]+\'(,\ \'[a-z-]+\')*\],\)$ ]]; then
            echo yes
            return 0
        fi
        echo "fprintd ListEnrolledFingers ($device): an answer that cannot be read: ${reply:0:200}"
        return 1
    done
    echo no
}

fingerprint_config=$(config fingerprint)
if [ -n "$fingerprint_config" ]; then
    answer=$(fingerprint_enrolled)
    case "$?:$answer" in
        0:yes) printf 'fingerprint\t%s\n' "$fingerprint_config" ;;
        0:no) ;;
        *) cannot_tell "cannot tell whether a finger is enrolled: $answer" ;;
    esac
fi

exit "$failed"
