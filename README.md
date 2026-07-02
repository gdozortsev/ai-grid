# Run OpenShell in External Mode with Praxis Sidecar

## Prerequisites
1. Running Podman/Docker machine
2. Running OpenShell gateway (can be run with run-mtls-gateway.sh script)
3. Compiled Praxis Linux (Ubuntu) Binary

## Quickstart

Cloning for this first time? Run this to initialize OpenShell:
```bash
git submodule update --init --recursive
```

TERMINAL A:
Instructions for running in interactive mode:
```bash
#build OpenShell
cd OpenShell && mise run build:docker:prebuilt

#run Praxis x OpenShell
cd ..
./test-praxis-podman.sh --log-level info -i
```

TERMINAL B:
Open up a second terminal, run podman ps -a and copy the CONTAINER_ID
Then run:
```bash
podman exec <CONTAINER_ID> tail -f /tmp/praxis.log
```

Running a curl command inside the interactive terminal should return
{"status": "ok", "server": "praxis-sidecar"} on the interactive terminal side, 
and should show in the praxis logs in the second terminal


For example, running this on Terminal A
```bash
curl http://142.250.190.46
```
should return (on Terminal A): 
```text
{"status": "ok", "server": "praxis-sidecar"}
```

and should show (on Terminal B):

```text
2026-07-02T14:42:00.794570Z DEBUG praxis_filter::pipeline::http: filter rejected request filter="static_response" status=200
2026-07-02T14:42:00.794602Z DEBUG praxis_protocol::http::pingora::convert: sending rejection response status=200
```