# MODELS MODULE

## OVERVIEW
数据模型层，定义了应用中的核心数据结构、序列化逻辑以及状态对象。

## KEY MODELS
- `Quote` (`quote_model.dart`): 核心笔记模型，包含 content (纯文本) 和 deltaContent (Quill JSON)。
- `NoteCategory` / `NoteTag`: 笔记分类与标签。
- `MultiAISettings` / `AIProviderSettings`: AI 服务商配置。
- `ChatMessage` / `ChatSession`: AI 聊天记录模型。
- `WeatherData`: 天气信息模型。

## CONVENTIONS
- **序列化**: 核心模型必须提供 `toMap()` 和 `fromMap()` 用于数据库存储。
- **不可变性**: 建议使用 `copyWith` 模式来更新模型状态。
- **数据库同步**: 模型变更时，务必同步更新 `DatabaseService` 的迁移逻辑并 bump 版本。
- **UI 模型**: `onboarding_models.dart` 等专用于特定流程的模型应保持独立。
