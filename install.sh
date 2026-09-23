#!/bin/bash
# install.sh — fresh-machine setup: installs `hun` + the launchd agent.
# Usage: ./install.sh [--interval SEC]
set -u
cd "$(dirname "$0")"

DEST_SHARE="${HOME}/.local/share/macos-hun"
DEST_BIN="${HOME}/.local/bin/hun"

mkdir -p "$DEST_SHARE" "${HOME}/.local/bin"
cp -R hun lib launchd "$DEST_SHARE/"
chmod +x "$DEST_SHARE/hun"
ln -sf "$DEST_SHARE/hun" "$DEST_BIN"

if ! command -v a2h >/dev/null 2>&1 && [[ ! -x "${HOME}/.local/bin/a2h" ]]; then
  echo "note: a2h not found on PATH. Install it first:"
  echo "  curl -fsSL https://raw.githubusercontent.com/TyrellD1/agenttohuman/main/install.sh | bash"
  echo "  a2h init   # configure your destination"
fi

"$DEST_BIN" install "$@"
echo "Done. Try: hun status  ·  hun test-notify"
