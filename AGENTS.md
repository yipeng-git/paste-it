# Agent notes — Paste It (macOS)

适用于整个仓库。优先遵循用户当前任务要求；以下约定用于避免破坏剪贴板行为、用户数据和 macOS 签名身份。

## 项目与代码入口

- 原生 macOS 菜单栏剪贴板管理器，使用 SwiftUI、AppKit、SwiftData，通过 Swift Package Manager 构建；不是 Web 项目，也不依赖 Xcode 工程文件。
- Swift tools version 为 **6.2**，最低支持 **macOS 14**。使用较新系统 API 时保留 availability 检查与旧系统回退；玻璃样式统一复用 `Utilities/LiquidGlass.swift`。
- `Package.swift` 定义应用 `PasteIt`、共享库 `PasteItCore`、测试 `PasteItTests`；外部依赖包括 Sparkle、MCP Swift SDK、PostHog。

| 路径（相对于仓库根目录） | 职责 |
| --- | --- |
| `Sources/PasteIt/App/` | 启动、依赖组装（`AppRuntime`）、应用状态、偏好设置和更新 |
| `Sources/PasteIt/Core/` | 剪贴板监听、内容写入、模拟粘贴、全局快捷键 |
| `Sources/PasteIt/Models/`、`Storage/` | SwiftData 模型、历史记录、文件和缩略图存储 |
| `Sources/PasteIt/Search/` | 搜索、OCR、链接元数据 |
| `Sources/PasteIt/UI/` | AppKit 面板控制器、SwiftUI 时间线、卡片与预览 |
| `Sources/PasteIt/Features/PasteStack/` | 粘贴队列及其面板 |
| `Sources/PasteIt/Settings/`、`Onboarding/` | 设置与引导界面 |
| `Sources/PasteIt/AgentAPI/`、`Analytics/` | 本地 MCP 服务、匿名统计 |
| `Sources/PasteItCore/`、`Tests/PasteItTests/` | 可独立测试的类型解析、文本处理、分类、本地化辅助及测试 |
| `Resources/`、`scripts/`、`docs/` | 资源、生成与打包脚本、专题文档 |

表中 `Storage/` 等缩写路径与同一行的完整路径具有相同父目录。

## 修改原则

- 开始先看 `git status --short` 和相关实现，保留已有的用户改动；避免无关重构、全仓格式化和顺带升级依赖。
- 沿用现有分层：共享解析逻辑优先放入 `PasteItCore`；系统交互留在应用目标；不要为了测试把面板或应用单例引入共享库。
- 遵守现有 `@MainActor` 隔离。UI 和 SwiftData 上下文操作留在所属 actor；图片解码、OCR、磁盘读取等耗时工作避免阻塞 UI。不要用新增 `@unchecked Sendable` 或 `nonisolated(unsafe)` 掩盖并发问题。
- 修改交互前先追踪控制器、状态和视图之间的调用链；复用现有面板、选中状态、焦点恢复和快捷键处理路径。
- 新的核心逻辑或缺陷修复，按需在现有 Swift Testing 测试中增加有意义的边界或回归用例（`import Testing`、`@Test`、`#expect`）；纯文档、文案或低风险样式改动不必硬加测试。

## 剪贴板、数据与隐私约束

- 区分“写入系统剪贴板”和“向前台应用自动粘贴”：前者无需 Accessibility，后者需要。保持无权限时的可用路径和提示。
- 应用自己写入剪贴板时，保留 `onPasteboardMutation` → `PasteboardMonitor.suppress(changeCount:)` 链路，避免把自身写入重复采集进历史或 Paste Stack。
- 保留暂停采集、忽略应用和受保护 pasteboard 类型过滤；测试使用合成内容，不使用真实密码或敏感剪贴板内容。
- 持久化目录为 `~/Library/Application Support/PasteIt/`，数据库为 `history.store`，附件在 `Blobs/` 和 `Thumbnails/`。**不要改用 SwiftData 默认的 `Application Support/default.store`**，它可能与其他未沙盒化应用冲突。
- 不要通过删除真实历史、附件、偏好设置或重置系统权限来让测试通过。模型、清理或迁移改动需考虑现有数据兼容性；测试优先使用临时目录和内存存储，复用已有 ephemeral 支持。
- 日志、测试快照和提交内容不得包含真实剪贴板正文、OCR、文件内容或私人路径。统计仅发送允许的元数据，不上传搜索词、剪贴板内容或 MCP payload；新增事件时同步 `AnalyticsCatalog` 与 [统计说明](docs/analytics.md)，并保留退出统计的行为。
- MCP 默认关闭，仅绑定 `127.0.0.1:17321`，不暴露主时间线、采集或设置的修改能力。截图工具使用临时历史；保持其与真实存储隔离。接口变化同步 [MCP 文档](docs/mcp.md)。
- 不打印或提交 `Secrets/posthog.env`、签名私钥、公证凭据；沿用脚本的凭据注入方式。

## 本地化与资源

- 用户可见文案使用现有 `L10n.tr` 模式与稳定 key，保留英文默认值；格式参数（如 `%@`、`%lld`）在各语言中必须匹配。
- 翻译源在 `scripts/generate-localizations.py`、`scripts/localization_batch2.py`、`scripts/localization_batch_cjk.py`。修改对应源表后，从仓库根目录运行：

  ```sh
  python3 scripts/generate-localizations.py
  ```

