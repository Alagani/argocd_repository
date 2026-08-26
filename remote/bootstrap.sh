#!/usr/bin/env bash
# One-time setup against the real k3s cluster (installed manually — no IaC
# in this repo provisions it): assumes kubectl is already pointed at it via
# KUBECONFIG, installs ArgoCD, and applies the fastapi-app Application.
# Everything after this is driven by git, same as the local kind flow in
# ../local — this script is only for (re-)bootstrapping ArgoCD on a
# cluster, never for deploying app changes.
set -euo pipefail
cd "$(dirname "$0")"

kubectl cluster-info >/dev/null || {
  echo "kubectl can't reach a cluster. Point KUBECONFIG at your k3s cluster's kubeconfig first — e.g. copy /etc/rancher/k3s/k3s.yaml from the server and fix its 'server:' address to the server's reachable IP/hostname." >&2
  exit 1
}

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side avoids kubectl's client-side apply embedding the full
# manifest into a last-applied-configuration annotation — ArgoCD's
# applicationsets.argoproj.io CRD is large enough that this trips
# Kubernetes' 262144-byte total-annotation-size limit on plain `apply`.
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

# No imagePullSecret step here as long as the Docker Hub repo stays public
# — k3s's containerd pulls it anonymously. If you make the repo private,
# create a docker-registry Secret in the `demo` namespace and reference it
# from the Deployment's imagePullSecrets (see ../README.md).

kubectl apply -f ../argocd/application.yaml

cat <<'EOF'

ArgoCD is installed and the fastapi-app Application is applied. Useful next
steps:
  kubectl -n argocd port-forward svc/argocd-server 8081:443
    -> https://localhost:8081 (user: admin, password: see below)
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

fastapi-app won't go healthy until:
  - apps/fastapi-app/overlays/prod/kustomization.yaml's `images.newName` /
    `newTag` point at an image that actually exists on Docker Hub, and
  - that Docker Hub repo is either public, or the Deployment has an
    imagePullSecret for it.
EOF
