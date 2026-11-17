#!/usr/bin/env bash
# Runs install.sh without letting it change the machine, and checks what it would have
# done: which packages it asks for and how, where the shell goes, that nothing runs as
# root but what it hands to sudo, that a second run changes nothing, and what it does when
# a step fails. The same on NixOS and on Arch: install.sh is for Arch, the test is not.
#
# How install.sh is kept from the machine:
#   - an empty environment (env -i) with a private HOME and a PATH of one directory, made
#     here: recording stand-ins for sudo, pacman, git, fc-list and for every program that
#     could change the system (below), and links to the five plain tools install.sh uses
#     (bash, mkdir, dirname, grep, cat). No stand-in runs anything real;
#   - no new privileges (setpriv): even a sudo reached by another way could not become root;
#   - before anything runs: every privileged name must resolve to a stand-in written here,
#     and install.sh is read for the ways around a PATH of stand-ins that reading can find
#     (guard_lines below: a program named by its path, `command -p`, an assignment to
#     PATH, `exec`, `eval`, `source` and `.`, a variable as the command, a command
#     substitution in a here-document) — else the test stops, status 2. That reading is no
#     proof: it refuses these forms, not every way a script could be written to reach a
#     real program. What holds whatever install.sh says is the list above: the empty
#     environment, the one-directory PATH, the private HOME, no new privileges.
#
# install.sh gives pacman the terminal (/dev/tty), so each run gets a terminal of its own
# (script, util-linux); the test needs none.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when the test could not be
# set up (a missing tool is named with its use) or would not be safe to start.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
INSTALL=$REPO/install.sh
setup_error() { echo "install-test.sh: $*" >&2; exit 2; }

