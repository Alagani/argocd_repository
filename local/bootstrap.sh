#!/usr/bin/env bash
# One-time local setup: kind cluster + ArgoCD + the app-of-apps root Application.
# Everything after this is driven by git — re-running this script is only for
# rebuilding the cluster from scratch, not for deploying changes.
set -euo pipefail
cd "$(dirname "$0")"

kind create cluster --config kind-config.yaml

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

# GHCR packages are private by default. Either make ghcr.io/alagani/fastapi-app
# public, or create this pull secret before ArgoCD syncs the app:
#   kubectl create secret docker-registry ghcr-pull-secret \
#     --namespace demo --docker-server=ghcr.io \
#     --docker-username="$GHCR_USERNAME" --docker-password="$GHCR_TOKEN"
# (values come from your own shell env — never hardcode them here or in git)

kubectl apply -f ../argocd/app-of-apps.yaml

cat <<'EOF'

Cluster is up. Useful next steps:
  kubectl -n argocd port-forward svc/argocd-server 8081:443
    -> https://localhost:8081 (user: admin, password: see below)
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  kubectl -n demo port-forward svc/fastapi-app 8000:80
    -> http://localhost:8000/healthz
EOF
