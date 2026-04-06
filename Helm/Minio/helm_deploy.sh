#!/usr/bin/env bash
set -euo pipefail

# Deploy script: apply Minio secret first, then deploy Minio Helm chart using values file
# Usage: ./helm_deploy.sh [--namespace NAMESPACE] [--secret FILE] [--values FILE] [--release NAME] [--chart CHART]

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAMESPACE="${NAMESPACE:-minio}"
SECRET_FILE="${SECRET_FILE:-$script_dir/Minio-secrets.yaml}"
VALUES_FILE="${VALUES_FILE:-$script_dir/Minio-values.yaml}"
RELEASE="${RELEASE:-minio}"
CHART="${CHART:-bitnami/minio}"
TIMEOUT="${TIMEOUT:-5m}"

print_help() {
	cat <<EOF
Usage: $0 [options]

Options:
	--namespace NAMESPACE   Kubernetes namespace (default: ${NAMESPACE})
	--secret FILE           Secret manifest file to apply (default: ${SECRET_FILE})
	--values FILE           Helm values file (default: ${VALUES_FILE})
	--release NAME          Helm release name (default: ${RELEASE})
	--chart CHART           Helm chart to install (default: ${CHART})
	--timeout DURATION      Helm wait timeout (default: ${TIMEOUT})
	-h, --help              Show this help and exit

Environment variables with the same names will override defaults.
EOF
}

while [[ ${#} -gt 0 ]]; do
	case "$1" in
		--namespace) NAMESPACE="$2"; shift 2;;
		--secret) SECRET_FILE="$2"; shift 2;;
		--values) VALUES_FILE="$2"; shift 2;;
		--release) RELEASE="$2"; shift 2;;
		--chart) CHART="$2"; shift 2;;
		--timeout) TIMEOUT="$2"; shift 2;;
		-h|--help) print_help; exit 0;;
		*) echo "Unknown arg: $1"; print_help; exit 2;;
	esac
done

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

for cmd in kubectl helm grep awk sed; do
	if ! cmd_exists "$cmd"; then
		echo "Error: required command '$cmd' not found in PATH" >&2
		exit 1
	fi
done

if [[ ! -f "$SECRET_FILE" ]]; then
	echo "Error: secret file not found: $SECRET_FILE" >&2
	exit 1
fi

if [[ ! -f "$VALUES_FILE" ]]; then
	echo "Error: values file not found: $VALUES_FILE" >&2
	exit 1
fi

# If the secret manifest declares a namespace, use it (so we apply exactly where the manifest expects)
file_ns=$(grep -E '^[[:space:]]*namespace:' "$SECRET_FILE" | head -n1 | awk -F: '{print $2}' | xargs || true)
if [[ -n "$file_ns" ]]; then
	NAMESPACE="$file_ns"
fi

# Parse secret name from manifest (metadata.name)
secret_name=$(grep -E '^[[:space:]]*name:' "$SECRET_FILE" | head -n1 | awk -F: '{print $2}' | xargs || true)
if [[ -z "$secret_name" ]]; then
	echo "Warning: could not parse secret name from $SECRET_FILE. The script will proceed but wait step may be skipped." >&2
fi

echo "Using namespace: $NAMESPACE"
echo "Secret file: $SECRET_FILE"
echo "Values file: $VALUES_FILE"
echo "Helm release: $RELEASE"
echo "Helm chart: $CHART"

echo "Ensuring namespace '$NAMESPACE' exists..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
	kubectl create namespace "$NAMESPACE"
fi

echo "Applying secret manifest..."
# Apply as-is (manifest may contain its own namespace)
kubectl apply -f "$SECRET_FILE"

if [[ -n "$secret_name" ]]; then
	echo "Waiting for secret '$secret_name' in namespace '$NAMESPACE'..."
	retries=30
	wait_sec=2
	i=0
	while ! kubectl -n "$NAMESPACE" get secret "$secret_name" >/dev/null 2>&1; do
		i=$((i+1))
		if [[ $i -ge $retries ]]; then
			echo "Timed out waiting for secret '$secret_name' in namespace '$NAMESPACE'" >&2
			kubectl -n "$NAMESPACE" get secret --no-headers || true
			exit 1
		fi
		sleep $wait_sec
	done
	echo "Secret '$secret_name' present."
fi

# # If chart looks like a repo/chart, ensure common repos are available (handle bitnami explicitly)
# if [[ "$CHART" == bitnami/* ]]; then
# 	if ! helm repo list | grep -q 'bitnami'; then
# 		echo "Adding Bitnami repo..."
# 		helm repo add bitnami https://charts.bitnami.com/bitnami
# 	fi
# 	helm repo update
# fi

echo "Installing/upgrading Helm release '$RELEASE' in namespace '$NAMESPACE'..."
helm upgrade --install "$RELEASE" "$CHART" \
	-n "$NAMESPACE" \
	-f "$VALUES_FILE" \
	--wait --timeout "$TIMEOUT"

echo "Helm deployment complete. To inspect resources run:"
echo "  kubectl -n $NAMESPACE get all"

