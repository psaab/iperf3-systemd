FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    libssl-dev \
    lsof \
    tcpdump \
    mtr \
    libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

COPY iperf/ /build/iperf/
WORKDIR /build/iperf
RUN (make distclean >/dev/null 2>&1 || true) && ./configure --prefix=/usr && make -j$(nproc) && make install DESTDIR=/build/out

FROM debian:bookworm-slim

# systemd provides systemd-socket-activate only; systemd is NOT run as PID 1.
RUN apt-get update && apt-get install -y \
    systemd \
    gdb \
    iproute2 \
    procps \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /build/out/usr/ /usr/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5200-5212

ENTRYPOINT ["/entrypoint.sh"]
