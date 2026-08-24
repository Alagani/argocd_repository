# argocd_repository

Source of truth for what's deployed. GitHub repo: `Alagani/argocd_repository`.
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

- **dev** — fully automated, no developer click required. `app_repository`'s
  CI opens the image-bump PR and immediately enables GitHub's native
  auto-merge on it; the PR still has to pass this repo's `validate.yml`
  checks before auto-merge actually lands it, and `automated.prune/selfHeal`
  then has ArgoCD deploy it. Requires "Allow auto-merge" enabled in this
  repo's Settings > General, and `validate.yml`'s jobs set as required
  status checks on `main` (Settings > Branches) — otherwise auto-merge won't
  wait for them.
- **staging** — same auto-sync, but promotion is a deliberate hand-edited/PR'd
  bump of the staging overlay's `newTag` (not auto-merged) once dev is
  verified — this is the first human checkpoint.
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
  from `argocd_repository/local`:

  ```
  ./bootstrap.sh
  ```

- `local/teardown.sh` — deletes the kind cluster.

After bootstrap, dev/staging/prod `Application`s are managed by ArgoCD
itself via the app-of-apps pattern — re-running `bootstrap.sh` is only for
rebuilding the cluster from scratch, never for deploying app changes.

`kind`'s nodes run in Docker and pull images over the network like any other
node, so `docker.io/jaga9989/simple-python-app` must be reachable. If the
Docker Hub repo is public, no `imagePullSecret` is needed; if it's private,
create one first — see the command in `bootstrap.sh`.
