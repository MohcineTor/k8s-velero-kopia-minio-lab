#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"
RELEASE="kube-prom-stack"
VALUES_FILE="$SCRIPT_DIR/values.yaml"

for cmd in helm kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is required" >&2
    exit 1
  fi
done

echo "Creating namespace $NAMESPACE if missing"
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# if ! helm repo list | grep -q 'prometheus-community'; then
#   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# fi
# if ! helm repo list | grep -q 'grafana'; then
#   helm repo add grafana https://grafana.github.io/helm-charts
# fi
# helm repo update

echo "Installing kube-prometheus-stack (this may take a few minutes)"
helm upgrade --install "$RELEASE" prometheus-community/kube-prometheus-stack -n "$NAMESPACE" -f "$VALUES_FILE" --wait --timeout 10m

echo "Done. Grafana will be available in the monitoring namespace. To access it locally run:"
echo "kubectl -n $NAMESPACE port-forward svc/$RELEASE-grafana 3000:80"
