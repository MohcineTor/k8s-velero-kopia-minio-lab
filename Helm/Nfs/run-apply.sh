#!/usr/bin/env bash
set -euo pipefail

# Robust installer for NFS CSI driver and local manifests
# Usage: ./run-apply.sh [--version vX.Y.Z] [--sleep SECONDS] [--manifests-dir DIR]

CSI_VERSION="${CSI_VERSION:-v4.11.0}"
SLEEP_AFTER_INSTALL="${SLEEP_AFTER_INSTALL:-20}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${MANIFESTS_DIR:-$SCRIPT_DIR}"

print_help() {
	cat <<EOF
Usage: $0 [options]

Options:
	--version VERSION       CSI driver version (default: ${CSI_VERSION})
	--sleep SECONDS         Seconds to wait after driver install (default: ${SLEEP_AFTER_INSTALL})
	--manifests-dir DIR     Directory containing local manifest files (default: ${MANIFESTS_DIR})
	-h, --help              Show this help and exit

This script will:
	1) Install the NFS CSI driver using the upstream install script
	2) Wait a short time for components to initialize
	3) Apply local manifests (namespace, service, nfserver, storageclass)
EOF
}

while [[ ${#} -gt 0 ]]; do
	case "$1" in
		--version) CSI_VERSION="$2"; shift 2;;
		--sleep) SLEEP_AFTER_INSTALL="$2"; shift 2;;
		--manifests-dir) MANIFESTS_DIR="$2"; shift 2;;
		-h|--help) print_help; exit 0;;
		*) echo "Unknown argument: $1" >&2; print_help; exit 2;;
	esac
done

for cmd in curl bash kubectl; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Error: required command '$cmd' not found in PATH" >&2
		exit 1
	fi
done

echo "Installing NFS CSI driver (version: ${CSI_VERSION})"
curl -sSL "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/${CSI_VERSION}/deploy/install-driver.sh" | bash -s "${CSI_VERSION}" --

if [[ -n "$SLEEP_AFTER_INSTALL" && "$SLEEP_AFTER_INSTALL" -gt 0 ]]; then
	echo "Waiting ${SLEEP_AFTER_INSTALL}s for the driver to initialize..."
	sleep "$SLEEP_AFTER_INSTALL"
fi

echo "Applying local manifests from: ${MANIFESTS_DIR}"

files=(Nfs-namespace.yaml Nfs-service.yaml Nfs-server.yaml Nfs-storageclass.yaml)
for f in "${files[@]}"; do
	path="$MANIFESTS_DIR/$f"
	if [[ ! -f "$path" ]]; then
		echo "Error: manifest not found: $path" >&2
		exit 1
	fi
	echo "Applying $f"
	kubectl apply -f "$path"
done

echo "All done. You can verify resources with: kubectl get all -n <namespace> and kubectl get storageclass"
