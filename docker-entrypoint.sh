#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# This wrapper is called by the gateway when the supervisor image is mounted
# at /opt/openshell/bin. All paths are relative to that mount point.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# Determine if we should use Praxis mode by checking if Praxis binary exists in the BASE image
# Praxis only exists when using --from localhost/openshell/supervisor:praxis-test
# The image root is mounted at SCRIPT_DIR, so check both locations:
# 1. In the supervisor mount: SCRIPT_DIR/usr/local/bin/praxis (exists for all sandboxes)
# 2. In the base container: /usr/local/bin/praxis (only exists for Praxis base image)
PRAXIS_IN_BASE="/usr/local/bin/praxis"
USE_PRAXIS_MODE=false

if [[ -x "${PRAXIS_IN_BASE}" ]]; then
    USE_PRAXIS_MODE=true
    echo "[docker-entrypoint] ✓ Praxis binary found in base image - enabling Praxis mode"
fi

# Start Praxis sidecars
if [[ "${USE_PRAXIS_MODE}" == "true" ]]; then
    echo "[docker-entrypoint] Starting Praxis sidecar on 0.0.0.0:8080 as sandbox user..."
    echo "[docker-entrypoint] Using Praxis binary: ${PRAXIS_IN_BASE}"

    echo "[docker-entrypoint] Spawning Praxis process..."
    su -s /bin/bash sandbox -c "RUST_LOG=praxis=debug,praxis_protocol=debug ${PRAXIS_IN_BASE} --config /etc/praxis-config.yaml > /tmp/praxis.log 2>&1 &"

    # Wait for Praxis to be ready (TCP listener, so check with netcat)
    echo "[docker-entrypoint] Waiting for Praxis to be ready..."
    for i in {1..5}; do
        if nc -z 127.0.0.1 8080 2>/dev/null; then
            echo "[docker-entrypoint] Praxis sidecar ready on 0.0.0.0:8080 ✓"
            break
        fi
        echo "[docker-entrypoint] Waiting for Praxis (attempt $i/5)..."
        sleep 1
    done
fi

# Start DNS forwarder so the sandbox netns can resolve hostnames.
# The sandbox netns has iptables DNAT rules redirecting port 53 to the veth
# host side (10.200.0.1:53). socat forwards those queries to the Podman DNS.
if [[ "${USE_PRAXIS_MODE}" == "true" ]]; then
    PODMAN_DNS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
    echo "[docker-entrypoint] Starting DNS forwarder (UDP+TCP) on :5353 → ${PODMAN_DNS}:53"
    socat UDP4-LISTEN:5353,fork,reuseaddr UDP4:${PODMAN_DNS}:53 &
    socat TCP4-LISTEN:5353,fork,reuseaddr TCP4:${PODMAN_DNS}:53 &
fi

# Run supervisor as root (needs privileges for netns/iptables)
# The real supervisor binary is in the same directory as this script
SUPERVISOR_BIN="${SCRIPT_DIR}/openshell-sandbox.real"
PRAXIS_POLICY_YAML="${SCRIPT_DIR}/etc/openshell-praxis-policy.yaml"
PRAXIS_POLICY_REGO="${SCRIPT_DIR}/etc/openshell-praxis-policy.rego"

echo "[docker-entrypoint] Starting supervisor: ${SUPERVISOR_BIN}"

# Conditional mode based on whether Praxis exists in the base image
if [[ "${USE_PRAXIS_MODE}" == "true" ]] && [[ -f "${PRAXIS_POLICY_YAML}" ]] && [[ -f "${PRAXIS_POLICY_REGO}" ]]; then
    echo "[docker-entrypoint] ✓ Using Praxis external network mode"
    echo "[docker-entrypoint]   Policy YAML: ${PRAXIS_POLICY_YAML}"
    echo "[docker-entrypoint]   Policy Rego: ${PRAXIS_POLICY_REGO}"
    # Pass both files to force local policy mode (bypasses gRPC, reads network.mode from YAML)
    exec "${SUPERVISOR_BIN}" --policy-data "${PRAXIS_POLICY_YAML}" --policy-rules "${PRAXIS_POLICY_REGO}" "$@"
else
    echo "[docker-entrypoint] ✓ Using standard gRPC policy mode"
    # Standard mode: supervisor will fetch policy via gRPC from gateway
    exec "${SUPERVISOR_BIN}" "$@"
fi