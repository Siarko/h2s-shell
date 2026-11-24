# shellcheck shell=bash
# The NixOS build with the shell's settings, evaluated only (nothing built, nothing linked, no
# lock file written), on three fixture configurations made in a scratch folder — a flake, the
# same flake in git, and a classic configuration (tests/fixtures/nixos-build/system/, each
# importing tests/system/nixos/build.nix) — with the shell's file holding one content:
#
# - the user's build exactly as NixBuildRules.plan gives it (tests/fixtures/nixos-build/argv.json,
#   which tests/NixBuildRulesTest.qml checks word for word), run with --dry-run, gives the
#   drvPath of the real configuration as nixos-rebuild evaluates it (the flake by the CLI's own
#   reference, classic by <nixpkgs/nixos>) for the same content;
# - the root step's evaluation (scripts/root/nixos-toplevel.sh's toplevel_inputs and
#   toplevel_paths, the very functions nixos-apply.sh runs, here as the user) gives the same
#   drvPath as the user's build;
# - another content gives another drvPath, and the real configuration with that content
#   written gives that one.
need nix "evaluates NixOS configurations"
need git "makes the fixture flake in git"

nix_program=/run/current-system/sw/bin/nix
[ -x "$nix_program" ] || nix_program=$(command -v nix)
work=$(mktemp -d "${TMPDIR:-/tmp}/system-build.XXXXXX") || cannot_run "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
fixtures=$REPO/tests/fixtures/nixos-build
expression=$(sed -n "/^nixos_toplevel='/,/'\$/p" "$REPO/scripts/root/nixos-toplevel.sh" | sed "1s/^nixos_toplevel='//; \$s/'\$//")
nixpkgs=$(sed -n 's/^export NIX_PATH="\(.*\)"$/\1/p' /etc/set-environment | tr ':' '\n' | sed -n 's/^nixpkgs=//p' | head -n 1)
[ -n "$expression" ] || cannot_run "nixos_toplevel not read from scripts/root/nixos-toplevel.sh"
[ -n "$nixpkgs" ] || cannot_run "no nixpkgs in /etc/set-environment's NIX_PATH (classic needs it)"
first='{"version":1,"polkit":{"rememberAdmin":{"minutes":7}}}'
second='{"version":1,"polkit":{"rememberAdmin":{"minutes":9}}}'

# The fixture folders
for kind in flake git classic; do
    mkdir -p "$work/$kind"
    cp "$REPO/tests/system/nixos/build.nix" "$work/$kind/build.nix"
    printf '%s' "$first" > "$work/$kind/h2s-shell.json"
done
for kind in flake git; do
    sed "s|@REPO@|$REPO|g" "$fixtures/system/flake.nix" > "$work/$kind/flake.nix"
done
sed "s|@REPO@|$REPO|g" "$fixtures/system/configuration.nix" > "$work/classic/configuration.nix"
git -C "$work/git" init -q && git -C "$work/git" add -A \
    && git -C "$work/git" -c user.name=test -c user.email=test@example.invalid commit -q -m fixture \
    || cannot_run "cannot make the fixture git repository"

# golden <entry> <nix list of entry>: argv.json's words for the entry, one per line (none
# holds a line break), read by nix itself
golden() {
    "$nix_program" --extra-experimental-features 'nix-command flakes' eval --raw --impure --expr \
        "let entry = (builtins.fromJSON (builtins.readFile $fixtures/argv.json)).$1; in builtins.concatStringsSep \"\\n\" ($2) + \"\\n\""
}

