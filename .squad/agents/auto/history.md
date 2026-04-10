# AUTO 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: 技术主管
- 技术栈: Flutter + Dart + SQLite + Provider

## 关键代码位置

- 入口: lib/main.dart
- 数据库: lib/services/database_service.dart
- AI 服务: lib/services/ai_service.dart
- 测试入口: test/all_tests.dart

## Learnings

<!-- 在此追加学到的项目知识 -->
- 2026-04-06: 设置页关于弹窗可通过与用户指南同款 `ElevatedButton.icon` 快速扩展外链操作，使用 `_launchUrl` 统一处理外部链接打开与失败提示。
- 2026-04-10: Daily Quote provider 切换到 API Ninjas 时需要即时刷新 API Key 状态，建议在 provider 变更入口主动触发状态加载以避免 UI 显示陈旧状态。
