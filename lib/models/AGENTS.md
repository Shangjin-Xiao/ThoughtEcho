# MODELS 模块

数据模型层（纯 Dart，**不依赖 Flutter 框架**）。

## 必须实现的接口
- `toMap()` / `fromMap()` — 数据库序列化
- `copyWith()` — 不可变更新
- 相等性基于业务 ID（`operator ==` + `hashCode`）

## 关键约束
- **Quote 双存储**：`content`（纯文本，搜索/摘要/AI）+ `deltaContent`（Quill Delta JSON，富文本渲染），保存时必须同步
- **fromMap 容错**：可选字段用 `map['key'] as String? ?? ''`，禁止抛异常导致列表加载失败
- **字段新增**→在 `DatabaseService` 添加迁移 + bump `_databaseVersion`
- **字段删除**→先全局搜索 UI 使用处，确认无依赖后再删
- **禁止** `import 'package:flutter/...'` — 纯 Dart 层
- **禁止** 模型持有 Service 引用 — 防循环依赖
- **禁止** `toMap()` 序列化关联表字段（如 tagIds 通过独立关联表管理）
