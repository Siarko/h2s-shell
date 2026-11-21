#!/usr/bin/env bash
# The stand-ins tests/ModuleBackupTest.qml backs up from, made in a new private temporary
# directory (printed on the last line): a folder module "kappa" (1.0.0, its manifest naming
# notes.db, sub, escape and missing for its backups), its store's file, and its data
# directory — notes.db, sub/a.txt, sub/out (a link out of it, inside a named folder), escape
# (a named path that is a link out), cache/big (not named) — and a file outside that the
# links point at. Nothing here is the user's.
set -euo pipefail

T=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}" h2s-backup.XXXXXX)
mkdir -p "$T/folders/kappa" "$T/outside" "$T/data/h2s-shell/modules" "$T/config/h2s_shell/modules" \
         "$T/data/h2s-shell/module-data/kappa/sub" "$T/data/h2s-shell/module-data/kappa/cache"
manifest() {   # <version>
    printf '{ "id": "kappa", "name": "Kappa", "version": "%s", "api": "1.37", "main": "Main.qml", "backup": ["notes.db", "sub", "escape", "missing"] }\n' "$1" \
        > "$T/folders/kappa/module.json"
}
manifest 1.0.0
printf 'import QtQuick\nQtObject {}\n' > "$T/folders/kappa/Main.qml"
printf 'secret\n' > "$T/outside/secret"
D=$T/data/h2s-shell/module-data/kappa
printf 'one\n' > "$D/notes.db"
printf 'a\n' > "$D/sub/a.txt"
ln -s "$T/outside/secret" "$D/sub/out"
ln -s "$T/outside/secret" "$D/escape"
printf 'big\n' > "$D/cache/big"
printf '{"token":"one"}' > "$T/config/h2s_shell/modules/kappa.json"
echo "$T"
