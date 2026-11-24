#!/usr/bin/env bash
# Runs install.sh — the top-level one, which runs distributions/arch/install.sh on Arch and
# systems based on it and refuses every other — without letting it change the machine, and
# checks what it would have done: which system it takes itself to be on (made-up
# os-release files), that given on standard input it fetches the Arch installer (a stand-in
# curl) and removes it after, which packages it asks for and how, where the shell goes, where its built-in modules
# are copied (and `--update`, which copies them again), that it builds the helper as the user
# (and goes on when that fails), that nothing runs as root but what it hands to sudo, that a second run changes nothing, and what it does when a step fails. The same on NixOS and on Arch: install.sh is for Arch, the test is not.
#
# How install.sh is kept from the machine:
#   - an empty environment (env -i) with a private HOME and a PATH of one directory, made
#     here: recording stand-ins for sudo, pacman, git, fc-list, curl and for every program that
#     could change the system (below), and links to the plain tools install.sh uses
#     (bash, mkdir, dirname, grep, cat, and cp, mv, rm, mktemp for the built-in modules, which work
#     only inside the private HOME). No stand-in runs anything real;
#   - no new privileges (setpriv): even a sudo reached by another way could not become root;
#   - before anything runs: every privileged name must resolve to a stand-in written here,
#     and both scripts are read for the ways around a PATH of stand-ins that reading can find
#     (guard_lines below: a program named by its path, `command -p`, an assignment to
#     PATH, `exec`, `eval`, `source` and `.`, a variable as the command, a command
#     substitution in a here-document) — else the test stops, status 2. That reading is no
#     proof: it refuses these forms, not every way a script could be written to reach a
#     real program. What holds whatever install.sh says is the list above: the empty
#     environment, the one-directory PATH, the private HOME, no new privileges.
#
# install.sh gives pacman the terminal (/dev/tty), so each run gets a terminal of its own
# (script, util-linux); the test needs none. The case of no terminal runs in a session
# without one (setsid).
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when the test could not be
# set up (a missing tool is named with its use) or would not be safe to start.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
DISPATCHER=$REPO/install.sh
ARCH_INSTALL=$REPO/distributions/arch/install.sh
setup_error() { echo "install-test.sh: $*" >&2; exit 2; }

