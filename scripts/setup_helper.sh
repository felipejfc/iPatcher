#!/bin/bash
set -euo pipefail

DEST="/var/jb/usr/local/libexec/ipatcher-helper"

find_helper() {
    local candidate

    for candidate in \
        "/var/jb/Applications/iPatcher.app/TweakPayload/ipatcher-helper" \
        "/var/jb/Applications/iPatcher.app/ipatcher-helper"
    do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    find /private/var/containers/Bundle/Application \
        -path '*/iPatcher.app/TweakPayload/ipatcher-helper' \
        -type f 2>/dev/null | head -n 1
}

SRC="$(find_helper)"

if [ -z "$SRC" ]; then
    echo "ERROR: could not find ipatcher-helper in any installed iPatcher app bundle" >&2
    exit 1
fi

mkdir -p "$(dirname "$DEST")"
cp "$SRC" "$DEST"
chown root:wheel "$DEST"
chmod 4755 "$DEST"

echo "Installed helper from:"
echo "  $SRC"
echo "to:"
echo "  $DEST"
ls -l "$DEST"
