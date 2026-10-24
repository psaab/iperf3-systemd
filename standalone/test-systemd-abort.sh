#!/bin/sh
# Regression test: an aborted control connection must not kill a
# --systemd server. The aborted client makes cleanup_server() run in
# the parent; it must not close the shared listening fd 3, or the next
# iperf_server_listen() fails with EBADF and the server exits.
#
# Usage: IPERF3_BIN=/path/to/iperf3 ./standalone/test-systemd-abort.sh
# IPERF3_BIN defaults to the build tree binary (src/.libs via libtool wrapper).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN=${IPERF3_BIN:-$ROOT/iperf/src/.libs/iperf3}
PORT=${TEST_PORT:-15261}
command -v systemd-socket-activate >/dev/null || { echo "systemd-socket-activate missing" >&2; exit 1; }
[ -x "$BIN" ] || { echo "iperf3 binary not executable: $BIN" >&2; exit 1; }

LOG=$(mktemp)
setsid -f systemd-socket-activate -l "$PORT" "$BIN" --systemd </dev/null >>"$LOG" 2>&1
cleanup() { pkill -f "socket-activate -l $PORT" 2>/dev/null || true; rm -f "$LOG"; }
trap cleanup EXIT
sleep 1

# Aborted client: connect the control socket and close immediately.
python3 -c "import socket; socket.create_connection(('127.0.0.1', $PORT)).close()"
sleep 1

# The server must still accept a real test on the same port.
if ! /usr/bin/iperf3 -c 127.0.0.1 -p "$PORT" -t 2 >/dev/null 2>&1 && \
   ! "$BIN" -c 127.0.0.1 -p "$PORT" -t 2 >/dev/null 2>&1; then
    echo "FAIL: server died after aborted connection" >&2
    cat "$LOG" >&2
    exit 1
fi
if grep -q "Bad file descriptor" "$LOG"; then
    echo "FAIL: Bad file descriptor in server log" >&2
    cat "$LOG" >&2
    exit 1
fi
echo "PASS: --systemd server survives aborted connection (port $PORT)"