missing=()
need() { type -P "$1" > /dev/null || missing+=("$1 not found on PATH ($2)"); }
need script "gives each run of install.sh a terminal of its own, as it hands pacman one"
need setpriv "runs install.sh with no new privileges, so that nothing in it could become root"
need timeout "ends a run that hangs"
need setsid "runs install.sh without a terminal, for the case of none"
need unshare "runs install.sh as root of a user namespace (no real privilege), for the case of a run as root"
need awk "reads install.sh for ways around the stand-ins before it is run"
need sed "makes the stand-in curl's other installer"
for tool in bash mkdir dirname grep cat cp mv rm mktemp readlink; do need "$tool" "install.sh uses it; linked into the private PATH"; done
if [ ${#missing[@]} -gt 0 ]; then
    printf 'install-test.sh: %s\n' "${missing[@]}" >&2
    exit 2
fi
SCRIPT=$(type -P script)
SETPRIV=$(type -P setpriv)
TIMEOUT=$(type -P timeout)
SETSID=$(type -P setsid)
UNSHARE=$(type -P unshare)
BASH_PATH=$(type -P bash)
SED_PATH=$(type -P sed)

work=$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX") || setup_error "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
# The scripts as a checkout holds them, reading os-release and pacman.conf under a made-up
# tree ($work/os-root, which each case fills) in place of the system's: the one line in each
# that names that folder or file, changed in the copies alone
OS_ROOT=$work/os-root
CHECKOUT=$work/checkout
mkdir -p "$CHECKOUT/distributions/arch" "$OS_ROOT/etc"
grep -qx 'system_root=""' "$DISPATCHER" || setup_error "install.sh has no line system_root=\"\" for the test to point at a made-up tree"
grep -qx 'pacman_conf=/etc/pacman.conf' "$ARCH_INSTALL" || setup_error "the Arch installer has no line pacman_conf=/etc/pacman.conf for the test to point at a made-up file"
sed "s|^system_root=\"\"\$|system_root=\"$OS_ROOT\"|" "$DISPATCHER" > "$CHECKOUT/install.sh"
sed "s|^pacman_conf=/etc/pacman.conf\$|pacman_conf=$OS_ROOT/etc/pacman.conf|" "$ARCH_INSTALL" > "$CHECKOUT/distributions/arch/install.sh"
INSTALL=$CHECKOUT/install.sh
FIXTURES=$REPO/tests/fixtures/distribution
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

# What must never be the real thing on the private PATH. The first four are install.sh's
# own; the rest are not expected at all and only say that they were called (status 97).
PRIVILEGED=(sudo pacman pkexec su doas systemctl yay paru)
UNEXPECTED=(pkexec su doas systemctl yay paru ln chmod chown install tee wget)
MARK="# a stand-in written by tests/install-test.sh"

# make_bin <directory>: the private PATH of one run, and its control directory beside it
# (<directory>/../control): `log` (one line per stand-in call), and files a case puts
# there: sudo-status, git-clone-fails, git-remote-fails, git-clone-no-builtin (a clone
# without builtin-modules/), git-clone-no-helper (a clone without scripts/build-helper.sh),
# build-fails (the clone's stand-in build-helper.sh fails), fonts (what fc-list prints),
# fc-list-fails (fc-list ends with an error), pacman-ok (pacman run directly succeeds),
# curl-fails (the fetch of the Arch installer fails), curl-other-dispatch (the installer
# fetched expects another hand-over version than the top-level script's).
make_bin() {
    local bin=$1 control name
    control=$(dirname "$bin")/control
    mkdir -p "$bin" "$control"
    for name in bash mkdir dirname grep cat cp mv rm mktemp readlink; do ln -s "$(type -P "$name")" "$bin/$name"; done
    standin() { { echo "#!$BASH_PATH"; echo "$MARK"; echo "control='$control'"; cat; } > "$bin/$1"; chmod +x "$bin/$1"; }
    standin sudo << 'STANDIN'
terminal=no
[ -t 0 ] && terminal=yes
privileges=unknown
while read -r key value; do [ "$key" = NoNewPrivs: ] && privileges=$value; done < /proc/self/status
echo "sudo stdin-terminal=$terminal no-new-privs=$privileges: $*" >> "$control/log"
[ -f "$control/sudo-status" ] && exit "$(cat "$control/sudo-status")"
exit 0
STANDIN
    standin pacman << 'STANDIN'
echo "pacman: $*" >> "$control/log"
[ -e "$control/pacman-ok" ] && exit 0
exit 97
STANDIN
    standin git << 'STANDIN'
echo "git: $*" >> "$control/log"
case "$*" in
    "-C "*" remote get-url origin")
        [ -e "$control/git-remote-fails" ] && { echo "fatal: not a git repository" >&2; exit 128; }
        [ -f "$2/.standin-origin" ] || exit 2
        cat "$2/.standin-origin"
        ;;
    "clone "*)
        [ -e "$control/git-clone-fails" ] && { echo "fatal: unable to access '$2'" >&2; exit 128; }
        shopt -s nullglob dotglob
        if [ -d "$3" ]; then
            entries=("$3"/*)
            [ ${#entries[@]} = 0 ] || { echo "fatal: destination path '$3' already exists and is not an empty directory." >&2; exit 128; }
        else
            mkdir "$3" || exit 128
        fi
        echo "$2" > "$3/.standin-origin"
        : > "$3/shell.qml"
        if [ ! -e "$control/git-clone-no-builtin" ]; then
            mkdir -p "$3/builtin-modules/sample"
            echo '{ "off": [] }' > "$3/builtin-modules/builtin.json"
            echo '{ "id": "sample" }' > "$3/builtin-modules/sample/module.json"
        fi
        # The helper's build script, a stand-in that notes its call (install.sh runs it with
        # bash) and fails when told: the real one is tests/run-helper.sh's
        if [ ! -e "$control/git-clone-no-helper" ]; then
            mkdir -p "$3/scripts"
            {
                echo "control='$control'"
                echo 'privileges=unknown'
                echo 'while read -r key value; do [ "$key" = NoNewPrivs: ] && privileges=$value; done < /proc/self/status'
                echo 'echo "build-helper no-new-privs=$privileges: $*" >> "$control/log"'
                echo '[ ! -e "$control/build-fails" ] || { echo "a compiler error" >&2; exit 1; }'
                echo 'echo "$HOME/.cache/h2s-shell/helper/0123456789abcdef/h2s-helper"'
            } > "$3/scripts/build-helper.sh"
        fi
        ;;
    *) exit 97 ;;
esac
STANDIN
    # The fetch of the Arch installer: this checkout's, written where -o says
    standin curl << STANDIN
echo "curl: \$*" >> "\$control/log"
[ -e "\$control/curl-fails" ] && { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
output=""
while [ \$# -gt 0 ]; do
    [ "\$1" = -o ] && { output=\$2; shift; }
    shift
done
[ -n "\$output" ] || exit 2
if [ -e "\$control/curl-other-dispatch" ]; then
    '$SED_PATH' 's/^dispatch_known=1\$/dispatch_known=2/' '$CHECKOUT/distributions/arch/install.sh' > "\$output"
else
    cat '$CHECKOUT/distributions/arch/install.sh' > "\$output"
fi
STANDIN
    standin fc-list << 'STANDIN'
echo "fc-list: $*" >> "$control/log"
[ -e "$control/fc-list-fails" ] && { echo "Fontconfig error: cannot load default config file" >&2; exit 1; }
# as fc-list itself: a reader that leaves early ends it (SIGPIPE), seen in its status
[ -f "$control/fonts" ] && exec cat "$control/fonts"
exit 0
STANDIN
    for name in "${UNEXPECTED[@]}"; do
        standin "$name" << STANDIN
echo "unexpected $name: \$*" >> "\$control/log"
exit 97
STANDIN
    done
}

# safe_bin <directory>: every privileged name resolves, on that PATH alone, to a stand-in
# written here — a regular file with the mark, not a link to something real
safe_bin() {
    local bin=$1 name found
    for name in "${PRIVILEGED[@]}"; do
        found=$(PATH=$bin type -P "$name") || found=""
        [ -z "$found" ] && continue
        [ "$found" = "$bin/$name" ] && [ ! -L "$found" ] && [ "$(sed -n 2p "$found")" = "$MARK" ] || return 1
    done
    return 0
}

# ---- Before anything runs --------------------------------------------------------------
# install.sh reaches programs through PATH only, and what reading it can show of a way
# around the stand-ins is refused.
# guard_lines <script>: the lines refused, as "<number>: <why>: <the line>". Whole-line
# comments and the first line's `#!/usr/bin/env bash` are not read. The body of a
# here-document is text, not commands: only a path and (unless its word is quoted) a command
# substitution are looked for there. "The command" is a word at the start of a line or after
# ; & | ( { ! or one of if, then, else, elif, do, while, until, time.
guard_lines() {
    awk '
        function refuse(why) { printf "%d: %s: %s\n", NR, why, $0 }
        BEGIN {
            name = "(^|[^[:alnum:]_])"
            command = "(^|[;&|({!]|(^|[[:space:]])(if|then|else|elif|do|while|until|time)[[:space:]])[[:space:]]*"
        }
        NR == 1 && $0 == "#!/usr/bin/env bash" { next }
        delimiter != "" {
            line = $0
            if (strip) sub(/^\t+/, "", line)
            if (line == delimiter) { delimiter = ""; next }
            if ($0 ~ /(^|[^[:alnum:]_.\/$-])\/(usr\/|s?bin\/|opt\/|run\/)/) refuse("a program named by its path")
            if (!quoted && $0 ~ /\$\(|(^|[^\\])`/) refuse("a command run from a here-document")
            next
        }
        /^[[:space:]]*#/ { next }
        $0 ~ /(^|[^[:alnum:]_.\/$-])\/(usr\/|s?bin\/|opt\/|run\/)/ { refuse("a program named by its path") }
        $0 ~ name "command[[:space:]]+-[[:alnum:]]*p" { refuse("command -p: a PATH of its own") }
        $0 ~ name "PATH\\+?=" { refuse("PATH is assigned") }
        $0 ~ command "(exec|eval|source|\\.)([[:space:]]|$)" { refuse("exec, eval, source or .") }
        $0 ~ command "\"?\\$[{[:alnum:]_]" { refuse("a variable as the command") }
        /<<</ { refuse("a here-string"); next }
        match($0, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/) {
            word = substr($0, RSTART, RLENGTH)
            strip = word ~ /^<<-/
            quoted = word ~ /["\047]/
            gsub(/^<<-?[[:space:]]*["\047]?|["\047]$/, "", word)
            delimiter = word
        }
        END { if (delimiter != "") printf "%d: a here-document without its end (%s): the rest was not read\n", NR, delimiter }
    ' "$1"
}
# guard_install <script>: stops the test (status 2) when guard_lines refuses a line
guard_install() {
    local refused
    refused=$(guard_lines "$1") || setup_error "could not read $1 for ways around the stand-ins. Nothing was run"
    [ -z "$refused" ] && return 0
    printf '%s\n' "$refused" >&2
    setup_error "$(basename "$1") could reach a program around the stand-ins (above). Nothing was run"
}
guard_install "$DISPATCHER"
guard_install "$ARCH_INSTALL"
# The guard itself: install.sh with one such line more stops it, status 2 — each line a
# way that ran the real program when the guard did not know it, or one of the same kind
guard_copies=0
guard_stops_at() {
    guard_copies=$((guard_copies + 1))
    local copy=$work/guard-install-$guard_copies.sh
    { cat "$ARCH_INSTALL"; printf '%s\n' "$@"; } > "$copy"
    (guard_install "$copy") 2> /dev/null
    [ $? = 2 ]
}
check "the guard stops at a quoted path" guard_stops_at '"/usr/bin/true" x'
check "the guard stops at a bare path" guard_stops_at 'x=1; /usr/bin/true x'
check "the guard stops at command -p" guard_stops_at 'command -p true'
check "the guard stops at a variable holding the directory" guard_stops_at 'p=$HOME; "$p/true" x'
check "the guard stops at a variable as the whole command" guard_stops_at 'if $tool x; then :; fi'
check "the guard stops at an assignment to PATH" guard_stops_at 'PATH=$HOME:$PATH'
check "the guard stops at PATH set for one command" guard_stops_at 'x=1 PATH+=:$HOME true'
check "the guard stops at exec" guard_stops_at 'true && exec true'
check "the guard stops at eval" guard_stops_at 'eval "$line"'
check "the guard stops at source" guard_stops_at 'source "$HOME/more.sh"'
check "the guard stops at ." guard_stops_at '. "$HOME/more.sh"'
check "the guard stops at a command substitution in a here-document" guard_stops_at 'cat << END' '$(true)' 'END'
check "the guard stops at a path in a here-document" guard_stops_at "cat << 'END'" '/usr/bin/true' 'END'
check "the guard stops at a here-document without its end" guard_stops_at 'cat << END' 'true'
check "the guard stops at a here-string" guard_stops_at 'cat <<< "$HOME"'
# … and a PATH where sudo is a link to a real program is refused
make_bin "$work/guard/bin"
safe_bin "$work/guard/bin" || setup_error "the private PATH is not safe as made; nothing was run"
rm "$work/guard/bin/sudo"
ln -s "$(type -P cat)" "$work/guard/bin/sudo"
guard_refuses() { ! safe_bin "$work/guard/bin"; }
check "the guard refuses a PATH whose sudo is not a stand-in" guard_refuses
[ "$failed" = 0 ] || { echo "install-test.sh: the guard does not hold; nothing was run" >&2; exit 2; }

# ---- One run ---------------------------------------------------------------------------
# start_case <name>: a fresh HOME, PATH and control directory; CASE, HOME_DIR, CONTROL, BIN
start_case() {
    CASE=$work/$1
    HOME_DIR=$CASE/home
    CONTROL=$CASE/control
    BIN=$CASE/bin
    mkdir -p "$HOME_DIR"
    make_bin "$BIN"
    echo "JetBrainsMono Nerd Font" > "$CONTROL/fonts"
    EXTRA_ENV=()
    mkdir -p "$CASE/tmp"
    os_release arch
    : > "$OS_ROOT/etc/pacman.conf"
    RUN_SCRIPT=$INSTALL
    NO_TERMINAL=""
    AS_ROOT=""
}
# os_release <fixture | none>: the made-up system's os-release, from tests/fixtures/distribution/
os_release() {
    rm -f "$OS_ROOT/etc/os-release"
    [ "$1" = none ] || cp "$FIXTURES/$1.os-release" "$OS_ROOT/etc/os-release"
}
# run_install [piped | piped-in <dir> | file-in <dir> <name> | <arguments>…]: runs install.sh
# once in the case's surroundings — from the file (RUN_SCRIPT, the checkout's unless a case
# names another; given those arguments), or given to bash on its standard input, as
# `curl … | bash` does (piped-in: the plain name `bash`, found on PATH, run in <dir>), or as
# `bash <name>` in <dir> (file-in). OUTPUT (both streams, as the terminal got them), STATUS.
run_install() {
    safe_bin "$BIN" || setup_error "the private PATH of $CASE is not safe; stopped before running install.sh"
    : > "$CONTROL/log"
    {
        echo "#!$BASH_PATH"
        { [ "${1:-}" = piped-in ] || [ "${1:-}" = file-in ]; } && printf 'cd %q || exit 99\n' "$2"
        printf 'exec '
        # root of a user namespace of its own: uid 0 there, no privilege outside it
        [ -n "$AS_ROOT" ] && printf '%q -r ' "$UNSHARE"
        printf 'env -i PATH=%q HOME=%q TMPDIR=%q' "$BIN" "$HOME_DIR" "$CASE/tmp"
        [ ${#EXTRA_ENV[@]} -gt 0 ] && printf ' %q' "${EXTRA_ENV[@]}"
        if [ "${1:-}" = piped ]; then
            printf ' %q --no-new-privs %q < %q\n' "$SETPRIV" "$BIN/bash" "$INSTALL"
        elif [ "${1:-}" = piped-in ]; then
            printf ' %q --no-new-privs bash < %q\n' "$SETPRIV" "$INSTALL"
        elif [ "${1:-}" = file-in ]; then
            printf ' %q --no-new-privs bash %q\n' "$SETPRIV" "$3"
        else
            printf ' %q --no-new-privs %q %q' "$SETPRIV" "$BIN/bash" "$RUN_SCRIPT"
            [ $# -gt 0 ] && printf ' %q' "$@"
            echo
        fi
    } > "$CASE/run.sh"
    chmod +x "$CASE/run.sh"
    if [ -n "${NO_TERMINAL:-}" ]; then
        # a session of its own without a controlling terminal: /dev/tty cannot be opened
        "$TIMEOUT" 60 "$SETSID" -w "$CASE/run.sh" < /dev/null > "$CASE/output" 2>&1
    else
        "$TIMEOUT" 60 "$SCRIPT" -qec "$CASE/run.sh" "$CASE/output" < /dev/null > /dev/null 2>&1
    fi
    STATUS=$?
    OUTPUT=$(tr -d '\r' < "$CASE/output" | grep -v '^Script \(started\|done\) on ')
}
status_is() { [ "$STATUS" = "$1" ]; }
status_nonzero() { [ "$STATUS" != 0 ] && [ "$STATUS" != 124 ]; }
says() { grep -qF -- "$1" <<< "$OUTPUT"; }
silent_on() { ! grep -qF -- "$1" <<< "$OUTPUT"; }
# none of bash's own error messages (they name the script and a line, or a missing command)
no_bash_error() { ! grep -q -- 'line [0-9]*:\|command not found\|No such device or address' <<< "$OUTPUT"; }
logged() { grep -qxF -- "$1" "$CONTROL/log"; }
log_count() { grep -c -- "$1" "$CONTROL/log"; }
none_logged() { ! grep -q -- "$1" "$CONTROL/log"; }
# Everything under the private HOME, one path per line
home_tree() { (cd "$HOME_DIR" && find . | LC_ALL=C sort); }

# The package list, read from the Arch installer a second way than it reads it itself
mapfile -t packages < <(sed -n '/^packages=(/,/^)/p' "$ARCH_INSTALL" | sed '1d;$d;s/#.*//' | tr -s ' \t' '\n' | grep .)
sudo_line="sudo stdin-terminal=yes no-new-privs=1: pacman -S --needed ${packages[*]}"
repository="https://github.com/Siarko/h2s-shell"

# ---- A first install, as `curl … | bash` -------------------------------------------------
start_case first
run_install piped
target=$HOME_DIR/.config/quickshell/default
check "first run: exit 0" status_is 0
check "first run: the package list is read (quickshell, hyprland and a font among at least 10)" \
    test "${#packages[@]}" -ge 10 -a "${packages[0]}" = quickshell -a "${packages[1]}" = hyprland -a "${packages[-1]}" = ttf-jetbrains-mono-nerd
check "first run: pacman -S --needed with exactly that list, through sudo, on the terminal (not the script on stdin), with no new privileges" \
    logged "$sudo_line"
check "first run: sudo is asked once" test "$(log_count '^sudo ')" = 1
check "first run: pacman is never run directly" none_logged '^pacman:'
check "first run: nothing else that changes a system is run" none_logged '^unexpected '
fetched_from_repository() {
    grep -qx -- "curl: -fsSL --proto =https -o $CASE/tmp/[^ ]* https://raw.githubusercontent.com/Siarko/h2s-shell/master/distributions/arch/install.sh" "$CONTROL/log"
}
check "first run, given on standard input: the Arch installer is fetched from the repository, over https only, into the temp folder" \
    fetched_from_repository
fetched_once() { [ "$(log_count '^curl: ')" = 1 ]; }
check "… once" fetched_once
tmp_empty() { [ -z "$(ls -A "$CASE/tmp")" ]; }
check "… and removed when done (nothing left in the temp folder)" tmp_empty
check "first run: the shell is cloned from its repository into ~/.config/quickshell/default" \
    logged "git: clone $repository $target"
check "first run: the clone is there" test -f "$target/shell.qml"
builtin=$HOME_DIR/.local/share/h2s-shell/builtin
check "first run: the checkout's built-in modules are copied to ~/.local/share/h2s-shell/builtin" \
    test "$(cat "$builtin/builtin.json" "$builtin/sample/module.json" 2> /dev/null)" = "$(printf '%s\n' '{ "off": [] }' '{ "id": "sample" }')"
check "first run: nothing else is put in the home directory" \
    test "$(home_tree)" = "$(printf '%s\n' . ./.config ./.config/quickshell ./.config/quickshell/default ./.config/quickshell/default/.standin-origin ./.config/quickshell/default/shell.qml \
        ./.config/quickshell/default/scripts ./.config/quickshell/default/scripts/build-helper.sh \
        ./.config/quickshell/default/builtin-modules ./.config/quickshell/default/builtin-modules/builtin.json ./.config/quickshell/default/builtin-modules/sample ./.config/quickshell/default/builtin-modules/sample/module.json \
        ./.local ./.local/share ./.local/share/h2s-shell ./.local/share/h2s-shell/builtin ./.local/share/h2s-shell/builtin/builtin.json ./.local/share/h2s-shell/builtin/sample ./.local/share/h2s-shell/builtin/sample/module.json | LC_ALL=C sort)"
check "first run: the helper is built once, by the checkout's scripts/build-helper.sh, not through sudo (no new privileges)" \
    test "$(log_count '^build-helper ')" = 1 -a "$(log_count '^build-helper no-new-privs=1: $')" = 1
check "first run: … after the clone" test "$(grep -n '^build-helper ' "$CONTROL/log" | cut -d: -f1)" -gt "$(grep -n '^git: clone' "$CONTROL/log" | cut -d: -f1)"
check "first run: the helper's packages are asked for (cmake, a compiler, Qt's headers)" \
    test -n "$(printf '%s\n' "${packages[@]}" | grep -x cmake)" -a -n "$(printf '%s\n' "${packages[@]}" | grep -x base-devel)" -a -n "$(printf '%s\n' "${packages[@]}" | grep -x qt6-base)"
check "first run: it ends by saying what is left to do" says "==> Done. Left for you:"
check "first run: the autostart line names the installed launch.sh" says "hl.exec_cmd(\"$target/scripts/launch.sh\")"
check "first run: with a Nerd Font installed, no warning about one" silent_on "no Nerd Font found"

# ---- A second run: nothing changes -----------------------------------------------------
tree_before=$(home_tree)
run_install
check "second run: exit 0" status_is 0
check "second run: says it is installed, and how to update" says "Already installed; update it with: git -C \"$target\" pull && \"$target/install.sh\" --update"
check "second run: no second clone" none_logged '^git: clone'
check "second run: the packages are asked for the same way (pacman's --needed skips what is there)" logged "$sudo_line"
check "second run: the home directory is as it was" test "$(home_tree)" = "$tree_before"
check "second run: nothing else that changes a system is run" none_logged '^unexpected '
check "second run, from the checkout: the installer beside it, nothing fetched" none_logged '^curl: '

# ---- --update: the built-in modules again, nothing else -----------------------------------
# What the checkout no longer holds goes; what it gained comes; no packages, no sudo
rm -r "$target/builtin-modules/sample"
mkdir -p "$target/builtin-modules/other"
echo '{ "id": "other" }' > "$target/builtin-modules/other/module.json"
: > "$builtin/left-by-hand"
run_install --update
check "--update: exit 0" status_is 0
check "--update: the built-in modules are the checkout's now" \
    test "$(cd "$builtin" && find . | LC_ALL=C sort | tr '\n' ' ')" = ". ./builtin.json ./other ./other/module.json "
check "--update: no sudo, no pacman" none_logged '^sudo \|^pacman:'
check "--update: no clone, no pull" none_logged '^git: clone\|pull'
check "--update: the helper is built again" test "$(log_count '^build-helper ')" = 1
nothing_beside() { ! compgen -G "$builtin.*" > /dev/null; }
check "--update: the built-in directory is a directory" test -d "$builtin" -a ! -L "$builtin"
check "--update: no copy or old one left beside it" nothing_beside
: > "$builtin.new.kept-by-someone"
run_install --update
check "--update: a file beside it that this run did not make is not deleted" test -e "$builtin.new.kept-by-someone"
rm "$builtin.new.kept-by-someone"
check "--update: says to restart the shell" says "Restart the shell to load the built-in modules and the helper again"

for arguments in "--upgrade" "--update --update"; do
    start_case "wrong-argument-${arguments// /}"
    read -r -a words <<< "$arguments"
    run_install "${words[@]}"
    check "install.sh $arguments: exit 2" status_is 2
    check "install.sh $arguments: says how it is used" says "usage: install.sh [--update]"
    check "install.sh $arguments: nothing is run at all" test ! -s "$CONTROL/log"
    check "install.sh $arguments: nothing is put in the home directory" test "$(home_tree)" = .
done
start_case update-not-installed
run_install --update
check "--update without an install: exit 1" status_is 1
check "--update without an install: says to install first" says "run this without --update first"
check "--update without an install: nothing is put in the home directory" test "$(home_tree)" = .

# ---- The built-in directory is a link: left alone ------------------------------------------
start_case builtin-link
mkdir -p "$HOME_DIR/elsewhere" "$HOME_DIR/.local/share/h2s-shell"
echo kept > "$HOME_DIR/elsewhere/file"
ln -s "$HOME_DIR/elsewhere" "$HOME_DIR/.local/share/h2s-shell/builtin"
run_install
check "a link where the built-in directory goes: exit 1" status_is 1
check "a link where the built-in directory goes: says it leaves it alone" says "is not a directory; leaving it alone"
check "a link where the built-in directory goes: the link and what it leads to are as they were" \
    test -L "$HOME_DIR/.local/share/h2s-shell/builtin" -a "$(cat "$HOME_DIR/elsewhere/file")" = kept -a "$(ls "$HOME_DIR/elsewhere")" = file
check "a link where the built-in directory goes: it does not say it is done" silent_on "==> Done"

# ---- A checkout without built-in modules (an older one): what is there stays ---------------
start_case no-builtin
: > "$CONTROL/git-clone-no-builtin"
mkdir -p "$HOME_DIR/.local/share/h2s-shell/builtin"
echo '{ "off": [] }' > "$HOME_DIR/.local/share/h2s-shell/builtin/builtin.json"
run_install
check "a checkout without built-in modules: exit 0" status_is 0
check "a checkout without built-in modules: says so" says "This checkout has no built-in modules"
check "a checkout without built-in modules: the built-in directory is as it was" \
    test "$(cat "$HOME_DIR/.local/share/h2s-shell/builtin/builtin.json")" = '{ "off": [] }'

# ---- XDG_CONFIG_HOME ---------------------------------------------------------------------
start_case xdg
EXTRA_ENV=(XDG_CONFIG_HOME="$CASE/config" XDG_DATA_HOME="$CASE/data")
run_install
check "XDG_CONFIG_HOME: exit 0" status_is 0
check "XDG_CONFIG_HOME: the shell goes under it" logged "git: clone $repository $CASE/config/quickshell/default"
check "XDG_DATA_HOME: the built-in modules go under it" test -f "$CASE/data/h2s-shell/builtin/sample/module.json"
check "XDG_CONFIG_HOME, XDG_DATA_HOME: nothing is put in the home directory" test "$(home_tree)" = .

# ---- Another Quickshell config is there --------------------------------------------------
start_case other-config
mkdir -p "$HOME_DIR/.config/quickshell/default"
echo "somebody's own" > "$HOME_DIR/.config/quickshell/default/shell.qml"
echo "https://example.org/another/shell" > "$HOME_DIR/.config/quickshell/default/.standin-origin"
run_install
check "another config: exit 1" status_is 1
check "another config: says it leaves it alone" says "already holds another Quickshell config; leaving it alone."
check "another config: no clone" none_logged '^git: clone'
check "another config: the file is as it was" test "$(cat "$HOME_DIR/.config/quickshell/default/shell.qml")" = "somebody's own"
check "another config: it does not say it is done" silent_on "==> Done"

# A config whose origin cannot be read is not taken for ours
start_case unreadable-origin
mkdir -p "$HOME_DIR/.config/quickshell/default"
: > "$HOME_DIR/.config/quickshell/default/shell.qml"
echo "$repository" > "$HOME_DIR/.config/quickshell/default/.standin-origin"
: > "$CONTROL/git-remote-fails"
run_install
check "git cannot say where the config comes from: exit 1, not 'already installed'" status_is 1
check "git cannot say where the config comes from: left alone" says "leaving it alone"
check "git cannot say where the config comes from: no clone" none_logged '^git: clone'

# Only this repository is ours: a fork, or another repository whose address merely contains
# its name, is somebody else's config
for origin in "https://github.com/someone/h2s-shell" "https://github.com/Siarko/h2s-shell-tailscale" \
              "https://example.org/mirror/Siarko/h2s-shell" "https://github.com.example.org/Siarko/h2s-shell" \
              "/home/someone/h2s-shell"; do
    start_case "fork-$(echo "$origin" | tr -c 'a-zA-Z0-9\n' '-')"
    mkdir -p "$HOME_DIR/.config/quickshell/default"
    : > "$HOME_DIR/.config/quickshell/default/shell.qml"
    echo "$origin" > "$HOME_DIR/.config/quickshell/default/.standin-origin"
    run_install
    check "a checkout of $origin: exit 1, not 'already installed'" status_is 1
    check "… says it leaves it alone, naming where it comes from" says "It comes from $origin, not from $repository."
    # another host with this repository's path may be a host alias: that gets the hint
    [ "${origin%/Siarko/h2s-shell}" != "$origin" ] || check "… no hint about a host alias" silent_on "remote set-url"
    check "… nothing installed first" none_logged "^sudo "
    check "… no clone" none_logged '^git: clone'
    run_install --update
    check "--update on a checkout of $origin: exit 1" status_is 1
    check "… says it leaves it alone" says "already holds another Quickshell config; leaving it alone."
    check "… no build, no copy" test "$(log_count '^build-helper ')" = 0 -a ! -e "$HOME_DIR/.local"
done
# The same repository in its other spellings is ours
for origin in "$repository.git" "$repository/" "git@github.com:Siarko/h2s-shell.git" \
              "ssh://git@github.com/Siarko/h2s-shell" "https://github.com/siarko/H2S-shell" \
              "http://github.com/Siarko/h2s-shell" "git://github.com/Siarko/h2s-shell.git" \
              "https://www.github.com/Siarko/h2s-shell" "https://someone:a-token@github.com/Siarko/h2s-shell.git" \
              "ssh://git@github.com:22/Siarko/h2s-shell.git" "https://github.com:443/Siarko/h2s-shell"; do
    start_case "ours-$(echo "$origin" | tr -c 'a-zA-Z0-9\n' '-')"
    mkdir -p "$HOME_DIR/.config/quickshell/default"
    : > "$HOME_DIR/.config/quickshell/default/shell.qml"
    echo "$origin" > "$HOME_DIR/.config/quickshell/default/.standin-origin"
    run_install
    check "a checkout of $origin: already installed" says "Already installed; update it with:"
    check "… exit 0" status_is 0
done

# Somebody else's address with a user and password: the password is never shown
start_case fork-token
mkdir -p "$HOME_DIR/.config/quickshell/default"
: > "$HOME_DIR/.config/quickshell/default/shell.qml"
echo "https://someone:s3cr3t-token@github.com:443/someone/h2s-shell.git" > "$HOME_DIR/.config/quickshell/default/.standin-origin"
run_install
check "a fork's address with a user and token: left alone, shown without them" says "It comes from https://github.com:443/someone/h2s-shell.git, not from $repository."
check "… the token is never shown" silent_on "s3cr3t-token"
check "… nor the user" silent_on "someone:"
check "… exit 1" status_is 1
# A host alias of the user's SSH config is not followed, but said how to go on
start_case host-alias
mkdir -p "$HOME_DIR/.config/quickshell/default"
: > "$HOME_DIR/.config/quickshell/default/shell.qml"
echo "github-personal:Siarko/h2s-shell.git" > "$HOME_DIR/.config/quickshell/default/.standin-origin"
run_install
check "an SSH host alias for this repository: exit 1, not 'already installed'" status_is 1
check "… says where it comes from" says "It comes from github-personal:Siarko/h2s-shell.git, not from $repository."
check "… and how to run anyway" says "git -C \"$HOME_DIR/.config/quickshell/default\" remote set-url origin git@github.com:Siarko/h2s-shell.git"

# ---- The target is there, without shell.qml ------------------------------------------------
start_case target-no-shell
mkdir -p "$HOME_DIR/.config/quickshell/default"
echo "notes" > "$HOME_DIR/.config/quickshell/default/notes.txt"
run_install
check "a target folder with files but no shell.qml: exit 1" status_is 1
check "… install.sh's own message" says "holds no Quickshell config (no shell.qml), but it is not empty; leaving it alone."
check "… no clone tried" none_logged '^git: clone'
check "… checked before the packages: nothing installed" none_logged "^sudo "
check "… not git's error" silent_on "fatal:"
check "… the folder is as it was" test "$(cat "$HOME_DIR/.config/quickshell/default/notes.txt")" = notes
check "… it does not say it is done" silent_on "==> Done"
start_case target-file
mkdir -p "$HOME_DIR/.config/quickshell"
echo "a file" > "$HOME_DIR/.config/quickshell/default"
run_install
check "a file where the target goes: exit 1, install.sh's own message" says "is not a folder; leaving it alone."
check "… no clone tried" none_logged '^git: clone'
check "… exit 1" status_is 1
start_case target-dangling
mkdir -p "$HOME_DIR/.config/quickshell"
ln -s "$HOME_DIR/nowhere" "$HOME_DIR/.config/quickshell/default"
run_install
check "a link to nothing where the target goes: install.sh's own message" says "is not a folder; leaving it alone."
check "… exit 1" status_is 1
check "… no clone tried" none_logged '^git: clone'
start_case target-hidden
mkdir -p "$HOME_DIR/.config/quickshell/default"
: > "$HOME_DIR/.config/quickshell/default/.hidden"
run_install
check "a target folder with only a hidden file: not empty, left alone" says "holds no Quickshell config (no shell.qml), but it is not empty; leaving it alone."
check "… exit 1, no clone" test "$STATUS" = 1 -a "$(log_count '^git: clone')" = 0
start_case target-unreadable
mkdir -p "$HOME_DIR/.config/quickshell/default"
chmod 000 "$HOME_DIR/.config/quickshell/default"
run_install
chmod 755 "$HOME_DIR/.config/quickshell/default"
check "a target folder that cannot be read: install.sh's own message" says "cannot be read; leaving it alone."
check "… exit 1, no clone, nothing installed" test "$STATUS" = 1 -a "$(log_count '^git: clone\|^sudo ')" = 0
start_case shell-qml-dangling
mkdir -p "$HOME_DIR/.config/quickshell/default"
ln -s "$HOME_DIR/nowhere" "$HOME_DIR/.config/quickshell/default/shell.qml"
run_install
check "shell.qml a link that leads nowhere: install.sh's own message" says "shell.qml is a link that leads nowhere; leaving $HOME_DIR/.config/quickshell/default alone."
check "… exit 1, no clone" test "$STATUS" = 1 -a "$(log_count '^git: clone')" = 0
start_case target-empty
mkdir -p "$HOME_DIR/.config/quickshell/default"
run_install
check "an empty target folder: the shell is cloned into it" logged "git: clone $repository $HOME_DIR/.config/quickshell/default"
check "… exit 0" status_is 0

# ---- Which system ------------------------------------------------------------------------
for system in nixos fedora linuxmint none; do
    for how in file piped; do
        start_case "system-$system-$how"
        os_release "$system"
        # Without pacman: a system that has it gets the Arch installer (below)
        [ "$system" = nixos ] || rm "$BIN/pacman"
        if [ "$how" = piped ]; then run_install piped; else run_install; fi
        check "$system ($how): exit 1" status_is 1
        check "$system ($how): nothing is run at all, nothing fetched" test ! -s "$CONTROL/log"
        check "$system ($how): nothing is put in the home directory" test "$(home_tree)" = .
        case $system in
            nixos) check "NixOS ($how): says this installer is not for NixOS, and the module instead" \
                says "This installer is not for NixOS: there the shell comes with its flake's NixOS module (programs.h2s-shell.enable)" ;;
            fedora) check "Fedora ($how): says only Arch and systems based on it are supported, naming this one" \
                says "This installer supports only Arch Linux and systems based on it, not Fedora Linux 43 (Workstation Edition)." ;;
            linuxmint) check "Linux Mint ($how): not supported, the README named" says "The README says what the shell needs" ;;
            none) check "no os-release ($how): not supported, without a name" says "systems based on it, not this system." ;;
        esac
    done
