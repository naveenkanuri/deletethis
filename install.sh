#!/usr/bin/env bash
set -euo pipefail

# --- versions (adjust if you want newer tags) ---
LIBEVENT_VER=2.1.12-stable
TMUX_TAG=3.5a # check https://github.com/tmux/tmux/tags for latest

# --- dirs ---
PREFIX_LIBEVENT="$HOME/apps/libevent"
PREFIX_TMUX="$HOME/apps/tmux"
BUILD="$HOME/build-src"
mkdir -p "$PREFIX_LIBEVENT" "$PREFIX_TMUX" "$BUILD"

CPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "==> Building libevent $LIBEVENT_VER to $PREFIX_LIBEVENT"
cd "$BUILD"
curl -LO "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VER}/libevent-${LIBEVENT_VER}.tar.gz"
tar xzf "libevent-${LIBEVENT_VER}.tar.gz"
cd "libevent-${LIBEVENT_VER}"
./configure --prefix="$PREFIX_LIBEVENT" --disable-openssl
make -j"$CPU"
make install

# OPTIONAL: Build your own ncurses if system one gives link errors:
# Uncomment this block only if tmux fails to link/find ncurses later.
#: <<'OPT_NCURSES'
# NCURSES_VER=6.5
# PREFIX_NCURSES="$HOME/apps/ncurses"
# cd "$BUILD"
# curl -LO "https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VER}.tar.gz" || \
# curl -LO "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VER}.tar.gz"
# tar xzf "ncurses-${NCURSES_VER}.tar.gz"
# cd "ncurses-${NCURSES_VER}"
# ./configure --prefix="$PREFIX_NCURSES" --with-termlib --enable-pc-files --with-pkg-config-libdir="$PREFIX_NCURSES/lib/pkgconfig"
# make -j"$CPU"
# make install
# export CPPFLAGS="-I$PREFIX_NCURSES/include"
# export LDFLAGS="-L$PREFIX_NCURSES/lib"
# export PKG_CONFIG_PATH="$PREFIX_NCURSES/lib/pkgconfig:$PKG_CONFIG_PATH"
#OPT_NCURSES

echo "==> Building tmux $TMUX_TAG to $PREFIX_TMUX"
cd "$BUILD"
if [ ! -d tmux ]; then
  git clone https://github.com/tmux/tmux.git
fi
cd tmux
git fetch --tags
git checkout "$TMUX_TAG"

# tmux uses autoconf; generate if missing
[ -f configure ] || sh autogen.sh

# Point tmux at your libevent; use system ncurses by default
export CPPFLAGS="-I$PREFIX_LIBEVENT/include ${CPPFLAGS:-}"
export LDFLAGS="-L$PREFIX_LIBEVENT/lib ${LDFLAGS:-}"
./configure --prefix="$PREFIX_TMUX"

make -j"$CPU"
make install

# Put it on PATH (zsh default; adjust for bash if you use that)
SHELL_RC="$HOME/.zshrc"
if [ -n "${BASH_VERSION-}" ]; then SHELL_RC="$HOME/.bashrc"; fi

grep -q 'export PATH="$HOME/apps/tmux/bin:$PATH"' "$SHELL_RC" 2>/dev/null ||
  echo 'export PATH="$HOME/apps/tmux/bin:$PATH"' >>"$SHELL_RC"

echo
echo "==> Done."
echo "Open a new shell or run: source $SHELL_RC"
echo "Then check: tmux -V"
