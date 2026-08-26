# argocd_repository

A small, focused demo of **how ArgoCD works**. GitHub repo:
`Alagani/argocd_repository`. App repo: `Alagani/app_repository` (builds and
pushes the image; see its README).

ArgoCD polls this repo and reconciles the cluster. No CI job in either repo
ever runs `kubectl apply` — that's the whole point.

Deploy target: a self-hosted **k3s** cluster, image registry: **Docker
Hub** (`<dockerhub-username>/myapp-repo`). Both are created **manually —
no Terraform/OpenTofu** provisions anything here.

## Layout

- `apps/fastapi-app/base` — Kustomize base (Deployment, Service). The
  container image is a symbolic placeholder (`fastapi-app:placeholder`);
  every overlay's `images:` block rewrites both registry and tag.
- `apps/fastapi-app/overlays/prod` — the one ArgoCD-managed environment, on
  k3s: Docker Hub image, replica count.
- `apps/fastapi-app/overlays/local` — kind-only, applied directly by
  `local/bootstrap.sh` via `kubectl apply -k` (not ArgoCD-managed). Points
  at a locally built+loaded image so kind's nodes never need registry
  credentials at all.
- `argocd/application.yaml` — the one ArgoCD `Application`, pointed at
  `overlays/prod`, with `automated: {prune: true, selfHeal: true}`.

## Pipeline (`.github/workflows/validate.yml`)

On every PR: `kustomize build` both overlays and validate the rendered
manifests against Kubernetes schemas (`kubeconform`), plus `yamllint`.
Validate-only — it never deploys anything. Deploying is: merge to `main`,
ArgoCD notices, ArgoCD syncs.

## Deployment model

Single environment (`prod`), fully automated end-to-end — no developer
click anywhere in the path:

1. `app_repository`'s CI builds, scans, and pushes the image, then opens an
   image-bump PR here and immediately enables GitHub's native auto-merge on
   it.
2. Auto-merge waits for this repo's `validate.yml` checks to pass, then
   merges the PR itself.
3. `fastapi-app`'s `automated.prune/selfHeal: true` (in
   `argocd/application.yaml`) has ArgoCD pick up the merge and sync the
   cluster.

Requires **Allow auto-merge** enabled in this repo's Settings > General,
and `validate.yml`'s jobs set as **required status checks** on `main`
(Settings > Branches) — otherwise auto-merge won't wait for them. There is
deliberately no CODEOWNERS/manual-review gate — every merge to `main` here
reaches the cluster automatically. See `app_repository`'s README for the
CI side of this.

## Manual setup (no IaC)

Create these once, by hand, before `remote/bootstrap.sh` will work:

1. A server (VM or bare metal) with [k3s](https://k3s.io) installed
   (`curl -sfL https://get.k3s.io | sh -`).
2. A kubeconfig on your machine pointed at it — copy
   `/etc/rancher/k3s/k3s.yaml` from the server and fix its `server:` field
   to the server's reachable IP/hostname, then `export KUBECONFIG=...` (or
   merge it into `~/.kube/config`).
3. The `myapp-repo` Docker Hub repository (already created) and the access
   token that pushes to it (see `app_repository`'s README).
4. If that Docker Hub repo is **private**: a `docker-registry` Secret in
   the `demo` namespace, referenced from the Deployment's
   `imagePullSecrets` (not needed for a public repo — k3s pulls those
   anonymously).

OPEN QUESTIONs before this touches anything shared: who owns/pays for the
server, and whether the Docker Hub repo should be public or private.
**CTO sign-off** applies before a shared/production apply.

## Remote cluster (the real thing: k3s)

```
./remote/bootstrap.sh
```

Assumes `kubectl` already points at the k3s cluster (see manual setup
above), installs ArgoCD, and applies `argocd/application.yaml`.
`remote/teardown.sh` removes ArgoCD from the cluster only — the k3s
cluster/nodes and Docker Hub repo themselves are torn down manually, the
same way they were created.

## Local cluster (kind) — dev-only smoke test, not ArgoCD-managed

`local/` stands up a throwaway cluster to demo ArgoCD itself without any
external dependency:

```
cd local
./bootstrap.sh
```

This creates a `kind` cluster, installs ArgoCD (for demoing the tool/UI
only — it's not pointed at `argocd/application.yaml`; the point of this
overlay is to skip the registry round trip entirely), builds the app
image from a sibling `app_repository` checkout, `kind load`s it in (no
registry, no credentials needed), and applies
`apps/fastapi-app/overlays/local` directly with `kubectl apply -k`.

```
kubectl -n argocd port-forward svc/argocd-server 8081:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n demo port-forward svc/fastapi-app 8000:80
```

`local/teardown.sh` deletes the kind cluster.

## What to actually try, to see ArgoCD do something

Run these against the real k3s cluster (`remote/bootstrap.sh`) — that's
the one ArgoCD is actually managing:

1. **Self-heal** — `kubectl -n demo scale deployment/fastapi-app --replicas=5`,
   then watch ArgoCD notice the live state has drifted from git and scale
   it back down. This is the core ArgoCD pitch: the cluster can't stay out
   of sync with git, even if someone edits it directly.
2. **Sync on change** — edit `apps/fastapi-app/overlays/prod/kustomization.yaml`
   by hand (bump `replicas`), commit, push. ArgoCD picks up the new commit
   and reconciles the cluster to match — no CI/CD pipeline involved on this
   side at all.
3. **Prune** — delete `service.yaml` from `apps/fastapi-app/base/kustomization.yaml`'s
   `resources:` list, push, and watch ArgoCD delete the Service from the
   cluster too (`prune: true`).
4. **New image, fully automated** — push a change in `app_repository` and
   stop touching anything: its CI builds, scans, and pushes a new tag to
   Docker Hub, opens the bump PR here, and auto-merges it once
   `validate.yml` passes. ArgoCD picks up the merge on its own. That's the
   full loop: app repo produces an artifact, its CI declares what should be
   running, ArgoCD makes it so — see `app_repository`'s README for the CI
   side.
