# Deploying hsync on Kubernetes

A containerised **High** tier: it pulls files up from a lower-security tier and
serves the received tree to the next tier. Data only ever flows upward.

```
 lower tier            this pod (namespace: hsync)              higher tier
 (HTTP server)   --->  [ hsync puller ] --writes--> /data       (its own hsync
                       [ nginx serve  ] --reads---> /data  --->   pulls from us)
                              PVC (RWX / NFS)
```

## Components

| File | Purpose |
|---|---|
| `../Dockerfile` / `../entrypoint.sh` | production image; runs a pull→sleep loop with a heartbeat |
| `namespace.yaml` | the `hsync` namespace, labelled `hsync-tier: higher` |
| `configmap.yaml` | source URL, interval, non-secret extra args |
| `secret.example.yaml` | template for HTTP-auth args (copy to `secret.yaml`, keep out of git) |
| `pvc.yaml` | the large RWX/NFS volume for received files |
| `deployment.yaml` | `replicas: 1`, `Recreate`; puller + nginx sidecar |
| `nginx-configmap.yaml` | nginx serving `/data` read-only on :8080 |
| `service.yaml` | ClusterIP exposing the served tree to the higher tier |
| `networkpolicy.yaml` | enforces pull-down / serve-up only |
| `kustomization.yaml` | ties it together |

## Design decisions

- **Deployment, not CronJob.** You asked for a single instance that also
  *serves* the files. A Deployment hosts the always-on nginx and the pull loop
  in one pod and self-heals via pod restart. (If you ever want pure scheduled
  pulls with no co-located serving, a `CronJob` with `concurrencyPolicy:
  Forbid` + a separate nginx Deployment is the alternative.)
- **`replicas: 1` + `strategy: Recreate`.** One instance by design; `Recreate`
  guarantees two pods never write the NFS volume at once. hsync's lockfile is a
  second line of defence.
- **Self-healing (cheap).** The puller touches a heartbeat after every
  successful pull; a liveness probe restarts the pod if no pull succeeds within
  the window (default 1800s). A restart also clears any stale lockfile, and
  hsync's per-file atomic writes + checkpointed signature mean a restart
  re-fetches only the in-flight file, not the whole tree.
- **NetworkPolicy.** Egress only to the lower tier (+DNS); ingress only from the
  higher tier on :8080. This is the network embodiment of hsync's one-way
  guarantee — set the tier selectors to match your namespaces and use a CNI
  that enforces policy.
- **Hardening.** Non-root (uid 1000), `fsGroup` for NFS writes, dropped
  capabilities, read-only rootfs on the puller (writable `/tmp` for the
  heartbeat).

## ⚠️ Memory sizing — read this

hsync buffers **each file entirely in memory** while fetching it (see the
project TODO: "write in-progress downloads to disk instead of memory"). The
deployment's memory **limit must exceed the size of the largest single file**
you sync. For multi-GB Debian packages / images, raise `resources.limits.memory`
accordingly, or that pod will OOM mid-pull. This is the single most likely
operational surprise.

## Deploy

```sh
# 1. Build and push the image (context = repo root).
docker build -f deploy/Dockerfile -t your-registry.example.com/hsync:0.9.82 .
docker push your-registry.example.com/hsync:0.9.82

# 2. Edit configmap.yaml (HSYNC_SOURCE_URL), pvc.yaml (storageClass/size),
#    networkpolicy.yaml (tier selectors), kustomization.yaml (image).

# 3. If the source needs auth: cp secret.example.yaml secret.yaml, fill in,
#    `kubectl apply -f secret.yaml` (do not commit it).

# 4. Apply.
kubectl apply -k deploy/k8s/

# 5. Watch.
kubectl -n hsync logs deploy/hsync -c hsync -f
```

## One-shot / debugging

The image's entrypoint is the loop; override it for a single manual pull:

```sh
kubectl -n hsync run hsync-once --rm -it --image=your-registry.example.com/hsync:0.9.82 \
  --command -- hsync -D /data -u http://hsync-lower.lower-tier.svc.cluster.local/
```
