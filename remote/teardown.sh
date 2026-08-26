#!/usr/bin/env bash
# Removes ArgoCD and its managed Application from the k3s cluster. Does NOT
# touch the cluster/nodes/Docker Hub repo themselves — those were created
# manually and are torn down manually too (destroying a shared k3s cluster
# is not something this script should do unattended).
set -euo pipefail
cd "$(dirname "$0")"

kubectl delete -f ../argocd/application.yaml --ignore-not-found
kubectl delete namespace argocd --ignore-not-found

cat <<'EOF'

ArgoCD removed from the current kubeconfig context's cluster. The k3s
cluster/nodes (uninstall with /usr/local/bin/k3s-uninstall.sh on the
server, if that's what you want), the Docker Hub repo, and any other
infra were created manually and are not affected by this script — remove
them the same way you created them.
EOF
