# DATABASE MIXINS 子模块

## 概览
`DatabaseService` 的功能拆分，通过 `part`/`part of` 机制组合为一个完整的数据库服务类。共 12 个 mixin 文件。

## 文件清单

| 文件 | 职责 |
|------|------|
| `database_quote_crud_mixin.dart` | 笔记基础增删改查（16k+ 行） |
| `database_query_mixin.dart` | 复杂查询（分类筛选、标签筛选、搜索）（14k+ 行） |
| `database_query_helpers_mixin.dart` | 查询构建辅助方法（13k+ 行） |
| `database_cache_mixin.dart` | 内存缓存层，减少 DB 读取频次 |
| `database_pagination_mixin.dart` | 分页加载逻辑（13k+ 行） |
| `database_favorite_mixin.dart` | 收藏计数与管理（9k+ 行） |
| `database_category_mixin.dart` | 分类 CRUD（13k+ 行） |
| `database_category_init_mixin.dart` | 默认分类初始化 |
| `database_hidden_tag_mixin.dart` | 隐藏标签管理（6k+ 行） |
| `database_import_export_mixin.dart` | 数据导入导出 |
| `database_migration_mixin.dart` | 数据库版本迁移（4k+ 行） |
| `database_trash_mixin.dart` | 回收站功能（15k+ 行） |

## Part 文件结构
```dart
// 父文件 database_service.dart
part 'database/database_quote_crud_mixin.dart';
part 'database/database_query_mixin.dart';
// ...

// Mixin 文件
part of '../database_service.dart';

mixin DatabaseCrudMixin on _DatabaseServiceBase {
  Future<String> insertQuote(Quote quote) async {
    // 可以直接访问父类的 _database, notifyListeners() 等
    final db = await _getDatabase();
    await db.insert('quotes', quote.toMap());
    notifyListeners();
    return quote.id;
  }
}
```

## 修改注意事项
- 新增字段**必须**在 `database_migration_mixin.dart` 中添加对应的 `ALTER TABLE` 语句
- 迁移按版本号顺序执行（`case 1: ... case 2: ...`），**禁止修改已有迁移语句**
- 每次 schema 变更**必须** bump `_databaseVersion` 常量（在 `database_schema_manager.dart` 中）
- 查询中的 `orderBy` 参数必须经过 `PathSecurityUtils.sanitizeOrderBy` 处理（防 SQL 注入）
- 所有写操作后**必须**调用 `notifyListeners()` 通知 UI 刷新

## Schema 管理
数据库 Schema 定义集中在 `database_schema_manager.dart`（57k+ 行），包括建表语句、索引定义和迁移逻辑。新增表或字段时需同步修改此文件。
