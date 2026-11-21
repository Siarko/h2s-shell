#!/usr/bin/env bash
# The stand-ins tests/ModuleUpdaterTest.qml updates from, made in a new private temporary
# directory (printed on the last line): local bare git repositories reached by file://, a
# script that publishes a new version to one of them, and a stand-in `git` first on the
# updater's PATH. The stand-in logs every command line it is given and then runs the real
# git — or does what the file `fake/mode` says: "lsrefuse" (ls-remote fails as a server that
# is not there), "lsslow" (ls-remote answers after a pause, then logs "answered ls-remote"),
# "cloneslow" (clone and fetch start after a pause), "clonerefuse" (clone and fetch fail). Its sleeps run as naps/sleep, a link to
# the system's sleep, so a suite can see none is left. Nothing here reaches the network or
# the user's own git configuration.
set -euo pipefail

real_git=$(command -v git) || { echo "git is not on PATH" >&2; exit 2; }
T=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}" h2s-updater.XXXXXX)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { "$real_git" -c user.name=tester -c user.email=tester@example.invalid -c init.defaultBranch=main \
          -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

mkdir -p "$T/work" "$T/repos" "$T/fake" "$T/data/h2s-shell/modules" "$T/config" "$T/naps"

# publish <name> <Name> <version> <tag: yes|no> [<extra JSON fields>]: a new commit of the
# module at that version (with a changelog section for it), tagged v<version> when asked,
# pushed to its bare repository
publish() {
    local name=$1 title=$2 version=$3 tag=$4 extra=${5:-}
    local work=$T/work/$name
    if [ ! -d "$work" ]; then
        g init -q "$work"
        printf '# Changelog\n' > "$work/CHANGELOG.md"
    fi
    printf '{ "id": "%s", "name": "%s", "version": "%s", "api": "1.36", "main": "Main.qml"%s }\n' \
        "$name" "$title" "$version" "${extra:+, $extra}" > "$work/module.json"
    printf 'import QtQuick\nQtObject {}\n' > "$work/Main.qml"
    { printf '# Changelog\n\n## %s\n\n- Version %s of %s.\n' "$version" "$version" "$title"
      tail -n +2 "$work/CHANGELOG.md"; } > "$work/CHANGELOG.new"
    mv "$work/CHANGELOG.new" "$work/CHANGELOG.md"
    g -C "$work" add -A
    g -C "$work" commit -q -m "$version"
    if [ "$tag" = yes ]; then g -C "$work" tag "v$version"; fi
    if [ ! -d "$T/repos/$name.git" ]; then
        g clone -q --bare "$work" "$T/repos/$name.git"
    else
        g -C "$work" push -q "$T/repos/$name.git" main --tags
    fi
}

privileged='"optionalPrograms": ["lpadmin"], "privileged": { "why": "Add printers", "programs": ["lpadmin"] }'

# Weather and Clock follow tags (1.0.0 installed, 1.1.0 published); Notes follows its
# default branch; Printers 1.1.0 first asks for administrator rights
publish wx Weather 1.0.0 yes
publish wx Weather 1.1.0 yes
publish cl Clock 1.0.0 yes
publish cl Clock 1.1.0 yes
publish nt Notes 1.0.0 no
publish pv Printers 1.0.0 yes
publish pv Printers 1.1.0 yes "$privileged"

# The script a suite publishes a new version with: publish <name> <Name> <version> <tag> [<extra>]
{
    printf '#!/usr/bin/env bash\nset -euo pipefail\nT=%q\nreal_git=%q\nexport GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1\n' "$T" "$real_git"
    declare -f g publish
    printf 'privileged=%q\n' "$privileged"
    printf 'extra=${5:-}\n[ "$extra" = privileged ] && extra=$privileged\npublish "$1" "$2" "$3" "$4" "$extra"\n'
} > "$T/publish"
chmod +x "$T/publish"

ln -s "$(command -v sleep)" "$T/naps/sleep"
cat > "$T/fake/git" <<STANDIN
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/git.log"
mode=\$(cat "$T/fake/mode" 2> /dev/null || true)
case " \$* " in
    *" ls-remote "*)
        case "\$mode" in
            lsrefuse) echo "fatal: '$T/nothere' does not appear to be a git repository" >&2; exit 128 ;;
            lsslow) "$T/naps/sleep" 2; "$real_git" "\$@"; status=\$?; printf 'answered ls-remote\n' >> "$T/git.log"; exit \$status ;;
        esac ;;
    *" clone "* | *" fetch "*)
        case "\$mode" in
            cloneslow) "$T/naps/sleep" 2 ;;
            clonerefuse) echo "fatal: repository 'stand-in' not found" >&2; exit 128 ;;
        esac ;;
esac
exec "$real_git" "\$@"
STANDIN
chmod +x "$T/fake/git"
: > "$T/fake/mode"
: > "$T/git.log"
echo "$T"
