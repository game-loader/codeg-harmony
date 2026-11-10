#!/bin/bash
export JAVA_HOME=~/ohos/jdk-17.0.21+9 PATH=~/ohos/jdk-17.0.21+9/bin:$PATH OHOS_BASE_SDK_HOME=~/ohos/sdk
cd ~/codeg-harmony
[ -e node_modules ] || ln -s ~/ohos/hvigor/node_modules node_modules
node ~/ohos/hvigor/node_modules/@ohos/hvigor/bin/hvigor.js --mode module -p module=entry@default -p product=default -p buildMode=${MODE:-debug} assembleHap --no-daemon "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
