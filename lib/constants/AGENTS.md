# CONSTANTS 模块

## 概览
应用常量定义，包含卡片模板、AI 提示词和全局常量。

## 关键文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `card_templates.dart` | **75k+** | 卡片模板定义，极复杂。修改前必须完整阅读相关模板 |
| `ai_card_prompts.dart` | 7k+ | AI 卡片生成的 Prompt 模板 |
| `app_constants.dart` | 3k | 全局常量（URL、默认值、阈值等） |

## 规范

- **禁止手动编辑 `thoughtecho_constants.dart`** — 它是占位文件，常量应放在 `app_constants.dart`
- `card_templates.dart` 体积巨大，修改任何模板前先搜索现有使用处
- 新增卡片模板必须同步更新 `app_zh.arb` 和 `app_en.arb` 中的模板名称文案
- AI Prompt 修改后需验证多个 Provider（OpenAI / Anthropic / DeepSeek / Ollama）的兼容性
