#!/usr/bin/env bash
set -euo pipefail

### --- versions / prefixes (edit if you want newer) ---
LIBEVENT_VER=2.1.12-stable # https://github.com/libevent/libevent/releases
UTF8PROC_VER=2.9.0         # https://github.com/JuliaStrings/utf8proc/releases
TMUX_VER=3.5a              # https://github.com/tmux/tmux/releases

PREFIX_LIBEVENT="$HOME/apps/libevent"
PREFIX_UTF8PROC="$HOME/apps/utf8proc"
PREFIX_TMUX="$HOME/apps/tmux"
BUILD_ROOT="$HOME/build-src"

# Optional: build a private ncurses if system ncurses causes link errors
USE_LOCAL_NCURSES=0 # set to 1 to enable
NCURSES_VER=6.5
PREFIX_NCURSES="$HOME/apps/ncurses"

### --- choose which shell rc to update PATH in ---
SHELL_RC="${SHELL_RC:-$HOME/.zshrc}"
if [ -n "${BASH_VERSION-}" ]; then SHELL_RC="$HOME/.bashrc"; fi

CPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

### --- prerequisite sanity checks (no sudo needed) ---
need() { command -v "$1" >/dev/null 2>&1 || {
  echo "Missing: $1"
  exit 1
}; }
need curl
need tar
need make
need clang
need git || true # not required, but nice to have for troubleshooting

mkdir -p "$BUILD_ROOT" "$PREFIX_LIBEVENT" "$PREFIX_UTF8PROC" "$PREFIX_TMUX"

echo "==> Building libevent ${LIBEVENT_VER} → ${PREFIX_LIBEVENT}"
cd "$BUILD_ROOT"
if [ ! -f "libevent-${LIBEVENT_VER}.tar.gz" ]; then
  curl -fL -o "libevent-${LIBEVENT_VER}.tar.gz" \
    "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VER}/libevent-${LIBEVENT_VER}.tar.gz"
fi
rm -rf "libevent-${LIBEVENT_VER}"
tar xzf "libevent-${LIBEVENT_VER}.tar.gz"
cd "libevent-${LIBEVENT_VER}"
# tmux doesn't require OpenSSL features; disabling makes it simpler
./configure --prefix="$PREFIX_LIBEVENT" --disable-openssl
make -j"$CPU"
make install

if [ "$USE_LOCAL_NCURSES" -eq 1 ]; then
  echo "==> Building ncurses ${NCURSES_VER} → ${PREFIX_NCURSES}"
  cd "$BUILD_ROOT"
  if [ ! -f "ncurses-${NCURSES_VER}.tar.gz" ]; then
    # try two mirrors
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

echo "==> Building utf8proc ${UTF8PROC_VER} → ${PREFIX_UTF8PROC}"
cd "$BUILD_ROOT"
if [ ! -f "utf8proc-${UTF8PROC_VER}.tar.gz" ]; then
  curl -fL -o "utf8proc-${UTF8PROC_VER}.tar.gz" \
    "https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v${UTF8PROC_VER}.tar.gz"
fi
rm -rf "utf8proc-${UTF8PROC_VER}"
tar xzf "utf8proc-${UTF8PROC_VER}.tar.gz"
cd "utf8proc-${UTF8PROC_VER}"
make -j"$CPU"
make prefix="$PREFIX_UTF8PROC" install

echo "==> Building tmux ${TMUX_VER} → ${PREFIX_TMUX}"
cd "$BUILD_ROOT"
if [ ! -f "tmux-${TMUX_VER}.tar.gz" ]; then
  curl -fL -o "tmux-${TMUX_VER}.tar.gz" \
    "https://github.com/tmux/tmux/releases/download/${TMUX_VER}/tmux-${TMUX_VER}.tar.gz"
fi
rm -rf "tmux-${TMUX_VER}"
tar xzf "tmux-${TMUX_VER}.tar.gz"
cd "tmux-${TMUX_VER}"

# Point the build at your home-built libs and embed rpaths so runtime finds them
export CPPFLAGS="-I$PREFIX_LIBEVENT/include -I$PREFIX_UTF8PROC/include ${CPPFLAGS-}"
export LDFLAGS="-L$PREFIX_LIBEVENT/lib -L$PREFIX_UTF8PROC/lib -Wl,-rpath,$PREFIX_LIBEVENT/lib -Wl,-rpath,$PREFIX_UTF8PROC/lib ${LDFLAGS-}"
export PKG_CONFIG_PATH="$PREFIX_UTF8PROC/lib/pkgconfig:$PREFIX_LIBEVENT/lib/pkgconfig:${PKG_CONFIG_PATH-}"

# tmux 3.5+ requires explicit utf8proc choice
./configure --prefix="$PREFIX_TMUX" --enable-utf8proc
make -j"$CPU"
make install

# Put tmux on PATH if not already there
if ! grep -q 'export PATH="$HOME/apps/tmux/bin:$PATH"' "$SHELL_RC" 2>/dev/null; then
  echo 'export PATH="$HOME/apps/tmux/bin:$PATH"' >>"$SHELL_RC"
fi

echo
echo "==> Done. Open a new shell or run: source \"$SHELL_RC\""
echo "==> Verify:"
echo "    $(printf '%q' "$PREFIX_TMUX")/bin/tmux -V"
echo "    otool -L $(printf '%q' "$PREFIX_TMUX")/bin/tmux | sed '1d'"
