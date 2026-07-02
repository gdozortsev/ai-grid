set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/OpenShell" && pwd)"
GATEWAY_BIN="${ROOT}/target/debug/openshell-gateway"
STATE_DIR="${ROOT}/.cache/gateway-podman-mtls"
TLS_DIR="${HOME}/.local/state/openshell/tls"
# Default to Praxis-enabled supervisor (supports both standard and Praxis modes)
SUPERVISOR_IMAGE="${OPENSHELL_SUPERVISOR_IMAGE:-localhost/openshell/supervisor:praxis-test}"

cd "${ROOT}"

# Set up build environment for macOS Homebrew dependencies
export PROTOC=/opt/homebrew/bin/protoc
export Z3_SYS_Z3_HEADER=/opt/homebrew/opt/z3/include/z3.h
# Override .cargo/config.toml BINDGEN_EXTRA_CLANG_ARGS with macOS path
export BINDGEN_EXTRA_CLANG_ARGS="-I/opt/homebrew/opt/z3/include -I/usr/include/z3"
export LIBRARY_PATH=/opt/homebrew/opt/z3/lib:${LIBRARY_PATH:-}
export RUSTFLAGS="-L /opt/homebrew/opt/z3/lib"

echo "Building openshell-gateway..."
# Bypass mise task to ensure environment variables are passed to cargo
cargo build -p openshell-server --bin openshell-gateway

# Create state directory and config
mkdir -p "${STATE_DIR}"

# Allow overriding supervisor image via env var for Praxis testing
SUPERVISOR_IMAGE_OVERRIDE="${OPENSHELL_SUPERVISOR_IMAGE_OVERRIDE:-${SUPERVISOR_IMAGE}}"

cat > "${STATE_DIR}/gateway.toml" <<EOF
[openshell]
version = 1

[openshell.gateway]
compute_drivers = ["podman"]
default_image = "ghcr.io/nvidia/openshell-community/sandboxes/base:latest"
supervisor_image = "${SUPERVISOR_IMAGE_OVERRIDE}"

[openshell.drivers.podman]
image_pull_policy = "missing"
EOF

# Register gateway metadata with CLI
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
GATEWAY_DIR="${CONFIG_HOME}/openshell/gateways/podman-mtls"
MTLS_DIR="${GATEWAY_DIR}/mtls"

mkdir -p "${MTLS_DIR}"

# Copy client certificates to gateway config directory
cp "${TLS_DIR}/ca.crt" "${MTLS_DIR}/"
cp "${TLS_DIR}/client/tls.crt" "${MTLS_DIR}/"
cp "${TLS_DIR}/client/tls.key" "${MTLS_DIR}/"

cat > "${GATEWAY_DIR}/metadata.json" <<EOF
{
  "name": "podman-mtls",
  "gateway_endpoint": "https://127.0.0.1:18080",
  "is_remote": false,
  "gateway_port": 18080
}
EOF

printf 'podman-mtls' > "${CONFIG_HOME}/openshell/active_gateway"

echo "Starting Podman gateway with mTLS..."
echo "  gateway:   podman-mtls"
echo "  endpoint:  https://127.0.0.1:18080"
echo "  state dir: ${STATE_DIR}"
echo "  TLS mode:  mTLS (mutual TLS authentication)"
echo ""
echo "Active gateway set to 'podman-mtls'. The CLI now targets this gateway by default."
echo ""

exec "${GATEWAY_BIN}" \
  --config "${STATE_DIR}/gateway.toml" \
  --port 18080 \
  --tls-cert "${TLS_DIR}/server/tls.crt" \
  --tls-key "${TLS_DIR}/server/tls.key" \
  --tls-client-ca "${TLS_DIR}/ca.crt" \
  --log-level info \
  --drivers podman \
  --db-url "sqlite:${STATE_DIR}/gateway.db?mode=rwc"
