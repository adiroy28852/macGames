#!/usr/bin/env bash
# Rebuild Wine's macOS display driver (winemac.so) so DXMT can draw.
#
# DXMT finds the window's Cocoa view through symbols that stock Wine hides,
# and expects the pre-Wine-11 macdrv_win_data layout. This builds winemac.so
# from the same Wine version as the runtime (plus the wine-staging patches
# that touch it), with every symbol exported and dxmt-compat.patch applied,
# which provides the CrossOver-style "macdrv_functions" table DXMT looks for.
#
# usage: build.sh <wine version> <winemac.so to replace> <build dir>
# needs: brew install bison mingw-w64
set -euo pipefail

ver="${1:?wine version, e.g. 11.21}"
dest="${2:?path to winemac.so to replace}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build="${3:?build directory}"
mkdir -p "$build/src"; build="$(cd "$build" && pwd)"
src="$build/src/wine-$ver"
export PATH="/opt/homebrew/opt/bison/bin:$PATH"

if [[ ! -d "$src" ]]; then
  curl -fL "https://dl.winehq.org/wine/source/${ver%%.*}.x/wine-$ver.tar.xz" | tar -xJ -C "$build/src"
  curl -fL "https://github.com/wine-staging/wine-staging/archive/refs/tags/v$ver.tar.gz" | tar -xz -C "$build/src"
  for p in "$build/src/wine-staging-$ver"/patches/{User32-recursive-activation,winemac.drv-no-flicker-patch}/*.patch \
           "$here/dxmt-compat.patch"; do
    patch -d "$src" -p1 --forward < "$p"
  done
fi

without=(--disable-tests --without-freetype --without-gstreamer --without-sdl --without-cups --without-krb5
  --without-gnutls --without-netapi --without-pcap --without-pcsclite --without-sane --without-usb
  --without-v4l2 --without-x --without-capi --without-gphoto --without-inotify --without-opencl
  --without-pulse --without-oss --without-udev --without-dbus --without-ffmpeg --without-wayland --without-vulkan)

# Native build tools (widl, winebuild, ...) first: the driver is cross-built for x86_64.
if [[ ! -x "$build/tools/tools/winebuild/winebuild" ]]; then
  mkdir -p "$build/tools"
  (cd "$build/tools" && "$src/configure" --enable-archs=x86_64 "${without[@]}" >configure.out && make -j"$(sysctl -n hw.ncpu)" __tooldeps__ >make.out)
fi

mkdir -p "$build/obj"
if [[ ! -f "$build/obj/Makefile" ]]; then
  (cd "$build/obj" && "$src/configure" --host=x86_64-apple-darwin --build=aarch64-apple-darwin \
    --with-wine-tools=../tools --enable-archs=x86_64 "${without[@]}" \
    CC="clang -arch x86_64" OBJC="clang -arch x86_64" \
    CFLAGS="-O2 -fvisibility=default" OBJCFLAGS="-O2 -fvisibility=default" >configure.out)
fi
(cd "$build/obj" && make -j"$(sysctl -n hw.ncpu)" dlls/winemac.drv/winemac.so >make-winemac.out)

built="$build/obj/dlls/winemac.drv/winemac.so"
nm -gU "$built" | grep -q _macdrv_functions || { echo "built winemac.so lacks macdrv_functions" >&2; exit 1; }
[[ -f "$dest.orig" ]] || cp "$dest" "$dest.orig"
rm -f "$dest" && cp "$built" "$dest" && codesign -s - -f "$dest" 2>/dev/null
echo "installed DXMT-compatible winemac.so"
