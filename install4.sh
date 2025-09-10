#!/usr/bin/env bash
set -euo pipefail

### Versions
PKGCONF_VER=2.3.0
LIBEVENT_VER=2.1.12-stable
UTF8PROC_VER=2.9.0
TMUX_VER=3.5a

### Prefixes (all under $HOME)
PREFIX_PKGCONF="$HOME/apps/pkgconf"
PREFIX_LIBEVENT="$HOME/apps/libevent"
PREFIX_UTF8PROC="$HOME/apps/utf8proc"
PREFIX_TMUX="$HOME/apps/tmux"
BUILD_ROOT="$HOME/build-src"

# Optional: build a private ncurses if system one causes link errors
USE_LOCAL_NCURSES=0
NCURSES_VER=6.5
PREFIX_NCURSES="$HOME/apps/ncurses"

### Shell rc (zsh default on macOS)
SHELL_RC="${SHELL_RC:-$HOME/.zshrc}"
if [ -n "${BASH_VERSION-}" ]; then SHELL_RC="$HOME/.bashrc"; fi

CPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

need() { command -v "$1" >/dev/null 2>&1 || {
  echo "Missing: $1"
  exit 1
}; }
need curl
need tar
need make
need clang
need install_name_tool

mkdir -p "$BUILD_ROOT" "$PREFIX_PKGCONF" "$PREFIX_LIBEVENT" "$PREFIX_UTF8PROC" "$PREFIX_TMUX"

echo "==> pkgconf ${PKGCONF_VER} → ${PREFIX_PKGCONF}"
cd "$BUILD_ROOT"
if [ ! -f "pkgconf-${PKGCONF_VER}.tar.xz" ]; then
  curl -fL -o "pkgconf-${PKGCONF_VER}.tar.xz" \
    "https://distfiles.dereferenced.org/pkgconf/pkgconf-${PKGCONF_VER}.tar.xz"
fi
rm -rf "pkgconf-${PKGCONF_VER}"
tar xf "pkgconf-${PKGCONF_VER}.tar.xz"
cd "pkgconf-${PKGCONF_VER}"
./configure --prefix="$PREFIX_PKGCONF"
make -j"$CPU"
make install
export PATH="$PREFIX_PKGCONF/bin:$PATH"
export PKG_CONFIG="$PREFIX_PKGCONF/bin/pkgconf"

echo "==> libevent ${LIBEVENT_VER} → ${PREFIX_LIBEVENT}"
cd "$BUILD_ROOT"
if [ ! -f "libevent-${LIBEVENT_VER}.tar.gz" ]; then
  curl -fL -o "libevent-${LIBEVENT_VER}.tar.gz" \
    "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VER}/libevent-${LIBEVENT_VER}.tar.gz"
fi
rm -rf "libevent-${LIBEVENT_VER}"
tar xzf "libevent-${LIBEVENT_VER}.tar.gz"
cd "libevent-${LIBEVENT_VER}"
./configure --prefix="$PREFIX_LIBEVENT" --disable-openssl
make -j"$CPU"
make install

