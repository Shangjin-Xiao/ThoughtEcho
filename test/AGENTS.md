# TEST 模块

测试入口 `all_tests.dart`，Mock 配置在 `test_setup.dart`（**禁止手动编辑 `*.mocks.dart`**）。

## 运行命令
```bash
flutter test test/unit/models/quote_model_test.dart              # 单文件
flutter test test/unit/services/                                  # 目录
flutter test test/unit/models/quote_model_test.dart --name "xxx" # 按名称
dart run build_runner build --delete-conflicting-outputs         # 重新生成 Mock
```
**禁止主动运行全量测试** — CI 超时风险。

## 编写规范
- 文件名：`<被测文件名>_test.dart`，路径镜像 `lib/` 结构
- Mock：`setupTestEnvironment()` 初始化所有平台 Mock
- 结构：`group → setUp/tearDown → group → test`（AAA 模式：Arrange/Act/Assert）

## 测试覆盖重点
| 模块 | 覆盖 |
|------|------|
| Model | quote, note_category, note_tag, app_settings, feature_guide |
| Database | CRUD, health, security, backup merge, trash, multi-tag filter |
| Service | settings, api, draft, location, weather, clipboard, smart_push |
| Controller | search_controller, onboarding_controller |
| Utils | ai_prompt_manager, time, color, string, lww, path_security |

## 注意
- 集成/数据库测试 CI 可能挂起，本地注意超时设置
- 性能测试仅基准对比时运行，不纳入日常 CI
