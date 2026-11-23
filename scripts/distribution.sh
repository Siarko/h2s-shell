#!/usr/bin/env bash
# shellcheck shell=bash
# Which distribution this is, for the shell's scripts — the detection the shell makes
# (singletons/DistributionRules.qml), from the same facts: each distributions/<id>/
# distribution.env, written from its distribution.json by scripts/distribution-env.py.
# Those files are parsed as key=value lines, never run. The scripts (lock-auth-methods.sh,
# launch.sh) source this, so that the lock's methods script answers without the shell's
# QML; tests/distribution-selftest.sh checks it against the same os-release fixtures the
# shell's suites read.
#
#   distribution_detect <shell dir> [<override> [<file root>]]
#
# sets distribution_id ("nixos", "arch", "generic"; "" when it cannot be told),
# distribution_how ("override", "marker", "id", "like", "fallback"; "" when unknown),
# distribution_problem (why it is unknown; "" when known), and the distribution's facts in
# the associative array distribution_facts (a list as one value joined with ":"). The rules,
# as the shell's: <override> (the H2S_DISTRIBUTION seam, given by the caller) names one and
# wins; else a distribution whose marker exists (`test -e`); else os-release's ID matched
# against each distribution's `matches`; else each word of ID_LIKE in its order; else the
# generic one. A distribution.env that cannot be used, an override that names none, an
# os-release that is there but cannot be read (none there: nothing to match), is too long or
# holds no well-formed assignment: unknown. <file root> is put before every system path (a
# test's scratch tree).
#
# Run as a command (tests): distribution.sh [--root <dir>] [--id <id>] prints id= and how=
# lines, status 0; or a problem= line, status 1.

# The distributions in the order their markers and matches are tried; the last is the
# fallback, which matches nothing (DistributionRules.ids)
distribution_ids=(nixos arch generic)
distribution_max_length=65536

# distribution_read_env <file> <id> <array name>: the file's lines into the array; status 1
# when it is not there, too long, has a line that is no `key=value` of a plain key, or its
# id is not <id>
distribution_read_env() {
    local file=$1 id=$2 line key text
    local -n distribution_read_into=$3
    distribution_read_into=()
    [ -f "$file" ] && [ -r "$file" ] || return 1
    [ "$(LC_ALL=C wc -c < "$file" 2> /dev/null || echo "$distribution_max_length")" -lt "$distribution_max_length" ] || return 1
    text=$(< "$file") || return 1
    while IFS= read -r line; do
        case "$line" in "" | "#"*) continue ;; esac
        [[ "$line" =~ ^([A-Za-z][A-Za-z0-9]*)=(.*)$ ]] || return 1
        key=${BASH_REMATCH[1]}
        distribution_read_into[$key]=${BASH_REMATCH[2]}
    done <<< "$text"
    [ "${distribution_read_into[id]-}" = "$id" ] && [ -n "${distribution_read_into[matches]+set}" ] && [ -n "${distribution_read_into[markers]+set}" ]
}

