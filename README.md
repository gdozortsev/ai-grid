# Run OpenShell Sandbox in External Mode with Praxis Sidecar

## Prerequisites
1. Running Podman/Docker machine

## Quickstart

Cloning for this first time? Run this to initialize OpenShell:
```bash
git submodule update --init --recursive
```

To start, run the following commands to build the environment
```bash
#Build the prebuilt supervisor binary
cd OpenShell

# 1. Build Linux supervisor binary (for containers)
mise run build:docker:prebuilt

#For MacOS, otherwise the cli won't compile
export Z3_SYS_Z3_HEADER=/opt/homebrew/opt/z3/include/z3.h
export BINDGEN_EXTRA_CLANG_ARGS="-I/opt/homebrew/opt/z3/include -I/usr/include/z3"
export LIBRARY_PATH=/opt/homebrew/opt/z3/lib:${LIBRARY_PATH:-}
export RUSTFLAGS="-L /opt/homebrew/opt/z3/lib"

# 2. compile the CLI
cargo build -p openshell-cli

#Build the Praxis supervisor image (with default deny config):
cd ..
podman build -f Dockerfile.supervisor-test -t localhost/openshell/supervisor:praxis-test .

#or, pass in your own config for Praxis:
podman build -f Dockerfile.supervisor-test --build-arg PRAXIS_CONFIG=/PATH/TO/CONFIG -t localhost/openshell/supervisor:praxis-test .

#Start the gateway
./run-mtls-gateway.sh
```


Now, we have a running gateway and all our binaries are built.
Open up a new terminal (the first one has the gateway running)

## Control: Running a sandbox with Openshell's proxy

To create a normal OpenShell sandbox without Praxis, run
```bash
OpenShell/target/debug/openshell sandbox create
```

Then, try to run a curl command in the sandbox, for example
```bash
curl http://142.250.190.46
```

This should return,
```text
{"detail":"GET 142.250.190.46:80/ not permitted by policy","error":"policy_denied"}
```

so the curl was blocked by OpenShell.

### Cleanup: exit out of the sandbox, run:
```bash
OpenShell/target/debug/openshell sandbox delete --all
```

## POC Test: Running a sandbox with Praxis as the proxy

```bash
./route-through-praxis.sh
```
This should drop you into a sandbox. Try to run a curl command, for example:
```bash
curl http://142.250.190.46
```

This should return,
```text
{"status": "ok", "server": "praxis-sidecar"}
```
so the curl was blocked by Praxis!! 🎉🎉

### Praxis logs
If you want to see the praxis logs, they are in /tmp/praxis.log inside the sandbox

In a separate terminal, connect to the sandbox
```bash
OpenShell/target/debug/openshell sandbox connect
```
then run
```bash
tail -f /tmp/praxis.log
```
If you run the curl command again in your original sandbox terminal, you'll see the request in the logs.

```text
2026-07-02T14:42:00.794570Z DEBUG praxis_filter::pipeline::http: filter rejected request filter="static_response" status=200
2026-07-02T14:42:00.794602Z DEBUG praxis_protocol::http::pingora::convert: sending rejection response status=200
```

### Cleanup: exit out of the sandbox, run:
```bash
OpenShell/target/debug/openshell sandbox delete --all
```