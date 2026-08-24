# argocd_respository

Source of truth for what's deployed. GitHub repo: `Alagani/argocd_respository`.
App repo: `Alagani/app_repository`. ArgoCD polls this repo and reconciles the
cluster — no CI job in this repo (or in `app_repository`) ever runs
`kubectl apply`.

## Layout

- `apps/fastapi-app/base` — Kustomize base (Deployment, Service).
- `apps/fastapi-app/overlays/{dev,staging,prod}` — per-environment image tag,
  replica count, resource patches.
- `argocd/applications/*.yaml` — one ArgoCD `Application` per environment.
- `argocd/app-of-apps.yaml` — root Application that syncs everything under
  `argocd/applications/` (apply this once, manually, to bootstrap).

## Pipeline (`.github/workflows/validate.yml`)

On every PR: `kustomize build` each overlay and validate the rendered
manifests against Kubernetes schemas (`kubeconform`), plus `yamllint`. This
is **validate-only** — merging to `main` is the deploy trigger; ArgoCD's own
`selfHeal`/`automated` sync policy (per-`Application`) does the rest.

## Promotion model

- **dev** — `automated.prune/selfHeal: true`. Deploys as soon as
  `app_repository`'s CI opens and merges an image-bump PR.
- **staging** — same auto-sync, promoted by hand-editing/PR-ing the staging
  overlay's `newTag` once dev is verified.
- **prod** — no `automated:` block by design. Promotion is a deliberate
  `argocd app sync fastapi-app-prod` (or UI click) after review. The
  `CODEOWNERS` file requires sign-off on any change under
  `overlays/prod/` or `fastapi-app-prod.yaml`.

## Local cluster (kind)

`local/` holds everything needed to stand up the demo cluster — this is
local dev tooling only, separate from the actual GitOps content above.

- `local/kind-config.yaml` — single control-plane + worker `kind` cluster
  named `argocd-demo`.
- `local/bootstrap.sh` — creates the cluster, installs ArgoCD from its
  official manifests, and applies `argocd/app-of-apps.yaml` once. Run it
  from `argocd_respository/local`:

  ```
  ./bootstrap.sh
  ```

- `local/teardown.sh` — deletes the kind cluster.

After bootstrap, dev/staging/prod `Application`s are managed by ArgoCD
itself via the app-of-apps pattern — re-running `bootstrap.sh` is only for
rebuilding the cluster from scratch, never for deploying app changes.

`kind`'s nodes run in Docker and pull images over the network like any other
node, so `ghcr.io/alagani/fastapi-app` must be reachable — either make the GHCR
package public, or create an `imagePullSecret` as described in
`bootstrap.sh` before the dev `Application` first syncs.
