#!/usr/bin/env bash
# Install (or update) lun.drawer into the Omarchy plugins directory.
# Omarchy forbids symlinks inside a plugin folder, so this copies the real files.
# Re-run it any time to update an existing install.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${OMARCHY_PLUGINS:-$HOME/.config/omarchy/plugins}/lun.drawer"

mkdir -p "$dest"
# Copy only the runtime plugin files — not docs, license, git, or this script.
install -m 0644 "$src/Drawer.qml" "$src/manifest.json" "$src/README.md" "$dest/"
echo "Copied plugin files to $dest"

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$dest"   # prints nothing, exits 0 on success
  echo "Validated. Restarting the shell…"
  omarchy restart shell
  echo "Done. Add a { \"id\": \"lun.drawer\", \"items\": [...] } entry to a bar section in ~/.config/omarchy/shell.json — see the README."
else
  echo "'omarchy' not on PATH — files are in place; restart your shell manually."
fi