missing=()
need() { type -P "$1" > /dev/null || missing+=("$1 not found on PATH ($2)"); }
need script "gives each run of install.sh a terminal of its own, as it hands pacman one"
need setpriv "runs install.sh with no new privileges, so that nothing in it could become root"
need timeout "ends a run that hangs"
need awk "reads install.sh for ways around the stand-ins before it is run"
for tool in bash mkdir dirname grep cat; do need "$tool" "install.sh uses it; linked into the private PATH"; done
if [ ${#missing[@]} -gt 0 ]; then
    printf 'install-test.sh: %s\n' "${missing[@]}" >&2
    exit 2
fi
SCRIPT=$(type -P script)
SETPRIV=$(type -P setpriv)
TIMEOUT=$(type -P timeout)
BASH_PATH=$(type -P bash)

work=$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX") || setup_error "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

# What must never be the real thing on the private PATH. The first four are install.sh's
# own; the rest are not expected at all and only say that they were called (status 97).
PRIVILEGED=(sudo pacman pkexec su doas systemctl yay paru)
UNEXPECTED=(pkexec su doas systemctl yay paru ln cp mv rm chmod chown install tee curl wget)
MARK="# a stand-in written by tests/install-test.sh"

# make_bin <directory>: the private PATH of one run, and its control directory beside it
# (<directory>/../control): `log` (one line per stand-in call), and files a case puts
# there: sudo-status, git-clone-fails, git-remote-fails, fonts (what fc-list prints).
make_bin() {
    local bin=$1 control name
    control=$(dirname "$bin")/control
    mkdir -p "$bin" "$control"
    for name in bash mkdir dirname grep cat; do ln -s "$(type -P "$name")" "$bin/$name"; done
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
        mkdir "$3" || exit 128
        echo "$2" > "$3/.standin-origin"
        : > "$3/shell.qml"
        ;;
    *) exit 97 ;;
esac
STANDIN
    standin fc-list << 'STANDIN'
echo "fc-list: $*" >> "$control/log"
[ -f "$control/fonts" ] && cat "$control/fonts"
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
guard_install "$INSTALL"
# The guard itself: install.sh with one such line more stops it, status 2 — each line a
# way that ran the real program when the guard did not know it, or one of the same kind
guard_copies=0
guard_stops_at() {
    guard_copies=$((guard_copies + 1))
    local copy=$work/guard-install-$guard_copies.sh
    { cat "$INSTALL"; printf '%s\n' "$@"; } > "$copy"
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
}
# run_install [piped]: runs install.sh once in the case's surroundings — from the file, or
# given to bash on its standard input, as `curl … | bash` does. OUTPUT (both streams, as
# the terminal got them), STATUS.
run_install() {
    safe_bin "$BIN" || setup_error "the private PATH of $CASE is not safe; stopped before running install.sh"
    : > "$CONTROL/log"
    {
        echo "#!$BASH_PATH"
        printf 'exec env -i PATH=%q HOME=%q' "$BIN" "$HOME_DIR"
        [ ${#EXTRA_ENV[@]} -gt 0 ] && printf ' %q' "${EXTRA_ENV[@]}"
        if [ "${1:-}" = piped ]; then
            printf ' %q --no-new-privs %q < %q\n' "$SETPRIV" "$BIN/bash" "$INSTALL"
        else
            printf ' %q --no-new-privs %q %q\n' "$SETPRIV" "$BIN/bash" "$INSTALL"
        fi
    } > "$CASE/run.sh"
    chmod +x "$CASE/run.sh"
    "$TIMEOUT" 60 "$SCRIPT" -qec "$CASE/run.sh" "$CASE/output" < /dev/null > /dev/null 2>&1
    STATUS=$?
    OUTPUT=$(tr -d '\r' < "$CASE/output" | grep -v '^Script \(started\|done\) on ')
}
status_is() { [ "$STATUS" = "$1" ]; }
status_nonzero() { [ "$STATUS" != 0 ] && [ "$STATUS" != 124 ]; }
says() { grep -qF -- "$1" <<< "$OUTPUT"; }
silent_on() { ! grep -qF -- "$1" <<< "$OUTPUT"; }
logged() { grep -qxF -- "$1" "$CONTROL/log"; }
log_count() { grep -c -- "$1" "$CONTROL/log"; }
none_logged() { ! grep -q -- "$1" "$CONTROL/log"; }
# Everything under the private HOME, one path per line
home_tree() { (cd "$HOME_DIR" && find . | LC_ALL=C sort); }

# The package list, read from install.sh a second way than it reads it itself
mapfile -t packages < <(sed -n '/^packages=(/,/^)/p' "$INSTALL" | sed '1d;$d;s/#.*//' | tr -s ' \t' '\n' | grep .)
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
check "first run: the shell is cloned from its repository into ~/.config/quickshell/default" \
    logged "git: clone $repository $target"
check "first run: the clone is there" test -f "$target/shell.qml"
check "first run: nothing else is put in the home directory" \
    test "$(home_tree)" = "$(printf '%s\n' . ./.config ./.config/quickshell ./.config/quickshell/default ./.config/quickshell/default/.standin-origin ./.config/quickshell/default/shell.qml | LC_ALL=C sort)"
check "first run: it ends by saying what is left to do" says "==> Done. Left for you:"
check "first run: the autostart line names the installed launch.sh" says "hl.exec_cmd(\"$target/scripts/launch.sh\")"
check "first run: with a Nerd Font installed, no warning about one" silent_on "no Nerd Font found"

# ---- A second run: nothing changes -----------------------------------------------------
tree_before=$(home_tree)
run_install
check "second run: exit 0" status_is 0
check "second run: says it is installed" says "Already installed"
check "second run: no second clone" none_logged '^git: clone'
check "second run: the packages are asked for the same way (pacman's --needed skips what is there)" logged "$sudo_line"
check "second run: the home directory is as it was" test "$(home_tree)" = "$tree_before"
check "second run: nothing else that changes a system is run" none_logged '^unexpected '

# ---- XDG_CONFIG_HOME ---------------------------------------------------------------------
start_case xdg
EXTRA_ENV=(XDG_CONFIG_HOME="$CASE/config")
run_install
check "XDG_CONFIG_HOME: exit 0" status_is 0
check "XDG_CONFIG_HOME: the shell goes under it" logged "git: clone $repository $CASE/config/quickshell/default"
check "XDG_CONFIG_HOME: nothing is put in the home directory" test "$(home_tree)" = .

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

start_case clone-fails
: > "$CONTROL/git-clone-fails"
run_install
check "the clone fails: a non-zero exit" status_nonzero
check "the clone fails: it does not say it is done" silent_on "==> Done"
check "the clone fails: no half-made config is left" test ! -e "$HOME_DIR/.config/quickshell/default"

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

echo
if [ "$failed" = 0 ]; then echo "install.sh under stand-ins: passed"; else echo "install.sh under stand-ins: FAILED"; fi
exit "$failed"
