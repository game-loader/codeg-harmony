# Codeg for HarmonyOS

Native ArkTS (ArkUI, Stage model, API 20) client for a `codeg-server`, matching the
feature set of the codeg iOS client: multiple servers, sessions with live ACP
streaming, permission / question / plan-approval cards, composer with images,
files, quick messages, expert skills, slash commands and agent delegation,
mode/model selectors, projects, file browser and preview (text, Markdown,
images, video), git (changes, commit, push/pull, history, branches), worktrees,
terminal (xterm.js in ArkWeb), Machines, Academic, Bark notifications and
agent settings.

## Layout

| Width | Layout |
|---|---|
| < 600 vp (phone, foldable cover screen) | bottom tabs, stacked pages |
| 600–840 vp (unfolded foldable) | side rail + list + detail |
| ≥ 840 vp (tablet, 2in1) | same, wider list |
| half-folded, horizontal crease | session splits across the crease: transcript above, composer below |

The open session survives folding and unfolding.

## Build (command line, no DevEco Studio)

Needs the OpenHarmony SDK (API 20) under `$OHOS_BASE_SDK_HOME`, JDK 17 and
`@ohos/hvigor` + `@ohos/hvigor-ohos-plugin` from `https://repo.harmonyos.com/npm/`.
See `scripts/build.sh` and `scripts/sign.sh`.

`sign.sh` signs with a certificate issued by the OpenHarmony public test CA.
That works on OpenHarmony developer boards. Consumer HarmonyOS NEXT phones
require a debug certificate and profile from AppGallery Connect (signed in
DevEco Studio with your Huawei developer account).