- 一并检查并提交生成的 `Resources/Localization/Localizable.xcstrings` 和 `Resources/*.lproj/Localizable.strings`；不要只修改会被生成脚本覆盖的输出。检查 diff，避免夹带无关翻译重写。
- 新增语言时同步 `Info.plist` 的 `CFBundleLocalizations`；新增或更新文案时检查长文本和中日韩字符的截断、换行。
- 用户可见功能或快捷键发生变化时，同步受影响的 README 语言版本和专题文档。

## 按改动范围验证

所有命令默认在仓库根目录执行。

| 改动 | 验证要求 |
| --- | --- |
| 仅文档 | 核对路径、命令与现有实现，运行 `git diff --check`；无需构建或安装 |
| Swift 核心逻辑 | `swift test`，并用 `swift build` 验证应用目标集成 |
| UI、面板、手势、选择、快捷键、粘贴、Accessibility | 构建检查，加下节的签名安装和真实交互验证；涉及核心逻辑时也运行测试 |
| 本地化、资源 | 核对生成 diff、占位符和资源打包；影响界面时用签名安装检查显示 |
| Shell 脚本 | `bash -n scripts/<changed-script>.sh`，再执行与任务相关的安全验证；不能把语法通过当作签名或发布成功 |

测试目标目前只依赖 `PasteItCore`；`swift test` 不能覆盖面板、系统权限或跨应用粘贴。`swift run PasteIt` / `./scripts/run-app.sh` 仅供临时调试，不代替下面的验收流程。

## UI / 行为必须使用签名安装验证

涉及手势、粘贴、Accessibility、面板、选择等需要真实应用验证的改动，**不能只跑 `swift build` 或 `run-app.sh` 就交付**。绝不把未签名、ad-hoc 签名或 `.build` 下的 debug 应用安装到 `/Applications`。

必须打包 **Developer ID 签名的 arm64 构建**，安装到 `/Applications`，并由 agent 自己启动验证。本地验证不需要公证，使用 `--skip-notarize` 即可。

```sh
./scripts/package-release.sh --variant arm64 --skip-notarize --skip-dmg
```

确认打包成功、产物存在且 Developer ID 签名正确后，退出正在运行的 Paste It，再执行替换安装；不要在打包失败时删除现有安装：

```sh
codesign --verify --deep --strict --verbose=2 "dist/arm64/Paste It.app"
codesign -dv "dist/arm64/Paste It.app" 2>&1 | grep Authority

rm -rf "/Applications/Paste It.app"
cp -R "dist/arm64/Paste It.app" "/Applications/Paste It.app"
xattr -dr com.apple.quarantine "/Applications/Paste It.app" 2>/dev/null || true
open "/Applications/Paste It.app"
```

交付前再次确认安装的应用身份：

```sh
codesign -dv "/Applications/Paste It.app" 2>&1 | grep Authority
```

输出必须包含 `Developer ID Application: …`。如果证书、系统权限或环境阻止验证，完成其他可执行检查，并明确说明阻塞和未验证行为，不得换用 ad-hoc 安装或声称已通过。

按本次改动选择真实交互场景，不必每次穷举：

- 采集与粘贴：复制合成文本、富文本、图片或文件，检查类型与去重；Return 粘贴到目标应用、⇧Return 纯文本粘贴，并确认焦点恢复及没有再次采集自身写入。
- 时间线与预览：⇧⌘V 打开/关闭、搜索与过滤、键盘选择、⌘-click 多选、Space 预览、⌘E 编辑；检查面板关闭和焦点切换。
- Paste Stack：⇧⌘C 打开、复制入队、在目标应用连续 ⌘V，核对 FIFO/LIFO 顺序与空队列行为。
- 存储与设置：相关设置生效，重启后历史、置顶和文件夹保持正确；权限相关改动验证对应授权状态，不擅自重置已有授权。
- 视觉改动：检查相关浅色/深色界面、长文案和窗口位置。MCP 的 `paste_it_render_screenshot` 可用合成卡片检查真实时间线样式，但截图不能代替粘贴、焦点和手势验证。

签名前置条件和公证细节见 [mac-packaging.md](docs/mac-packaging.md)。

## 打包、发布与交付

- 日常本地验证使用 `package-release.sh --variant arm64 --skip-notarize --skip-dmg`，不需要提升版本、生成 appcast 或发布。
- 发布按 [mac-updates.md](docs/mac-updates.md) 和 `scripts/release.sh` 执行；版本由脚本管理，保持 `CFBundleVersion` 单调递增，不手工拼装更新签名。
- **`release.sh` 是有副作用的发布流程，不是构建检查命令。** 默认会改版本、签名、公证、创建 GitHub Release、更新 `docs/appcast.xml`、提交、打 tag 和 push，仅在任务已授权发布时使用。
- `--dry-run` 仍会修改 `Info.plist`、打包/公证和更新本地 appcast；`--no-push` 仍会创建 GitHub Release、提交和 tag。不要把这些选项当成只读或仅本地构建的保证。
- 保持现有 bundle ID 和签名方式；`PasteIt.entitlements` 不添加 XML 注释。签名、Sparkle 嵌套组件和资源拷贝沿用打包脚本，不用临时命令替代发布实现。
- 不提交 `.build/`、`dist/`、`updates/` 下的发布二进制、`.tools/` 或本地凭据；生成的本地化资源是需要提交的项目资源。
- 结束前检查 `git diff --check`、`git diff --stat` 和 `git status --short`，确认没有无关修改。交付时简要说明改了什么、执行了哪些验证、结果如何，以及尚未验证的部分；UI 改动说明签名安装与实际操作结果。
