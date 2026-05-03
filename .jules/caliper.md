## 2026-03-10 - [补充 TimeUtils 的单元测试]
**盲点:** `TimeUtils` 作为一个大量被调用的核心格式化工具类，却长期缺乏单元测试覆盖，导致关于个位数补零、本地化兜底和跨时区回退的逻辑变得十分脆弱。
**对策:** 为其编写隔离纯函数的测试。利用 `DateTime` 等基础类型构建 Mock 数据，避免引入 `BuildContext` 及复杂的 UI Mock，保持测试的极简与快速运行。
## 2026-03-23 - [补充 StringUtils.removeObjectReplacementChar 的测试]
**盲点:** `StringUtils.removeObjectReplacementChar` 是富文本处理（移除 `U+FFFC` 占位符以获取纯文本）中非常核心且被频繁调用的纯函数，但在测试套件中长期缺乏覆盖，容易在未来迭代或重构中被意外修改而导致依赖其的 AI 分析、SVG 卡片生成等功能静默失效。
**对策:** 为此类明确的字符串替换类纯函数编写隔离测试。测试包含该特殊字符、不包含该字符以及多个占位符和空字符串等各种边界条件，确保断言精确有效。
## 2026-03-24 - [补充 I18nLanguage 的测试]
**盲点:** `I18nLanguage` 负责系统语言代码解析和 HTTP 头部生成，这类纯函数直接影响应用的国际化展示逻辑，但由于通常被当作简单的工具类而缺乏测试覆盖。这可能导致处理极端输入（如全大写、前后包含空格的 locale 字符串）或新增语言支持时引入错误。
**对策:** 为 `base`、`appLanguage`、`appLanguageOrSystem` 及 `buildAcceptLanguage` 编写无依赖的单元测试，涵盖正常区域代码格式、空值回退机制及大小写容错，保证核心语言映射逻辑稳定可靠。
## 2026-03-24 - [补充 MemoryOptimizationHelper 的测试]
**盲点:** `ProcessingStrategyExt` 在 `MemoryOptimizationHelper` 中作为一个核心的纯枚举扩展，包含了内存优化策略的状态描述与隔离执行判断（`description`, `useIsolate`）。但由于缺乏单元测试覆盖，其逻辑在重构或新增状态时可能出现遗漏。
**对策:** 编写极简的枚举扩展测试。通过直接断言各种策略类型在调用 `description` 和 `useIsolate` 方法时的返回结果，快速验证且不依赖其他环境。
## 2026-04-28 - [补充 MediaOptimizationUtils 的测试]
**盲点:** `MediaOptimizationUtils` 中的 `getMimeType` 和 `estimateOptimizedSize` 等纯函数负责媒体类型识别与大小估算，但长期缺乏单元测试覆盖。这容易在添加新的文件类型支持或调整大小估算逻辑时引入无法预料的错误。
**对策:** 为此类明确的输入输出映射纯函数编写了极简的单元测试。覆盖了正常情况（如常见的图片、视频、音频扩展名与大小映射）、边界条件（如未知文件类型、空字符串）及容错情况（大写扩展名）。测试完全隔离并只断言基本逻辑。

## 2024-05-27 - 补充 SearchController 的测试
**盲点:** `NoteSearchController` 的 `clearSearch` 方法未经过充分测试，且其内部处理未被防抖定时器延迟的空查询清空逻辑时存在未完整重置状态的 bug。
**对策:** 添加了针对 `clearSearch` 方法的单元测试。利用 `fake_async` 模拟防抖延时并确保方法能正确取消进行中的定时器。同时修复了代码中的 bug，确保当 `_isSearching` 为 true 时（不论 `_searchQuery` 是否为空），清除逻辑也能正确重置搜索状态并触发状态更新。
