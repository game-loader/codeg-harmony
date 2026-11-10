#!/usr/bin/env bash
# Builds entry-default-unsigned.hap. MODE=release|debug (default debug).
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"
printf 'sdk.dir=%s\n' "$OHOS_BASE_SDK_HOME" > local.properties
if [ -L node_modules ] || [ ! -e node_modules ]; then ln -sfn "$HVIGOR_HOME/node_modules" node_modules; fi
set +e
node "$HVIGOR_HOME/node_modules/@ohos/hvigor/bin/hvigor.js" --mode module -p module=entry@default \
  -p product=default -p buildMode="${MODE:-debug}" assembleHap --no-daemon "$@" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | tee "$ROOT/.build.log"
status=${PIPESTATUS[0]}
set -e
grep -q "BUILD SUCCESSFUL" "$ROOT/.build.log" || exit "${status:-1}"
# `$$` two-way binding is only compiled on built-in components; on a custom
# component it reaches the device verbatim and throws ReferenceError on render.
OUT="$ROOT/entry/build/default/cache/default/default@CompileArkTS/esmodule/${MODE:-debug}"
if grep -rnF '$$this' "$OUT" --include=*.ts --include=*.js; then
  echo "error: uncompiled \$\$ binding in compiled output (see lines above)" >&2
  exit 1
fi
ls -la "$ROOT/entry/build/default/outputs/default/"
