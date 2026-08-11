# Paste It

[English](README.md) | **中文** | [日本語](README.ja.md) | [한국어](README.ko.md)

面向 macOS 的本地剪贴板管理器 — 视觉时间线、可搜索的历史（含截图里的字），原生体验，不打扰你。

**网站：** [paste-it.app](https://paste-it.app)

![Paste It timeline panel](docs/screenshots/paste-it-history-panel.png)

## 功能

- 可视化时间线，浏览你复制过的内容
- 能搜文本，也能搜截图和图片里的字
- 预览一条，改完再粘贴
- 钉住重要条目（还可放进文件夹）
- Paste Stack：按顺序粘贴多段内容

## 安装

1. 从 [paste-it.app](https://paste-it.app) 或 [GitHub Releases](https://github.com/yipeng-git/paste-it/releases/latest) 下载最新版。
2. 打开 `.dmg`（或解压），把 **Paste It** 拖进 **应用程序**。
3. 从应用程序启动。它会待在菜单栏。
4. 若希望一键粘贴到其他 App，按提示开启 **辅助功能**（系统设置 → 隐私与安全性 → 辅助功能）。

需要 macOS 14 或更高版本。官方构建会在后台自动更新。

## 使用

1. 照常复制 — Paste It 在本机记录历史。
2. 按 **⇧⌘V**（或点菜单栏图标）打开时间线。
3. 输入搜索，或按类型筛选。用 **⌘1…9** 快速选中，或选中卡片后按 **Return** 粘贴。
4. 按 **Space** 在时间线上方预览。点文字可编辑；图片可看 OCR，链接有网页预览。
5. 需要保留的条目可以钉住，或放进自定义文件夹（最多三个）。

### 更多快捷键

| 快捷键 | 作用 |
|--------|------|
| **⇧⌘V** | 打开 / 关闭时间线 |
| **⌘1…9** | 选中该卡片并关闭面板 |
| **Return** | 粘贴选中项（需辅助功能） |
| **⇧Return** | 按纯文本粘贴 |
| **Space** | 预览 |
| **⌘E** | 编辑选中项 |
| **⇧⌘C** | 打开 Paste Stack |
| **⌥⌘V** | 粘贴 Stack 下一项 |
| **⌃⌘V** | 当前剪贴板按纯文本粘贴一次 |
| **⇧⌘T** | 暂停 / 继续捕获（菜单里） |

**Paste Stack：** 按 **⇧⌘C**，连续复制几段进队列，再用 **⌥⌘V**（或 Stack 打开时按 **⌘V**）一项项粘贴。顺序（先旧 / 先新）在「设置 → Stack」。

**多选：** **⌘**-点击多张卡片，再按 **Return** 按顺序粘贴。

点选一条会先放到系统剪贴板（不需要辅助功能）。自动粘贴（**Return**、Stack、**⌃⌘V**）需要辅助功能。

## 隐私

历史只留在这台 Mac — 不用账号，不同步云端。密码管理器等受保护的 pasteboard 类型默认会跳过。可在设置里暂停捕获、忽略 App、限制保留时间。

可选匿名统计（官方构建默认开启）**不会**包含剪贴板内容、OCR、路径或搜索词。随时可在 **设置 → 隐私** 关闭。说明：[`docs/analytics.md`](docs/analytics.md)。

## 给 Agent 用（可选）

Paste It 可开启本地 [MCP](https://modelcontextprotocol.io)，让 Agent 读取和搜索历史。**默认关闭** — 应用运行时在菜单栏打开 **MCP**（`http://127.0.0.1:17321/mcp`）。配置与工具：[`docs/mcp.md`](docs/mcp.md)。

## 从源码构建

给贡献者：

```sh
swift run PasteIt
# 或
./scripts/run-app.sh
```

需要 Xcode / Swift 6.2。打包与签名见 [`docs/mac-packaging.md`](docs/mac-packaging.md)。更新机制见 [`docs/mac-updates.md`](docs/mac-updates.md)。

## 许可证

[PolyForm Noncommercial License 1.0.0](LICENSE) — 个人、教育、研究、业余等非商业用途免费。**商用需要向版权方另行授权**。

改成这份许可之前以 MIT 发布的版本，那些旧版本仍可按 MIT 使用。
