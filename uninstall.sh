#!/bin/bash
# uninstall.sh — removes the agent and installed files. Usage: ./uninstall.sh [--purge]
set -u
cd "$(dirname "$0")"

if [[ -x "${HOME}/.local/bin/hun" ]]; then
  "${HOME}/.local/bin/hun" uninstall "$@"
else
  ./hun uninstall "$@"
fi
rm -rf "${HOME}/.local/share/macos-hun" "${HOME}/.local/bin/hun"
echo "Done."