done
start_case system-endeavouros
os_release endeavouros
run_install piped
check "EndeavourOS (ID_LIKE=arch): the Arch installer runs" status_is 0
check "… it installs" logged "$sudo_line"
start_case system-endeavouros-update
os_release endeavouros
run_install --update
check "EndeavourOS, an argument: handed to the Arch installer (--update without an install)" says "run this without --update first"

start_case system-fedora-pacman
os_release fedora
run_install piped
check "Fedora with pacman: warned, not refused" says "Warning: Fedora Linux 43 (Workstation Edition) is not detected as Arch-based (os-release), but it has pacman: continuing with the Arch installer."
check "… the Arch installer runs" logged "$sudo_line"
check "… and ends" status_is 0
start_case update-any-system
os_release fedora
rm "$BIN/pacman"
run_install --update
check "--update from a checkout on a system the installer does not support: handed to the Arch installer" says "run this without --update first"
check "… not refused" silent_on "supports only Arch Linux"

# Piped, by the plain name bash, in a folder that holds a distributions/arch/install.sh: that
# file is someone else's, and only the fetched installer runs
start_case decoy
mkdir -p "$CASE/cwd/distributions/arch"
printf '%s\n' '#!/usr/bin/env bash' 'echo "decoy ran" >&2' 'exit 42' > "$CASE/cwd/distributions/arch/install.sh"
run_install piped-in "$CASE/cwd"
check "piped as plain bash, a distributions/arch/install.sh in the folder: it is not run" silent_on "decoy ran"
check "… the installer is fetched" fetched_from_repository
check "… and runs" status_is 0

