---
name: thoughtecho-docs-automation
description: "Manually triggered skill to update developer (AGENTS.md, README.md) and user (USER_MANUAL.md, index.html, user-guide.html) documentation based on recent Flutter/Dart code changes. ONLY trigger when the user EXPLICITLY requests a documentation update. Trigger phrases include: '更新文档', 'update docs', 'sync docs', '同步文档', '文档同步', '根据最近的改动更新说明', '帮我更新一下文档', '帮我把文档同步一下'. DO NOT trigger when the user just mentions '文档' in passing, when discussing code changes without asking for docs, or when making edits to code. This skill must never run proactively or as a side effect of code changes."
---

# ThoughtEcho Documentation Automation

Manually triggered documentation sync for the ThoughtEcho project.

## When NOT to use this skill

- The user is writing code, fixing bugs, or discussing features — even if docs could theoretically be updated.
- The user mentions "文档" but does not ask you to update it.
- The user just finished a feature but hasn't asked to update docs yet.
- **Only use when the user explicitly says something like "更新文档" or "帮我同步文档".**

## Documentation Files

| File | Audience | Purpose |
|------|----------|---------|
| `AGENTS.md` | AI/Developers | Architecture rules, anti-patterns, complexity hotspots |
| `README.md` | Developers + Users | Project overview, tech stack, quick start |
| `docs/USER_MANUAL.md` | End Users | Bilingual user manual (中文 + English) |
| `res/index.html` | Website Visitors | Landing page with feature cards, tech, FAQ |
| `res/user-guide.html` | End Users (Web) | Web user manual (mirrors USER_MANUAL.md) |

## Scope Rules: What triggers a doc update

### Trigger matrix for `docs/USER_MANUAL.md`

Only update if the change maps to an existing chapter:

| Chapter | What counts |
|---------|-------------|
| `1. 快速入门 / Getting Started` | Onboarding, daily quotes, quick capture, clipboard |
| `2. AI 服务配置 / AI Service Configuration` | New AI providers, API key logic, local model |
| `3. 富文本编辑器 / Rich Text Editor` | Formatting tools, editor UI changes |
| `4. 笔记管理 / Note Management` | Search, filtering, categories, trash, pinning |
| `5. AI 功能 / AI Features` | Rewrite, summarize, translate, prompts, reports |
| `6. 设备同步 / Device Sync` | LocalSend, cross-device sync |
| `7. 备份与恢复 / Backup & Restore` | Export/import formats, backup behavior |
| `8. 设置详解 / Settings Guide` | Theme, language, preferences, developer mode |
| `9. 常见问题 / FAQ` | Only if no existing section fits AND users will be confused |

**Rules:**
- Add one tight bullet under the matching heading. Not a paragraph.
- Update BOTH 中文版本 and English Version sections.
- No code, no variable names, no class names.

### Trigger matrix for `res/index.html`

| Section | ID/Class | When to update |
|---------|----------|----------------|
| Hero (口号区) | `.hero` | Tagline/subtitle changed |
| 功能特性 | `#features` | New user-facing feature → add feature-card in matching category |
| Feature categories | `.feature-category-title` | 🎨 心迹 (core), 💡 懂你所想 (AI), 🛡️ 安全无忧 (security), 🚀 开放自由 (open source) |
| 截图 | `#screenshots` | Screenshots added/removed |
| 技术栈 | `#tech` | Major tech stack change |
| 快速开始 | `#quickstart` | Install/build steps change |
| 路线图 | `#roadmap` | Committed roadmap changes |
| 常见问题 | `#faq` | New FAQ needed |

**Rules:**
- Match existing HTML patterns exactly (same `<div class="feature-card">` structure).
- Both `content-zh` and `content-en` spans required.
- Small changes (bug fixes, internal refactors) → skip the website entirely.

### Trigger matrix for `README.md`

| Section | When to update |
|---------|----------------|
| `当前功能 / Current Features` | Major new feature |
| `技术栈 / Tech Stack` | Dependency/platform change |
| `快速开始 / Quick Start` | Install/run steps change |
| `发展路线图 / Development Roadmap` | Committed roadmap changes |
| `如何贡献 / How to Contribute` | Contributor workflow changes |

### Trigger matrix for `AGENTS.md`

| Section | When to update |
|---------|----------------|
| 目录结构 | New major folders |
| 常用命令 | New build/test/lint commands |
| 架构约定 | Provider/service/model pattern changes |
| 禁止事项 | New anti-patterns |
| 复杂度热点 | File past 1000 lines or new complex service |
| AI 服务配置 | New AI provider |
| 平台差异 | Platform behavior changes |

### `res/user-guide.html`

Mirrors `docs/USER_MANUAL.md`. If you update USER_MANUAL.md, also update user-guide.html.

### `res/privacy.html`

Do NOT touch unless privacy policy text actually changes.

## Anti-Patterns

Do NOT:
- Update docs for internal refactors that don't change user behavior
- Add "总结", "综上所述", "Enjoy the new feature" or any filler
- Write class/variable names in user-facing docs
- Create new files when existing sections suffice
- Update Chinese section but forget English section
- Rewrite unaffected sections to "improve" them
- Add features to index.html that don't exist in the app
- Touch privacy.html unless privacy policy changes
- Update AGENTS.md for a pure UI copy tweak

## Execution Steps

1. Read recent code changes (git diff, git log, or ask user).
2. Check trigger matrix: does this change map to any doc section? If no, say so and stop.
3. Draft minimum text needed. One bullet per section.
4. Apply edits with `edit` tool. Match exact strings for oldString.
5. For bilingual files, update both Chinese and English.
6. Verify: read file back, check no broken HTML/Markdown.