# distribution_os_release <file root>: sets distribution_os_id and distribution_os_like
# from the first os-release there (/etc/os-release, else /usr/lib/os-release), parsed as
# DistributionRules.parseOsRelease does; status 1 when it cannot be told (see above)
distribution_os_release() {
    local root=$1 path file="" text line name value assignments=0
    local -A values=()
    distribution_os_id=""
    distribution_os_like=""
    for path in /etc/os-release /usr/lib/os-release; do
        if [ -e "$root$path" ] || [ -L "$root$path" ]; then
            file=$root$path
            break
        fi
    done
    [ -n "$file" ] || return 0
    [ -f "$file" ] && [ -r "$file" ] || return 1
    [ "$(LC_ALL=C wc -c < "$file" 2> /dev/null || echo "$distribution_max_length")" -le "$distribution_max_length" ] || return 1
    text=$(< "$file") 2> /dev/null || return 1
    while IFS= read -r line; do
        line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
        name=${BASH_REMATCH[1]}
        value=${BASH_REMATCH[2]}
        if [[ "$value" == '"'* ]]; then
            [[ "$value" =~ ^\"(([^\"\\]|\\.)*)\"$ ]] || continue
            value=$(distribution_unescape "${BASH_REMATCH[1]}")
        elif [[ "$value" == "'"* ]]; then
            [[ "$value" =~ ^\'([^\']*)\'$ ]] || continue
            value=${BASH_REMATCH[1]}
        elif [[ "$value" =~ [\"\'\\\$\`[:space:]] ]]; then
            continue
        fi
        values[$name]=$value
        assignments=$((assignments + 1))
    done <<< "$text"
    [ "$assignments" -gt 0 ] || return 1
    distribution_os_id=${values[ID]-}
    distribution_os_like=${values[ID_LIKE]-}
}

# The text inside double quotes with \\ \" \$ \` taken as the character they escape
distribution_unescape() {
    local text=$1 out="" character
    while [ -n "$text" ]; do
        character=${text:0:1}
        if [ "$character" = "\\" ] && [[ "${text:1:1}" == [\\\"\$\`] ]]; then
            out+=${text:1:1}
            text=${text:2}
        else
            out+=$character
            text=${text:1}
        fi
    done
    printf '%s' "$out"
}

# distribution_matching <word>: the id whose `matches` holds it, or nothing
distribution_matching() {
    local word=$1 id match list=()
    [[ "$word" =~ ^[a-z0-9._-]{1,64}$ ]] || return 0
    for id in "${distribution_ids[@]}"; do
        distribution_list "$id" matches list
        for match in "${list[@]}"; do
            [ "$match" = "$word" ] && { echo "$id"; return 0; }
        done
    done
}

# distribution_list <id> <key> <array name>: that fact of that distribution, split at ":"
distribution_list() {
    local -n distribution_list_env=distribution_env_$1 distribution_list_out=$3
    distribution_list_out=()
    [ -z "${distribution_list_env[$2]-}" ] || IFS=: read -r -a distribution_list_out <<< "${distribution_list_env[$2]}"
}

# Takes <id> as the answer, found <how>, with its facts
distribution_known() {
    local key
    local -n distribution_known_env=distribution_env_$1
    distribution_id=$1
    distribution_how=$2
    for key in "${!distribution_known_env[@]}"; do
        distribution_facts[$key]=${distribution_known_env[$key]}
    done
}

distribution_detect() {
    local shell_dir=$1 override=${2-} root=${3-} id marker word found="" markers=()
    distribution_id=""
    distribution_how=""
    distribution_problem=""
    declare -gA distribution_facts=()
    for id in "${distribution_ids[@]}"; do
        declare -gA "distribution_env_$id=()"
        if ! distribution_read_env "$shell_dir/distributions/$id/distribution.env" "$id" "distribution_env_$id"; then
            distribution_problem="distributions/$id/distribution.env cannot be used"
            return 1
        fi
    done
    if [ -n "$override" ]; then
        for id in "${distribution_ids[@]}"; do
            [ "$id" = "$override" ] && { distribution_known "$id" override; return 0; }
        done
        distribution_problem="H2S_DISTRIBUTION names no distribution: $override"
        return 1
    fi
    for id in "${distribution_ids[@]}"; do
        distribution_list "$id" markers markers
        for marker in "${markers[@]}"; do
            if [ -e "$root$marker" ] || [ -L "$root$marker" ]; then
                distribution_known "$id" marker
                return 0
            fi
        done
    done
    if ! distribution_os_release "$root"; then
        distribution_problem="os-release cannot be read"
        return 1
    fi
    found=$(distribution_matching "$distribution_os_id")
    [ -n "$found" ] && { distribution_known "$found" id; return 0; }
    for word in $distribution_os_like; do
        found=$(distribution_matching "$word")
        [ -n "$found" ] && { distribution_known "$found" like; return 0; }
    done
    distribution_known "${distribution_ids[-1]}" fallback
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    root="" override=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --root) root=${2-}; shift 2 ;;
            --id) override=${2-}; shift 2 ;;
            *) echo "usage: distribution.sh [--root <dir>] [--id <id>]" >&2; exit 2 ;;
        esac
    done
    if distribution_detect "$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)" "$override" "$root"; then
        printf 'id=%s\nhow=%s\n' "$distribution_id" "$distribution_how"
        exit 0
    fi
    printf 'problem=%s\n' "$distribution_problem"
    exit 1
fi
