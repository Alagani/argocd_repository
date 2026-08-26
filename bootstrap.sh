#!/usr/bin/env bash
# One-time setup: a kind cluster + ArgoCD, actually managing fastapi-app —
# pulling the real image from Docker Hub via apps/fastapi-app/overlays/prod,
# same as a real k3s cluster would. There's no separate "remote" environment
# in this demo: this kind cluster IS the ArgoCD-managed environment.
# Re-running this script is only for rebuilding the cluster from scratch —
# never for deploying app changes, that's `git push` (see repo README).
set -euo pipefail
cd "$(dirname "$0")"

kind create cluster --config kind-config.yaml

kubectl create namespace argocd
# --server-side avoids kubectl's client-side apply embedding the full
# manifest into a last-applied-configuration annotation — ArgoCD's
# applicationsets.argoproj.io CRD is large enough that this trips
# Kubernetes' 262144-byte total-annotation-size limit on plain `apply`.
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

# NodePort the https port (argocd-server serves both plaintext-detecting-TLS
# on the same containerPort 8080 internally) so the UI is reachable at
# localhost:8443 via kind-config.yaml's extraPortMappings, no port-forward
# needed. install.yaml's Service ships without a `type` field (defaults to
# ClusterIP) and isn't part of our kustomize overlays — it's applied
# straight from upstream above, so this is a one-off patch, not a
# kustomize patch.
kubectl -n argocd patch svc argocd-server --type=json -p='[
  {"op":"add","path":"/spec/type","value":"NodePort"},
  {"op":"add","path":"/spec/ports/1/nodePort","value":30443}
]'

# No imagePullSecret step here as long as the Docker Hub repo stays public
# — kind's nodes pull it anonymously, same as a real cluster would. If you
# make the repo private, create a docker-registry Secret in the `demo`
# namespace and reference it from the Deployment's imagePullSecrets (see
# ../README.md).

kubectl apply -f argocd/application.yaml

cat <<'EOF'

Cluster is up and ArgoCD is watching apps/fastapi-app/overlays/prod for
real. Both services are NodePort'd via kind-config.yaml's
extraPortMappings — no port-forward needed:
  https://localhost:8443        -> ArgoCD UI (user: admin, password: see below)
  http://localhost:8080/healthz -> fastapi-app (once ArgoCD has synced it)

  kubectl -n argocd get secret argocd-initial-admin-secret -o go-template="{{.data.password | base64decode}}"

(kubectl port-forward still works as a fallback if you change the
NodePort/extraPortMappings pairing later:
  kubectl -n argocd port-forward svc/argocd-server 8081:443
  kubectl -n demo port-forward svc/fastapi-app 8000:80
)

fastapi-app won't go healthy until apps/fastapi-app/overlays/prod/kustomization.yaml's
images.newName/newTag point at an image that actually exists on Docker
Hub — see repo README for how that's bumped automatically by app_repository's CI.
EOF
