#!/bin/bash
# sign.sh <in.hap> <out.hap> — signs with a cert issued by the OpenHarmony public test CA
export PATH=~/ohos/jdk-17.0.21+9/bin:$PATH; L=~/ohos/sdk/20/toolchains/lib; S=~/ohos/sign
java -jar $L/hap-sign-tool.jar sign-app -keyAlias "codeg-app" -signAlg SHA256withECDSA -mode localSign \
  -appCertFile $S/app.pem -profileFile $S/codeg.p7b -inFile "$1" -keystoreFile $S/codeg.p12 \
  -keystorePwd 123456 -keyPwd 123456 -outFile "$2" -compatibleVersion 20 -signCode 1 2>&1 | grep -E "success|ERROR|Message"
java -jar $L/hap-sign-tool.jar verify-app -inFile "$2" -outCertChain /tmp/vchain.cer -outProfile /tmp/vprof.p7b 2>&1 | grep -E "success|fail|ERROR"
