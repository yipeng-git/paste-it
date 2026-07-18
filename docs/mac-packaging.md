# Mac packaging (Developer ID + notarization)

Direct distribution (GitHub Releases + Sparkle)，**不是** Mac App Store。产物：签名并公证的 `Paste It.app`，再打成 `PasteIt-{version}.dmg`。

一键脚本：[`scripts/package-release.sh`](../scripts/package-release.sh)  
更新发版：[`mac-updates.md`](mac-updates.md)

## 前置条件

本机 Keychain 需具备：

| 项 | 用途 |
| --- | --- |
| **Developer ID Application** 证书 | 签名 `.app` / Sparkle / DMG 内应用 |
| **notarytool** 凭据（Apple ID + App-specific password + Team ID） | 公证 |
| Sparkle EdDSA 私钥（Keychain） | `generate_appcast` 给更新签名 |

确认本机身份：

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## 公证凭据（一次）

```sh
xcrun notarytool store-credentials "paste-it-notary" \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOURTEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

可选环境变量：

```sh
export PASTEIT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export PASTEIT_NOTARY_PROFILE="paste-it-notary"
```

## 打包

```sh
./scripts/package-release.sh
```

默认产出两份 DMG：`dist/PasteIt-{ver}-arm64.dmg` 与 `dist/PasteIt-{ver}-universal.dmg`。

常用选项：

```sh
./scripts/package-release.sh --skip-notarize
./scripts/package-release.sh --skip-dmg
./scripts/package-release.sh --variant arm64
```

DMG 背景图：[`Resources/dmg-background.png`](../Resources/dmg-background.png)，由 [`scripts/make-dmg-background.py`](../scripts/make-dmg-background.py) 生成。

## 发版衔接

```sh
./scripts/release.sh 0.2.0
```

细节见 [`mac-updates.md`](mac-updates.md)。Sparkle 工具链由 `generate-appcast.sh` 下载到 `.tools/sparkle/`（已 gitignore）。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| 找不到 Developer ID Application | 证书未下到本机 |
| `notarytool` 认证失败 | App 专用密码过期或 Team ID 错 |
| 公证被拒 Invalid signature | Sparkle 内层组件需按官方顺序重签；勿盲目 `--deep` |
| Gatekeeper 仍拦 | 检查 staple；`spctl -a -vv` / `stapler validate` |
| `codesign` 报 entitlements XML 语法错 | `PasteIt.entitlements` 禁止 XML 注释 |

## 检查命令

```sh
security find-identity -v -p codesigning
codesign -dv --verbose=4 "dist/Paste It.app"
codesign --verify --deep --strict --verbose=2 "dist/Paste It.app"
xcrun stapler validate "dist/Paste It.app"
spctl -a -vv "dist/Paste It.app"
```
