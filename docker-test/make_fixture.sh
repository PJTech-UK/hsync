#!/bin/sh
# Build a DETERMINISTIC fake file tree to sync from Low -> High.
# Deterministic content + fixed mtimes so the golden baseline is stable.
# Run on the host; the tree is mounted into the Low container.
set -eu

DATA="${1:-./data}"
rm -rf "$DATA"
mkdir -p "$DATA"

# A spread of cases the sync cares about: nested dirs, an empty file,
# a larger file, a unicode filename (the bytes/str trap), and a symlink.
mkdir -p "$DATA/docs" "$DATA/src/sub" "$DATA/empty"

printf 'hello world\n'                          > "$DATA/README.txt"
printf 'line A\nline B\nline C\n'               > "$DATA/docs/notes.txt"
printf 'int main(void){return 0;}\n'            > "$DATA/src/main.c"
printf 'static int x = 42;\n'                   > "$DATA/src/sub/util.c"
: > "$DATA/empty/.keep"
# ~1MB deterministic file (no randomness -> stable hash).
yes 'the quick brown fox jumps over the lazy dog' | head -c 1048576 > "$DATA/src/big.dat"
# Unicode filename: this is exactly where a naive Py3 port breaks.
printf 'accented filename content\n'            > "$DATA/docs/café-déjà.txt"
# Symlink (relative, in-tree).
ln -sf main.c "$DATA/src/link_to_main.c"

# Fix every mtime so the SIG is reproducible run-to-run.
find "$DATA" -depth -exec touch -h -d '2020-01-01T00:00:00Z' {} +

echo "Fixture built at $DATA:"
find "$DATA" | sort
