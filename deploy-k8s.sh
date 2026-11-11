#!/usr/bin/env bash
# One-command deploy to a local kind cluster:  ./deploy-k8s.sh
set -euo pipefail
cd "$(dirname "$0")"
CLUSTER=three-tier
NS=three-tier

need() { command -v "$1" >/dev/null || { echo "Missing tool: $1 (see docs/06-deployment-guide.md)"; exit 1; }; }
need docker; need kind; need kubectl

if ! kind get clusters | grep -qx "$CLUSTER"; then
  echo ">> Creating kind cluster..."
  kind create cluster --name "$CLUSTER" --config kind-config.yaml
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo ">> Building images..."
docker build -f Dockerfile.backend  -t app-backend:1.0  .
docker build -f Dockerfile.frontend -t app-frontend:1.0 .

echo ">> Loading images into the cluster..."
kind load docker-image app-backend:1.0 app-frontend:1.0 --name "$CLUSTER"

echo ">> Applying manifests..."
kubectl apply -f k8s/

echo ">> Waiting for rollout..."
kubectl -n $NS rollout status statefulset/db     --timeout=180s
kubectl -n $NS rollout status deployment/backend  --timeout=180s
kubectl -n $NS rollout status deployment/frontend --timeout=180s

kubectl -n $NS get pods,svc
echo ">> App is UP at http://localhost:8080"
