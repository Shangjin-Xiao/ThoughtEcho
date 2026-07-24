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
## 2026-05-03 - 补充 SearchController 的测试
**对策:** 添加了针对 `clearSearch` 方法的单元测试。利用 `fake_async` 模拟防抖延时并确保方法能正确取消进行中的定时器。同时修复了代码中的 bug，确保当 `_isSearching` 为 true 时（不论 `_searchQuery` 是否为空），清除逻辑也能正确重置搜索状态并触发状态更新。
## 2026-05-04 - 补充 updateSearchImmediate 的测试
**盲点:** `NoteSearchController` 的 `updateSearchImmediate` 方法缺乏测试，导致搜索防抖取消逻辑和立即状态更新未受覆盖。
**对策:** 在 `test/unit/controllers/search_controller_test.dart` 中新增针对 `updateSearchImmediate` 的单元测试，利用 `fakeAsync` 模拟验证正在进行的延时任务能够被正确取消，并验证正常及无变化时的状态更新情况。
## 2026-05-19 - [补充 DailyPromptGenerator 的单元测试]
**盲点:** `DailyPromptGenerator` 负责根据时间、天气、温度及随机策略生成用户提示语，属于典型的数据驱动纯逻辑，但长期缺乏测试。其内部依赖于未 Mock 的本地化字典和隐式 `DateTime.now()`，可能导致未来迭代或新增语言时，某些边界条件（例如极端温度解析异常）静默崩溃。
**对策:** 通过自定义简单的 `FakeAppLocalizations` 实现了与 Flutter UI（`AppLocalizations.of(context)`）的环境隔离，并针对日期兜底、天气及城市插入、温度解析等分支进行了纯粹的方法调用验证，提升代码健壮性且不增加集成测试维护成本。
## 2026-06-10 - [补充 SafeCompute 和 StreamingJsonParser 的测试]
**盲点:** `SafeCompute` 和 `StreamingJsonParser` 作为隔离运行和流式解析的核心工具类，长期缺乏测试，容易在重构或者修改时导致未预见的边缘情况崩溃。
**对策:** 通过编写简单的隔离测试及文件存取操作测试验证流式解析。利用 `ComputeCallback` 的同步调用特性模拟成功与异常的回退逻辑；利用临时小文件及无效文件测试大 JSON 分块解析器的各项方法（包括安全边界检查、内存预估），从而加强代码库的健壮性。
## 2026-06-25 - [补充 SVGTestHelper 的测试]
**盲点:** `SVGTestHelper` 包含生成、验证和清理修复 SVG 内容的核心纯函数，在测试环境中用于快速构建和校验 SVG 格式。然而，它作为一个基础的测试工具集却没有自己的测试覆盖。如果后续调整了标签验证或补全规则，容易导致依赖它的上层组件测试集遭遇大面积的断言失败。
**对策:** 为其编写独立的纯函数单元测试，涵盖了正确的 SVG 结构验证、空内容与缺失标签等边界条件的失败验证，以及清理函数对多余 markdown 和缺失基础属性（`xmlns`, `viewBox`）的容错机制。这保证了底层辅助工具自身的健壮性。
## 2026-06-28 - 补充 SearchController 的测试
**盲点:** SearchController 的核心 `updateSearch` 和 `resetSearchState` 逻辑（包含长度校验和异步超时定时器）缺失测试覆盖。
**对策:** 添加了针对这部分逻辑的单元测试，涵盖了空查询清除、短查询忽略、超时定时器挂起等核心场景，并使用 `fakeAsync` 测试了定时器的启动与取消，防止定时器泄漏。
## 2026-06-30 - [补充 homepage 各项功能的测试]
**盲点:** `HomePage` 作为最复杂的主页面，其内部包含众多 Service 和子视图，原本仅进行了极其简单的 widget 测试，缺乏对 `DailyQuoteView`、`HomeDailyPromptPanel` 等核心业务组件的加载与切换验证。
**对策:**
1. 为 `HomeDailyPromptPanel` 编写了独立的 Widget 测试，采用 `MultiProvider` 注入 `MockAIService`、`MockSettingsService` 等完整依赖链，成功测试了流式提示信息的渲染以及失败降级的本地提示加载机制。
2. 彻底重构 `HomePage` 的 Widget 测试，Mock 其依赖的至少 8 个核心 Service，验证了 `DailyQuoteView` 和 `HomeDailyPromptPanel` 的正确挂载，并通过模拟用户交互点击 `NavigationBar`，全面验证了由主页向 `NoteListView`、`AIFeaturesPage`、`SettingsPage` 三个主要 Tab 页面的无缝切换逻辑，大幅提升了主页面的功能稳定性保证。
## 2026-06-30 - [补充 Utils 核心纯函数的测试]
**盲点:** 诸如 `AIRequestHelper`, `DatabasePlatformInit`, `ChatThemeHelper` 等核心工具类和纯函数缺乏基本测试覆盖。它们涉及 AI 参数组装、核心 FFI 数据库初始化和聊天主题配置，如果被破坏可能导致核心功能静默失效或引发启动崩溃。
**对策:** 为这些高优先级、易测试的纯函数和单例/配置类编写了极简的隔离测试。比如校验 AIRequestHelper 的消息格式是否符合 Provider 标准，以及确保 DatabasePlatformInit 的状态重置逻辑正常，在不增加过多执行成本的前提下，提升基础代码的健壮性。
## 2026-07-07 - [补充 MergeReport 及 Builder 的测试]
**盲点:** 核心业务模型/工具类如 `MergeReport` 及其对应的生成构建器 `MergeReportBuilder` 负责生成合并同步的数据报告及统计，其功能纯粹为数据计算和状态变更记录（纯函数/简单类），但缺乏相关的单元测试覆盖，无法保证在代码重构或演进过程中各类计数器及日志拼接逻辑的正确性。
**对策:** 针对该类无依赖且职责单一的数据统计模型，补充详尽的断言测试。覆盖其工厂方法、状态链式修改方法（`addInsertedQuote` 等）、组合聚合计算（`totalProcessedQuotes`）以及序列化/本地化输出结果（`summary` / `detailedLog`）。确保这些不依赖外部环境、易于搭建测试用例的基础类 100% 被覆盖。
## 2026-07-14 - 补充 ExpiringCache 的测试
**盲点:** removeExpired 方法的非过期情况、混合情况以及边界条件未经过测试验证。
**对策:** 添加非过期、混合和边界情况的测试，保证缓存过期逻辑完全可靠。
## 2026-07-21 - [补充 AICommandHelpers 的测试]
**盲点:** `AICommandHelpers` 包含多个核心静态工具类（如 `WebCommandHelper`, `NoteQueryHelper`, `SessionMessageHelper`），负责 AI 助手命令的解析、URL提取、笔记查询参数组装以及工具调用系统消息的生成。这些纯函数由于一直缺乏单元测试覆盖，在调整正则规则或修改字典格式时极易引发 Agent 行为静默异常。
**对策:** 通过编写隔离测试，覆盖了各工具类方法的输入边界条件。对于 `WebCommandHelper` 验证了多种前缀和自然语言的 URL 提取；对于 `NoteQueryHelper` 验证了 Agent 查询参数的构建和对缺省参数的安全回退；对于 `SessionMessageHelper` 验证了基于 JSON 的工具消息的可靠生成。测试代码同样保持极简且快速执行。
## 2024-05-24 - 补充 AddNoteController 的测试

**盲点:** `lib/controllers/add_note_controller.dart` 中存在较多逻辑（如位置/天气信息获取、元数据修改、一言状态判断等），但在 `test/unit/controllers/add_note_controller_test.dart` 中只有极少的两个位置清理测试。核心的位置获取（包括权限处理）、天气获取流程、一言工具方法的测试完全缺失。

**对策:**
1. 引入了 `mockito`，通过 `build_runner` 生成了 `LocationService`、`WeatherService`、`DatabaseService` 的 Mock 类。
2. 补充了控制器初始状态和基于 `initialQuote` 解析逻辑的测试用例。
3. 补充了 `fetchLocationForNewNote` 方法中各种边界条件（权限被拒、正常获取）的测试用例。
4. 补充了 `fetchWeatherForNewNote` 方法中各种边界条件（坐标缺失、正常获取）的测试用例。
5. 补充了与 `hitokoto` 相关的若干纯工具方法（如 `shouldApplyHitokotoSubtypeTag`、`convertHitokotoTypeToTagName`、`getIconForHitokotoType`）的测试。
6. 补充了 metadata 状态切换 (`setIncludeLocation`, `hydrateFromQuote` 等) 逻辑的测试用例。
