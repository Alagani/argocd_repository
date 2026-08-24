# argocd_repository

Source of truth for what's deployed. GitHub repo: `Alagani/argocd_repository`.
App repo: `Alagani/app_repository`. ArgoCD polls this repo and reconciles the
cluster — no CI job in this repo (or in `app_repository`) ever runs
`kubectl apply`.

## Layout

- `apps/fastapi-app/base` — Kustomize base (Deployment, Service).
- `apps/fastapi-app/overlays/prod` — the single environment: image tag,
  replica count, resource patches.
- `argocd/applications/fastapi-app-prod.yaml` — the one ArgoCD `Application`.
- `argocd/app-of-apps.yaml` — root Application that syncs everything under
  `argocd/applications/` (apply this once, manually, to bootstrap).

## Pipeline (`.github/workflows/validate.yml`)

On every PR: `kustomize build` the prod overlay and validate the rendered
manifests against Kubernetes schemas (`kubeconform`), plus `yamllint`. This
is **validate-only** — merging to `main` is the deploy trigger; ArgoCD's own
`selfHeal`/`automated` sync policy does the rest.

## Deployment model

Single environment (`prod`), fully automated end-to-end — no developer click
anywhere in the path:

1. `app_repository`'s CI builds, scans, and pushes the image, then opens an
   image-bump PR here and immediately enables GitHub's native auto-merge on
   it.
2. Auto-merge waits for this repo's `validate.yml` checks to pass, then
   merges the PR itself.
3. `fastapi-app-prod`'s `automated.prune/selfHeal: true` has ArgoCD pick up
   the merge and sync the cluster.

Requires "Allow auto-merge" enabled in this repo's Settings > General, and
`validate.yml`'s jobs set as required status checks on `main` (Settings >
Branches) — otherwise auto-merge won't wait for them. There is deliberately
no CODEOWNERS/manual-review gate — every merge to `main` here reaches the
cluster automatically.

## Local cluster (kind)

`local/` holds everything needed to stand up the demo cluster — this is
local dev tooling only, separate from the actual GitOps content above.

- `local/kind-config.yaml` — single control-plane + worker `kind` cluster
  named `argocd-demo`.
- `local/bootstrap.sh` — creates the cluster, installs ArgoCD from its
  official manifests, and applies `argocd/app-of-apps.yaml` once. Run it
  from `argocd_repository/local`:

  ```
  ./bootstrap.sh
  ```

- `local/teardown.sh` — deletes the kind cluster.

After bootstrap, the `fastapi-app-prod` `Application` is managed by ArgoCD
itself via the app-of-apps pattern — re-running `bootstrap.sh` is only for
rebuilding the cluster from scratch, never for deploying app changes.

`kind`'s nodes run in Docker and pull images over the network like any other
node, so `docker.io/jaga9989/simple-python-app` must be reachable. If the
Docker Hub repo is public, no `imagePullSecret` is needed; if it's private,
create one first — see the command in `bootstrap.sh`.
