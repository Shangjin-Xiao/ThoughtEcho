# MODELS 模块

## 概览
数据模型层，定义应用中所有核心数据结构、序列化逻辑和状态对象。模型为纯 Dart 类，**不依赖 Flutter 框架**。

## 核心模型

| 文件 | 说明 |
|------|------|
| `quote_model.dart` | **核心笔记模型**，双存储：`content`（纯文本）+ `deltaContent`（Quill Delta JSON） |
| `note_category.dart` | 笔记分类 |
| `note_tag.dart` | 标签，通过关联表管理（不在 Quote.toMap 中序列化） |
| `ai_provider_settings.dart` | AI 服务商配置，含 `getPresetProviders()` 预设列表 |
| `multi_ai_settings.dart` | 多 AI Provider 聚合配置 |
| `chat_message.dart` / `chat_session.dart` | AI 对话记录 |
| `weather_data.dart` | 天气信息 |
| `smart_push_settings.dart` | 智能推送配置 |
| `app_settings.dart` | 全局应用设置 |
| `merge_report.dart` | LWW 同步合并结果报告 |

## 规范

### 必须实现的接口
```dart
class XxxModel {
  // 1. 命名构造函数（可选 const）
  const XxxModel({required this.id, ...});

  // 2. 数据库序列化（必须）
  Map<String, dynamic> toMap() => {'id': id, ...};
  factory XxxModel.fromMap(Map<String, dynamic> map) => XxxModel(
    id: map['id'] as String,
    ...
  );

  // 3. 不可变更新（必须）
  XxxModel copyWith({String? id, ...}) => XxxModel(
    id: id ?? this.id,
    ...
  );

  // 4. 相等性基于业务 ID（推荐）
  @override
  bool operator ==(Object other) =>
    identical(this, other) || (other is XxxModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
```

### 数据库同步规则
- **字段新增**：在 `DatabaseService` 中添加对应迁移语句，并 bump `_databaseVersion`
- **字段删除**：先全局搜索 UI 层使用处，确认无依赖后再删除（`delta_content` 等字段被列表卡片使用）
- **字段重命名**：迁移时用 `ALTER TABLE ... RENAME COLUMN`（SQLite 3.25+）或新建表迁移

### Quote 双存储特殊处理
```dart
// content: 纯文本，用于搜索、摘要、AI 分析
// deltaContent: Quill Delta JSON，用于富文本渲染
// 两者必须保持同步，保存时由编辑器同时更新
```

### 容错解析原则
- `fromMap` 必须对所有可选字段使用安全转换（`map['key'] as String? ?? ''`）
- 不允许在 `fromMap` 中抛出异常导致整个列表加载失败

## 禁止事项
- 模型文件中禁止 `import 'package:flutter/...'`（纯 Dart 层）
- 禁止在模型中持有 Service 引用（防循环依赖）
- 禁止在 `toMap()` 中序列化关联表字段（如 tagIds 通过独立关联表管理）
