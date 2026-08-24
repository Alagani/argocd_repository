# gitops-argocd

Source of truth for what's deployed. ArgoCD polls this repo and reconciles
the cluster — no CI job in this repo (or in `fastapi-app`) ever runs
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
  `fastapi-app`'s CI opens and merges an image-bump PR.
- **staging** — same auto-sync, promoted by hand-editing/PR-ing the staging
  overlay's `newTag` once dev is verified.
- **prod** — no `automated:` block by design. Promotion is a deliberate
  `argocd app sync fastapi-app-prod` (or UI click) after review. The
  `CODEOWNERS` file requires sign-off on any change under
  `overlays/prod/` or `fastapi-app-prod.yaml`.

## Bootstrap (once, against your kind cluster)

```
kubectl apply -f argocd/app-of-apps.yaml
```

Everything else — dev/staging/prod Applications — is then managed by ArgoCD
itself via the app-of-apps pattern.
