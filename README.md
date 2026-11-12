# Codeg for HarmonyOS

Native ArkTS (ArkUI, Stage model, API 20) client for a `codeg-server`, matching the
feature set of the codeg iOS client: multiple servers, sessions with live ACP
streaming, permission / question / plan-approval cards, composer with images,
files, quick messages, expert skills, slash commands and agent delegation,
mode/model selectors, projects, file browser and preview (text, Markdown,
images, video, PDF), files referenced in replies (tap to preview, save to the
device, open in another app), git (changes, commit, push/pull, history, branches), worktrees,
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

```bash
scripts/setup-sdk.sh            # OpenHarmony 6.0 SDK (API 20) + hvigor into ~/ohos
MODE=release scripts/build.sh   # entry/build/default/outputs/default/entry-default-unsigned.hap
scripts/sign.sh in.hap out.hap  # sign + verify
```

Needs JDK 17, Node 20+, curl, unzip and python3. Paths can be overridden with
`OHOS_TOOLS`, `OHOS_BASE_SDK_HOME`, `HVIGOR_HOME` and `SIGN_DIR`.

## Tests

```bash
test/run.sh                 # no device, no server needed
test/run.sh live [agent]    # mode/model options against a real codeg-server (CODEG_HOST, CODEG_PORT, CODEG_TOKEN)
test/run.sh live-files      # file preview, video stream and download against a codeg-server on this machine
```

The non-UI ArkTS (`net/`, `session/`, `store/`) is bundled as TypeScript with the
HarmonyOS kits replaced by small Node stand-ins (`test/stubs/`), so the same code
the app ships is what runs. `test/run.sh` checks the mode/model option parser
against catalogs recorded from a server, the rules that recognise and locate
files referenced in replies, and drives `SessionController` and the streamed
download against a local stand-in server (`test/fake_server.mjs`). `live` runs
the session logic against a real server: it starts an agent, changes its
settings and disconnects, without sending a prompt. `live-files` reads and
downloads temporary files it creates itself. Views are not covered.

## CI

`.github/workflows/build-hap.yml` runs `test/run.sh`, then builds and signs a
release HAP on every push and pull request and uploads it as the
`codeg-harmony-hap` artifact.

- Every push to `main` replaces the rolling **latest** release:
  https://github.com/game-loader/codeg-harmony/releases/tag/latest
- Pushing a `v*` tag publishes a versioned release.

## Signing

Without secrets, CI signs with a certificate issued by the OpenHarmony public
test CA. That installs on OpenHarmony developer boards, but consumer HarmonyOS
NEXT phones reject it.

To produce a HAP that installs on your own phone, create a debug certificate
and a debug profile (with your device registered) in AppGallery Connect, then
add these repository secrets:

| Secret | Value |
|---|---|
| `HAP_SIGN_P12_BASE64` | `base64 -w0 your.p12` |
| `HAP_SIGN_CERT_BASE64` | `base64 -w0 your.cer` |
| `HAP_SIGN_PROFILE_BASE64` | `base64 -w0 your.p7b` |
| `HAP_SIGN_KEY_ALIAS` | key alias in the .p12 |
| `HAP_SIGN_STORE_PASSWORD` | keystore password |
| `HAP_SIGN_KEY_PASSWORD` | key password |

The bundle name in the profile must be `com.gameloader.codeg`. Install with
`hdc install <file>.hap`.
