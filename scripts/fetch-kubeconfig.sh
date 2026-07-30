#!/usr/bin/env bash
# Fetch admin kubeconfig from leader-01 with API server via HAProxy LB.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Fetch K3s kubeconfig from the first leader and point server: at the HAProxy LB.

Options:
  -o, --output PATH   Output file (default: kubeconfigs/<env>.kubeconfig)
  -h, --help          Show this help

Example:
  export KUBECONFIG=\$(pwd)/kubeconfigs/<env-id>.kubeconfig
  kubectl get nodes -o wide
EOF
}

OUTPUT="$(kubeconfig_path)"
SHOW_SUMMARY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --summary) SHOW_SUMMARY=true; shift ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

load_secrets
fetch_kubeconfig "${OUTPUT}"

if ${SHOW_SUMMARY}; then
  show_kubeconfig_summary "${OUTPUT}"
fi
