# Paste It

[English](README.md) | **中文** | [日本語](README.ja.md) | [한국어](README.ko.md)

只在本机运行的 macOS 剪贴板管理器 — 原生 SwiftUI、Liquid Glass，以及给 Agent 用的 MCP。

**网站：** [paste-it.app](https://paste-it.app)

![Paste It timeline panel](docs/screenshots/paste-it-history-panel.png)

- **纯本地** — 不用账号，不同步云端。历史只存在这台 Mac。
- **原生 SwiftUI** — AppKit 浮动面板 + SwiftUI 时间线。**macOS 26+ 用 Liquid Glass**（更早系统用材质效果兜底）。
- **给 AI 用** — 可选本地 **MCP**，Agent 能读历史、搜索（含 OCR），还能生成临时时间线截图。
- **能搜到图里的字** — Vision OCR 会索引复制的图片和截图；文本、富文本、HTML、文件、链接一样能搜。

![Search clipboard history including OCR](docs/screenshots/paste-it-ocr-search.png)

截图和图片里的文字也能搜到 — 不只是纯文本。

## 功能

- 浮动时间线（**Shift + Command + V**）— 看卡片和预览。
- Pinboard：拖放固定，可永久保留。
- Paste Stack（**Shift + Command + C**）— 收集、排序，再按顺序粘贴。
- **无格式粘贴** — **Control + Command + V** 把当前剪贴板剥成纯文本并粘贴（自动粘贴需要辅助功能权限）。
- Quick Copy：**Command + 1…9**，也支持多条一起复制。
- 隐私控制：暂停捕获、忽略指定 App 或 pasteboard 类型、保留期限、清理存储。
- 可选匿名统计（PostHog）— **不会**上传剪贴板内容；见 [`docs/analytics.md`](docs/analytics.md) 和 [`docs/analytics-dashboard.md`](docs/analytics-dashboard.md)。在「设置 → 隐私」里开关。
- 用 Sparkle 做应用内更新。

点选一条会先放到系统剪贴板（不需要辅助功能）。Paste Stack 的「Paste Next」可以自动按 **Command + V**，这时需要辅助功能权限。

## 隐私与分析

剪贴板历史 **只在本机**。官方构建默认开启 PostHog，只上报面板开关、粘贴准备、新手引导、更新流程这类匿名事件 — **不含**剪贴板文本、OCR、路径或搜索词。事件列表：[`docs/analytics.md`](docs/analytics.md)。看板怎么搭：[`docs/analytics-dashboard.md`](docs/analytics-dashboard.md)。随时可在 **设置 → 隐私** 关掉。

## 给 Agent 用的 MCP

可选的本地 [Model Context Protocol](https://modelcontextprotocol.io) 服务 — **默认关闭**。Paste It 运行时，在菜单栏点 **MCP** 打开。

- URL：`http://127.0.0.1:17321/mcp`（仅本机，Stateless HTTP）
- 只读历史：list、get、search（来源 App、OCR，查询语法和 App 里一样）
- 按卡片内容生成临时时间线截图（不写入主历史）

工具说明、curl 示例、客户端配置见 [`docs/mcp.md`](docs/mcp.md)（英文）。

## 系统要求

- macOS 14+
- Xcode / Swift 6.2 工具链

## 运行

```sh
swift run PasteIt
```

打一个最小 `.app`（内嵌 Sparkle，用来检查更新）：

```sh
./scripts/run-app.sh
```

也可以用 Xcode 打开这个目录，当 Swift Package 跑和调试。

## 更新

自动更新走 Sparkle。订阅地址是 [`Info.plist`](Info.plist) 里的 `SUFeedURL`（GitHub Pages）。见 [`docs/mac-updates.md`](docs/mac-updates.md)。签名发布用 [`scripts/package-release.sh`](scripts/package-release.sh)，配置见 [`docs/mac-packaging.md`](docs/mac-packaging.md)。

## 许可证

[PolyForm Noncommercial License 1.0.0](LICENSE) — 个人、教育、研究、业余等非商业用途免费。**商用需要向版权方另行授权**。

改成这份许可之前以 MIT 发布的版本，那些旧版本仍可按 MIT 使用。