# (Optional) normalize libevent install names to @rpath (safe even if already fine)
shopt -s nullglob
for f in "$PREFIX_LIBEVENT"/lib/*.dylib; do
  install_name_tool -id "@rpath/$(basename "$f")" "$f" || true
done
shopt -u nullglob

if [ "$USE_LOCAL_NCURSES" -eq 1 ]; then
  echo "==> ncurses ${NCURSES_VER} → ${PREFIX_NCURSES}"
  cd "$BUILD_ROOT"
  if [ ! -f "ncurses-${NCURSES_VER}.tar.gz" ]; then
    curl -fL -o "ncurses-${NCURSES_VER}.tar.gz" \
      "https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VER}.tar.gz" ||
      curl -fL -o "ncurses-${NCURSES_VER}.tar.gz" \
        "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VER}.tar.gz"
  fi
  rm -rf "ncurses-${NCURSES_VER}"
  tar xzf "ncurses-${NCURSES_VER}.tar.gz"
  cd "ncurses-${NCURSES_VER}"
  ./configure --prefix="$PREFIX_NCURSES" \
    --with-termlib --enable-pc-files \
    --with-pkg-config-libdir="$PREFIX_NCURSES/lib/pkgconfig"
  make -j"$CPU"
  make install
  export CPPFLAGS="-I$PREFIX_NCURSES/include ${CPPFLAGS-}"
  export LDFLAGS="-L$PREFIX_NCURSES/lib ${LDFLAGS-}"
  export PKG_CONFIG_PATH="$PREFIX_NCURSES/lib/pkgconfig:${PKG_CONFIG_PATH-}"
fi

echo "==> utf8proc ${UTF8PROC_VER} → ${PREFIX_UTF8PROC}"
cd "$BUILD_ROOT"
if [ ! -f "utf8proc-${UTF8PROC_VER}.tar.gz" ]; then
  curl -fL -o "utf8proc-${UTF8PROC_VER}.tar.gz" \
    "https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v${UTF8PROC_VER}.tar.gz"
fi
rm -rf "utf8proc-${UTF8PROC_VER}"
tar xzf "utf8proc-${UTF8PROC_VER}.tar.gz"
cd "utf8proc-${UTF8PROC_VER}"

# Try to set install_name at link time; then enforce with install_name_tool post-install.
make clean >/dev/null 2>&1 || true
make LDFLAGS="-Wl,-install_name,@rpath/libutf8proc.3.dylib" -j"$CPU"
make prefix="$PREFIX_UTF8PROC" install

# Ensure the installed dylib uses a portable @rpath ID (avoids /usr/local fallback)
if [ -f "$PREFIX_UTF8PROC/lib/libutf8proc.3.dylib" ]; then
  install_name_tool -id @rpath/libutf8proc.3.dylib "$PREFIX_UTF8PROC/lib/libutf8proc.3.dylib"
fi
# Also normalize any other utf8proc*.dylib symlinks/files
shopt -s nullglob
for f in "$PREFIX_UTF8PROC"/lib/libutf8proc*.dylib; do
  install_name_tool -id "@rpath/$(basename "$f")" "$f" || true
done
shopt -u nullglob

# Prepare flags and rpaths for tmux link
export CPPFLAGS="-I$PREFIX_LIBEVENT/include -I$PREFIX_UTF8PROC/include ${CPPFLAGS-}"
export LDFLAGS="-L$PREFIX_LIBEVENT/lib -L$PREFIX_UTF8PROC/lib -Wl,-rpath,$PREFIX_LIBEVENT/lib -Wl,-rpath,$PREFIX_UTF8PROC/lib ${LDFLAGS-}"
export PKG_CONFIG_PATH="$PREFIX_UTF8PROC/lib/pkgconfig:$PREFIX_LIBEVENT/lib/pkgconfig:${PKG_CONFIG_PATH-}"

echo "==> tmux ${TMUX_VER} → ${PREFIX_TMUX}"
cd "$BUILD_ROOT"
if [ ! -f "tmux-${TMUX_VER}.tar.gz" ]; then
  curl -fL -o "tmux-${TMUX_VER}.tar.gz" \
    "https://github.com/tmux/tmux/releases/download/${TMUX_VER}/tmux-${TMUX_VER}.tar.gz"
fi
rm -rf "tmux-${TMUX_VER}"
tar xzf "tmux-${TMUX_VER}.tar.gz"
cd "tmux-${TMUX_VER}"

./configure --prefix="$PREFIX_TMUX" --enable-utf8proc
make -j"$CPU"
make install

# Ensure PATH contains tmux and pkgconf for future shells
grep -q 'export PATH="$HOME/apps/tmux/bin:$PATH"' "$SHELL_RC" 2>/dev/null ||
  echo 'export PATH="$HOME/apps/tmux/bin:$PATH"' >>"$SHELL_RC"
grep -q 'export PATH="$HOME/apps/pkgconf/bin:$PATH"' "$SHELL_RC" 2>/dev/null ||
  echo 'export PATH="$HOME/apps/pkgconf/bin:$PATH"' >>"$SHELL_RC"

echo
echo "==> Done. Open a new shell or: source \"$SHELL_RC\""
echo "==> Verify:"
echo "    tmux -V"
echo "    otool -L $(command -v tmux) | sed '1d'"
