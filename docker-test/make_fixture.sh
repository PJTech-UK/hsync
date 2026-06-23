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

# Real binary formats (the kind actually synced: debs, jars, zips, exes) plus
# an all-byte-values file. Contents are never decoded by hsync, so these prove
# the bytes survive the 2->3 port byte-for-byte. Generated deterministically
# (fixed internal timestamps) so the golden baseline is stable run-to-run.
mkdir -p "$DATA/pkgs"
python3 - "$DATA/pkgs" <<'PY'
import os, sys, struct, zipfile, gzip, io

d = sys.argv[1]

def w(name, data):
    with open(os.path.join(d, name), 'wb') as f:
        f.write(data)

# The acid test: every byte value 0x00-0xFF, repeated. Any stray text-mode,
# newline translation or encoding step would corrupt this and change its hash.
w('allbytes.bin', bytes(range(256)) * 4096)

# A deterministic high-entropy-ish body reused by the "binary format" files.
body = bytes((i * 31 + 7) & 0xFF for i in range(65536))

# Real ZIP and JAR (a jar IS a zip). Fixed date_time => reproducible bytes.
def make_zip(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, data in entries:
            zi = zipfile.ZipInfo(n, date_time=(1980, 1, 1, 0, 0, 0))
            z.writestr(zi, data)
    return buf.getvalue()

w('archive.zip', make_zip([('a.txt', b'alpha'), ('b.bin', body)]))
w('app.jar', make_zip([('META-INF/MANIFEST.MF', b'Manifest-Version: 1.0\n'),
                       ('Main.class', body)]))

# Real gzip with a pinned mtime (mtime=0) so the stream is reproducible.
gz = io.BytesIO()
with gzip.GzipFile(fileobj=gz, mode='wb', mtime=0) as g:
    g.write(body)
w('payload.gz', gz.getvalue())

# A plausible Windows PE: 'MZ' DOS header magic + deterministic body.
w('installer.exe', b'MZ' + struct.pack('<H', 0x90) + body)

# A real Debian package is an 'ar' archive; emit the magic + one ar member so
# the bytes (incl. nulls and the ar header) are exercised.
ar = b'!<arch>\n'
member = b'debian-binary   '          # 16-byte name field
member += b'0           '             # mtime (12)
member += b'0     0     '             # uid/gid (6+6)
member += b'100644  '                 # mode (8)
payload = b'2.0\n'
member += ('%-10d' % len(payload)).encode()   # size (10)
member += b'\x60\x0a'                          # magic
member += payload
if len(payload) % 2:
    member += b'\n'
w('package.deb', ar + member + body)
PY

# Fix every mtime so the SIG is reproducible run-to-run.
find "$DATA" -depth -exec touch -h -d '2020-01-01T00:00:00Z' {} +

echo "Fixture built at $DATA:"
find "$DATA" | sort
