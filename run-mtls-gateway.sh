set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/OpenShell" && pwd)"
GATEWAY_BIN="${ROOT}/target/debug/openshell-gateway"
STATE_DIR="${ROOT}/.cache/gateway-podman-mtls"
TLS_DIR="${HOME}/.local/state/openshell/tls"
SUPERVISOR_IMAGE="${OPENSHELL_SUPERVISOR_IMAGE:-openshell/supervisor:dev}"

cd "${ROOT}"


echo "Building openshell-gateway..."
mise run build:gateway

if [[ ! -x "${GATEWAY_BIN}" ]]; then
  echo "ERROR: expected gateway binary at ${GATEWAY_BIN}" >&2
  exit 1
fi

# Check if TLS certificates exist
if [[ ! -f "${TLS_DIR}/ca.crt" ]]; then
  echo "ERROR: TLS certificates not found at ${TLS_DIR}" >&2
  echo "Generate them first with:" >&2
  echo "  ./target/debug/openshell-gateway generate-certs --output-dir ~/.local/state/openshell/tls" >&2
  exit 1
fi

# Ensure Podman service is running
if ! command -v podman >/dev/null 2>&1; then
  echo "ERROR: podman is not installed or not in PATH" >&2
  exit 1
fi

if ! podman info >/dev/null 2>&1; then
  echo "ERROR: podman service is not reachable. Start it with:" >&2
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "  podman machine start" >&2
  else
    echo "  systemctl --user start podman.socket" >&2
  fi
  exit 1
fi

# Ensure supervisor image exists
if ! podman image exists "${SUPERVISOR_IMAGE}" >/dev/null 2>&1; then
  echo "Building Podman supervisor sideload image (${SUPERVISOR_IMAGE})..."
  CONTAINER_ENGINE=podman IMAGE_TAG=dev mise run build:docker:supervisor
fi

# Create state directory and config
mkdir -p "${STATE_DIR}"
cat > "${STATE_DIR}/gateway.toml" <<EOF
[openshell]
version = 1

[openshell.gateway]
compute_drivers = ["podman"]
default_image = "ghcr.io/nvidia/openshell-community/sandboxes/base:latest"
supervisor_image = "${SUPERVISOR_IMAGE}"

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
