#!/bin/sh
# Launch one systemd-socket-activate supervisor per port in IPERF3_PORTS.
# Each passes its listening socket (fd 3) to `iperf3 --systemd`, which
# forks per test. No xinetd, no systemd as PID 1.
# IPERF3_PORTS accepts: 5201 | 5200-5212 | 5200,5202,5210 | mixed
set -eu

PORTS=${IPERF3_PORTS:-5201}
ACTIVATE=$(command -v systemd-socket-activate || echo /usr/bin/systemd-socket-activate)
[ -x "$ACTIVATE" ] || { echo "systemd-socket-activate not found" >&2; exit 1; }

pids=""
cleanup() {
    # shellcheck disable=SC2086
    [ -n "$pids" ] && kill $pids 2>/dev/null || true
}
trap 'cleanup; exit 0' TERM INT

spawn() {
    case "$1" in
        ''|*[!0-9]*) echo "invalid port: '$1'" >&2; exit 1 ;;
    esac
    if [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        echo "port out of range: $1" >&2; exit 1
    fi
    echo "listening on $1 (iperf3 --systemd via socket activation)"
    "$ACTIVATE" -l "$1" /usr/bin/iperf3 --systemd &
    pids="$pids $!"
}

for token in $(printf '%s' "$PORTS" | tr ',' ' '); do
    case "$token" in
        *-*)
            p=${token%-*}
            end=${token#*-}
            case "$p$end" in *[!0-9]*) echo "invalid range: '$token'" >&2; exit 1 ;; esac
            while [ "$p" -le "$end" ]; do
                spawn "$p"
                p=$((p + 1))
            done
            ;;
        *) spawn "$token" ;;
    esac
done

wait
