#!/usr/bin/env bash
# Runs the app's non-UI ArkTS (net/, session/, store/) under Node: the .ets files
# are bundled as TypeScript with the HarmonyOS kits replaced by stubs/.
#   test/run.sh            option parser, session and file tests against a local stand-in server
#   test/run.sh live [agent]   the same session logic against a real codeg-server
#                              (needs CODEG_HOST, CODEG_PORT, CODEG_TOKEN; sends no prompt)
#   test/run.sh live-files     file preview, video stream and download against a real codeg-server
#                              running on this machine (same variables; only reads files it creates)
set -euo pipefail
cd "$(dirname "$0")"
[ -d node_modules ] || npm ci --no-audit --no-fund >/dev/null
SRC="$(cd ../entry/src/main/ets && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
bundle() {
  node_modules/.bin/esbuild "$1" --bundle --platform=node --format=esm --outfile="$OUT/$(basename "$1" .ts).mjs" \
    --loader:.ets=ts --resolve-extensions=.ets,.ts,.js --log-level=warning --external:ws \
    --alias:@kit.NetworkKit="$PWD/stubs/network.ts" --alias:@kit.ArkTS="$PWD/stubs/arkts.ts" \
    --alias:@kit.ArkData="$PWD/stubs/data.ts" --alias:@kit.AssetStoreKit="$PWD/stubs/empty.ts" \
    --alias:@kit.CoreFileKit="$PWD/stubs/files.ts" \
    --alias:@kit.AbilityKit="$PWD/stubs/empty.ts" --alias:@kit.LocalizationKit="$PWD/stubs/empty.ts" \
    --alias:@kit.BasicServicesKit="$PWD/stubs/empty.ts" --alias:@app="$SRC" \
    --tsconfig-raw='{"compilerOptions":{"experimentalDecorators":true,"useDefineForClassFields":false}}' \
    --banner:js='const ObservedV2 = (c) => c; const Trace = () => {};'
}
run() {
  bundle "$1.ts"
  # The bundle resolves `ws` and fixtures relative to this folder.
  cp "$OUT/$1.mjs" "./.$1.run.mjs"
  local rc=0
  node "./.$1.run.mjs" "${@:2}" || rc=$?
  rm -f "./.$1.run.mjs"
  return $rc
}
if [ "${1:-}" = "live" ]; then
  run options_live "${2:-claude_code}"
elif [ "${1:-}" = "live-files" ]; then
  run files_live
else
  run options_parse
  run options_session
  run files
fi
