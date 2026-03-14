# DATABASE MIXINS 子模块

## 概览
`DatabaseService` 的功能拆分，通过 `part`/`part of` 机制组合为一个完整的数据库服务类。

## 文件清单

| 文件 | 职责 |
|------|------|
| `database_crud_mixin.dart` | 笔记基础增删改查 |
| `database_query_mixin.dart` | 复杂查询（分类筛选、标签筛选、搜索） |
| `database_query_helpers_mixin.dart` | 查询构建辅助方法 |
| `database_cache_mixin.dart` | 内存缓存层，减少 DB 读取频次 |
| `database_pagination_mixin.dart` | 分页加载逻辑 |
| `database_favorite_mixin.dart` | 收藏计数与管理 |
| `database_category_mixin.dart` | 分类 CRUD |
| `database_category_init_mixin.dart` | 默认分类初始化 |
| `database_hidden_tag_mixin.dart` | 隐藏标签管理 |
| `database_import_export_mixin.dart` | 数据导入导出 |
| `database_migration_mixin.dart` | 数据库版本迁移 |

## 规范

### Part 文件结构
```dart
// 父文件 database_service.dart
part 'database/database_crud_mixin.dart';

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

### 修改注意事项
- 新增字段必须在 `database_migration_mixin.dart` 中添加对应的 `ALTER TABLE` 语句
- 迁移按版本号顺序执行（`case 1: ... case 2: ...`），**禁止修改已有迁移语句**
- 每次 schema 变更必须 bump `_databaseVersion` 常量
- 查询中的 `orderBy` 参数必须经过 `PathSecurityUtils.sanitizeOrderBy` 处理（防 SQL 注入）