# Where install.sh is run from
start_case no-slash
run_install file-in "$CHECKOUT" install.sh
check "bash install.sh in the checkout (no slash): the installer beside it runs" status_is 0
check "… nothing fetched" none_logged '^curl: '
check "… it installs" logged "$sudo_line"
start_case link
mkdir -p "$CASE/elsewhere"
ln -s "$CHECKOUT/install.sh" "$CASE/elsewhere/install.sh"
RUN_SCRIPT=$CASE/elsewhere/install.sh
run_install
check "install.sh run through a link elsewhere: the checkout's installer runs" status_is 0
check "… nothing fetched" none_logged '^curl: '
start_case lone
mkdir -p "$CASE/lone"
cp "$INSTALL" "$CASE/lone/install.sh"
RUN_SCRIPT=$CASE/lone/install.sh
run_install
check "an install.sh on its own (downloaded): the installer is fetched" fetched_from_repository
check "… and runs" status_is 0
start_case update-nixos
os_release nixos
run_install --update
check "--update from a checkout on NixOS: exit 1" status_is 1
check "… the NixOS refusal" says "This installer is not for NixOS"
check "… nothing is run at all" test ! -s "$CONTROL/log"

# pacman without its settings: another program of that name (Debian's game)
start_case pacman-game
os_release fedora
rm "$OS_ROOT/etc/pacman.conf"
run_install piped
check "a program pacman without /etc/pacman.conf, not Arch-based: refused" says "supports only Arch Linux and systems based on it"
check "… exit 1, nothing run" test "$STATUS" = 1 -a ! -s "$CONTROL/log"
start_case pacman-game-arch
rm "$OS_ROOT/etc/pacman.conf"
run_install
check "os-release says Arch but no /etc/pacman.conf: the Arch installer refuses" says "This script is for Arch Linux (pacman)"
check "… exit 1, nothing run" test "$STATUS" = 1 -a ! -s "$CONTROL/log"

