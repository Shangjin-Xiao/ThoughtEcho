# Models 模块

本目录同时包含领域模型、持久化模型和少量携带 Material 展示信息的 UI 模型；不要把它错误地
视为完全纯 Dart 层。新增模型默认保持与 Flutter 解耦，只有展示语义确实属于模型时才引入
Flutter 类型。

## 序列化与不可变更新

- SQLite 持久化模型使用与表字段一致的 `toMap()` / `fromMap()`；JSON 配置和协议模型使用
  `toJson()` / `fromJson()`。不要要求不持久化的临时模型实现无意义接口。
- 不可变模型提供 `copyWith()`；新增字段时同步更新构造函数、序列化、`copyWith`、相等性、
  日志脱敏和测试。
- 解析外部/旧版本数据时使用明确默认值和类型检查。容错不能掩盖必填字段损坏；需要降级时
  记录足够上下文，但不能记录密钥或完整私人笔记。
- 只有业务需要值相等性时才实现 `operator ==` / `hashCode`，并保持二者字段一致；不要统一
  假设所有模型都按 `id` 相等。

## 数据约束

- `Quote.content` 是纯文本，供搜索、摘要和 AI 使用；`Quote.deltaContent` 是 Quill Delta JSON，
  供富文本恢复和渲染使用。任何编辑、导入、同步或合并都必须维持二者一致。
- 关联表数据（如笔记与标签）由对应关系表和 Service 管理，除非 schema 明确定义，否则不要
  塞进主表 `toMap()`。
- 持久化字段变更必须联动检查 `DatabaseSchemaManager`、升级路径、备份/恢复、同步协议和测试。
- 模型不持有 Service、Provider 或 `BuildContext`，避免反向依赖和隐式 I/O。
