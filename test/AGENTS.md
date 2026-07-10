# Test 模块

本目录包含 unit、widget、integration、performance 以及少量历史根级测试。新增测试优先镜像
`lib/` 路径放入 `test/unit/` 或 `test/widget/`；不要继续无理由增加根级测试文件。

## 运行命令

```bash
# 单文件（默认）
timeout 60s flutter test --reporter compact test/unit/models/quote_model_test.dart

# 单用例
timeout 60s flutter test --reporter compact test/unit/models/quote_model_test.dart --name "xxx"

# 目录（仅当范围确实需要）
timeout 180s flutter test --reporter compact test/unit/services/localsend/

# 聚合入口（仅用户明确要求全量验证时）
timeout 180s flutter test --reporter compact test/all_tests.dart

# 重新生成 Mockito 文件
dart run build_runner build --delete-conflicting-outputs
```

首次 Flutter 测试可能因冷编译超过 60 秒；可预热或将相关单文件临时提高到 180 秒。超时后先
检查是否为编译、平台初始化或未释放异步资源，不要盲目重复运行。

## 编写规则

- 文件名 `<被测文件名>_test.dart`，目录尽量镜像 `lib/`。一个测试只表达一个可观察行为。
- 使用 Arrange / Act / Assert，`setUp`/`tearDown` 保持隔离；测试名称描述条件和结果，不写
  “works” 或实现细节。
- Bug 修复先写能稳定失败的回归测试；覆盖正常路径、边界值、失败/取消和资源释放，而不是追求
  无意义覆盖率数字。
- 平台插件和文件系统使用 `test_setup.dart` 及已有 mock/fake。测试不能读取真实用户目录、调用
  真实 AI/网络服务或依赖真实 API 密钥。
- 数据库测试使用独立临时库并在 `tearDown` 清理；迁移测试分别验证新建和旧版本升级，避免用
  开发数据库。
- Widget 测试通过语义、文本 key 或稳定 Widget key 查找，避免依赖易变的层级/坐标；异步动画
  使用有界 pump，谨慎使用可能永不 settle 的 `pumpAndSettle()`。
- 性能测试只在基准任务中运行，断言使用容忍环境波动的指标；集成测试不纳入默认快速验证。
- `*.mocks.dart` 和其他生成测试文件禁止手动编辑。

`test/all_tests.dart` 是历史聚合入口，不保证自动包含每个新增测试；新增测试是否加入该入口应
根据其稳定性和运行成本判断，同时单文件必须可独立运行。