start_case other-dispatch
: > "$CONTROL/curl-other-dispatch"
run_install piped
check "the fetched installer expects another hand-over: exit 1" status_is 1
check "… says the two do not match" says "This Arch installer does not match the install.sh that ran it (hand-over 1, it knows 2)."
grep -qx 'dispatch_version=1' "$DISPATCHER" && grep -qx 'dispatch_known=1' "$ARCH_INSTALL"
check "the top-level script and the Arch installer of one checkout agree on the hand-over's version" test $? = 0
check "… nothing but the fetch is run" test "$(grep -vc '^curl: ' "$CONTROL/log")" = 0
check "… nothing is put in the home directory" test "$(home_tree)" = .

start_case no-curl
rm "$BIN/curl"
run_install piped
check "given on standard input without curl: exit 1" status_is 1
check "… says the fetch needs curl" says "Fetching the Arch installer needs curl"
check "… nothing is run at all" test ! -s "$CONTROL/log"
start_case curl-fails
: > "$CONTROL/curl-fails"
run_install piped
check "the fetch fails: a non-zero exit" status_nonzero
check "… nothing but the fetch is run" test "$(grep -vc '^curl: ' "$CONTROL/log")" = 0
check "… nothing is put in the home directory" test "$(home_tree)" = .
check "… nothing left in the temp folder" tmp_empty

