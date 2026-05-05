# M-O 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: 测试工程师
- 测试入口: test/all_tests.dart

## Learnings

<!-- 在此追加学到的项目知识 -->
- Widget 测试涉及本地化或插件依赖时，应统一在 `setUpAll`/`setUp` 调用
  `TestSetup.setupWidgetTest()`（`test/test_setup.dart`），避免遗漏
  `SharedPreferences` 与 `path_provider` mock 初始化。
- PR 评论要求初始化测试环境时，优先在具体 Widget 测试文件 `setUpAll` 中接入
  `TestSetup.setupWidgetTest()`，并通过最小目标测试文件验证通过后再提交。
- Model 单测若收到初始化一致性反馈，也应按仓库统一模式引入
  `../../test_setup.dart` 并在 `setUpAll` 调用 `TestSetup.setupUnitTest()`，
  以确保基础测试绑定与 mock 初始化行为一致。
