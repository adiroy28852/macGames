#!/usr/bin/env bash
# Build CrossOver's Wine from CodeWeavers' GPL source, with Apple's D3DMetal
# (from the Game Porting Toolkit) as Direct3D 10/11/12.
#
# Upstream Wine can't host D3DMetal on macOS: D3DMetal calls its own unix code
# directly from Windows threads, which breaks once Wine points %gs at the TEB
# (Wine 10+), and it imports ntdll's __wine_unix_call, which Wine 11 dropped.
# CrossOver's Wine keeps both working (and has D3DMetal's window hooks in
# winemac.drv/d3dmetal.c), so this builds that instead. It is x86_64 code run
# by Rosetta; the macOS libraries it needs (FreeType, GnuTLS, SDL2, Vulkan) are taken
# as x86_64 builds from an existing Wine runtime, with Homebrew's headers.
#
# usage: build.sh <crossover version> <libs from: Wine .app> <gptk .app> <output dir> <build dir>
# needs: brew install autoconf bison mingw-w64 freetype gnutls sdl2 vulkan-headers
set -euo pipefail

ver="${1:?CrossOver version, e.g. 26.3.0}"
libs_app="${2:?Wine .app whose lib/ has x86_64 libfreetype, libgnutls, libSDL2}"
gptk_app="${3:?path to Game Porting Toolkit.app}"
out="${4:?output directory (no spaces)}"
build="${5:?build directory (no spaces)}"
mkdir -p "$build" "$out"; build="$(cd "$build" && pwd)"; out="$(cd "$out" && pwd)"
src="$build/src/sources/wine"
# Linker flags can't carry the space in "Wine Staging.app", so link to it.
ln -sfn "$libs_app/Contents/Resources/wine/lib" "$build/x86_64-libs"
deps="$build/x86_64-libs"
brew="$(brew --prefix)"
export PATH="$brew/opt/bison/bin:$PATH"
jobs="$(sysctl -n hw.ncpu)"
# Build against the SDK of the running macOS: a newer one (the Command Line
# Tools can ship macOS N+1's) makes configure find functions such as pipe2 that
# this macOS lacks, and Wine then calls a null pointer at startup.
export SDKROOT="$(xcode-select -p)/SDKs/MacOSX$(sw_vers -productVersion | cut -d. -f1).sdk"
[[ -d "$SDKROOT" ]] || { echo "no SDK for this macOS at $SDKROOT" >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=14.0  # Sonoma: needed for direct syscalls (SIGSYS) and D3DMetal

if [[ ! -d "$src" ]]; then
  mkdir -p "$build/src"
  curl -fL "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$ver.tar.gz" | tar -xz -C "$build/src"
fi

# CrossOver stamps its C++ runtime (msvcp140, vcruntime140_1) as 14.42, older
# than games built with newer Visual Studio accept: Unreal's launcher stops with
# "Microsoft Visual C++ 2015-2022 Redistributable is required". Report 14.51,
# as upstream Wine 11.21 does.
sed -i '' 's/^#define WINE_FILEVERSION 14,42,34433,0$/#define WINE_FILEVERSION 14,51,36247,0/' \
  "$src"/dlls/msvcp140/version.rc "$src"/dlls/msvcp140_2/version.rc "$src"/dlls/vcruntime140_1/version.rc

common=(--disable-tests --without-x --without-wayland --without-dbus --without-pulse --without-alsa
  --without-oss --without-udev --without-v4l2 --without-sane --without-pcap --without-krb5 --without-cups
  --without-gphoto --without-netapi --without-capi --without-usb --without-pcsclite --without-inotify
  --without-gstreamer --without-ffmpeg --without-opencl)

# configure records absolute paths; start over if the build dir has moved.
for d in "$build/tools" "$build/obj"; do
  if [[ -f "$d/Makefile" ]] && ! grep -qF "$src" "$d/Makefile"; then rm -rf "$d"; fi
done

# Native build tools (winebuild, widl, ...) first; the runtime is cross-built for x86_64.
# sfnt2fon needs FreeType here (Homebrew's, native), to build Wine's bitmap fonts.
if [[ ! -x "$build/tools/tools/winebuild/winebuild" ]]; then
  mkdir -p "$build/tools"
  (cd "$build/tools" && "$src/configure" --enable-archs=x86_64 "${common[@]}" --without-gnutls --without-sdl \
     >configure.out && make -j"$jobs" __tooldeps__ nls/locale.nls >make.out)  # wrc needs locale.nls
fi

mkdir -p "$build/obj"
if [[ ! -f "$build/obj/Makefile" ]]; then
  # pkg-config would hand back Homebrew's arm64 libraries; name the x86_64 ones instead.
  # Their install names lack a version ("libgnutls.dylib"), which configure can't
  # parse, so give the names to load them by (as Gcenx's builds do).
  (cd "$build/obj" && PKG_CONFIG_LIBDIR=/nonexistent \
     ac_cv_lib_soname_freetype=libfreetype.6.dylib ac_cv_lib_soname_gnutls=libgnutls.30.dylib \
     ac_cv_lib_soname_SDL2=libSDL2-2.0.0.dylib ac_cv_lib_soname_vulkan=libvulkan.1.dylib "$src/configure" \
     --host=x86_64-apple-darwin --build=aarch64-apple-darwin --with-wine-tools=../tools \
     --enable-archs=i386,x86_64 --prefix="$out" "${common[@]}" \
     CC="clang -arch x86_64" OBJC="clang -arch x86_64" CFLAGS="-O2" OBJCFLAGS="-O2" CPPFLAGS="-I$brew/include" \
     LDFLAGS="-L$deps -Wl,-rpath,@loader_path/../../" \
     FREETYPE_CFLAGS="-I$brew/include/freetype2" FREETYPE_LIBS="-L$deps -lfreetype" \
     GNUTLS_CFLAGS="-I$brew/include" GNUTLS_LIBS="-L$deps -lgnutls" \
     SDL2_CFLAGS="-I$brew/include/SDL2" SDL2_LIBS="-L$deps -lSDL2" >configure.out)
fi
(cd "$build/obj" && make -j"$jobs" >make.out 2>&1 && make install >install.out 2>&1)
# This Wine installs its loader next to the unix modules; macgames expects bin/wine.
ln -sfn ../lib/wine/x86_64-unix/wine "$out/bin/wine"

# The x86_64 libraries the unix modules load (found via @loader_path/../../).
for l in "$deps"/*.dylib; do cp -cfP "$l" "$out/lib/"; done
# Wine Mono and Gecko in the versions this Wine asks for, so prefixes don't
# stop at an installer prompt.
addons="$src/dlls/appwiz.cpl/addons.c"
mono="$(sed -n 's/^#define MONO_VERSION "\(.*\)"/\1/p' "$addons")"
gecko="$(sed -n 's/^#define GECKO_VERSION "\(.*\)"/\1/p' "$addons")"
mkdir -p "$out/share/wine/mono" "$out/share/wine/gecko"
[[ -d "$out/share/wine/mono/wine-mono-$mono" ]] ||
  curl -fL "https://dl.winehq.org/wine/wine-mono/$mono/wine-mono-$mono-x86.tar.xz" | tar -xJ -C "$out/share/wine/mono"
for arch in x86 x86_64; do
  [[ -d "$out/share/wine/gecko/wine-gecko-$gecko-$arch" ]] ||
    curl -fL "https://dl.winehq.org/wine/wine-gecko/$gecko/wine-gecko-$gecko-$arch.tar.xz" | tar -xJ -C "$out/share/wine/gecko"
done

# D3DMetal: GPTK's Direct3D DLLs and its framework. Every unix half is a link to
# the one libd3dshared.dylib, as GPTK ships them: they must load as a single
# library, since d3d12.dll relies on the Win32 table that dxgi.dll hands it.
glib="$gptk_app/Contents/Resources/wine/lib"
mkdir -p "$out/lib/external"; cp -cR "$glib/external/." "$out/lib/external/"
for d in d3d10 d3d11 d3d12 dxgi nvapi64 nvngx atiadlxx:atidxx64; do
  cp -f "$glib/wine/x86_64-windows/${d%%:*}.dll" "$out/lib/wine/x86_64-windows/"
  ln -sfn ../../external/libd3dshared.dylib "$out/lib/wine/x86_64-unix/${d##*:}.so"
done
echo "built $out ($("$out/bin/wine" --version 2>/dev/null || echo "CrossOver $ver"))"
