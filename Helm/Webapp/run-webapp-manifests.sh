#!/usr/bin/env bash
set -euo pipefail

# Usage: ./run-nginx-manifests.sh [--manifests-dir DIR] [--wait-seconds N]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${MANIFESTS_DIR:-$SCRIPT_DIR}"
WAIT_SECONDS="${WAIT_SECONDS:-60}"

print_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  --manifests-dir DIR   Directory with manifests (default: ${MANIFESTS_DIR})
  --wait-seconds N      Seconds to wait for pods to become ready after apply (default: ${WAIT_SECONDS})
  -h, --help            Show this help and exit
EOF
}

while [[ ${#} -gt 0 ]]; do
  case "$1" in
    --manifests-dir) MANIFESTS_DIR="$2"; shift 2;;
    --wait-seconds) WAIT_SECONDS="$2"; shift 2;;
    -h|--help) print_help; exit 0;;
    *) echo "Unknown arg: $1"; print_help; exit 2;;
  esac
done

for cmd in kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found in PATH" >&2
    exit 1
  fi
done

NAMESPACE_FILE="$MANIFESTS_DIR/namespace.yaml"
POSTGRES_SVC_FILE="$MANIFESTS_DIR/postgres-service.yaml"
POSTGRES_STATEFULSET_FILE="$MANIFESTS_DIR/postgres-statefulset.yaml"
WEBAPP_CONFIGMAP="$MANIFESTS_DIR/webapp-configmap.yaml"
WEBAPP_DEPLOY="$MANIFESTS_DIR/webapp-deployment.yaml"
WEBAPP_SVC="$MANIFESTS_DIR/webapp-service.yaml"

for f in "$NAMESPACE_FILE" "$POSTGRES_SVC_FILE" "$POSTGRES_STATEFULSET_FILE" \
         "$WEBAPP_CONFIGMAP" "$WEBAPP_DEPLOY" "$WEBAPP_SVC" ; do
  if [[ ! -f "$f" ]]; then
    echo "Error: required manifest not found: $f" >&2
    exit 1
  fi
done

echo "Applying namespace..."
kubectl apply -f "$NAMESPACE_FILE"

echo "Applying Postgres service and StatefulSet..."
kubectl apply -f "$POSTGRES_SVC_FILE"
kubectl apply -f "$POSTGRES_STATEFULSET_FILE"

echo "Waiting for Postgres to be ready..."
ns=$(grep -E '^[[:space:]]*name:' "$NAMESPACE_FILE" | head -n1 | awk -F: '{print $2}' | xargs || true)
kubectl -n "$ns" wait --for=condition=ready pod -l app=postgres --timeout="${WAIT_SECONDS}s" || echo "Postgres not ready within timeout"

echo "Applying webapp (ConfigMap, Deployment, Service)..."
kubectl apply -f "$WEBAPP_CONFIGMAP"
kubectl apply -f "$WEBAPP_DEPLOY"
kubectl apply -f "$WEBAPP_SVC"

echo "Waiting for webapp to be ready..."
kubectl -n "$ns" wait --for=condition=ready pod -l app=webapp --timeout="${WAIT_SECONDS}s" || echo "Webapp not ready within timeout"

echo "Done."