# user <kind> <content>: the drvPath of the user's build (argv.json, --dry-run)
user() {
    local kind=$1 scratch=$work/scratch-$1
    rm -rf "$scratch"; mkdir -p "$scratch"
    printf '%s' "$2" > "$scratch/h2s-shell.json"
    local entry=$kind
    local -a words environment
    mapfile -t words < <(golden "$entry" 'entry.argv')
    mapfile -t environment < <(golden "$entry" 'map (name: name + "=" + entry.environment.${name}) (builtins.attrNames entry.environment)')
    local i
    for i in "${!words[@]}"; do
        words[i]=${words[i]//@NIX@/$nix_program}; words[i]=${words[i]//@SCRATCH@/$scratch}; words[i]=${words[i]//@FOLDER@/$work/$kind}
        words[i]=${words[i]//@HOST@/fixture}; words[i]=${words[i]//@NIXPKGS@/$nixpkgs}; words[i]=${words[i]//@EXPR@/$expression}
    done
    for i in "${!environment[@]}"; do
        environment[i]=${environment[i]//@SCRATCH@/$scratch}; environment[i]=${environment[i]//@FOLDER@/$work/$kind}
        environment[i]=${environment[i]//@HOST@/fixture}
    done
    env "${environment[@]}" "${words[@]}" --dry-run 2> "$work/user-$kind.log" | sed -n 's/^\[{"drvPath":"\([^"]*\)".*/\1/p'
}

# root <kind> <content>: the drvPath root's evaluation gives, by nixos-toplevel.sh's own code
root() (
    local kind=$1 home=$work/root-home-$1 entry=flake.nix host=fixture
    [ "$kind" = classic ] && { entry=configuration.nix; host=-; }
    rm -rf "$home"; mkdir -p "$home/candidate"
    printf '%s' "$2" > "$home/candidate/h2s-shell.json"
    # replace-lib.sh's helpers (is_plain, refuse); base "" — the system's own places
    # shellcheck source=/dev/null
    . "$REPO/scripts/root/replace-lib.sh"
    # shellcheck source=/dev/null
    . "$REPO/scripts/root/nixos-toplevel.sh"
    base=
    toplevel_inputs "$work/$kind" "$entry" "$host"
    printf '[safe]\n\tdirectory = %s\n' "$work/$kind" > "$home/.gitconfig"
    if [ -n "$flake" ]; then set --; else set -- -I "nixpkgs=$nixpkgs" -I "nixos-config=$nixos_config"; fi
    toplevel_paths "$nix_program" "$home" "$work/root-cache" "$home/candidate/h2s-shell.json" "$@" 2> "$work/root-$kind.log" | cut -d' ' -f1
)

# real <kind>: the configuration's own drvPath, as nixos-rebuild evaluates it
real() {
    if [ "$1" = classic ]; then
        nix-instantiate --extra-experimental-features 'nix-command flakes' -I "nixpkgs=$nixpkgs" -I "nixos-config=$work/classic/configuration.nix" \
            '<nixpkgs/nixos>' -A system 2> "$work/real-$1.log"
    else
        "$nix_program" --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file \
            "$work/$1#nixosConfigurations.fixture.config.system.build.toplevel.drvPath" 2> "$work/real-$1.log"
    fi
}

is_drv() { [[ $1 == /nix/store/*.drv ]]; }
show_log() { is_drv "$2" || tail -n 15 "$work/$1.log"; }

for kind in flake git classic; do
    real_first=$(real "$kind"); show_log "real-$kind" "$real_first"
    user_first=$(user "$kind" "$first"); show_log "user-$kind" "$user_first"
    root_first=$(root "$kind" "$first"); show_log "root-$kind" "$root_first"
    user_second=$(user "$kind" "$second"); show_log "user-$kind" "$user_second"
    printf '%s' "$second" > "$work/$kind/h2s-shell.json"
    real_second=$(real "$kind"); show_log "real-$kind" "$real_second"
    check "$kind: the configuration evaluates ($real_first)" is_drv "$real_first"
    check "$kind: the user's build, as NixBuildRules words it, gives the real drvPath for the same content" test "$user_first" = "$real_first"
    check "$kind: the root step's evaluation gives the user's drvPath" test "$root_first" = "$user_first"
    check "$kind: another content, another drvPath" test "$user_second" != "$user_first"
    check "$kind: … the real one once that content is written" test "$user_second" = "$real_second"
done
check "the fixture git repository not written by the evaluations (no lock file)" test ! -e "$work/git/flake.lock"
check "… nor the plain flake's" test ! -e "$work/flake/flake.lock"
