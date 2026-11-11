#!/usr/bin/env bash
# Remove the app only:        ./cleanup-k8s.sh
# Remove the whole cluster:   ./cleanup-k8s.sh --cluster
set -euo pipefail
if [ "${1:-}" = "--cluster" ]; then
  kind delete cluster --name three-tier
else
  kubectl delete namespace three-tier --ignore-not-found
fi