# ---- A step fails ------------------------------------------------------------------------
start_case no-pacman
rm "$BIN/pacman"
run_install
check "no pacman: exit 1" status_is 1
check "no pacman: says the script is for Arch" says "This script is for Arch Linux (pacman)"
check "no pacman: nothing is run at all" test ! -s "$CONTROL/log"
check "no pacman: nothing is put in the home directory" test "$(home_tree)" = .

start_case pacman-fails
echo 1 > "$CONTROL/sudo-status"
run_install piped
check "the packages are not installed (pacman or sudo fails, or the answer is no): a non-zero exit" status_nonzero
check "the packages are not installed: no clone" none_logged '^git:'
check "the packages are not installed: nothing is put in the home directory" test "$(home_tree)" = .
check "the packages are not installed: it does not say it is done" silent_on "==> Done"
check "the packages are not installed: its own message" says "The packages were not installed (above); nothing else was done."
check "… exit 1" status_is 1

start_case as-root
AS_ROOT=1
rm "$BIN/sudo"
: > "$CONTROL/pacman-ok"
run_install
check "as root without sudo: pacman run directly" logged "pacman: -S --needed ${packages[*]}"
check "… and the install goes on" status_is 0
check "… not bash's error" no_bash_error
start_case as-root-pacman-fails
AS_ROOT=1
run_install
check "as root, pacman fails: its own message" says "The packages were not installed (above); nothing else was done."
check "… exit 1, no clone" test "$STATUS" = 1 -a "$(log_count '^git: clone')" = 0
check "… sudo not used" none_logged "^sudo "

