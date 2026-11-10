# Shared paths. Override any of these from the environment (CI sets them).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OHOS_TOOLS="${OHOS_TOOLS:-$HOME/ohos}"
export OHOS_BASE_SDK_HOME="${OHOS_BASE_SDK_HOME:-$OHOS_TOOLS/sdk}"
export HVIGOR_HOME="${HVIGOR_HOME:-$OHOS_TOOLS/hvigor}"
export SIGN_DIR="${SIGN_DIR:-$OHOS_TOOLS/sign}"
export OHOS_API="${OHOS_API:-20}"
if [ -z "${JAVA_HOME:-}" ] && [ -d "$OHOS_TOOLS/jdk-17.0.21+9" ]; then
  export JAVA_HOME="$OHOS_TOOLS/jdk-17.0.21+9"
fi
[ -n "${JAVA_HOME:-}" ] && export PATH="$JAVA_HOME/bin:$PATH"
SDK_LIB="$OHOS_BASE_SDK_HOME/$OHOS_API/toolchains/lib"
