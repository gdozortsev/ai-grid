#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSHELL_DIR="${SCRIPT_DIR}/OpenShell"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}==>${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}ERROR:${NC} $*"
}

PRAXIS_ENDPOINT="${OPENSHELL_PRAXIS_ENDPOINT:-http://host.containers.internal:8080}"
POLICY_DATA="${OPENSHELL_POLICY_DATA:-${SCRIPT_DIR}/praxis-poc-policy.yaml}"
POLICY_RULES="${OPENSHELL_POLICY_RULES:-${OPENSHELL_DIR}/crates/openshell-supervisor-network/data/sandbox-policy.rego}"
LOG_LEVEL="${OPENSHELL_LOG_LEVEL:-info}"
BUILD="${BUILD:-yes}"

# Parse arguments
INTERACTIVE=false
COMMAND="bash"

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        --no-build)
            BUILD=no
            shift
            ;;
        --endpoint)
            PRAXIS_ENDPOINT="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        -h|--help)
            cat <<EOF
Usage: $0 [OPTIONS] [COMMAND]

Test the Praxis integration POC using Podman.

Options:
  -i, --interactive     Run in interactive mode
  --no-build           Skip building the image
  --endpoint URL       Praxis endpoint (default: http://localhost:9090)
  --log-level LEVEL    Log level (default: info)
  -h, --help           Show this help message

Environment Variables:
  OPENSHELL_PRAXIS_ENDPOINT   Praxis control endpoint
  OPENSHELL_POLICY_DATA       Path to policy YAML file
  OPENSHELL_POLICY_RULES      Path to Rego rules file
  OPENSHELL_LOG_LEVEL         Log level (trace, debug, info, warn, error)
  BUILD                       Set to 'no' to skip build

EOF
            exit 0
            ;;
        *)
            COMMAND="$*"
            break
            ;;
    esac
done

# Build the image
if [[ "${BUILD}" == "yes" ]]; then
    log_info "Building supervisor test image with binaries..."
    cd "${OPENSHELL_DIR}"

    PREBUILT_BINARY="deploy/docker/.build/prebuilt-binaries/arm64/openshell-sandbox"
    if [[ ! -f "${PREBUILT_BINARY}" ]]; then
        log_error "Prebuilt Linux binary not found at ${PREBUILT_BINARY}"
        log_error "Run 'mise run build:docker:prebuilt' first"
        exit 1
    fi
    log_info "Using prebuilt Linux ARM64 binary ✓"

    log_info "Building Podman image with Praxis sidecar..."
    cd "${SCRIPT_DIR}"

    podman build -f Dockerfile.supervisor-test \
        --build-arg TARGETARCH=arm64 \
        -t localhost/openshell/supervisor:test \
        .

    if [[ $? -ne 0 ]]; then
        log_error "Failed to build supervisor test image"
        exit 1
    fi

    log_info "Build complete ✓"
    echo ""
else
    log_info "Skipping build (--no-build or BUILD=no)"
fi

PODMAN_ARGS=(
    "run"
    "--rm"
)

if [[ "${INTERACTIVE}" == "true" ]]; then
    PODMAN_ARGS+=("-it")
fi

PODMAN_ARGS+=(
    "--cap-add" "NET_ADMIN"
    "--cap-add" "SYS_ADMIN"
    "-e" "OPENSHELL_NETWORK_MODE=external"
    "-e" "OPENSHELL_PRAXIS_ENDPOINT=${PRAXIS_ENDPOINT}"
    "-e" "OPENSHELL_LOG_LEVEL=${LOG_LEVEL}"
    "-v" "${POLICY_DATA}:/policy.yaml:ro"
    "-v" "${POLICY_RULES}:/policy.rego:ro"
    "localhost/openshell/supervisor:test"
    "--mode" "network,process"
    "--policy-rules" "/policy.rego"
    "--policy-data" "/policy.yaml"
)

if [[ "${INTERACTIVE}" == "true" ]]; then
    PODMAN_ARGS+=("--interactive")
fi

if [[ -n "${COMMAND}" ]]; then
    read -ra CMD_ARRAY <<< "${COMMAND}"
    PODMAN_ARGS+=("${CMD_ARRAY[@]}")
fi

# Display configuration
log_info "Configuration:"
echo "  OpenShell dir:   ${OPENSHELL_DIR}"
echo "  Praxis endpoint: ${PRAXIS_ENDPOINT}"
echo "  Policy data:     ${POLICY_DATA}"
echo "  Policy rules:    ${POLICY_RULES}"
echo "  Log level:       ${LOG_LEVEL}"
echo "  Interactive:     ${INTERACTIVE}"
echo "  Command:         ${COMMAND}"
echo ""

# Run the container
log_info "Starting sandbox with external network mode..."
echo ""
log_info "Running: podman ${PODMAN_ARGS[*]}"
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

exec podman "${PODMAN_ARGS[@]}"

