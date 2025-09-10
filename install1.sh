#!/usr/bin/env bash
set -euo pipefail

# -------- Settings (adjust versions if you want) --------
LIBEVENT_VER=2.1.12-stable # https://github.com/libevent/libevent/releases
TMUX_VER=3.5a              # https://github.com/tmux/tmux/releases
BUILD_ROOT="$HOME/build-src"
PREFIX_LIBEVENT="$HOME/apps/libevent"
PREFIX_TMUX="$HOME/apps/tmux"

# Optional ncurses if needed:
USE_LOCAL_NCURSES=0 # set to 1 if linking against system ncurses fails
NCURSES_VER=6.5
PREFIX_NCURSES="$HOME/apps/ncurses"

# Pick shell rc to append PATH
SHELL_RC="${SHELL_RC:-$HOME/.zshrc}"
if [ -n "${BASH_VERSION-}" ]; then SHELL_RC="$HOME/.bashrc"; fi

CPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

mkdir -p "$BUILD_ROOT" "$PREFIX_LIBEVENT" "$PREFIX_TMUX"

echo "==> Building libevent $LIBEVENT_VER"
cd "$BUILD_ROOT"
if [ ! -f "libevent-${LIBEVENT_VER}.tar.gz" ]; then
  curl -LO "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VER}/libevent-${LIBEVENT_VER}.tar.gz"
fi
rm -rf "libevent-${LIBEVENT_VER}"
tar xzf "libevent-${LIBEVENT_VER}.tar.gz"
cd "libevent-${LIBEVENT_VER}"

# --disable-openssl keeps it simple (tmux doesn't need the OpenSSL features)
./configure --prefix="$PREFIX_LIBEVENT" --disable-openssl
make -j"$CPU"
make install

if [ "$USE_LOCAL_NCURSES" -eq 1 ]; then
  echo "==> Building ncurses $NCURSES_VER (optional)"
  cd "$BUILD_ROOT"
  if [ ! -f "ncurses-${NCURSES_VER}.tar.gz" ]; then
    curl -LO "https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VER}.tar.gz" ||
      curl -LO "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VER}.tar.gz"
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

echo "==> Building tmux $TMUX_VER"
cd "$BUILD_ROOT"
if [ ! -f "tmux-${TMUX_VER}.tar.gz" ]; then
  curl -LO "https://github.com/tmux/tmux/releases/download/${TMUX_VER}/tmux-${TMUX_VER}.tar.gz"
fi
rm -rf "tmux-${TMUX_VER}"
tar xzf "tmux-${TMUX_VER}.tar.gz"
cd "tmux-${TMUX_VER}"

# Point tmux at your home-built libevent; use system ncurses by default
export CPPFLAGS="-I$PREFIX_LIBEVENT/include ${CPPFLAGS-}"
export LDFLAGS="-L$PREFIX_LIBEVENT/lib ${LDFLAGS-}"

# No sudo, install under $HOME
./configure --prefix="$PREFIX_TMUX"
make -j"$CPU"
make install

# Add to PATH if not present
if ! grep -q 'export PATH="$HOME/apps/tmux/bin:$PATH"' "$SHELL_RC" 2>/dev/null; then
  echo 'export PATH="$HOME/apps/tmux/bin:$PATH"' >>"$SHELL_RC"
fi

echo
echo "==> Done. Open a new shell or run: source $SHELL_RC"
echo "==> Verify: $(printf '%q' "$PREFIX_TMUX")/bin/tmux -V"
