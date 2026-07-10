# Constants 模块

本目录包含应用常量、卡片模板和 AI Prompt。`card_templates.dart` 是约 2,000 行的复杂模板集合；
`ai_card_prompts.dart` 与 `app_constants.dart` 相对较小。不要用易过期的字节数冒充行数。

## 规则

- `thoughtecho_constants.dart` 当前只是兼容占位文件，不在其中新增常量；通用常量放
  `app_constants.dart`，局部常量优先留在其唯一使用模块附近。
- 只有编译期不变量使用 `const`。运行配置、密钥、用户偏好和可国际化文案不属于常量。
- URL、阈值和默认值新增前先搜索已有定义，避免多个真源；常量名表达单位，如秒、字节、像素。
- 修改 `card_templates.dart` 前搜索模板 ID、渲染器、保存/导出和快照测试。模板 ID 属于兼容数据，
  不随意重命名或复用。
- 新增/改名用户可见模板时同步中英文 ARB，并运行相关模板渲染测试。
- AI Prompt 不包含真实密钥、私人数据或仅某个 Provider 支持的未说明语法。修改后至少验证结构、
  插值/转义、输出约束和多个 Provider 的兼容路径。

针对性测试位于 `test/card_templates_test.dart`、`test/sota_card_templates_test.dart`、
`test/ai_card_prompts_test.dart` 和 `test/unit/constants/`。
