#!/bin/sh
# Build a standalone Debian package from the vendored iperf/ source tree.
# No Docker required. Produces standalone/dist/iperf3_<ver>_amd64.deb
#
# Usage: ./standalone/build-deb.sh [--static]
#   --static  try a fully static binary (--enable-static-bin --without-openssl,
#             loses `iperf3 --auth`); output still packaged as .deb.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/iperf"
STATIC=0
[ "${1:-}" = "--static" ] && STATIC=1

command -v dpkg-deb >/dev/null || { echo "dpkg-deb missing: apt install dpkg-dev" >&2; exit 1; }
for t in gcc make autoconf automake libtoolize; do
  command -v "$t" >/dev/null || { echo "build tool missing: $t (apt install build-essential autoconf automake libtool libssl-dev)" >&2; exit 1; }
done

VER=$(sed -n 's/.*AC_INIT(\[iperf\],\[\([^]]*\)\].*/\1/p' "$SRC/configure.ac" | head -n1)
GITREV=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo nogit)
PKGVER="${VER}systemd.${GITREV}"
ARCH=$(dpkg --print-architecture)
OUT="$ROOT/standalone/dist"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> copying pristine source (working tree, build artifacts stripped)"
mkdir -p "$WORK/src"
cp -a "$SRC/." "$WORK/src/"
# Drop in-tree build artifacts so configure starts clean; keep configure itself.
make -C "$WORK/src" distclean >/dev/null 2>&1 || true
find "$WORK/src" -name '*.o' -o -name '*.lo' -o -name '*.log' -o -name '*.trs' | xargs rm -f 2>/dev/null || true
rm -rf "$WORK/src/.git"

echo "==> configure + make (static=$STATIC)"
cd "$WORK/src"
if [ "$STATIC" = 1 ]; then
  ./configure --prefix=/usr --enable-static-bin --without-openssl
else
  ./configure --prefix=/usr
fi
make -j"$(nproc)"

STAGE="$WORK/stage"
echo "==> make install DESTDIR=$STAGE"
make install DESTDIR="$STAGE"
strip "$STAGE/usr/bin/iperf3" 2>/dev/null || true

echo "==> adding systemd payload (xinetd kept as doc example)"
mkdir -p "$STAGE/usr/lib/systemd/system" \
         "$STAGE/usr/share/doc/iperf3-standalone"
cp "$ROOT/standalone/systemd/iperf3@.socket" "$ROOT/standalone/systemd/iperf3@.service" \
   "$STAGE/usr/lib/systemd/system/"
cp "$ROOT/xinetd.d/iperf3" "$STAGE/usr/share/doc/iperf3-standalone/iperf3.xinetd.example"
cp "$ROOT/standalone/systemd/iperf3.service" \
   "$STAGE/usr/share/doc/iperf3-standalone/iperf3.service.example"
cp "$ROOT/standalone/README.md" "$STAGE/usr/share/doc/iperf3-standalone/"

echo "==> writing DEBIAN/control ($PKGVER, $ARCH)"
mkdir -p "$STAGE/DEBIAN"
SSLDEP=$(dpkg-query -W -f='${Package}' libssl3t64 2>/dev/null || echo libssl3)
cat > "$STAGE/DEBIAN/control" <<EOF
Package: iperf3
Version: $PKGVER
Section: net
Priority: optional
Architecture: $ARCH
Maintainer: standalone packaging <root@localhost>
Depends: libc6 (>= 2.36), $SSLDEP, systemd
Recommends: iproute2, procps, xinetd
Conflicts: libiperf0
Replaces: libiperf0
Description: iperf3 with --systemd/--inetd multi-client serving
 Custom iperf3 build (adds --inetd and --systemd) for bare-metal Debian/Ubuntu.
 systemd socket units (Accept=no) own ports 5200-5212; each service forks
 per test so many clients can test concurrently without Docker or xinetd.
 Installs /usr/bin/iperf3, libiperf and iperf3@.socket/iperf3@.service.
EOF
cp "$ROOT/standalone/debian/postinst" "$STAGE/DEBIAN/postinst"
cp "$ROOT/standalone/debian/prerm" "$STAGE/DEBIAN/prerm"
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm"
# /etc files are conffiles automatically when under /etc in a .deb.

mkdir -p "$OUT"
DEB="$OUT/iperf3_${PKGVER}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$DEB" >/dev/null
echo "==> built $DEB"
dpkg-deb -I "$DEB" | sed -n '1,20p'
echo "Install with: sudo ./standalone/install.sh"
