# WALL·E 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: 产品顾问
- 平台: Android（主要）、iOS、Windows

## Learnings

### 2026-04-06: 产品现状全面分析

**项目规模**: 成熟的中大型 Flutter 应用
- lib/services: 68+ 服务文件（含数据库、AI、备份、同步等）
- lib/pages: 35+ 页面（覆盖笔记、AI、设置、同步等场景）
- lib/widgets: 45+ UI 组件
- 平台: Android、iOS、Windows（已上架 Microsoft Store）

**核心功能模块**:
1. 笔记管理 - 富文本编辑、多媒体、草稿自动保存
2. AI 助手 - 多 Provider 架构（OpenAI/Anthropic/DeepSeek 等）、问答、润色、洞察报告
3. 智能推送 - 基于上下文的智能提醒
4. 数据同步 - LocalSend 协议、局域网多设备同步
5. 备份恢复 - ZIP 流式处理、紧急恢复机制
6. 情境感知 - 位置、天气、时间段自动记录

**技术亮点**:
- 大文件流式处理，防 OOM
- 本地优先存储策略，保护隐私
- Material 3 动态主题
- 完整的国际化支持（中英双语）

**产品定位**: "AI 赋能的个人灵感笔记本" — 差异化在于 AI 深度集成 + 本地隐私保护
