# DATABASE MIXINS 子模块

`DatabaseService` 的 `part`/`part of` 拆分，共 12 个 mixin。Schema 定义在 `database_schema_manager.dart`（57k+ 行）。

## 修改注意事项
- 新增字段**必须**在 `database_migration_mixin.dart` 添加 `ALTER TABLE`，**禁止修改已有迁移语句**
- 每次 schema 变更**必须** bump `_databaseVersion`（在 `database_schema_manager.dart`）
- `orderBy` 参数必须经 `sanitizeOrderBy()` 处理（防 SQL 注入，方法在 `database_service.dart` 中定义）
- 所有写操作后**必须** `notifyListeners()`
