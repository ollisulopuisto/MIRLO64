#!/bin/bash
# Installs Quartus Prime Lite 25.1std (build 1129) + Cyclone V support into $HOME/altera/25.1std.
# Installers are kept in $HOME/quartus-dl (restored from the Actions cache when present).
set -euxo pipefail
BASE=https://downloads.intel.com/akdlm/software/acdsinst/25.1std/1129/ib_installers
DL=$HOME/quartus-dl
mkdir -p "$DL"
cd "$DL"
for f in QuartusLiteSetup-25.1std.0.1129-linux.run cyclonev-25.1std.0.1129.qdz; do
  if [ ! -s "$f" ]; then curl -fL --retry 5 --retry-delay 10 -o "$f" "$BASE/$f"; fi
done
ls -l
[ "${DOWNLOAD_ONLY:-0}" = 1 ] && exit 0
chmod +x QuartusLiteSetup-25.1std.0.1129-linux.run
./QuartusLiteSetup-25.1std.0.1129-linux.run --mode unattended --unattendedmodeui none \
  --accept_eula 1 --installdir "$HOME/altera/25.1std"
QSH=$(find "$HOME/altera" -name quartus_sh -type f | head -1)
test -n "$QSH"
echo "QUARTUS_BIN=$(dirname "$QSH")" >> "$GITHUB_ENV"
"$QSH" --version