start_case clone-fails
: > "$CONTROL/git-clone-fails"
run_install
check "the clone fails: a non-zero exit" status_nonzero
check "the clone fails: it does not say it is done" silent_on "==> Done"
check "the clone fails: no half-made config is left" test ! -e "$HOME_DIR/.config/quickshell/default"
check "the clone fails: no built-in modules are copied" test ! -e "$HOME_DIR/.local"

# ---- The helper's build -------------------------------------------------------------------
start_case build-fails
: > "$CONTROL/build-fails"
run_install
check "the helper does not build: exit 0 (the shell runs without it)" status_is 0
check "the helper does not build: a warning, and how to build it again" says "Warning: the helper did not build"
check "… naming the script" says "scripts/build-helper.sh"
check "the helper does not build: it still ends by saying what is left to do" says "==> Done. Left for you:"

start_case no-helper
: > "$CONTROL/git-clone-no-helper"
run_install
check "a checkout without the helper (an older one): exit 0" status_is 0
check "a checkout without the helper: says so" says "This checkout has no helper to build."
check "a checkout without the helper: nothing is built" none_logged '^build-helper '

# ---- The font warning --------------------------------------------------------------------
start_case no-font
echo "DejaVu Sans" > "$CONTROL/fonts"
run_install
check "no Nerd Font: a warning" says "Warning: no Nerd Font found"
check "no Nerd Font: the install goes on" status_is 0
check "no Nerd Font: the clone is made" test -f "$HOME_DIR/.config/quickshell/default/shell.qml"

