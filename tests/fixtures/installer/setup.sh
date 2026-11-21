#!/usr/bin/env bash
# The stand-ins tests/ModuleInstallerTest.qml installs from, made in a new private temporary
# directory (printed on the last line): local bare git repositories reached by file://, folders,
# a hand-placed folder and a hand-made link in the user root, and a stand-in `git` first on the
# installer's PATH. The stand-in logs every command line it is given and then runs the real
# git — or, for clone and fetch, does what the file `fake/mode` says: "hang", "refuse",
# "large" (a progress line past the size cap, then hangs), "progress" (a progress line, then
# the real git). Nothing here reaches the network or the user's own git configuration.
set -euo pipefail

real_git=$(command -v git) || { echo "git is not on PATH" >&2; exit 2; }
T=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}" h2s-installer.XXXXXX)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { "$real_git" -c user.name=tester -c user.email=tester@example.invalid -c init.defaultBranch=main \
          -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

mkdir -p "$T/work" "$T/repos" "$T/fake" "$T/folders" "$T/outside" "$T/elsewhere" \
         "$T/data/h2s-shell/modules" "$T/config"

module() {   # <dir> <module.json text> [<Main.qml text>]
    mkdir -p "$1"
    printf '%s\n' "$2" > "$1/module.json"
    if [ $# -ge 3 ]; then printf '%s\n' "$3" > "$1/Main.qml"; fi
}
plain_main='import QtQuick
QtObject {}'
provider_main='import QtQuick
QtObject {
    readonly property QtObject exports: QtObject {}
}'
broken_main='import QtQuick
QtObject { this is not QML'

start() { g init -q "$T/work/$1"; }
commit() { g -C "$T/work/$1" add -A && g -C "$T/work/$1" commit -q -m "$2"; }
publish() { g clone -q --bare "$T/work/$1" "$T/repos/$1.git"; }

# alpha: 1.0.0 tagged, 1.1.0 on main, 1.2.0 that does not start on the branch "broken"
start alpha
module "$T/work/alpha" '{ "id": "alpha", "name": "Alpha", "version": "1.0.0", "api": "1.36", "main": "Main.qml" }' "$plain_main"
commit alpha "1.0.0"; g -C "$T/work/alpha" tag v1.0.0
module "$T/work/alpha" '{ "id": "alpha", "name": "Alpha", "version": "1.1.0", "api": "1.36", "main": "Main.qml" }' "$plain_main"
commit alpha "1.1.0"
g -C "$T/work/alpha" checkout -q -b broken
module "$T/work/alpha" '{ "id": "alpha", "name": "Alpha", "version": "1.2.0", "api": "1.36", "main": "Main.qml" }' "$broken_main"
commit alpha "1.2.0, broken"
g -C "$T/work/alpha" checkout -q main
publish alpha

# A chain of two: beta uses gamma, named with its source
for name in gamma pi; do
    start "$name"
    module "$T/work/$name" '{ "id": "'"$name"'", "name": "'"${name^}"'", "version": "1.0.0", "api": "1.36", "main": "Main.qml", "exports": { "version": "1.0" } }' "$provider_main"
    commit "$name" "1.0.0"; publish "$name"
done
for pair in beta:gamma rho:pi; do
    name=${pair%:*}; uses=${pair#*:}
    start "$name"
    module "$T/work/$name" '{ "id": "'"$name"'", "name": "'"${name^}"'", "version": "2.0.0", "api": "1.36", "main": "Main.qml",
      "uses": { "'"$uses"'": { "version": "1.0", "source": "file://'"$T"'/repos/'"$uses"'.git" } } }' "$plain_main"
    commit "$name" "2.0.0"; publish "$name"
done

# delta needs a module nothing names a source for
start delta
module "$T/work/delta" '{ "id": "delta", "name": "Delta", "version": "0.1.0", "api": "1.36", "uses": { "nothere": "1.0" } }'
commit delta "0.1.0"; publish delta

# bad: no API; taken: the id of the hand-placed folder
start bad
module "$T/work/bad" '{ "id": "bad", "name": "Bad", "version": "0.1.0" }'
commit bad "0.1.0"; publish bad
start taken
module "$T/work/taken" '{ "id": "handmade", "name": "Taken", "version": "9.0.0", "api": "1.36" }'
commit taken "9.0.0"; publish taken

# Folders: a clean one, and one with a link out of it
module "$T/folders/clean" '{ "id": "folded", "name": "Folded", "version": "0.3.0", "api": "1.36", "main": "Main.qml" }' "$plain_main"
module "$T/folders/leaky" '{ "id": "leaky", "name": "Leaky", "version": "0.1.0", "api": "1.36" }'
ln -s /etc/hostname "$T/folders/leaky/hostname"

# The user root: a folder placed by hand, a link made by hand to a module elsewhere
module "$T/data/h2s-shell/modules/handmade" '{ "id": "handmade", "name": "Handmade", "version": "0.1.0", "api": "1.36" }'
module "$T/outside/linked" '{ "id": "linked", "name": "Linked", "version": "0.1.0", "api": "1.36" }'
ln -s "$T/outside/linked" "$T/data/h2s-shell/modules/linked"
printf 'keep\n' > "$T/elsewhere/marker"

# The stand-in git
cat > "$T/fake/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/git.log"
mode=\$(cat "$T/fake/mode" 2> /dev/null || true)
case " \$* " in
    *" clone "* | *" fetch "*)
        case "\$mode" in
            hang) exec sleep 30 ;;
            refuse) echo "fatal: repository 'stand-in' not found" >&2; exit 128 ;;
            large) printf 'Receiving objects:  10%% (1/10), 300.00 MiB | 10.00 MiB/s\n' >&2; exec sleep 30 ;;
            progress) printf 'Receiving objects:  50%% (1/2), 1.00 MiB | 2.00 MiB/s\n' >&2 ;;
        esac ;;
esac
exec "$real_git" "\$@"
EOF
chmod +x "$T/fake/git"
: > "$T/fake/mode"
: > "$T/git.log"
echo "$T"
