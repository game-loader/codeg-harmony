#!/usr/bin/env bash
# sign.sh <in.hap> <out.hap>
#
# Two modes:
#  * AGC (installs on consumer HarmonyOS phones): set SIGN_P12, SIGN_CERT, SIGN_PROFILE
#    (paths to the .p12, .cer and .p7b from AppGallery Connect), SIGN_KEY_ALIAS,
#    SIGN_STORE_PASSWORD and SIGN_KEY_PASSWORD.
#  * Test (default): a key issued by the OpenHarmony public test CA, generated on
#    first use into $SIGN_DIR. Installs on OpenHarmony dev boards only.
set -euo pipefail
source "$(dirname "$0")/env.sh"
IN="$1"
OUT="$2"
TOOL="$SDK_LIB/hap-sign-tool.jar"
BUNDLE="${BUNDLE_NAME:-com.gameloader.codeg}"

if [ -n "${SIGN_P12:-}" ]; then
  P12="$SIGN_P12"; CERT="$SIGN_CERT"; PROFILE="$SIGN_PROFILE"
  ALIAS="$SIGN_KEY_ALIAS"; SPW="$SIGN_STORE_PASSWORD"; KPW="$SIGN_KEY_PASSWORD"
else
  P12="$SIGN_DIR/codeg.p12"; CERT="$SIGN_DIR/app.pem"; PROFILE="$SIGN_DIR/codeg.p7b"
  ALIAS="codeg-app"; SPW=123456; KPW=123456
  if [ ! -f "$PROFILE" ]; then
    mkdir -p "$SIGN_DIR"
    cp "$SDK_LIB/OpenHarmony.p12" "$P12"
    keytool -exportcert -rfc -alias "openharmony application root ca" -keystore "$P12" -storepass 123456 > "$SIGN_DIR/root.cer"
    keytool -exportcert -rfc -alias "openharmony application ca" -keystore "$P12" -storepass 123456 > "$SIGN_DIR/subca.cer"
    java -jar "$TOOL" generate-keypair -keyAlias "$ALIAS" -keyAlg ECC -keySize NIST-P-256 \
      -keystoreFile "$P12" -keystorePwd 123456 -keyPwd 123456
    java -jar "$TOOL" generate-app-cert -keyAlias "$ALIAS" -signAlg SHA256withECDSA \
      -issuer "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA" \
      -issuerKeyAlias "openharmony application ca" -issuerKeyPwd 123456 \
      -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=Codeg Release" \
      -keystoreFile "$P12" -keystorePwd 123456 -keyPwd 123456 -outForm certChain \
      -rootCaCertFile "$SIGN_DIR/root.cer" -subCaCertFile "$SIGN_DIR/subca.cer" \
      -outFile "$CERT" -validity 3650
    python3 - "$SDK_LIB/UnsgnedReleasedProfileTemplate.json" "$CERT" "$SIGN_DIR/profile.json" "$BUNDLE" <<'PY'
import json, sys, time
tpl, cert, out, bundle = sys.argv[1:]
p = json.load(open(tpl))
leaf = open(cert).read().split('-----END CERTIFICATE-----')[0] + '-----END CERTIFICATE-----\n'
p['type'] = 'release'
p['bundle-info']['bundle-name'] = bundle
p['bundle-info'].pop('development-certificate', None)
p['bundle-info']['distribution-certificate'] = leaf
p['validity'] = {'not-before': int(time.time()) - 86400, 'not-after': int(time.time()) + 86400 * 3650}
p['acls'] = {'allowed-acls': []}
p['permissions'] = {'restricted-permissions': []}
p.pop('debug-info', None)
json.dump(p, open(out, 'w'), indent=2)
PY
    java -jar "$TOOL" sign-profile -keyAlias "openharmony application profile release" \
      -signAlg SHA256withECDSA -mode localSign -profileCertFile "$SDK_LIB/OpenHarmonyProfileRelease.pem" \
      -inFile "$SIGN_DIR/profile.json" -keystoreFile "$P12" -keystorePwd 123456 -keyPwd 123456 \
      -outFile "$PROFILE"
  fi
fi

java -jar "$TOOL" sign-app -keyAlias "$ALIAS" -signAlg SHA256withECDSA -mode localSign \
  -appCertFile "$CERT" -profileFile "$PROFILE" -inFile "$IN" -keystoreFile "$P12" \
  -keystorePwd "$SPW" -keyPwd "$KPW" -outFile "$OUT" -compatibleVersion "$OHOS_API" -signCode 1
VDIR="$(mktemp -d)"
java -jar "$TOOL" verify-app -inFile "$OUT" -outCertChain "$VDIR/chain.cer" -outProfile "$VDIR/profile.p7b" \
  | tee "$VDIR/verify.log"
grep -q "verify-app success" "$VDIR/verify.log"
