#!/bin/bash
# Installs Quartus Prime Lite 25.1std + Cyclone V into $HOME/altera/25.1std.
# Altera's installers are not public: they sit in the private repo $ASSETS_REPO (release $ASSETS_TAG),
# fetched with the token in $ASSETS_TOKEN, and are kept in $HOME/quartus-dl (Actions cache).
set -euxo pipefail
ASSETS_REPO=${ASSETS_REPO:-ollisulopuisto/mirlo64-quartus-assets}
ASSETS_TAG=${ASSETS_TAG:-q25.1}
DL=$HOME/quartus-dl
mkdir -p "$DL"
cd "$DL"
for f in qinst-lite-linux-25.1std-1129.run cyclonev-25.1std.0.1129.qdz; do
  if [ ! -s "$f" ]; then
    : "${ASSETS_TOKEN:?ASSETS_TOKEN secret is not set}"
    GH_TOKEN=$ASSETS_TOKEN gh release download "$ASSETS_TAG" -R "$ASSETS_REPO" -p "$f"
  fi
done
# refuse an HTML error page posing as an installer
head -c 2 qinst-lite-linux-25.1std-1129.run | grep -q '#!'
unzip -tq cyclonev-25.1std.0.1129.qdz >/dev/null
ls -l
[ "${DOWNLOAD_ONLY:-0}" = 1 ] && exit 0
chmod +x qinst-lite-linux-25.1std-1129.run
./qinst-lite-linux-25.1std-1129.run --nox11 --noprogress -- --cli --download-dir "$DL" --install-dir "$HOME/altera/25.1std" \
  --accept-eula --components quartus,cyclonev
QSH=$HOME/altera/25.1std/quartus/bin/quartus_sh
test -x "$QSH"
echo "QUARTUS_BIN=$(dirname "$QSH")" >> "$GITHUB_ENV"
"$QSH" --version
