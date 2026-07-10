# Database Mixins 子模块

本目录包含 `DatabaseService` 的 12 个 `part`/mixin，覆盖缓存、查询、CRUD、分类、收藏、隐藏标签、
回收站、分页、导入导出和数据维护。Schema、版本号及 `onUpgrade` 逻辑位于
`../database_schema_manager.dart`。

## 数据安全规则

- Schema 变更同时更新 `createTables`、追加新的 `_performVersionUpgrades` 版本分支并递增
  `DatabaseSchemaManager.schemaVersion`；不要改写已有版本分支。
- `database_migration_mixin.dart` 主要承载运行期数据迁移/维护，不要把 schema 升级错误地只放
  在该文件。
- SQL 值一律参数绑定。动态排序字段必须经过父文件的 `sanitizeOrderBy()`；动态标识符必须来自
  内部白名单。
- 批量读取先预加载关系或聚合结果，禁止在结果循环中逐条查询。批量写入使用事务、`Batch` 或
  单条集合 SQL，并评估 SQLite 参数数量上限。
- 写入成功且可观察状态改变后再 `notifyListeners()`；事务失败时不能留下只更新了一半的缓存。
- 删除/重命名查询字段前搜索 Model、UI、备份、同步和测试的所有读取点。
- 保持非 Web 路径为实现目标；现有 Web 内存分支是历史代码，不得扩展。

至少验证新建数据库、从上一个 schema 版本升级、失败回滚，以及受影响 CRUD/查询测试。迁移
测试不得依赖开发机上的真实用户数据库。
