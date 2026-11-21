#!/bin/sh
# The lock screen's files and every file they build, transitively — then those of them that
# name anything of the module system (ModuleSlot; AnchorContent and the anchor blocks — AnchorBlock,
# SettingsPage, SettingsSection, SettingsCard, SettingsRow, PopupRow, PopupSection — that
# host modules' elements; ModuleContribution, Modules., PrivilegedRuns —
# the modules' queue of runs as administrator, which reads Modules — and FileChooser, the
# modules' file chooser, which reads Modules and the lock's state — and SafeModeBanner, the
# banner about the shell started without modules): printed as
# "LOCK:<file>", nothing when clean (notes/plans/modules.md §4 item 1; ModuleRegistriesTest).
#
#   tests/lock-closure.sh <shell tree>
#
# A pragmatic check, not a QML resolver. The roots: screensaver/, singletons/lock/,
# singletons/Lockscreen.qml, pam/. From each file it follows the component types it
# instantiates — a capitalised name followed by "{" (`Shared {`, `Foo.Bar {`: the last part) —
# looked up as <Name>.qml in the file's own directory and in each directory its
# `import qs.<a>.<b>` lines name (qs.a.b → a/b/). Not followed: singletons used by name
# (Profiles.value(...) — the lock reads settings through those, and the singletons the lock
# needs must not depend on Modules either: Profiles reads ModuleLists, plain values),
# components made with Qt.createComponent or a Loader's `source` (none on the lock path),
# and quoted imports. So a shared component that gains a ModuleSlot or an anchor block is caught.
set -u
root=$1
cd "$root" || exit 2

queue=$(find screensaver singletons/lock pam -name '*.qml' 2>/dev/null; [ -f singletons/Lockscreen.qml ] && echo singletons/Lockscreen.qml)
seen=""
while [ -n "$queue" ]; do
    file=$(printf '%s\n' "$queue" | head -n 1)
    queue=$(printf '%s\n' "$queue" | tail -n +2)
    case " $seen " in *" $file "*) continue ;; esac
    seen="$seen $file"
    dirs="$(dirname "$file") $(sed -n 's/^[[:space:]]*import[[:space:]]\{1,\}qs\.\([A-Za-z0-9_.]*\).*/\1/p' "$file" | tr . / | tr '\n' ' ')"
    for name in $(grep -oE '\b[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*[[:space:]]*\{' "$file" | sed 's/[[:space:]]*{$//; s/.*\.//' | sort -u); do
        for dir in $dirs; do
            if [ -f "$dir/$name.qml" ]; then
                queue=$(printf '%s\n%s' "$queue" "$dir/$name.qml" | sed '/^$/d')
                break
            fi
        done
    done
done
for file in $seen; do
    if grep -qE 'ModuleSlot|AnchorContent|AnchorBlock|SettingsPage|SettingsSection|SettingsCard|SettingsRow|PopupRow|PopupSection|ModuleContribution|Modules\.|PrivilegedRuns|FileChooser|SafeModeBanner' "$file"; then
        echo "LOCK:$file"
    fi
done
# How many files were looked at, for the suite to check the walk went somewhere
echo "LOCKFILES:$(echo $seen | wc -w)"
