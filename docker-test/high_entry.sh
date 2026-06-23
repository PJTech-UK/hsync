#!/bin/sh
# HIGH (higher security) side: PULL files up from Low. Nothing is ever pushed
# down. Demonstrates first-pull, idempotent no-op re-run, and change detection.
set -eu

BASE="http://low:8080"

echo "[high] Waiting for Low's HTTP server..."
python - "$BASE/HSYNC.SIG" <<'PY'
import sys, time
try:
    from urllib.request import urlopen      # py3
except ImportError:
    from urllib2 import urlopen             # py2
url = sys.argv[1]
for _ in range(120):
    try:
        urlopen(url).read(); print("[high] Low is up"); sys.exit(0)
    except Exception:
        time.sleep(0.5)
sys.exit("[high] Low never came up")
PY

echo "[high] ===== PULL #1 (cold) ====="
hsync -D /dest -u "$BASE"

echo "[high] ===== PULL #2 (should be a no-op except the SIG) ====="
hsync -D /dest -u "$BASE"

echo "[high] ===== Simulate drift: add a stray file + delete a real one ====="
echo "i should be removed" > /dest/STRAY.txt
rm -f /dest/README.txt

echo "[high] ===== PULL #3 (must re-fetch README.txt, remove STRAY.txt) ====="
hsync -D /dest -u "$BASE"

echo "[high] Final destination tree:"
find /dest -not -name 'HSYNC.SIG*' | sort

echo "[high] DONE"
