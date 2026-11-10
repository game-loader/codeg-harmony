#!/usr/bin/env bash
# Installs the OpenHarmony SDK (Linux components) and hvigor without DevEco Studio.
set -euo pipefail
source "$(dirname "$0")/env.sh"
SDK_RELEASE="${SDK_RELEASE:-6.0-Release}"
SDK_URL="${SDK_URL:-https://repo.huaweicloud.com/openharmony/os/$SDK_RELEASE/ohos-sdk-windows_linux-public.tar.gz}"
HVIGOR_VERSION="${HVIGOR_VERSION:-6.26.9}"

if [ ! -f "$OHOS_BASE_SDK_HOME/$OHOS_API/ets/oh-uni-package.json" ]; then
  tmp="$(mktemp -d)"
  echo "Downloading $SDK_URL"
  curl -fL --retry 3 -o "$tmp/sdk.tar.gz" "$SDK_URL"
  # Only the Linux zips; native + previewer are needed for hvigor's license check.
  tar -xzf "$tmp/sdk.tar.gz" -C "$tmp" --wildcards 'linux/*.zip'
  rm "$tmp/sdk.tar.gz"
  mkdir -p "$OHOS_BASE_SDK_HOME/$OHOS_API"
  for z in "$tmp"/linux/*.zip; do
    unzip -q -o "$z" -d "$OHOS_BASE_SDK_HOME/$OHOS_API"
  done
  rm -rf "$tmp"
fi
cat "$OHOS_BASE_SDK_HOME/$OHOS_API/ets/oh-uni-package.json"

if [ ! -f "$HVIGOR_HOME/node_modules/@ohos/hvigor/bin/hvigor.js" ]; then
  mkdir -p "$HVIGOR_HOME"
  echo '{"name":"hvigor-host","version":"1.0.0","private":true}' > "$HVIGOR_HOME/package.json"
  npm install --prefix "$HVIGOR_HOME" --no-audit --no-fund \
    --registry=https://repo.harmonyos.com/npm/ \
    "@ohos/hvigor@$HVIGOR_VERSION" "@ohos/hvigor-ohos-plugin@$HVIGOR_VERSION"
fi
echo "SDK: $OHOS_BASE_SDK_HOME  hvigor: $HVIGOR_HOME"
