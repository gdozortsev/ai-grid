#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Start Praxis sidecar on 0.0.0.0:8080 (accessible from netns via veth)
# Run as sandbox user (Praxis refuses to run as root)
if command -v praxis >/dev/null 2>&1; then
    echo "Starting Praxis sidecar on 0.0.0.0:8080 as sandbox user..."

    # Create Praxis config that binds to 0.0.0.0 (accessible from netns)
    # Use /etc instead of /tmp to avoid tmpfs triggering constant reloads
    cat > /etc/praxis-config.yaml <<'EOF'
admin:
  address: "127.0.0.1:9901"

listeners:
  - name: default
    address: "0.0.0.0:8080"
    filter_chains:
      - default-response

filter_chains:
  - name: default-response
    filters:
      - filter: static_response
        status: 200
        headers:
          - name: Content-Type
            value: application/json
        body: '{"status": "ok", "server": "praxis-sidecar"}'
        conditions:
          - when:
              path: "/"
      - filter: static_response
        status: 404
        headers:
          - name: Content-Type
            value: application/json
        body: '{"error": "not found"}'
EOF

    # Run Praxis as sandbox user (not root) with custom config
    # Set RUST_LOG=debug to see request logs
    su -s /bin/bash sandbox -c "RUST_LOG=praxis=debug,praxis_protocol=debug praxis --config /etc/praxis-config.yaml > /tmp/praxis.log 2>&1 &"
    PRAXIS_PID=$!

    # Wait for Praxis to be ready
    for i in {1..5}; do
        if curl -s http://127.0.0.1:8080/ > /dev/null 2>&1; then
            echo "Praxis sidecar ready on 0.0.0.0:8080"
            break
        fi
        sleep 1
    done
fi

# Run supervisor as root (needs privileges for netns/iptables)
exec /openshell-sandbox "$@"
