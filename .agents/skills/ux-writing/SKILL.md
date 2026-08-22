---
name: ux-writing
description: "Guidance and rules for UX writing, microcopy, feature descriptions, and dialog messages in ThoughtEcho. Use when writing, reviewing, or translating user-facing text, settings descriptions, onboarding steps, error messages, and tooltips in lib/l10n/."
---

# ThoughtEcho UX Writing & Microcopy Guide

This skill provides guidelines for crafting, reviewing, and auditing user-facing copy in ThoughtEcho.

## Core Brand Tone
- **Warm, introspective, and focused on personal thoughts** ("你的专属灵感摘录本").
- **Concise and respectful**: Avoid conversational filler or aggressive marketing speak.
- **Calm and trustworthy**: Respect user privacy and local-first data ownership.

## 4 Golden Rules

### 1. User-Facing, Not Code-Facing (面向用户而非实现细节)
- ❌ Do NOT expose technical implementation details (e.g. `SQL`, `Sentry`, `401`, `JSON`, `HTML`, `SVG`, `FFI`, `MMKV`, `tokens`, `内存保护`, `流式处理`, `管道`, `锁冲突`).
- ✅ Describe the user-facing purpose or benefit:
  - ❌ "已与云端网盘建立加密合并管道" → ✅ "已连接云端网盘，实时同步已就绪"
  - ❌ "数据库仅记录 SQL 模板和耗时" → ✅ "仅收集应用闪退日志与基础性能，绝不收集笔记与隐私"
  - ❌ "流式处理技术，防止内存溢出" → ✅ "优化媒体存储与流畅播放，低内存占用"

### 2. Benefit-Driven, Actionable Copy (行动与价值导向)
- Describe what the user gains or needs to do, rather than the internal mechanics.
  - ❌ "新建笔记时自动勾选位置信息" → ✅ "新建笔记时自动记录当前位置"
  - ❌ "网络通信或云盘文件锁冲突。我们将自动重试。" → ✅ "网络连接不稳定或云端正在被其他设备更新，稍后将自动重试。"

### 3. Consistency in Terminology & Tone (术语与语气统一)
- **Daily Quotes**: Use "每日一言" everywhere. Do NOT use hitokoto or quote API names in user-facing UI.
- **Sync**: Distinguish "附近设备同步" (LAN / Wi-Fi P2P) from "WebDAV 云同步" (private cloud sync).
- **AI Assistant**: Use "Thoughter" or "灵感对话 / AI 助手", never "Agent 功能".
- **Pronouns**: Default to polite, warm phrasing. Keep consistent with the app voice.

### 4. Actionable Error Messages (错误提供可操作路径)
- Clearly state what happened in plain language.
- Provide actionable next steps (e.g., 1. 重新生成 2. 检查 AI 服务商设置 3. 查看基础统计).
- Never dump raw stack traces or internal parsing errors to end users without friendly packaging.

## Multi-Language Rule (l10n)
- Always update both `lib/l10n/app_zh.arb` and `lib/l10n/app_en.arb`.
- Preserve any `{placeholders}` used by code and declare them in `@key` metadata.
- Avoid hardcoding text in Dart widgets (`lib/pages/` or `lib/widgets/`).
