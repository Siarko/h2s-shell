# shellcheck shell=bash
# Every package install.sh installs or names, and the font the HUD's hint names, exists in
# the repositories this machine's pacman knows (`pacman -Si`: reads the sync database,
# changes nothing). A name that pacman dropped or renamed fails here, not on a new machine.
# Without a sync database (a machine never synced, one whose database was removed) no name
# can be looked up: that is "cannot run", not every name failing.
need pacman "asks the sync database for each package name"
# (Read into a variable: under pipefail a `grep -q` that leaves early fails the pipeline.)
listed=$(pacman -Sl 2> /dev/null | head -n 1)
[ -n "$listed" ] \
    || cannot_run "pacman's sync database is missing or empty (pacman -Sl lists no package): no name can be looked up"

# The names in install.sh's `packages=( … )`, comments dropped
mapfile -t installed < <(sed -n '/^packages=(/,/^)/p' "$REPO/install.sh" | sed '1d;$d;s/#.*//' | tr -s ' \t' '\n' | grep .)
# The names after "pacman -S" in what install.sh and the HUD print
mapfile -t named < <(grep -ho 'pacman -S [a-z0-9][a-z0-9-]*' "$REPO/install.sh" "$REPO/Hud.qml" | sed 's/^pacman -S //' | grep . | sort -u)

check "install.sh's package list is read (some names)" test "${#installed[@]}" -ge 10
check "the names install.sh and the HUD print are read (some names)" test "${#named[@]}" -ge 3
# "--": a name is never read as an option (pacman -Si without a name lists everything)
in_repositories() { [ -n "$1" ] && pacman -Si -- "$1" > /dev/null 2>&1; }
for package in "${installed[@]}"; do
    check "installed by install.sh: $package is in the repositories" in_repositories "$package"
done
for package in "${named[@]}"; do
    check "named to the user: $package is in the repositories" in_repositories "$package"
done
