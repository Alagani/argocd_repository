#!/usr/bin/env bash
# One-time local setup: kind cluster + ArgoCD, plus a direct (non-ArgoCD)
# deploy of the local overlay so you can smoke-test the app without any
# registry credentials. The real deploy target is k3s/Docker Hub (see
# ../remote) — prod is ArgoCD-managed there, never here. Re-running this
# script is only for rebuilding the cluster from scratch.
set -euo pipefail
cd "$(dirname "$0")"

# Assumes app_repository is checked out as a sibling of this repo, e.g.
#   .../ArgoCD Demo/{fastapi-app,gitops-argocd}
# OPEN QUESTION: adjust if your local layout differs.
APP_REPO_PATH="${APP_REPO_PATH:-../../fastapi-app}"

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

# ArgoCD here demos the tool itself but is deliberately NOT pointed at
# argocd/application.yaml: that Application targets a Docker Hub image —
# resolvable from kind's nodes, but pulling the demo's own overlay isn't
# the point of this script. Instead, build the image locally, load it
# straight into kind's nodes (no registry round trip, no credentials
# needed), and apply the local overlay directly.
docker build -t fastapi-app:local "$APP_REPO_PATH"
kind load docker-image fastapi-app:local --name argocd-demo

kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k ../apps/fastapi-app/overlays/local

cat <<'EOF'

Cluster is up. Both services are NodePort'd via kind-config.yaml's
extraPortMappings — no port-forward needed:
  https://localhost:8443  -> ArgoCD UI (user: admin, password: see below)
  http://localhost:8080/healthz -> fastapi-app

  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

(kubectl port-forward still works as a fallback if you change the
NodePort/extraPortMappings pairing later:
  kubectl -n argocd port-forward svc/argocd-server 8081:443
  kubectl -n demo port-forward svc/fastapi-app 8000:80
)

To exercise the real ArgoCD-managed path (prod on k3s/Docker Hub), see
../remote instead — this kind cluster never touches that setup.
EOF
