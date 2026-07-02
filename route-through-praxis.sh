#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSHELL_DIR="${SCRIPT_DIR}/OpenShell"
OPENSHELL_CLI="${OPENSHELL_DIR}/target/debug/openshell"

# Configuration
PRAXIS_ENDPOINT="${OPENSHELL_PRAXIS_ENDPOINT:-http://host.containers.internal:8080}"
POLICY_DATA="${OPENSHELL_POLICY_DATA:-${SCRIPT_DIR}/praxis-poc-policy.yaml}"
LOG_LEVEL="${OPENSHELL_LOG_LEVEL:-info}"
SANDBOX_NAME="${OPENSHELL_SANDBOX_NAME:-praxis-test-$(date +%s)}"
KEEP_SANDBOX="${KEEP:-yes}"



# Build CLI arguments
# Use localhost/openshell/supervisor:praxis-test as the base image
CLI_ARGS=(
    "sandbox" "create"
    "--name" "${SANDBOX_NAME}"
    "--from" "localhost/openshell/supervisor:praxis-test"
    "--policy" "${POLICY_DATA}"
)

if [[ "${KEEP_SANDBOX}" == "yes" ]]; then
    CLI_ARGS+=("--keep")
fi

"${OPENSHELL_CLI}" "${CLI_ARGS[@]}"
EXIT_CODE=$?

exit ${EXIT_CODE}