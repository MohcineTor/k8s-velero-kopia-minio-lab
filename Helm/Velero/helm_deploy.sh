#!/usr/bin/env bash
set -euo pipefail

# Deploy Velero: create secret from cloud-credentials, then helm upgrade --install
# Usage: ./helm_deploy_velero.sh [--namespace NAMESPACE] [--credentials FILE] [--values FILE] [--release NAME] [--chart CHART]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-velero}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$SCRIPT_DIR/cloud-credentials}"
VALUES_FILE="${VALUES_FILE:-$SCRIPT_DIR/velero-values.yaml}"
RELEASE="${RELEASE:-velero}"
CHART="${CHART:-vmware-tanzu/velero}"
TIMEOUT="${TIMEOUT:-5m}"

print_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  --namespace NAMESPACE   Kubernetes namespace (default: ${NAMESPACE})
  --credentials FILE      File with cloud credentials (default: ${CREDENTIALS_FILE})
  --values FILE           Helm values file (default: ${VALUES_FILE})
  --release NAME          Helm release name (default: ${RELEASE})
  --chart CHART           Helm chart to install (default: ${CHART})
  --timeout DURATION      Helm wait timeout (default: ${TIMEOUT})
  -h, --help              Show this help and exit
EOF
}

while [[ ${#} -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2;;
    --credentials) CREDENTIALS_FILE="$2"; shift 2;;
    --values) VALUES_FILE="$2"; shift 2;;
    --release) RELEASE="$2"; shift 2;;
    --chart) CHART="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    -h|--help) print_help; exit 0;;
    *) echo "Unknown arg: $1"; print_help; exit 2;;
  esac
done

for cmd in kubectl helm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found in PATH" >&2
    exit 1
  fi
done

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "Error: credentials file not found: $CREDENTIALS_FILE" >&2
  exit 1
fi

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Error: values file not found: $VALUES_FILE" >&2
  exit 1
fi

echo "Ensuring namespace '$NAMESPACE' exists..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  kubectl create namespace "$NAMESPACE"
fi

SECRET_MANIFEST="$SCRIPT_DIR/velero-repo-secret.yaml"
if [[ -f "$SECRET_MANIFEST" ]]; then
  echo "Applying secret manifest: $SECRET_MANIFEST"
  kubectl apply -f "$SECRET_MANIFEST"
else
  echo "Creating secret 'velero-repo-credentials' in namespace '$NAMESPACE' from file: $CREDENTIALS_FILE"
  kubectl -n "$NAMESPACE" delete secret velero-repo-credentials --ignore-not-found
  kubectl -n "$NAMESPACE" create secret generic velero-repo-credentials --from-file=cloud="$CREDENTIALS_FILE"
fi

# # Add Velero repo if using vmware-tanzu/velero
# if [[ "$CHART" == vmware-tanzu/* ]]; then
#   if ! helm repo list | grep -q 'vmware-tanzu'; then
#     echo "Adding vmware-tanzu repo..."
#     helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
#   fi
#   helm repo update
# fi

echo "Installing/upgrading Helm release '$RELEASE' in namespace '$NAMESPACE'..."
helm upgrade --install "$RELEASE" "$CHART" -n "$NAMESPACE" -f "$VALUES_FILE" --wait --timeout "$TIMEOUT"

echo "Done. Check Velero pods: kubectl -n $NAMESPACE get pods"
