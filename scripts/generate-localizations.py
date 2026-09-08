#!/usr/bin/env python3
"""Generate Resources/Localization/Localizable.xcstrings from the translation table."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from localization_batch2 import BATCH2_LANGS, merge_batch2
from localization_batch_cjk import merge_batch_cjk

OUT = ROOT / "Resources" / "Localization" / "Localizable.xcstrings"
LPROJ_ROOT = ROOT / "Resources"

SUPPORTED_LANGS = ("en", "zh-Hans", "zh-Hant", "ja", "ko", *BATCH2_LANGS)

# key -> { en, zh-Hans, ja, ... }
STRINGS: dict[str, dict[str, str]] = {
    # Filter categories
    "filter.all": {"en": "All types", "zh-Hans": "全部类型", "ja": "すべての種類"},
    "filter.text": {"en": "Text", "zh-Hans": "文本", "ja": "テキスト"},
    "filter.number": {"en": "Number", "zh-Hans": "数字", "ja": "数値"},
    "filter.link": {"en": "Link", "zh-Hans": "链接", "ja": "リンク"},
    "filter.image": {"en": "Image", "zh-Hans": "图片", "ja": "画像"},
    "filter.file": {"en": "File", "zh-Hans": "文件", "ja": "ファイル"},
    "filter.byType": {"en": "Filter by type", "zh-Hans": "按类型筛选", "ja": "種類で絞り込み"},
    "filter.clear": {"en": "Clear type filter", "zh-Hans": "清除类型筛选", "ja": "種類フィルタを解除"},
    # Timeline tabs
    "tab.default": {"en": "Default", "zh-Hans": "默认", "ja": "デフォルト"},
    "tab.pinned": {"en": "Pinned", "zh-Hans": "已固定", "ja": "ピン留め"},
    "tab.folder": {"en": "Folder", "zh-Hans": "文件夹", "ja": "フォルダ"},
    # Clip types
    "clipType.text": {"en": "Text", "zh-Hans": "文本", "ja": "テキスト"},
    "clipType.richText": {"en": "Rich Text", "zh-Hans": "富文本", "ja": "リッチテキスト"},
    "clipType.html": {"en": "HTML", "zh-Hans": "HTML", "ja": "HTML"},
    "clipType.image": {"en": "Image", "zh-Hans": "图片", "ja": "画像"},
    "clipType.file": {"en": "File", "zh-Hans": "文件", "ja": "ファイル"},
    "clipType.url": {"en": "Link", "zh-Hans": "链接", "ja": "リンク"},
    "clipType.mixed": {"en": "Mixed", "zh-Hans": "混合", "ja": "混合"},
    "clipType.folder": {"en": "Folder", "zh-Hans": "文件夹", "ja": "フォルダ"},
    "clipType.empty": {"en": "Empty", "zh-Hans": "空", "ja": "空"},
    "clipPreview.oneCharacter": {"en": "1 character", "zh-Hans": "1 个字符", "ja": "1 文字"},
    "clipPreview.characters": {"en": "%lld characters", "zh-Hans": "%lld 个字符", "ja": "%lld 文字"},
    # Keep history
    "keepHistory.oneDay": {"en": "1 Day", "zh-Hans": "1 天", "ja": "1 日"},
    "keepHistory.oneWeek": {"en": "1 Week", "zh-Hans": "1 周", "ja": "1 週間"},
    "keepHistory.oneMonth": {"en": "1 Month", "zh-Hans": "1 个月", "ja": "1 か月"},
    "keepHistory.forever": {"en": "Forever", "zh-Hans": "永久", "ja": "無期限"},
    # Paste stack
    "stack.fifo": {"en": "First in, first out", "zh-Hans": "先进先出", "ja": "先入れ先出し"},
    "stack.lifo": {"en": "Last in, first out", "zh-Hans": "后进先出", "ja": "後入れ先出し"},
    "stack.fifoHelp": {
        "en": "Copy order. Click to reverse.",
        "zh-Hans": "按复制顺序。点击切换方向。",
        "ja": "コピー順。クリックで反転。",
    },
    "stack.lifoHelp": {
        "en": "Newest first. Click for copy order.",
        "zh-Hans": "最新优先。点击切换为复制顺序。",
        "ja": "新しい順。クリックでコピー順に。",
    },
    "stack.paste": {"en": "Paste", "zh-Hans": "粘贴", "ja": "ペースト"},
    "stack.open": {"en": "Open Paste Stack", "zh-Hans": "打开粘贴堆栈", "ja": "ペーストスタックを開く"},
    "stack.close": {"en": "Close Paste Stack", "zh-Hans": "关闭粘贴堆栈", "ja": "ペーストスタックを閉じる"},
    "stack.title": {"en": "Stack", "zh-Hans": "堆栈", "ja": "スタック"},
    "stack.statusWithCount": {"en": "Stack · %lld", "zh-Hans": "堆栈 · %lld", "ja": "スタック · %lld"},
    "stack.collecting": {"en": "Collecting", "zh-Hans": "收集中", "ja": "収集中"},
    "stack.closeHelp": {"en": "Close Paste Stack (⇧⌘C)", "zh-Hans": "关闭粘贴堆栈 (⇧⌘C)", "ja": "ペーストスタックを閉じる (⇧⌘C)"},
    "stack.pasteNext": {"en": "⌘V pastes next", "zh-Hans": "⌘V 粘贴下一项", "ja": "⌘V で次をペースト"},
    "stack.emptyTitle": {"en": "Copy to fill the stack", "zh-Hans": "复制内容以填充栈", "ja": "コピーしてスタックを埋める"},
    "stack.emptySubtitle": {"en": "Then ⌘V in any app", "zh-Hans": "然后在任意应用中按 ⌘V", "ja": "その後、任意のアプリで ⌘V"},
    "stack.accessibilityHint": {
        "en": "Grant Accessibility so ⌘V can advance the stack",
        "zh-Hans": "请允许辅助功能权限，以便 ⌘V 可推进堆栈",
        "ja": "⌘V でスタックを進めるにはアクセシビリティを許可してください",
    },
    "stack.resizeHelp": {"en": "Drag to resize height", "zh-Hans": "拖动以调整高度", "ja": "ドラッグで高さを変更"},
    "stack.moveToNext": {"en": "Move to Next", "zh-Hans": "移到下一项", "ja": "次へ移動"},
    "stack.delete": {"en": "Delete", "zh-Hans": "删除", "ja": "削除"},
    # Menu bar
    "menu.openPaste": {"en": "Open Paste", "zh-Hans": "打开剪贴板", "ja": "クリップボードを開く"},
    "menu.clearStack": {"en": "Clear Paste Stack", "zh-Hans": "清空粘贴堆栈", "ja": "ペーストスタックをクリア"},
    "menu.pastePlain": {"en": "Paste Without Formatting", "zh-Hans": "粘贴为纯文本", "ja": "書式なしでペースト"},
    "menu.pauseCapture": {"en": "Pause Capture", "zh-Hans": "暂停捕获", "ja": "キャプチャを一時停止"},
    "menu.resumeCapture": {"en": "Resume Capture", "zh-Hans": "恢复捕获", "ja": "キャプチャを再開"},
    "menu.mcp": {"en": "MCP", "zh-Hans": "MCP", "ja": "MCP"},
    "menu.copyMcpURL": {"en": "Copy MCP URL", "zh-Hans": "复制 MCP 地址", "ja": "MCP URL をコピー"},
    "menu.preferences": {"en": "Preferences…", "zh-Hans": "偏好设置…", "ja": "環境設定…"},
    "menu.checkUpdates": {"en": "Check for Updates…", "zh-Hans": "检查更新…", "ja": "アップデートを確認…"},
    "menu.quit": {"en": "Quit Paste It", "zh-Hans": "退出 Paste It", "ja": "Paste It を終了"},
    "menu.more": {"en": "More", "zh-Hans": "更多", "ja": "その他"},
    "menu.statusTooltip": {
        "en": "Paste It — hold ⌘C / ⌘V to press the keys",
        "zh-Hans": "Paste It — 按住 ⌘C / ⌘V 查看按键",
        "ja": "Paste It — ⌘C / ⌘V を押し続けてキーを表示",
    },
    "menu.statusClickHint": {
        "en": "Left-click: timeline · Right-click: menu",
        "zh-Hans": "左键：时间线 · 右键：菜单",
        "ja": "左クリック：タイムライン · 右クリック：メニュー",
    },
    # Timeline
    "timeline.clearFilter": {"en": "Clear filter", "zh-Hans": "清除筛选", "ja": "フィルタを解除"},
    "timeline.selectedCount": {
        "en": "%lld selected — Return to paste",
        "zh-Hans": "已选 %lld 项 — 按 Return 键粘贴",
        "ja": "%lld 件選択 — Return でペースト",
    },
    "timeline.newFolder": {"en": "New Folder", "zh-Hans": "新建文件夹", "ja": "新規フォルダ"},
    "timeline.newFolderHelp": {"en": "New Folder", "zh-Hans": "新建文件夹", "ja": "新規フォルダ"},
    "timeline.search": {"en": "Search (⌘F)", "zh-Hans": "搜索 (⌘F)", "ja": "検索 (⌘F)"},
    "timeline.searchHistory": {"en": "Search history", "zh-Hans": "搜索历史", "ja": "履歴を検索"},
    "timeline.noMatch": {"en": "No matching clips", "zh-Hans": "没有匹配的剪贴项", "ja": "一致する項目がありません"},
    "timeline.noTypeInPinned": {
        "en": "No %@ clips in Pinned",
        "zh-Hans": "已固定中没有 %@ 类型的剪贴项",
        "ja": "ピン留めに %@ の項目はありません",
    },
    "timeline.noTypeInFolder": {
        "en": "No %@ clips in this folder",
        "zh-Hans": "此文件夹中没有 %@ 类型的剪贴项",
        "ja": "このフォルダに %@ の項目はありません",
    },
    "timeline.noType": {
        "en": "No %@ clips",
        "zh-Hans": "没有 %@ 类型的剪贴项",
        "ja": "%@ の項目はありません",
    },
    "timeline.emptyDefault": {
        "en": "Copy something to build your clipboard history",
        "zh-Hans": "复制一些内容以建立剪贴板历史",
        "ja": "コピーしてクリップボード履歴を作成",
    },
    "timeline.emptyPinned": {
        "en": "Pin clips to keep them here permanently",
        "zh-Hans": "固定剪贴项以永久保留在此",
        "ja": "ピン留めしてここに常に表示",
    },
    "timeline.emptyFolder": {
        "en": "Add clips to this folder from the context menu",
        "zh-Hans": "从右键菜单将剪贴项添加到此文件夹",
        "ja": "コンテキストメニューからこのフォルダに追加",
    },
    "timeline.unpin": {"en": "Unpin", "zh-Hans": "取消固定", "ja": "ピン留めを解除"},
    "timeline.pin": {"en": "Pin", "zh-Hans": "固定", "ja": "ピン留め"},
    "timeline.addToFolder": {"en": "Add to Folder", "zh-Hans": "添加到文件夹", "ja": "フォルダに追加"},
    "timeline.removeFromFolder": {"en": "Remove from Folder", "zh-Hans": "从文件夹移除", "ja": "フォルダから削除"},
    "timeline.delete": {"en": "Delete", "zh-Hans": "删除", "ja": "削除"},
    "timeline.removeFromFolderAction": {"en": "Remove from Folder", "zh-Hans": "从文件夹移除", "ja": "フォルダから削除"},
    "timeline.copy": {"en": "Copy to Clipboard", "zh-Hans": "复制到剪贴板", "ja": "クリップボードにコピー"},
    "timeline.copyPlain": {"en": "Copy as Plain Text", "zh-Hans": "复制为纯文本", "ja": "プレーンテキストでコピー"},
    "timeline.edit": {"en": "Edit", "zh-Hans": "编辑", "ja": "編集"},
    "timeline.cancel": {"en": "Cancel", "zh-Hans": "取消", "ja": "キャンセル"},
    "timeline.create": {"en": "Create", "zh-Hans": "创建", "ja": "作成"},
    # Settings tabs
    "settings.tab.about": {"en": "About", "zh-Hans": "关于", "ja": "このアプリについて"},
    "settings.tab.general": {"en": "General", "zh-Hans": "通用", "ja": "一般"},
    "settings.tab.privacy": {"en": "Privacy", "zh-Hans": "隐私", "ja": "プライバシー"},
    "settings.tab.folders": {"en": "Folders", "zh-Hans": "文件夹", "ja": "フォルダ"},
    "settings.tab.stack": {"en": "Stack", "zh-Hans": "粘贴堆栈", "ja": "スタック"},
    "settings.tab.storage": {"en": "Storage", "zh-Hans": "存储", "ja": "ストレージ"},
    "settings.version": {"en": "Paste It %@ (%@)", "zh-Hans": "Paste It %@ (%@)", "ja": "Paste It %@ (%@)"},
    "settings.aboutBlurb": {
        "en": "Paste It is a local-first clipboard manager. History stays on this Mac.",
        "zh-Hans": "Paste It 是一款本地优先的剪贴板管理器。历史记录仅保存在本 Mac。",
        "ja": "Paste It はローカル優先のクリップボードマネージャーです。履歴はこの Mac にのみ保存されます。",
    },
    "settings.versionLabel": {"en": "Version", "zh-Hans": "版本", "ja": "バージョン"},
    "settings.showTutorial": {"en": "Show Tutorial…", "zh-Hans": "显示教程…", "ja": "チュートリアルを表示…"},
    "settings.whatsNew": {"en": "What's New…", "zh-Hans": "新功能…", "ja": "新機能…"},
    "settings.checkingUpdates": {"en": "Checking for updates…", "zh-Hans": "正在检查更新…", "ja": "アップデートを確認中…"},
    "settings.pauseCapture": {"en": "Pause clipboard capture", "zh-Hans": "暂停剪贴板捕获", "ja": "クリップボードのキャプチャを一時停止"},
    "settings.pastePlainDefault": {
        "en": "Paste as plain text by default",
        "zh-Hans": "默认粘贴为纯文本",
        "ja": "デフォルトでプレーンテキストとしてペースト",
    },
    "settings.plainTextFootnote": {
        "en": "⌃⌘V pastes once as plain text, then restores the original clipboard (Accessibility required to auto-paste). In the timeline, ⇧↩ pastes the selection as plain text.",
        "zh-Hans": "⌃⌘V 会粘贴一次纯文本，然后恢复原来的剪贴板内容（自动粘贴需要辅助功能权限）。在时间轴中，⇧↩ 会将所选内容粘贴为纯文本。",
        "ja": "⌃⌘V で一度プレーンテキストをペーストし、元のクリップボードを復元します（自動ペーストにはアクセシビリティが必要）。タイムラインでは ⇧↩ で選択項目をプレーンテキストとしてペーストします。",
    },
    "settings.launchAtLogin": {"en": "Launch at login", "zh-Hans": "登录时启动", "ja": "ログイン時に起動"},
    "settings.keepHistory": {"en": "Keep history", "zh-Hans": "保留历史", "ja": "履歴の保持"},
    "settings.maxHistoryItems": {"en": "Max history items", "zh-Hans": "最大历史条数", "ja": "履歴の最大件数"},
    "settings.clipboardPolling": {"en": "Clipboard polling", "zh-Hans": "剪贴板轮询", "ja": "クリップボードのポーリング"},
    "settings.seconds": {"en": "s", "zh-Hans": "秒", "ja": "秒"},
    "settings.stackDirection": {"en": "Default paste direction", "zh-Hans": "默认粘贴方向", "ja": "デフォルトのペースト方向"},
    "settings.stackFootnote": {
        "en": "⇧⌘C opens or closes Paste Stack. While the stack has items, ⌘V in any app pastes the next one (Accessibility required). Runtime controls live in the Stack panel and the ⋯ menu.",
        "zh-Hans": "⇧⌘C 可打开或关闭粘贴堆栈。堆栈中有内容时，在任意应用中按 ⌘V 可粘贴下一项（需辅助功能权限）。运行时控制位于堆栈面板和 ⋯ 菜单。",
        "ja": "⇧⌘C でペーストスタックを開閉。スタックに項目がある間、任意のアプリで ⌘V が次をペーストします（アクセシビリティが必要）。実行時の操作はスタックパネルと ⋯ メニューにあります。",
    },
    "settings.maxBinaryStorage": {
        "en": "Max binary storage: %lld MB",
        "zh-Hans": "最大二进制存储：%lld MB",
        "ja": "最大バイナリ容量：%lld MB",
    },
    "settings.pruneNow": {"en": "Prune Now", "zh-Hans": "立即清理", "ja": "今すぐ整理"},
    "settings.clearKeepPinned": {
        "en": "Clear History, Keep Pinned",
        "zh-Hans": "清除历史，保留已固定",
        "ja": "履歴を消去（ピン留めは保持）",
    },
    "settings.clearAllHistory": {"en": "Clear All History", "zh-Hans": "清除全部历史", "ja": "履歴をすべて消去"},
    # Folders settings
    "folders.pinnedFooter": {
        "en": "The Pinned tab cannot be renamed or deleted. Use Pin / Unpin on clips to manage its contents.",
        "zh-Hans": "「已固定」标签无法重命名或删除。在剪贴项上使用固定/取消固定来管理内容。",
        "ja": "「ピン留め」タブは名前変更・削除できません。項目のピン留め/解除で内容を管理します。",
    },
    "folders.noCustom": {"en": "No custom folders", "zh-Hans": "没有自定义文件夹", "ja": "カスタムフォルダはありません"},
    "folders.rename": {"en": "Rename…", "zh-Hans": "重命名…", "ja": "名前を変更…"},
    "folders.addHelp": {"en": "Add Folder", "zh-Hans": "添加文件夹", "ja": "フォルダを追加"},
    "folders.renameHelp": {"en": "Rename Folder", "zh-Hans": "重命名文件夹", "ja": "フォルダ名を変更"},
    "folders.deleteHelp": {"en": "Delete Folder", "zh-Hans": "删除文件夹", "ja": "フォルダを削除"},
    "folders.footer": {
        "en": "Create up to %lld custom folders. They appear as tabs next to Default and Pinned. Clips in folders are kept when history is pruned.",
        "zh-Hans": "最多创建 %lld 个自定义文件夹。它们会显示在「默认」和「已固定」旁的标签中。清理历史时文件夹中的剪贴项会保留。",
        "ja": "カスタムフォルダは最大 %lld 個。デフォルトとピン留めの隣のタブに表示されます。履歴整理時もフォルダ内の項目は保持されます。",
    },
    "folders.renameTitle": {"en": "Rename Folder", "zh-Hans": "重命名文件夹", "ja": "フォルダ名を変更"},
    "folders.namePlaceholder": {"en": "Folder name", "zh-Hans": "文件夹名称", "ja": "フォルダ名"},
    "folders.renameConfirm": {"en": "Rename", "zh-Hans": "重命名", "ja": "名前を変更"},
    # Privacy
    "privacy.analytics": {"en": "Analytics", "zh-Hans": "分析", "ja": "アナリティクス"},
    "privacy.shareAnalytics": {
        "en": "Share anonymous usage analytics",
        "zh-Hans": "分享匿名使用分析",
        "ja": "匿名の利用状況分析を共有",
    },
    "privacy.whatWeCollect": {"en": "What we collect", "zh-Hans": "我们收集的内容", "ja": "収集するデータ"},
    "privacy.eventsBlurb": {
        "en": "Events help improve Paste It (activation, panel use, updates). Data is anonymous and sent to PostHog when enabled.",
        "zh-Hans": "事件数据有助于改进 Paste It（激活、面板使用、更新等）。启用后匿名发送至 PostHog。",
        "ja": "イベントは Paste It の改善に役立ちます（有効化、パネル利用、アップデートなど）。有効時は匿名で PostHog に送信されます。",
    },
    "privacy.neverCollected": {"en": "Never collected", "zh-Hans": "永不收集", "ja": "収集しないもの"},
    "privacy.productEvents": {"en": "Product events", "zh-Hans": "产品事件", "ja": "プロダクトイベント"},
    "privacy.fullDisclosure": {"en": "Full disclosure on GitHub", "zh-Hans": "GitHub 上的完整说明", "ja": "GitHub で完全な開示"},
    "privacy.analyticsFooter": {
        "en": "Optional. Off means no events are sent. See %@ in the open-source repo.",
        "zh-Hans": "可选。关闭后不会发送任何事件。详见开源仓库中的 %@。",
        "ja": "任意です。オフの場合イベントは送信されません。オープンソースリポジトリの %@ を参照してください。",
    },
    "privacy.noIgnoredApps": {"en": "No ignored apps", "zh-Hans": "没有忽略的应用", "ja": "無視するアプリはありません"},
    "privacy.addApp": {"en": "Add App", "zh-Hans": "添加应用", "ja": "アプリを追加"},
    "privacy.removeApp": {"en": "Remove App", "zh-Hans": "移除应用", "ja": "アプリを削除"},
    "privacy.ignoredApps": {"en": "Ignored Apps", "zh-Hans": "忽略的应用", "ja": "無視するアプリ"},
    "privacy.ignoredAppsFooter": {
        "en": "Copies made in these apps are never saved to history. Use this for password managers and other sensitive apps.",
        "zh-Hans": "这些应用中的复制内容不会保存到历史。适用于密码管理器等敏感应用。",
        "ja": "これらのアプリでのコピーは履歴に保存されません。パスワードマネージャーなどに使用してください。",
    },
    "privacy.protectedContent": {"en": "Protected Content", "zh-Hans": "受保护内容", "ja": "保護されたコンテンツ"},
    "privacy.protectedBlurb": {
        "en": "Sensitive clipboard markers from apps — such as password fields and temporary clips — are ignored automatically.",
        "zh-Hans": "来自应用的敏感剪贴板标记（如密码字段和临时剪贴）会自动忽略。",
        "ja": "パスワード欄や一時クリップなど、アプリの機密クリップボードマーカーは自動的に無視されます。",
    },
    "privacy.protectedFooter": {
        "en": "Ignored Apps skip everything from a whole app. Protected Content skips only marked sensitive pasteboard data, from any app.",
        "zh-Hans": "忽略的应用会跳过整个应用的所有内容。受保护内容仅跳过任何应用中标记为敏感的剪贴板数据。",
        "ja": "無視するアプリはアプリ全体をスキップします。保護されたコンテンツは、任意のアプリで機密とマークされたペーストボードデータのみをスキップします。",
    },
    "privacy.addIgnoredApp": {"en": "Add Ignored App", "zh-Hans": "添加忽略的应用", "ja": "無視するアプリを追加"},
    "privacy.chooseApp": {"en": "Choose…", "zh-Hans": "选择…", "ja": "選択…"},
    "privacy.search": {"en": "Search", "zh-Hans": "搜索", "ja": "検索"},
    "privacy.loadingApps": {"en": "Loading apps…", "zh-Hans": "正在加载应用…", "ja": "アプリを読み込み中…"},
    "privacy.chooseAppPanel": {"en": "Choose an app to ignore", "zh-Hans": "选择要忽略的应用", "ja": "無視するアプリを選択"},
    # Onboarding
    "onboarding.capture.title": {"en": "Copy to save", "zh-Hans": "复制即保存", "ja": "コピーして保存"},
    "onboarding.paste.title": {"en": "Pick from the timeline", "zh-Hans": "从时间线选取", "ja": "タイムラインから選択"},
    "onboarding.browse.title": {"en": "Preview & edit", "zh-Hans": "预览与编辑", "ja": "プレビューと編集"},
    "onboarding.organize.title": {"en": "Multi-select paste", "zh-Hans": "多选粘贴", "ja": "複数選択してペースト"},
    "onboarding.stack.title": {"en": "Paste Stack", "zh-Hans": "粘贴堆栈", "ja": "ペーストスタック"},
    "onboarding.capture.caption": {
        "en": "Copy anything — Paste It saves it and flashes ⌘C in the menu bar.",
        "zh-Hans": "复制任意内容 — Paste It 会保存并在菜单栏闪烁 ⌘C。",
        "ja": "何でもコピー — Paste It が保存し、メニューバーで ⌘C を点滅させます。",
    },
    "onboarding.paste.caption": {
        "en": "⇧⌘V opens history. Double-click a clip, then ⌘V — or ⌃⌘V to paste without formatting.",
        "zh-Hans": "⇧⌘V 打开历史。双击剪贴项后按 ⌘V — 或 ⌃⌘V 无格式粘贴。",
        "ja": "⇧⌘V で履歴を開く。項目をダブルクリックして ⌘V — または ⌃⌘V で書式なしペースト。",
    },
    "onboarding.browse.caption": {
        "en": "Press Space to preview above the timeline. Click the text to edit.",
        "zh-Hans": "按空格键在时间线上方预览。点击文本可编辑。",
        "ja": "スペースでタイムライン上にプレビュー。テキストをクリックして編集。",
    },
    "onboarding.organize.caption": {
        "en": "⌘-click several clips, then press Return to paste them in order.",
        "zh-Hans": "⌘-点击多个剪贴项，然后按 Return 按顺序粘贴。",
        "ja": "⌘-クリックで複数選択し、Return で順にペースト。",
    },
    "onboarding.stack.caption": {
        "en": "⇧⌘C opens a queue on the right. Copy several things, then ⌘V in the target app to paste them one by one.",
        "zh-Hans": "⇧⌘C 在右侧打开队列。复制多项后，在目标应用中按 ⌘V 逐一粘贴。",
        "ja": "⇧⌘C で右にキューを開く。複数コピー後、対象アプリで ⌘V を押して順にペースト。",
    },
    "onboarding.step.copy": {"en": "Copy", "zh-Hans": "复制", "ja": "コピー"},
    "onboarding.step.saved": {"en": "Saved", "zh-Hans": "已保存", "ja": "保存済み"},
    "onboarding.step.open": {"en": "Open", "zh-Hans": "打开", "ja": "開く"},
    "onboarding.step.doubleClick": {"en": "Double-click", "zh-Hans": "双击", "ja": "ダブルクリック"},
    "onboarding.step.paste": {"en": "Paste", "zh-Hans": "粘贴", "ja": "ペースト"},
    "onboarding.step.plain": {"en": "Plain", "zh-Hans": "纯文本", "ja": "プレーン"},
    "onboarding.step.space": {"en": "Space", "zh-Hans": "空格", "ja": "スペース"},
    "onboarding.step.preview": {"en": "Preview", "zh-Hans": "预览", "ja": "プレビュー"},
    "onboarding.step.edit": {"en": "Edit", "zh-Hans": "编辑", "ja": "編集"},
    "onboarding.step.cmdClick": {"en": "⌘-click", "zh-Hans": "⌘-点击", "ja": "⌘-クリック"},
    "onboarding.step.order": {"en": "Order", "zh-Hans": "顺序", "ja": "順序"},
    "onboarding.step.return": {"en": "Return", "zh-Hans": "Return", "ja": "Return"},
    "onboarding.demo.next": {"en": "NEXT", "zh-Hans": "下一步", "ja": "次へ"},
    "onboarding.demo.clickToEdit": {"en": "Click to edit", "zh-Hans": "点击编辑", "ja": "クリックして編集"},
    "onboarding.demo.copyToCollect": {"en": "Copy to collect", "zh-Hans": "复制以收集", "ja": "コピーして収集"},
    "onboarding.demo.doubleClick": {"en": "Double-click", "zh-Hans": "双击", "ja": "ダブルクリック"},
    # Misc
    "common.cancel": {"en": "Cancel", "zh-Hans": "取消", "ja": "キャンセル"},
    "common.delete": {"en": "Delete", "zh-Hans": "删除", "ja": "削除"},
    "common.create": {"en": "Create", "zh-Hans": "创建", "ja": "作成"},
}


# Product experience: primary actions, permission recovery, and removal undo.
STRINGS.update({
    "removal.undoShort": {
        "en": "Undo",
        "zh-Hans": "撤销",
        "ja": "取り消す"
    },
    "removal.namedFolder": {
        "en": "Remove from “%@”",
        "zh-Hans": "从「%@」移除",
        "ja": "「%@」から取り除く"
    },
    "removal.removedFolder": {
        "en": "Removed from “%@”",
        "zh-Hans": "已从「%@」移除",
        "ja": "「%@」から取り除きました"
    },
    "removal.removedHistory": {
        "en": "Removed from History",
        "zh-Hans": "已从历史移除",
        "ja": "履歴から取り除きました"
    },
    "removal.unpinned": {
        "en": "Unpinned",
        "zh-Hans": "已取消置顶",
        "ja": "ピン留めを解除しました"
    },
    "removal.restored": {
        "en": "Removal undone",
        "zh-Hans": "已撤销移除",
        "ja": "取り除きを取り消しました"
    }
})

STRINGS.update({
    "action.paste": {
        "en": "Direct Paste",
        "zh-Hans": "直接粘贴",
        "ja": "直接ペースト"
    },
    "action.copyOnly": {
        "en": "Copy Only",
        "zh-Hans": "仅复制",
        "ja": "コピーのみ"
    },
    "action.cannotEdit": {
        "en": "Editing is not available for this clip",
        "zh-Hans": "此剪贴项不支持编辑",
        "ja": "この項目は編集できません"
    },
    "removal.everywhere": {
        "en": "Delete Everywhere",
        "zh-Hans": "从所有位置删除",
        "ja": "すべての場所から削除"
    },
    "removal.everywhereDetail": {
        "en": "Delete this clip from history, Pinned, and all folders? This cannot be undone.",
        "zh-Hans": "从历史、置顶和所有文件夹中删除此项？此操作无法撤销。",
        "ja": "履歴、ピン留め、すべてのフォルダからこの項目を削除しますか？取り消しできません。"
    },
    "action.dismiss": {
        "en": "Dismiss message",
        "zh-Hans": "关闭提示",
        "ja": "メッセージを閉じる"
    },
    "action.retry": {
        "en": "Retry",
        "zh-Hans": "重试",
        "ja": "再試行"
    },
    "action.returnToApp": {
        "en": "Return to App",
        "zh-Hans": "返回目标应用",
        "ja": "アプリに戻る"
    },
    "action.selectionCount": {
        "en": "%lld selected",
        "zh-Hans": "已选 %lld 项",
        "ja": "%lld 件選択"
    },
    "removal.undo": {
        "en": "Undo Removal",
        "zh-Hans": "撤销移除",
        "ja": "取り除きを取り消す"
    },
    "removal.undoHelp": {
        "en": "Undo recent removals for 30 seconds (⌘Z).",
        "zh-Hans": "30 秒内可撤销最近的移除（⌘Z）。",
        "ja": "30秒以内の取り除きを取り消します（⌘Z）。"
    },
    "action.enablePaste": {
        "en": "Enable Direct Paste",
        "zh-Hans": "启用直接粘贴",
        "ja": "直接ペーストを有効にする"
    },
    "removal.stillSaved": {
        "en": "Removed from History; still saved in Pinned or folders",
        "zh-Hans": "已从历史移除，仍保存在置顶或文件夹中",
        "ja": "履歴から取り除きました。ピン留めまたはフォルダには残っています"
    },
    "removal.history": {
        "en": "Remove from History",
        "zh-Hans": "从历史移除",
        "ja": "履歴から取り除く"
    },
    "action.copySingle": {
        "en": "Select one clip to copy. Use ⇧Return to paste multiple clips as plain text.",
        "zh-Hans": "请选择一项进行复制。多项可用 ⇧Return 按纯文本粘贴。",
        "ja": "コピーする項目を1つ選択してください。複数項目は ⇧Return でプレーンテキストとしてペーストできます。"
    },
    "action.writeFailed": {
        "en": "Could not copy this clip. Its content or attachment may be unavailable. Restore the file, then retry.",
        "zh-Hans": "无法复制此项，内容或附件可能不可用。请恢复文件后重试。",
        "ja": "内容または添付ファイルを利用できないためコピーできませんでした。ファイルを復元して再試行してください。"
    },
    "action.copiedManual": {
        "en": "Copied. Return to your app and press ⌘V. Enable Accessibility for direct paste.",
        "zh-Hans": "已复制。返回目标应用后按 ⌘V。开启辅助功能即可直接粘贴。",
        "ja": "コピーしました。対象アプリに戻って ⌘V を押してください。直接ペーストにはアクセシビリティを許可してください。"
    },
    "action.copied": {
        "en": "Copied to Clipboard",
        "zh-Hans": "已复制到剪贴板",
        "ja": "クリップボードにコピーしました"
    },
    "action.multiPermission": {
        "en": "Enable Accessibility to paste multiple clips, or select one clip to copy manually.",
        "zh-Hans": "请启用辅助功能以粘贴多项，或选择一项复制后手动粘贴。",
        "ja": "複数項目のペーストにはアクセシビリティを許可するか、1項目を選んで手動でコピー・ペーストしてください。"
    },
    "action.focusChanged": {
        "en": "Paste stopped because the destination or permission changed. Focus your destination and try the remaining clips again.",
        "zh-Hans": "目标应用或权限已变化，粘贴已停止。请聚焦目标位置后重试剩余项。",
        "ja": "対象アプリまたは権限が変わったため停止しました。対象にフォーカスして残りの項目を再試行してください。"
    },
    "action.pasteSent": {
        "en": "Paste request sent",
        "zh-Hans": "已发送粘贴请求",
        "ja": "ペースト要求を送信しました"
    },
    "removal.confirmTitle": {
        "en": "Review History Cleanup",
        "zh-Hans": "确认历史清理范围",
        "ja": "履歴の整理内容を確認"
    },
    "removal.confirmCount": {
        "en": "%lld clips will be permanently deleted. This cannot be undone and ends removal undo.",
        "zh-Hans": "将永久删除 %lld 项。此操作无法撤销，并会结束之前的移除撤销。",
        "ja": "%lld 件を完全に削除します。この操作と以前の項目の削除を取り消せなくなります。"
    },
    "removal.keepSaved": {
        "en": "Pinned clips and clips in folders will be kept.",
        "zh-Hans": "置顶和文件夹中的内容将保留。",
        "ja": "ピン留めとフォルダ内の項目は保持されます。"
    },
    "removal.includeSaved": {
        "en": "This includes Pinned and every folder. The folders themselves will remain.",
        "zh-Hans": "包括置顶和所有文件夹中的内容，文件夹本身将保留。",
        "ja": "ピン留めとすべてのフォルダ内の項目を含みます。フォルダ自体は保持されます。"
    },
    "removal.newRetention": {
        "en": "New retention period: %@",
        "zh-Hans": "新的保留期限：%@",
        "ja": "新しい保存期間：%@"
    },
    "removal.confirmDelete": {
        "en": "Delete Reviewed Clips",
        "zh-Hans": "删除已确认的记录",
        "ja": "確認した項目を削除"
    },
    "removal.failedTitle": {
        "en": "History Was Not Changed",
        "zh-Hans": "历史记录未更改",
        "ja": "履歴は変更されませんでした"
    },
    "action.setting": {
        "en": "Timeline primary action",
        "zh-Hans": "时间线主要操作",
        "ja": "タイムラインの主操作"
    },
    "action.settingDetail": {
        "en": "Double-click, Return, and ⌘1–9 use the selected action. Direct Paste is the default. ⇧Return always pastes plain text.",
        "zh-Hans": "双击、Return 和 ⌘1–9 统一执行所选操作，默认直接粘贴。⇧Return 始终按纯文本粘贴。",
        "ja": "ダブルクリック・Return・⌘1–9は選択した操作を実行します。既定は直接ペーストです。⇧Returnは常にプレーンテキストでペーストします。"
    },
    "removal.clearKeepSaved": {
        "en": "Clear History, Keep Pinned & Folders…",
        "zh-Hans": "清空历史，保留置顶和文件夹…",
        "ja": "履歴を消去し、ピン留めとフォルダを保持…"
    },
    "action.permissionReady": {
        "en": "Direct paste is enabled",
        "zh-Hans": "已启用直接粘贴",
        "ja": "直接ペーストは有効です"
    },
    "action.permissionNeeded": {
        "en": "Direct paste needs Accessibility",
        "zh-Hans": "直接粘贴需要辅助功能权限",
        "ja": "直接ペーストにはアクセシビリティが必要です"
    },
    "action.permissionDetail": {
        "en": "Accessibility lets Paste It send ⌘V to your destination app. You can still copy clips and paste them manually without granting access.",
        "zh-Hans": "辅助功能允许 Paste It 向目标应用发送 ⌘V。未授权也可以复制内容后手动粘贴。",
        "ja": "アクセシビリティを許可すると対象アプリに ⌘V を送信できます。許可しなくてもコピーして手動でペーストできます。"
    },
    "removal.saveFailed": {
        "en": "Could not save the change. Your history has been restored; try again.",
        "zh-Hans": "无法保存更改，已恢复历史记录，请重试。",
        "ja": "変更を保存できませんでした。履歴を復元しました。再試行してください。"
    },
    "action.tutorial": {
        "en": "Select a clip, ⌘C to copy, then ⌘V in your app. Choose Direct Paste in Settings for one-step reuse.",
        "zh-Hans": "选中一项，按 ⌘C 复制，再到目标应用按 ⌘V。可在设置中选择直接粘贴以一步完成。",
        "ja": "項目を選んで ⌘C でコピーし、対象アプリで ⌘V。設定で直接ペーストを選ぶと一度の操作で再利用できます。"
    }
})


def escape_strings_value(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_strings_files(strings: dict[str, dict[str, str]], out_dir: Path) -> None:
    for lang in SUPPORTED_LANGS:
        lproj = out_dir / f"{lang}.lproj"
        lproj.mkdir(parents=True, exist_ok=True)
        lines = []
        for key, locs in sorted(strings.items()):
            value = locs.get(lang, locs["en"])
            lines.append(f'"{escape_strings_value(key)}" = "{escape_strings_value(value)}";')
        (lproj / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_catalog(strings: dict[str, dict[str, str]]) -> dict:
    catalog_strings: dict = {}
    for key, locs in strings.items():
        entry: dict = {
            "localizations": {
                lang: {
                    "stringUnit": {
                        "state": "translated",
                        "value": value,
                    }
                }
                for lang, value in locs.items()
            }
        }
        catalog_strings[key] = entry
    return {
        "sourceLanguage": "en",
        "strings": catalog_strings,
        "version": "1.0",
    }


def main() -> None:
    strings = merge_batch_cjk(merge_batch2(STRINGS))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(build_catalog(strings), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_strings_files(strings, LPROJ_ROOT)
    print(f"Wrote {len(strings)} keys × {len(SUPPORTED_LANGS)} langs to {OUT} and {LPROJ_ROOT}/*.lproj")


if __name__ == "__main__":
    main()
