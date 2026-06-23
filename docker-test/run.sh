#!/bin/sh
# Drive a full High <- Low hsync demo in two containers and capture a golden
# baseline of the signature file.
#
#   ./run.sh                      # uses Python 2.7 baseline
#   PY_IMAGE=python:3.12-slim ./run.sh   # uses the port
#
# Exit status is the HIGH side's status: non-zero => the pull failed.
set -eu

cd "$(dirname "$0")"

PY_IMAGE="${PY_IMAGE:-python:2.7.18-slim}"
export PY_IMAGE
TAG="$(echo "$PY_IMAGE" | tr ':/.' '___')"
GOLDEN="golden/$TAG"

echo "=================================================================="
echo " hsync High<-Low harness   PY_IMAGE=$PY_IMAGE"
echo "=================================================================="

# Fresh state every run. The containers write into ./dest as root, so clean it
# from inside a container to avoid host-side permission errors on re-runs.
sh ./make_fixture.sh ./data >/dev/null
docker run --rm -v "$PWD/dest:/dest" "$PY_IMAGE" \
    sh -c 'rm -rf /dest/* /dest/.[!.]* 2>/dev/null' || true
rm -rf ./dest "$GOLDEN"
mkdir -p ./dest "$GOLDEN"

# Run it. high exits when the demo finishes; --abort-on-container-exit then
# stops low's web server, and --exit-code-from surfaces high's status.
set +e
docker compose up --build --abort-on-container-exit --exit-code-from high
STATUS=$?
set -e
docker compose down -v --remove-orphans >/dev/null 2>&1 || true

echo
echo "------------------------------------------------------------------"
if [ "$STATUS" -ne 0 ]; then
  echo "RESULT: FAILED (high exit $STATUS)"
  exit "$STATUS"
fi

# ---- Capture the golden baseline -------------------------------------------
# The raw SIG should be byte-identical between a faithful py2 and py3 build
# (root:root ownership, fixed mtimes, deterministic content). We also keep a
# normalised view (mtime+size stripped) as the interop-critical invariant.
cp ./data/HSYNC.SIG "$GOLDEN/HSYNC.SIG.raw"
awk '/^FINAL:/{print;next}{printf "%s %s %s %s",$1,$2,$3,$4; for(i=7;i<=NF;i++)printf " %s",$i; print ""}' \
    ./data/HSYNC.SIG > "$GOLDEN/HSYNC.SIG.normalised"
grep '^FINAL:' ./data/HSYNC.SIG > "$GOLDEN/FINAL.txt"

# Prove the pulled tree matches the source tree (content only).
( cd ./data && find . -type f -not -name 'HSYNC.SIG*' | sort | \
    xargs sha256sum ) | sed 's# \./# #' > "$GOLDEN/src.sha256"
( cd ./dest && find . -type f -not -name 'HSYNC.SIG*' | sort | \
    xargs sha256sum ) | sed 's# \./# #' > "$GOLDEN/dest.sha256"

echo "RESULT: PASS"
echo "FINAL checksum: $(cat "$GOLDEN/FINAL.txt")"
if diff -q "$GOLDEN/src.sha256" "$GOLDEN/dest.sha256" >/dev/null; then
  echo "TREE MATCH: dest content == src content  (one-way pull verified)"
else
  echo "TREE MISMATCH: see $GOLDEN/{src,dest}.sha256"; exit 1
fi
echo "Golden baseline saved under docker-test/$GOLDEN/"
