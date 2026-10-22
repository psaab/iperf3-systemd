# iperf3 standalone (no Docker)

Native Debian/Ubuntu packaging of the vendored `../iperf/` tree (branch
`add-inetd-option`, plus a new `--systemd` mode). A `.deb` replaces the
two-stage `../Dockerfile`; `systemd` replaces `docker compose` and
`xinetd`. `iperf3@<port>.socket` units (`Accept=no`) own ports 5200-5212;
each `iperf3@<port>.service` runs `iperf3 --systemd`, which forks per
test so clients test concurrently. `--inetd`/`xinetd` remains supported
as a legacy path (doc example in the package).

## Quick start

```bash
./standalone/build-deb.sh          # -> standalone/dist/iperf3_*_amd64.deb
sudo ./standalone/install.sh       # apt-installs .deb, enables sockets
iperf3 -c 127.0.0.1 -p 5201 -t 3   # smoke test
systemctl list-sockets 'iperf3@*.socket'
sudo systemctl status 'iperf3@5201.service'
journalctl -u 'iperf3@5201.service' -f
```

Remove: `sudo apt remove iperf3 && sudo apt install iperf3` (restores distro
build, which lacks `--inetd`).

## What maps to what

| Docker / compose | Standalone |
|---|---|
| build stage (`build-essential libssl-dev …`) | build host packages, `Depends` generated in `DEBIAN/control` |
| runtime `libssl3 xinetd` | `Depends: libssl3t64, xinetd` (`gdb iproute2 procps` were debug only; `iproute2 procps` are `Recommends`) |
| `COPY --from=build /build/out/usr/ /usr/` | `.deb` payload: `/usr/bin/iperf3`, `/usr/lib/libiperf.so*`, man pages |
| `entrypoint.sh`: `xinetd -dontfork` | `iperf3@.socket` + `iperf3@.service` (`--systemd`, `Accept=no`, fork-per-test) |
| `xinetd.conf` defaults (`instances=200 cps=50 10`) | no direct equivalent; concurrency is unbounded fork-per-test — cap with `TasksMax`/`CPUQuota` in the service if needed |
| compose `ulimits.nofile` + CPU/mem limits | in `iperf3@.service`: `LimitNOFILE CPUQuota MemoryMax` |
| `EXPOSE 5201`, `ports: 5201:5201` | host listeners 5200-5212 directly; open firewall (below). Compose only published 5201 — standalone exposes all 13, as the container's `xinetd` already listened on all 13 |
| `saab-vlan80` net + fixed `172.16.80.200` / v6 | host networking; VLAN/IP is host config (`netplan`/`systemd-networkd`), not package scope |
| `.env` `IPERF3_PORT/MAX_INSTANCES/PER_SOURCE` | not wired to anything in Docker either (dead vars); edit `/etc/xinetd.d/iperf3` (`instances`, `per_source`, `cps`) and restart `xinetd` |

## Firewall

```bash
sudo ufw allow 5200:5212/tcp        # or: nft add rule inet filter input tcp dport 5200-5212 accept
```

## Options

- Static tarball: `./standalone/build-deb.sh --static` links
  `--enable-static-bin --without-openssl` (same recipe as
  `iperf/contrib/Dockerfile`). Single-file easy, but loses `--auth`
  (OpenSSL). Prefer the dynamic `.deb` unless copying one binary to
  many hosts.
- Why `Accept=no`, not `Accept=yes`: `Accept=yes` hands each service a
  *connected* socket, but iperf3 still needs to `accept()` its data
  streams on the same port — those would spawn fresh instances and fail.
  `--systemd` therefore uses `Accept=no` (listening fd 3, `LISTEN_FDS`
  checked) and forks per test like `--inetd`, except the parent stays
  alive as the acceptor instead of exiting for `xinetd`. Verified under
  a real user manager: concurrent clients, `-P 4`, UDP, and `-R` pass.
- Legacy `xinetd`: keep the `--inetd` path with
  `iperf3.xinetd.example` from the package docs if a host cannot use
  systemd. Single-client fallback remains `systemd/iperf3.service`
  (`iperf3 -s`, one test at a time).
- RPM hosts: `../iperf/iperf3.spec` already exists; build with the same
  `--inetd` tree and ship `xinetd.d/iperf3` equivalently.

## Sidecars (were `network_mode: service:iperf3-local`)

They shared the container netns only to see the same interfaces/IP.
On a host they are just independent services:

- `caddy-debug` (serves `../assets/` test files): `apt install caddy`,
  point `../Caddyfile` root at the host `assets/` path, `systemctl enable
  --now caddy`. Drop the Cloudflare token env unless DNS-01 is needed.
- `tcpdump-grpc` (`../tcpdump-grpc/`): Go binaries are already
  `CGO_ENABLED=0` static. `make build` natively (needs `protoc` +
  `protoc-gen-go*`), install `tcpdump`, `setcap cap_net_raw+eip
  /usr/bin/tcpdump`, run under a systemd unit with `User=capturer`,
  `CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN`, TLS from `../tls/`.
  No netns sharing or `cap_drop: ALL` translation needed.

Known race: clients connecting in the same instant can land on one
server instance and get `the server is busy running a test` (same in
Docker — the listener is shared until the first server forks). Retry, or
stagger starts by a second; verified working with 1 s stagger and with
simultaneous starts under an xinetd emulator.

## Verify concurrency (the point of `--inetd`)

```bash
iperf3 -c HOST -p 5201 -t 5 & iperf3 -c HOST -p 5201 -t 5 & wait
ps aux | grep '[i]perf3 --inetd'   # one child per client
```
