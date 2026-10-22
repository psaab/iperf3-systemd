#!/bin/sh
# Install the standalone .deb built by build-deb.sh (builds it first if absent).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEB=$(ls -t "$ROOT"/standalone/dist/iperf3_*_*.deb 2>/dev/null | head -n1 || true)
if [ -z "${DEB:-}" ]; then
  "$ROOT/standalone/build-deb.sh"
  DEB=$(ls -t "$ROOT"/standalone/dist/iperf3_*_*.deb | head -n1)
fi
echo "Installing $DEB (libssl from apt; systemd already present)"
sudo apt-get update -qq
sudo apt-get install -y "$DEB"
echo "--- sockets (expect iperf3@5200..5212.socket listening) ---"
systemctl list-sockets 'iperf3@*.socket' --no-pager || true
ss -tlnp | grep -E ':(520[0-9]|521[0-2])\b' || true
echo "Test: iperf3 -c 127.0.0.1 -p 5201 -t 3"