start_case no-fc-list
rm "$BIN/fc-list"
run_install
check "no fc-list: exit 0" status_is 0
check "no fc-list: no warning (it cannot tell)" silent_on "no Nerd Font found"

# Under pipefail a pipe into grep -q fails when grep has its match and leaves while fc-list
# is still writing: a long list with the Nerd Font early must give no warning
start_case many-fonts
# (megabytes after it: far more than a pipe holds, so fc-list is surely still writing)
{ echo "JetBrainsMono Nerd Font"; seq -f "Filler Sans %g" 1 500000; } > "$CONTROL/fonts"
run_install
check "a long font list with a Nerd Font early: no warning" silent_on "no Nerd Font found"
check "… exit 0" status_is 0
start_case fc-list-fails
: > "$CONTROL/fc-list-fails"
run_install
check "fc-list fails: no warning (it cannot tell)" silent_on "no Nerd Font found"
check "… exit 0" status_is 0

# ---- No terminal, no sudo -----------------------------------------------------------------
for how in file piped; do
    start_case "no-terminal-$how"
    NO_TERMINAL=1
    if [ "$how" = piped ]; then run_install piped; else run_install; fi
    check "no terminal ($how): exit 1" status_is 1
    check "… install.sh's own message, naming the terminal" says "Installing the packages needs a terminal, for pacman's questions and sudo's password, and there is none."
    check "… not bash's" no_bash_error
    check "… nothing run, nothing put in the home directory" test "$(grep -vc '^curl: ' "$CONTROL/log")" = 0 -a "$(home_tree)" = .
done
start_case no-sudo
rm "$BIN/sudo"
run_install
check "no sudo: exit 1" status_is 1
check "… install.sh's own message, naming sudo and its use" says "Installing the packages needs sudo (the package sudo), to run pacman as root, and there is none."
check "… not bash's" no_bash_error
check "… nothing run, nothing put in the home directory" test ! -s "$CONTROL/log" -a "$(home_tree)" = .

echo
if [ "$failed" = 0 ]; then echo "install.sh under stand-ins: passed"; else echo "install.sh under stand-ins: FAILED"; fi
exit "$failed"
