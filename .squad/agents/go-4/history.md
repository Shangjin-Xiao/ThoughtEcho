# GO-4 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: 代码审查员
- 何时出场: 大型重构时

## 审查工具

- Copilot 内置 review
- CodeRabbit CLI (本地)

## Learnings

<!-- 在此追加学到的项目知识 -->
- 2026-04-10 PR #197 triage：CodeRabbit 的 7 条 inline + 1 条 outside diff 评论中，目前仅 2 条（两个 widget 测试接入 `test_setup.dart`）在工作区已处理，其余核心逻辑问题仍未落地（`app_settings` 容错反序列化、API Ninjas 分类过滤、provider 切换刷新 key 状态、`humor -> l` 映射、旧 provider 兼容、unit test 初始化）。
- 审查时需同时读取 `/pulls/{id}/comments` 与 `/pulls/{id}/reviews`；outside diff 评论不会出现在 inline comments 列表，只能从 review body 的 `Outside diff range comments` 区块提取并单独跟踪。
