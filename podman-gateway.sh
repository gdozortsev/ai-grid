#!/usr/bin/env bash
# Start OpenShell gateway with Podman and mTLS

set -euo pipefail

# Configuration
PORT="${OPENSHELL_PORT:-17670}"
GATEWAY_NAME="${OPENSHELL_GATEWAY_NAME:-podman-dev}"
STATE_DIR="${OPENSHELL_STATE_DIR:-${HOME}/.openshell/gateway-podman}"
SANDBOX_IMAGE="${OPENSHELL_SANDBOX_IMAGE:-ghcr.io/nvidia/openshell-community/sandboxes/base:latest}"
SUPERVISOR_IMAGE="${OPENSHELL_SUPERVISOR_IMAGE:-ghcr.io/nvidia/openshell/supervisor:latest}"
TLS_DIR="${HOME}/.openshell/tls"

mkdir -p "${STATE_DIR}"

# Create gateway config file
CONFIG_PATH="${STATE_DIR}/gateway.toml"
cat >"${CONFIG_PATH}" <<EOF
[openshell]
version = 1

[openshell.gateway]
bind_address = "0.0.0.0:${PORT}"
log_level = "info"
compute_drivers = ["podman"]
disable_tls = false

[openshell.gateway.tls]
cert_path = "${TLS_DIR}/server/tls.crt"
key_path = "${TLS_DIR}/server/tls.key"
client_ca_path = "${TLS_DIR}/ca.crt"

[openshell.drivers.podman]
default_image = "${SANDBOX_IMAGE}"
supervisor_image = "${SUPERVISOR_IMAGE}"
image_pull_policy = "missing"
network_name = "openshell"
grpc_endpoint = "https://host.docker.internal:${PORT}"
guest_tls_ca = "${TLS_DIR}/ca.crt"
guest_tls_cert = "${TLS_DIR}/client/tls.crt"
guest_tls_key = "${TLS_DIR}/client/tls.key"
EOF

echo "Starting OpenShell gateway with Podman and mTLS..."
echo "  Gateway:  ${GATEWAY_NAME}"
echo "  Port:     ${PORT}"
echo "  State:    ${STATE_DIR}"
echo "  Config:   ${CONFIG_PATH}"
echo "  TLS:      enabled"
echo ""

# Register gateway metadata for CLI
config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
gateway_dir="${config_home}/openshell/gateways/${GATEWAY_NAME}"
mkdir -p "${gateway_dir}"
cat >"${gateway_dir}/metadata.json" <<EOF
{
  "name": "${GATEWAY_NAME}",
  "gateway_endpoint": "https://127.0.0.1:${PORT}",
  "is_remote": false,
  "gateway_port": ${PORT},
  "auth_mode": "mtls"
}
EOF

# Copy mTLS certificates to CLI config
mkdir -p "${gateway_dir}/mtls"
cp "${TLS_DIR}/ca.crt" "${gateway_dir}/mtls/ca.crt"
cp "${TLS_DIR}/client/tls.crt" "${gateway_dir}/mtls/tls.crt"
cp "${TLS_DIR}/client/tls.key" "${gateway_dir}/mtls/tls.key"

# Start the gateway with config file
# Note: Use host.docker.internal which is in the server cert SAN
# (Podman accepts this alias even though it typically uses host.containers.internal)
exec openshell-gateway \
  --config "${CONFIG_PATH}" \
  --db-url "sqlite:${STATE_DIR}/gateway.db?mode=rwc"
