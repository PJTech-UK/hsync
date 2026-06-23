#!/bin/sh
# LOW (lower security) side: generate the signature file over the source tree,
# then publish the tree over plain HTTP. Data only ever flows OUT of here.
set -eu

cd /srv/data

# Use an ABSOLUTE source path: `hsync -S .` is a known-broken case (see TODO,
# and it trips PathMustBeAbsoluteError on symlinks).
echo "[low] Generating signature file (hsync -S)"
hsync -S /srv/data

echo "[low] HSYNC.SIG generated:"
ls -l /srv/data/HSYNC.SIG

# Serve the tree. Works on both Python 2 (SimpleHTTPServer) and 3 (http.server).
echo "[low] Serving /srv/data on :8080"
python -m SimpleHTTPServer 8080 2>/dev/null || python -m http.server 8080
