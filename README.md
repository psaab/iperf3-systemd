# iperf3 Multi-Client Docker

Runs a public iperf3 server that accepts **multiple simultaneous clients on
the same ports**, without Docker networking tricks. Inside the container,
`systemd-socket-activate` passes each listening socket to
`iperf3 --systemd`, which forks per test. On bare metal the same binary
runs under real systemd socket units — see `standalone/README.md`.
`xinetd`/`--inetd` is legacy.

## Quick Start

```bash
git clone --recursive https://github.com/psaab/iperf3-systemd.git
cd iperf3-systemd
cp .env.example .env   # optional: edit IPERF3_PORTS
docker compose up -d
```

Bare metal without Docker: see `standalone/README.md`.

## Configuration

Edit `.env` to tune the server:

| Variable | Default | Description |
|---|---|---|
| `IPERF3_PORTS` | `5200-5212` | Ports to listen on **and** publish: single port (`5201`) or range (`5200-5212`). The entrypoint also accepts comma lists (`5200,5202`), but compose publishing needs a single port or range |
| `IPERF3_CPU_LIMIT` | `4.0` | Container CPU cap (cores) |
| `IPERF3_MEM_LIMIT` | `1G` | Container memory cap |

Example, one port only: set `IPERF3_PORTS=5201` in `.env`, then
`docker compose up -d`.

## Client Usage

Clients connect exactly as normal — no special flags needed:

```bash
iperf3 -c your.server.ip
iperf3 -c your.server.ip -R
iperf3 -c your.server.ip -P 8
iperf3 -c your.server.ip -u -b 100M
```

Note: clients connecting in the same instant can occasionally get
`the server is busy running a test` (pre-existing race, also under
`xinetd`). Retry the client.

## Monitoring

```bash
docker compose logs -f
docker exec iperf3-local ps aux | grep iperf3
```

## How It Works

For each port in `IPERF3_PORTS`, the entrypoint starts one
`systemd-socket-activate -l <port> /usr/bin/iperf3 --systemd`.
Socket activation gives iperf3 the listening socket on fd 3
(`Accept=no` semantics). After a client's streams are accepted, the
server forks: the child runs the test, the parent accepts the next
client. `systemd` is only the source of `systemd-socket-activate`;
it does not run as PID 1 in the container.

## Firewall

```bash
ufw allow 5200:5212/tcp
# or: nft add rule inet filter input tcp dport 5200-5212 accept
```
