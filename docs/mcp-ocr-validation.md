# MCP 与中文 OCR 修复验收

日期：2026-09-24。本次是本地源码与 Developer ID 签名安装版验收，未创建公开发行版。应用版本号仍为 0.2.8 / build 10，不代表此前下载的 0.2.8 已包含修复。

2026-09-28 已进一步改为自动语言检测，最新行为及验收见文末；9 月 24 日的固定语言配置和性能数据保留为历史记录。

## 修复内容

- MCP 无状态 HTTP 入口为每次请求创建独立 SDK Server 和 transport。客户端初始化状态与响应等待表不再共享，独立客户端、重连及相同 JSON-RPC ID 的并发请求可以正常工作。每次请求完成后关闭 transport，开关重启通过 generation 隔离旧请求。端口、默认关闭状态、工具范围不变；协议与取消限制见 [MCP 文档](mcp.md)。
- OCR 使用 Vision accurate 模式，并按该模式支持的语言筛选简中、繁中和英文。图片解码和识别在 utility 串行队列执行；采集插入不等待 OCR，完成后通过原有 MainActor 路径更新搜索索引。去掉 completion handler 与 throw 分别恢复同一 continuation 的双重完成路径。
- 不自动批量重写旧图片 OCR 或用户编辑的文字；已有图片可通过预览的 **Re-run** 重新识别。四种语言的 README 已同步操作说明。

## 自动化检查

- `swift test`：63 项测试、13 个 suite 通过；另有原本需环境变量开启的搜索性能基准跳过。
- 新增 `MCPStatelessRequestTests`：双客户端及重连、24 个客户端使用相同 ID 的并发请求、无效请求/Origin/协议版本校验、停止和重启。使用独立内存 transport，不读取实际历史。
- 新增 `OCRServiceTests`：简中、繁中、中英混排、空白/损坏图片、并发结果隔离，以及临时 HistoryStore 中重新识别后已缓存搜索结果的刷新。
- `swift build` 及 `package-release.sh --variant arm64 --skip-notarize --skip-dmg` 通过。
- `git diff --check` 通过。构建仍报告已有资源处理、截图 API 弃用和 dSYM 模块路径告警；未把这些无关项并入本次修复。

## 签名安装与实际应用

确认打包产物 Developer ID 签名有效后，退出旧应用，保留临时备份，替换 `/Applications/Paste It.app` 并启动。安装后的 `codesign --verify --deep --strict` 通过，签名链包含 `Developer ID Application`，arm64 架构；未改系统权限或清除用户数据。

- `python3 scripts/test-mcp-clients.py`：两个独立 HTTP 客户端初始化成功，重连成功；24 个客户端的初始化、工具发现、health 和使用相同请求 ID 的区别化响应验证通过。脚本不枚举历史内容。
- 使用三张新绘制的非敏感 PNG，经原生 NSPasteboard 写入触发安装版采集。复制前用唯一测试标记确认无图片结果。
- 简体样例能按“星河”找到，繁体样例也能按“星河”找到；英文样例能按 RAVEN 找到。查询始终同时带唯一测试标记和 image 过滤。
- 三条结果均为 `image`、`plainText` 为空、`ocrText` 含对应文字；通过已知测试 ID 取回的 PNG 与输入逐字节一致，排除了普通文本命中造成的假阳性。
- 用新的合成文本替换剪贴板后，仍能找回上述三张图片。
- 等待图片索引期间的 56 次 health 请求全部成功，端到端响应约 0.9–88.8 ms；这是本机有限样例观察，不是 UI 帧率或所有图片负载的性能保证。

测试仅写入合成内容、检索唯一标记及对应已知 ID；没有查看无关历史。测试结束时剪贴板为合成结束标记，测试条目按正常历史保留规则处理。

## OCR 对照与边界

在同机使用此前实测的七张合成 PNG，对比修改前后的 OCRService；每张各运行三次。图片为 1400 × 360，包括英文 28 px、英文 12 px、8 px 低对比、简中、繁中、代码符号及空白。

- 修改前简中/繁中不能读出“星河”；修改后两种均能识别，英文 12 px 样例也能正确读出 RAVEN 和 Invoice。
- accurate 首个英文样例约 298 ms，后续含文字样例约 45–76 ms；原 fast 对照除首次加载外约 6–28 ms。accurate 有计算成本，串行后台队列限制同时运行的 Vision 请求数量。
- 空白图返回 nil。8 px 低对比文字仍存在误识别，代码中的易混字符和标点仍需核对，不保证逐字符还原。
- 已验证 HTTP 客户端及签名应用的图片采集/搜索链路；没有把这些结果写成 Cursor 图形客户端、系统截图快捷键、跨应用粘贴或竞品完整应用测试通过。
- 未运行旧 macOS 版本实机测试；最低部署版本保持 macOS 14。公开网站文章和发行信息本轮未更新。

## 自动语言检测 — 2026-09-28

按用户要求启用 `VNRecognizeTextRequest.automaticallyDetectsLanguage`，移除简中、繁中、英文的固定语言列表，让系统选择识别模型。保留 accurate 模式、关闭自动文字纠正和串行后台队列。该属性自 macOS 13 可用，项目最低 macOS 14 无需额外 availability 回退。能力范围仍取决于系统 Vision 模型，不保证所有语言均可识别。参考 [Apple 自动语言检测说明](https://developer.apple.com/documentation/vision/vnrecognizetextrequest/automaticallydetectslanguage)。

### 回归测试与已知限制

- 修改前新增的日文、韩文和日英混排样例失败；修改后七组样例通过：简中、繁中、中英混排、英文、日文、韩文和日英混排。
- `swift test`：64 项测试、13 个 suite 通过，**另记录 1 项 known issue**；原有可选搜索性能基准未开启。
- 原中英混排样例 `Clipboard 星河 4821 Search` 在自动检测下把“星河”识别为 `Æ`。本机模型即使返回 confidence 1.0 也会出错；增加全部系统支持语言、调整语言顺序或开启文字纠正未解决。包含更多中文上下文的混排样例通过。
- 这个原样例没有删除，保留在 `sparseChineseInEnglishHasKnownSystemDetectionLimitation`，以 Swift Testing 的 `withKnownIssue(isIntermittent: true)` 明确记录系统限制，允许未来模型修复后正常通过。没有把该样例算作正确识别，也没有增加静默的固定中文二次识别。
- 四种语言 README 已同步自动检测、旧图片 Re-run 和短文本/混排误判说明。

### 签名安装与真实采集

- `swift build` 及 arm64 Developer ID 签名打包成功，保留原版本号。本机应用已备份、替换并启动；安装后严格签名验证通过，包含 `Developer ID Application` 身份。未创建公开发行版或更新网站文章。
- 六张新绘制的合成 PNG 经 NSPasteboard 触发真实应用采集：简中、繁中、英文、日文、韩文和中英混排。开始前唯一标记的图片查询为空。
- 六张均通过对应文字加唯一标记搜索：`星河`、`RAVEN`、`クリップボード`、`클립보드`、`截图搜索`；结果为 image、普通文本为空，原图取回逐字节一致。替换当前剪贴板为合成结束文本后，六张仍可检索。
- 混排图片首次在 20 秒等待窗口内没有出现在标记搜索结果中；直接识别该文件文字正确，重新写入相同 PNG 后约 0.43 秒可查回。最终六张逐一核验通过，但不将此记录作为快速连续复制零丢失的保证；本轮没有修改采集器。
- 仅查询合成标记和对应已知测试 ID，不枚举无关历史。旧图片仍需 Re-run 才会应用新语言策略；旧系统实机和全部支持语言未逐一测试。
