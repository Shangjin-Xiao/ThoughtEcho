# Squad Team

> ThoughtEcho (心迹) — 你的专属灵感摘录本

## Coordinator

| 名字 | 角色 | 备注 |
|------|------|------|
| Squad | 协调员 | 分配任务、执行交接、质量把关 |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| WALL·E | 产品顾问 | .squad/agents/wall-e/charter.md | 🟢 Active |
| GOPHER | 项目经理 | .squad/agents/gopher/charter.md | 🟢 Active |
| EVE | UI/UX 设计师 | .squad/agents/eve/charter.md | 🟢 Active |
| AUTO | 技术主管 | .squad/agents/auto/charter.md | 🟢 Active |
| GO-4 | 代码审查员 | .squad/agents/go-4/charter.md | 🟡 按需 |
| M-O | 测试工程师 | .squad/agents/m-o/charter.md | 🟢 Active |
| BURN-E | 营销专家 | .squad/agents/burn-e/charter.md | 🟢 Active |
| HAN-S | 内容策划 | .squad/agents/han-s/charter.md | 🟢 Active |
| VN-GO | 用户研究员 | .squad/agents/vn-go/charter.md | 🟢 Active |
| PR-T | 商店运营 | .squad/agents/pr-t/charter.md | 🟢 Active |
| Scribe | 记录员 | .squad/agents/scribe/charter.md | 📋 静默 |
| Ralph | 工作监控 | — | 🔄 监控 |

## Project Context

- **项目**: ThoughtEcho (心迹)
- **负责人**: 上晋
- **技术栈**: Flutter 3.x + Dart + SQLite + Provider + FlutterQuill + AI 多 Provider
- **平台**: Android（主要）、iOS、Windows（**不支持 Web**）
- **定位**: AI 驱动的灵感摘录本
- **创建日期**: 2026-04-06

## Team Directives

- **语言**: 所有团队成员使用**中文**与上晋沟通
- **联网搜索**: 团队成员必须**主动联网搜索最新信息**，不要依赖过时的知识
- **工作模式**: 上晋只描述产品愿景，团队全权执行技术和策略
- **开源意识**: 仓库公开可见，记录内容需适合开源环境

## Current Tasks (ToDo)

### AI Agent 核心优化
- [ ] **[紧急] 重构 WebSearchTool**：放弃脆弱的正则爬虫，接入更健壮的搜索解析逻辑（或官方 API）。
- [ ] **[急切] 补全 Agent 思考流**：在 `AgentService` 中增加 `AgentReasoningEvent`，让 AI 的“内心独白”与工具调用同步显示。
- [ ] **[进阶] 多模态 Agent 升级**：让 Agent 能够理解上传的图片，实现“看图搜笔记”。
- [ ] **[修复] 增强 Smart Result 解析**：优化正则表达式，支持更复杂的嵌套格式，确保“一键应用”功能的稳定性。
- [ ] **[优化] WebFetch 增强**：探索支持简单动态内容的抓取，或增加抓取失败的友好降级提示。
