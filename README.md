# argocd_repository

A small, focused demo of **how ArgoCD works**. GitHub repo:
`Alagani/argocd_repository`. App repo: `Alagani/app_repository` (builds and
pushes the image; see its README).

ArgoCD polls this repo and reconciles the cluster. No CI job in either repo
ever runs `kubectl apply` — that's the whole point.

Cluster: a **kind** cluster on your own machine (`./bootstrap.sh`) — no VM,
no server to provision. Image registry: **Docker Hub**
(`<dockerhub-username>/myapp-repo`), created **manually — no
Terraform/OpenTofu**. There's a single environment (`prod`); it's real in
every way that matters for this demo (ArgoCD actually manages it, the
image is actually pulled from Docker Hub) — the only thing "local" about
it is that the cluster happens to run on your laptop instead of a rented
server. ArgoCD only needs outbound access to GitHub and Docker Hub to make
that work; nothing needs to be reachable from the internet.

## Layout

- `apps/fastapi-app/base` — Kustomize base (Deployment, Service). The
  container image is a symbolic placeholder (`fastapi-app:placeholder`);
  the `prod` overlay's `images:` block rewrites both registry and tag.
- `apps/fastapi-app/overlays/prod` — the one environment: Docker Hub
  image, replica count, NodePort Service.
- `argocd/application.yaml` — the one ArgoCD `Application`, pointed at
  `overlays/prod`, with `automated: {prune: true, selfHeal: true}`.
- `kind-config.yaml`, `bootstrap.sh`, `teardown.sh` — stand the cluster up
  and down.

## Pipeline (`.github/workflows/validate.yml`)

On every PR: `kustomize build` the `prod` overlay and validate the
rendered manifests against Kubernetes schemas (`kubeconform`), plus
`yamllint`. Validate-only — it never deploys anything. Deploying is: merge
to `main`, ArgoCD notices, ArgoCD syncs.

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

Create these once, by hand:

1. The `myapp-repo` Docker Hub repository (already created) and the access
   token that pushes to it (see `app_repository`'s README).
2. If that Docker Hub repo is **private**: a `docker-registry` Secret in
   the `demo` namespace, referenced from the Deployment's
   `imagePullSecrets` (not needed for a public repo — kind's nodes pull
   those anonymously, same as any cluster would).
3. `kind` and `docker` installed locally.

No server to provision, no `KUBECONFIG` to copy from anywhere — `kind
create cluster` sets up kubectl access to itself automatically.

## Bootstrap

```
./bootstrap.sh
```

Creates the kind cluster, installs ArgoCD (NodePort'd for direct UI
access), and applies `argocd/application.yaml` — from there ArgoCD is
managing `overlays/prod` for real, pulling from Docker Hub.

```
https://localhost:8443        -> ArgoCD UI (user: admin)
http://localhost:8080/healthz -> fastapi-app (once ArgoCD has synced it)
kubectl -n argocd get secret argocd-initial-admin-secret -o go-template="{{.data.password | base64decode}}"
```

`teardown.sh` deletes the kind cluster (ArgoCD and the app go with it —
there's no separate persistent infra to preserve, unlike a real server).

fastapi-app won't go healthy until `overlays/prod/kustomization.yaml`'s
`images.newName`/`newTag` point at an image that actually exists on
Docker Hub — see "What to actually try" below for triggering that.

## What to actually try, to see ArgoCD do something

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
