# hsync High &larr; Low test harness

Two containers demonstrating the core guarantee: a **High** (higher-security)
side *pulls* files up from a **Low** side over plain HTTP, and data only ever
flows Low &rarr; High. Doubles as the regression bed for the Python 3 port.

## Run

```sh
./run.sh                                # current Python 2.7 baseline
PY_IMAGE=python:3.12-slim ./run.sh      # the port (once it exists)
```

`run.sh` builds a deterministic fake tree, runs the sync in two containers
(`low` serves + signs, `high` pulls), and verifies the pulled tree matches the
source. It then writes a **golden baseline** to `golden/<image>/`:

- `HSYNC.SIG.raw` &mdash; the exact signature file
- `HSYNC.SIG.normalised` &mdash; mtime/size stripped (interop-critical invariant)
- `FINAL.txt` &mdash; the aggregate `FINAL:` checksum
- `src.sha256` / `dest.sha256` &mdash; content hashes of both trees

## Verifying the port

The port is faithful iff the py3.12 run reproduces the py2.7 baseline:

```sh
diff -r golden/python_2_7_18-slim golden/python_3_12-slim
```

A clean diff proves a py3 client/server interoperates with py2 on the wire.
The fixture deliberately includes a **unicode filename** (`café-déjà.txt`) and
a **symlink** &mdash; the two cases most likely to diverge under a naive port.

## Files

| File | Role |
|---|---|
| `make_fixture.sh` | deterministic source tree (fixed mtimes/content) |
| `low_entry.sh`    | Low: `hsync -S`, then serve over HTTP |
| `high_entry.sh`   | High: pull, no-op re-pull, drift-correction pull |
| `docker-compose.yml` / `Dockerfile` | two-container wiring, `PY_IMAGE`-parametrised |
| `run.sh`          | orchestrates + captures golden baseline |

`data/`, `dest/`, `golden/` are runtime artifacts (git-ignored).
