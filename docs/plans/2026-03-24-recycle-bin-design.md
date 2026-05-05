# 回收站功能设计方案

> 日期: 2026-03-28
> 状态: 确认版 v4（按已确认产品规则重写）

---

## 1. 需求概述

用户删除笔记后，笔记不再立即永久移除，而是进入"回收站"。回收站保留期由用户在 **7 天 / 30 天 / 90 天** 中选择，默认 **30 天**，并在多设备间保持一致。用户可在回收站中**恢复**或**永久删除**单条/全部笔记。多设备冲突统一采用 **最新操作优先**。

### 已确认产品规则

1. **普通删除先确认**：用户点击删除后先弹确认框；确认后才进入回收站。
2. **删除后不提供撤销按钮**：删除完成后仅提示"已移至回收站，可在回收站恢复"。
3. **永久删除需二次确认**：单条永久删除、清空回收站都必须再确认一次。
4. **回收站保留期可配置**：固定选项为 `7/30/90` 天，默认 `30` 天。
5. **保留期跨设备同步**：一台设备改动后，其他设备也应采用同一设置。
6. **同步冲突规则为最新操作优先**：删除、恢复、编辑、永久删除都按时间戳比较，最后一次有效操作生效。

### 核心用户场景

1. **误删恢复**：用户误删笔记 → 进入回收站 → 恢复 → 回到原列表
2. **批量清理**：用户想释放空间 → 回收站 → 清空 → 永久删除全部
3. **自动过期**：超过当前保留期（7/30/90 天）的回收站笔记 → 应用启动时异步清理（不弹窗）
4. **跨设备一致**：A 设备永久删除，B 设备稍后恢复或编辑 → 以较新的操作为准

---

## 2. 技术方案：软删除 (Soft Delete)

### 为什么选软删除

| 维度 | 软删除 ✅ | 移动到新表 |
|------|------|------|
| 实现复杂度 | 低：加 2 个字段 + 改查询 | 高：新表 + 跨表事务 + 迁移 quote_tags |
| 恢复操作 | 1 条 UPDATE | INSERT + 恢复 quote_tags + DELETE |
| 备份/同步 | 字段自然随数据流动 | 需改导出逻辑适配新表 |
| quote_tags | 外键不触发 CASCADE，标签保留 | 需处理 CASCADE 或手动迁移 |

---

## 3. 数据库层

### 3.1 Schema 变更

#### 新增字段（quotes 表）

| 字段 | 类型 | 说明 |
|------|------|------|
| `is_deleted` | `INTEGER DEFAULT 0` | 0=正常，1=在回收站 |
| `deleted_at` | `TEXT` (ISO 8601) | 删除时间戳，用于自动清理 |

#### 版本升级 19 → 20

**`database_schema_manager.dart`** 需改 5 处：

1. **`version`** 改为 `20`

2. **`createTables()`** — quotes 的 `CREATE TABLE` 直接包含新列，同时新增 tombstone 表：
   ```sql
   is_deleted INTEGER DEFAULT 0,
   deleted_at TEXT

   CREATE TABLE quote_tombstones (
     quote_id TEXT PRIMARY KEY,
     deleted_at TEXT NOT NULL,
     device_id TEXT
   );
   ```

3. **`_performVersionUpgrades()`** 添加 `if (oldVersion < 20)` 迁移分支：
   ```sql
   -- 需先 PRAGMA table_info 检查列是否存在（与项目已有迁移模式一致）
   ALTER TABLE quotes ADD COLUMN is_deleted INTEGER DEFAULT 0;
   ALTER TABLE quotes ADD COLUMN deleted_at TEXT;
   CREATE INDEX IF NOT EXISTS idx_quotes_is_deleted ON quotes(is_deleted);
   CREATE INDEX IF NOT EXISTS idx_quotes_deleted_at ON quotes(deleted_at);

   CREATE TABLE IF NOT EXISTS quote_tombstones (
     quote_id TEXT PRIMARY KEY,
     deleted_at TEXT NOT NULL,
     device_id TEXT
   );
   ```

4. **`_removeTagIdsColumnSafely()`**（约 L770-830）— `CREATE TABLE quotes_new` 和 `INSERT INTO quotes_new` 必须包含 `is_deleted` / `deleted_at` 列，否则该修复流程会丢失回收站数据。

5. **`checkAndFixDatabaseStructure()`** — 补充 `is_deleted` / `deleted_at` / `quote_tombstones` / 新索引 的自修复，避免部分升级数据库在初始化后缺字段。

### 3.2 模型变更 (`quote_model.dart`)

新增字段：

```dart
final bool isDeleted;       // 默认 false
final String? deletedAt;
```

需同步修改：
- `构造函数` — 新增参数
- `toJson()` — 序列化 `is_deleted`(int) / `deleted_at`
- `fromJson()` — 容错：`is_deleted` 为 null 或缺失时默认 `0`/`false`
- `copyWith()` — 新增参数
- `validated()` — 新增参数

### 3.3 保留时间设置模型

回收站保留时间不放在数据库 `quotes` 表中，而是放到全局设置中，由 `SettingsService` 持久化并随备份/同步传播。

建议在 `app_settings.dart` 中新增：

```dart
final int trashRetentionDays;              // 仅允许 7 / 30 / 90，默认 30
final String? trashRetentionLastModified;  // ISO 8601 UTC，用于多设备 LWW
```

说明：

- `trashRetentionDays` 决定自动清理阈值
- `trashRetentionLastModified` 决定多设备同步时哪个设置更新更晚
- 若旧版本备份/设置中没有这两个字段，则默认回退到 `30` 天

---

## 4. 查询接口契约 — 核心设计决策

### 设计原则

**不是"到处加 `is_deleted = 0`"，而是分两类接口**：

| 接口类型 | 默认行为 | 说明 |
|----------|---------|------|
| **面向用户/UI** | 排除已删除 | 列表、统计、每日一言、智能推送 |
| **面向内部维护** | 包含已删除 | 媒体引用校验、备份导出、完整性检查 |

#### 接口签名变更

```dart
Future<Quote?> getQuoteById(String id, {bool includeDeleted = false});
Future<List<Quote>> getAllQuotes({..., bool includeDeleted = false});
Future<List<Quote>> getUserQuotes({..., bool includeDeleted = false});
Future<int> getQuotesCount({..., bool includeDeleted = false});

// ⚠️ searchQuotesByContent 默认包含已删除！
// 原因：MediaReferenceService.quickCheckAndDeleteIfOrphan() 用它做"孤儿媒体二次校验"
// 如果排除回收站，会误判回收站笔记的媒体为孤儿并删除物理文件
Future<List<Quote>> searchQuotesByContent(String query, {bool includeDeleted = true});
```

### 4.1 必须排除已删除的查询（默认 `includeDeleted = false`）

| 方法 | 文件 | 备注 |
|------|------|------|
| `getAllQuotes()` | `database_quote_crud_mixin.dart` | |
| `getQuoteById()` | `database_quote_crud_mixin.dart` | 编辑器/详情/通知打开 |
| `getUserQuotes()` / `_performDatabaseQuery()` | `database_query_mixin.dart` | 首页列表 |
| `getQuotesCount()` | `database_query_helpers_mixin.dart` | 分页统计 |
| `_directGetQuotes()` | `database_query_helpers_mixin.dart` | |
| `getQuotesForSmartPush()` | `database_query_helpers_mixin.dart` | 智能推送选笔记 |
| `getMostFavoritedQuotesThisWeek()` | `database_favorite_mixin.dart` | |
| `getLocalDailyQuote()` — 两段 SQL | `database_health_service.dart` | |
| `_getLocalQuoteFromMemory()` | `database_health_service.dart` | Web 分支 |
| `getHourDistributionForSmartPush()` — SQL+Web | `database_migration_mixin.dart` | |
| `getHiddenQuoteIds()` — SQL 改为 JOIN quotes + Web | `database_hidden_tag_mixin.dart` | |

**使用默认值即自动排除的调用点**（不需要改调用代码，只要接口实现正确）：

| 调用方 | 文件 | 说明 |
|--------|------|------|
| `_loadAllQuotesForSmartPush()` | `home_page.dart` L383 | `getAllQuotes()` |
| `_getQuoteById(draftId)` | `home_page.dart` L628 | `getQuoteById()` |
| `getQuotesCount()` | `insights_page.dart` L216 | AI 分析统计 |
| `getUserQuotes()` | `insights_page.dart` L400 | |
| `getUserQuotes()` | `settings_page.dart` L1323/1363 | |
| `getAllQuotes()` | `ai_report/report_data_loading.dart` L13 | AI 报告 |
| `getUserQuotes()` | `ai_analysis_history_page_clean.dart` L593 | |
| `getQuoteById()` | `note_editor/editor_document_init.dart` L12 | 编辑器打开 |
| `getQuoteById()` | `smart_push/smart_push_notification.dart` L133 | 通知点击打开笔记 |
| `getQuotesCount()` | `background_push_handler.dart` L129 | 后台推送诊断 |

### 4.2 必须包含已删除的内部路径（显式 `includeDeleted: true`）

| 调用点 | 文件 | 原因 |
|--------|------|------|
| `searchQuotesByContent()` | `database_quote_crud_mixin.dart` | 默认 `true`，无需改调用 |
| `quickCheckAndDeleteIfOrphan()` | `media_reference_service.dart` L572 | 孤儿媒体校验 |
| `_collectQuoteReferenceIndex()` — `getAllQuotes()` | `media_reference_service.dart` L417 | 需显式加 `includeDeleted: true` |
| `_collectQuoteReferenceIndexStreamed()` — `getUserQuotes()` | `media_reference_service.dart` L451 | 需显式加 `includeDeleted: true` |
| `migrateExistingQuotes()` — `getUserQuotes()` | `media_reference_service.dart` L895 | 需显式加 `includeDeleted: true` |
| `verifyMediaIntegrity()` — `getAllQuotes()` | `media_cleanup_service.dart` L238 | 需显式加 `includeDeleted: true` |
| `exportDataAsMap()` — 裸 SQL | `database_backup_service.dart` L27 | 无接口调用，SQL 不加过滤 |

### 4.3 备份服务特殊处理

**`backup_service.dart`** 中的流式导出（L242-253）：

```dart
final allQuotesCount = await _databaseService.getQuotesCount(excludeHiddenNotes: false);
final quotes = await _databaseService.getUserQuotes(offset: offset, limit: pageSize, excludeHiddenNotes: false);
```

这两处需加 `includeDeleted: true`，否则 ZIP 备份会漏掉回收站笔记。

### 4.4 统计口径调整

`database_health_service.dart` 的 `performStartupHealthCheck()` (L119) / `getDatabaseHealthInfo()` (L446)：

```sql
-- 原：SELECT COUNT(*) as count FROM quotes
-- 改为分别统计
SELECT COUNT(*) as total,
       SUM(CASE WHEN is_deleted = 0 THEN 1 ELSE 0 END) as active,
       SUM(CASE WHEN is_deleted = 1 THEN 1 ELSE 0 END) as deleted
FROM quotes
```

展示：`笔记数量: 128 (活跃 120 / 回收站 8)`

### 4.5 防御性约束

| 操作 | 对已删除笔记的行为 |
|------|-------------------|
| `incrementFavoriteCount()` | 拒绝操作（提前检查 is_deleted 后返回） |
| `resetFavoriteCount()` | 拒绝操作 |
| `updateQuote()` | 拒绝操作（已删除笔记不应被编辑） |

---

## 5. 服务层变更

### 5.1 修改 `deleteQuote()` 为软删除

**文件**: `database/database_quote_crud_mixin.dart`

```dart
@override
Future<void> deleteQuote(String id) async {
  // UPDATE quotes
  // SET is_deleted = 1, deleted_at = <now>, last_modified = <now>
  // WHERE id = ? AND is_deleted = 0
  //
  // ⚠️ last_modified 必须更新，否则 LWW 同步无法传播删除状态
  //
  // 不再执行 DELETE、不再清理媒体文件
  // 删除后不要手动维护 _currentQuotes / _currentQuoteIds
  // 统一 clear cache + refreshQuotesStreamForParts()
  // 仍需清理 QuoteContent 渲染缓存
}
```

Web 分支：`_memoryStore` 中标记 `isDeleted: true`，而非 `removeWhere`。

### 5.2 新建 `database/database_trash_mixin.dart`

```dart
part of '../database_service.dart';

mixin _DatabaseTrashMixin on _DatabaseServiceBase {

  /// 获取回收站中的笔记
  Future<List<Quote>> getDeletedQuotes({
    int offset = 0,
    int limit = 20,
    String orderBy = 'deleted_at DESC',
  });

  /// 获取回收站笔记数量
  Future<int> getDeletedQuotesCount();

  /// 恢复单条笔记
  /// UPDATE: is_deleted=0, deleted_at=NULL, last_modified=now
  Future<void> restoreQuote(String id);

  /// 永久删除单条笔记（复用 _hardDeleteQuotes）
  Future<void> permanentlyDeleteQuote(String id);

  /// 清空回收站（复用 _hardDeleteQuotes）
  Future<void> emptyTrash();

  /// 自动清理过期笔记
  Future<int> autoCleanupExpiredTrash({int retentionDays = 30});

  /// 内部共享方法：批量硬删除
  Future<void> _hardDeleteQuotes(List<String> ids);
}
```

### 5.3 永久删除流程 (`_hardDeleteQuotes`)

**顺序至关重要**：

```
1. 读出待删笔记的媒体路径（引用表 + 内容提取）
   ⚠️ 必须在 DELETE 之前，因为 CASCADE 会删除 media_references
2. DELETE FROM quotes WHERE id = ?
   → quote_tags 通过 ON DELETE CASCADE 自动清理 ✅
   → media_references 通过 ON DELETE CASCADE 自动清理 ✅
3. 对步骤1的路径逐个做 orphan check 并删物理文件
4. 清理 QuoteContent 渲染缓存
```

`permanentlyDeleteQuote`、`emptyTrash`、`autoCleanupExpiredTrash` 三个方法复用同一个 `_hardDeleteQuotes` 实现。

### 5.4 自动清理策略

**触发时机**：`DatabaseService.init()` 完成后异步执行，不阻塞启动。保留期取自同步后的设置值，且仅允许 `7 / 30 / 90`。

```dart
Future<int> autoCleanupExpiredTrash({required int retentionDays}) async {
  assert([7, 30, 90].contains(retentionDays));

  // 1. 查出过期的 quote ids
  final expiredIds = await db.rawQuery(
    "SELECT id FROM quotes WHERE is_deleted = 1 "
    "AND deleted_at IS NOT NULL "
    "AND julianday(deleted_at) <= julianday('now', '-$retentionDays days')"
  );
  if (expiredIds.isEmpty) return 0;

  // 2. 复用完整硬删除流程
  final ids = expiredIds.map((r) => r['id'] as String).toList();
  await _hardDeleteQuotes(ids);
  return ids.length;
}
```

> **⚠️ 不能用裸 `DELETE FROM quotes WHERE is_deleted = 1 AND ...`！** CASCADE 会先删 media_references，导致无法获取媒体路径来清理物理文件。

> **⚠️ 删除后、恢复后、永久删除后都统一走 `refreshQuotesStreamForParts()`，不要只手动修改 `_currentQuotes`，否则会和 `_currentQuoteIds` 去重缓存打架。**

---

## 6. Web 平台 `_memoryStore` 完整适配清单

| 方法 | 文件 | 变更 |
|------|------|------|
| `deleteQuote()` | `database_quote_crud_mixin.dart` | 改为标记 `isDeleted: true`，不再 `removeWhere` |
| `getQuoteById()` | `database_quote_crud_mixin.dart` | 默认跳过 `isDeleted`，`includeDeleted` 时不跳 |
| `getAllQuotes()` | `database_quote_crud_mixin.dart` | 默认过滤 `!q.isDeleted` |
| `searchQuotesByContent()` | `database_quote_crud_mixin.dart` | 默认**不过滤** |
| `updateQuote()` | `database_quote_crud_mixin.dart` | 拒绝对 `isDeleted` 笔记操作 |
| `getUserQuotes()` | `database_query_mixin.dart` | 默认过滤 `!q.isDeleted` |
| `_directGetQuotes()` | `database_query_helpers_mixin.dart` | 同上 |
| `getQuotesForSmartPush()` | `database_query_helpers_mixin.dart` | 同上 |
| `getQuotesCount()` | `database_query_helpers_mixin.dart` | 同上 |
| `getMostFavoritedQuotesThisWeek()` | `database_favorite_mixin.dart` | 过滤 `!q.isDeleted` |
| `incrementFavoriteCount()` | `database_favorite_mixin.dart` | 拒绝对已删除笔记操作 |
| `resetFavoriteCount()` | `database_favorite_mixin.dart` | 同上 |
| `getHiddenQuoteIds()` | `database_hidden_tag_mixin.dart` | 过滤 `!q.isDeleted` |
| `getHourDistributionForSmartPush()` | `database_migration_mixin.dart` | 过滤 `!q.isDeleted` |
| `_getLocalQuoteFromMemory()` | `database_health_service.dart` | 过滤 `!q.isDeleted` |
| 回收站专用方法 | `database_trash_mixin.dart` | 只返回 `q.isDeleted` |

---

## 7. 备份/同步兼容

### 7.1 备份导出：默认包含回收站与永久删除信号

备份语义 = "完整恢复应用状态"，回收站是状态的一部分；而永久删除信号是同步正确性的组成部分。

- `quotes` 导出时应保留 `is_deleted` / `deleted_at`，这样回收站内容可以完整恢复
- `quote_tombstones` 导出时应一并带上，供多设备同步传播永久删除信号
- **必须同时改两条链路**：
  - `database_backup_service.dart` 的 `exportDataAsMap()`
  - `backup_service.dart` 的流式 ZIP / 同步导出

同步包中的 `notes` 建议扩展为：

```json
{
  "categories": [...],
  "quotes": [...],
  "tombstones": [...],
  "trash_settings": {
    "retention_days": 30,
    "last_modified": "2026-03-28T10:00:00.000Z"
  }
}
```

### 7.2 全量备份恢复

全量恢复的目标是"回到备份时的可见状态"，而不是重放同步删除历史。

- 备份中的 `quotes`（包括 `is_deleted = 1` 的回收站笔记）应正常恢复
- 恢复前应先清空本地 `quote_tombstones` 表
- **全量恢复时不应用 tombstone 删除逻辑**
- 若备份中携带 tombstones，可忽略不导入，避免恢复后又把刚恢复的笔记删掉
- 旧版备份没有 `is_deleted` / `deleted_at` / `tombstones` 时，按默认值兼容即可

### 7.3 设备同步：最新操作优先

这是本方案的核心规则。

| 场景 | 生效依据 | 结果 |
|------|----------|------|
| 软删除 vs 正常笔记 | 比较 `last_modified` | 更新更晚者生效 |
| 恢复 vs 软删除 | 比较 `last_modified` | 更新更晚者生效 |
| 永久删除 vs 正常/回收站笔记 | 比较 `tombstone.deleted_at` 与 `quote.last_modified` | 时间更晚者生效 |
| 永久删除 vs 恢复后的新笔记 | 比较 `tombstone.deleted_at` 与恢复后笔记的 `last_modified` | 时间更晚者生效 |

#### 7.3.1 Tombstone 表

```sql
CREATE TABLE quote_tombstones (
  quote_id TEXT PRIMARY KEY,
  deleted_at TEXT NOT NULL,
  device_id TEXT
);
```

说明：

- tombstone 只表示"这条笔记曾在某时刻被永久删除"
- tombstone **不是绝对优先**，它要和笔记 `last_modified` 比较
- 若后来有更晚的恢复/编辑，则旧 tombstone 不应继续阻止该笔记回来

#### 7.3.2 本地永久删除写入时机

在 `_hardDeleteQuotes(List<String> ids)` 中，**先收集媒体路径，再写 tombstone，再 DELETE**：

```dart
Future<void> _hardDeleteQuotes(List<String> ids) async {
  final now = DateTime.now().toUtc().toIso8601String();

  // 1. 收集媒体路径（引用表 + 内容提取）
  // 2. UPSERT tombstone
  // 3. DELETE quotes
  // 4. 事务提交后做 orphan check，删物理文件
}
```

`permanentlyDeleteQuote`、`emptyTrash`、`autoCleanupExpiredTrash` 全部复用这一套。

#### 7.3.3 同步导入：按时间比较 tombstone 与笔记

`_applyTombstones()` 不能再写成"只要有 tombstone 就删"，而要写成：

1. 取出本地 quote（若存在）和本地 tombstone（若存在）
2. 若本地 tombstone 时间更新，不处理远端 tombstone
3. 若本地 quote 存在，且 `incoming.deleted_at >= localQuote.last_modified`
   - 执行硬删除
   - 写入/更新本地 tombstone
4. 若本地 quote 比 tombstone 更新
   - 忽略这条远端 tombstone

这样才能满足"最新操作优先"。

#### 7.3.4 `_mergeQuotes()` 的 tombstone 处理

插入/更新远端笔记前，要先查本地 tombstone：

```dart
final localTombstone = await txn.query(
  'quote_tombstones',
  where: 'quote_id = ?',
  whereArgs: [quoteId],
  limit: 1,
);

if (localTombstone.isNotEmpty) {
  final deletedAt = localTombstone.first['deleted_at'] as String;
  final quoteLastModified = quoteData['last_modified'] as String?;

  if (_compareIsoTime(quoteLastModified, deletedAt) > 0) {
    // 远端笔记更新更晚，允许恢复/更新，并移除旧 tombstone
    await txn.delete('quote_tombstones', where: 'quote_id = ?', whereArgs: [quoteId]);
  } else {
    reportBuilder.addSkippedQuote();
    continue;
  }
}
```

这一步是保证"恢复后可以重新出现"的关键。

#### 7.3.5 Tombstone 保存策略

- tombstone 可长期保留，存储开销很低
- 但它们只代表最近一次永久删除时间，不是不可推翻的封印
- 当更晚的恢复/编辑到来时，应允许删除旧 tombstone 或至少让它失效

### 7.4 回收站保留时间同步

回收站保留时间属于用户设置，也必须跨设备一致。

- 在 `app_settings.dart` / `settings_service.dart` 中持久化 `trashRetentionDays` 与 `trashRetentionLastModified`
- 在全量备份中通过 `SettingsService.getAllSettingsForBackup()` / `restoreAllSettingsFromBackup()` 完整导出导入
- 在设备同步中，额外通过 `notes.trash_settings` 传播，因为当前 LWW 合并入口只拿 `notes` 段
- 合并规则同样采用 LWW：`last_modified` 更新更晚的设置覆盖更早的设置

### 7.5 版本兼容性

| 场景 | 行为 |
|------|------|
| 旧版备份无 `is_deleted` | 默认按 `false` 处理 |
| 旧版备份无 `tombstones` | 视为空列表 |
| 旧版备份无 `trash_settings` | 默认回退到 30 天 |
| 旧版应用接收带 `tombstones` / `trash_settings` 的同步包 | 旧版忽略未知字段，不影响读取已知字段 |

---

## 8. UI 设计

### 8.1 入口位置 — 双入口

#### 入口 1（浅入口）：首页 AppBar overflow 菜单

```
首页 AppBar [...] 菜单
├── 回收站 (3)     ← 新增，带角标
├── ...
```

#### 入口 2：设置页 → 数据管理区域

```
📦 备份与恢复
🔄 设备同步
🗑️ 回收站 (3)     ← 新增
💾 存储管理
```

### 8.2 回收站页面 (`trash_page.dart`)

```
┌─────────────────────────────────────────┐
│ ← 回收站                    清空回收站    │  AppBar
├─────────────────────────────────────────┤
│ ⓘ 已删除的笔记将在当前保留期后自动清除      │  提示条
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ 笔记内容摘要...                      │ │
│ │ 删除于 3月20日 · 剩余 26 天           │ │
│ │              [恢复]  [永久删除]      │ │
│ └─────────────────────────────────────┘ │
│ ┌─────────────────────────────────────┐ │
│ │ 另一条笔记内容...                     │ │
│ │ 删除于 2月28日 · 剩余 4 天            │ │
│ │              [恢复]  [永久删除]      │ │
│ └─────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│              回收站为空 🗑️               │  空状态
│          删除的笔记会出现在这里            │
└─────────────────────────────────────────┘
```

### 8.3 删除流程变更

**新流程**：
```
用户点击删除 → 确认弹窗 → 软删除
                     └→ SnackBar("已移至回收站，可在回收站恢复")
```

**永久删除 / 清空回收站**仍保留二次确认弹窗（不可逆操作）。

### 8.4 回收站保留时间设置入口

建议把保留时间设置放在 `settings_page.dart` 的数据管理区域，与回收站入口相邻：

```
🗑️ 回收站
🕒 回收站保留时间：30 天
```

点击后弹出单选底部菜单：

- 7 天
- 30 天
- 90 天

选择后立即保存，并参与后续同步。

---

## 9. 国际化 (i18n)

需在所有 ARB 文件（`app_zh.arb`、`app_en.arb`、`app_ja.arb`、`app_ko.arb`、`app_fr.arb`）新增：

| Key | 中文 | 英文 |
|-----|------|------|
| `trash` | 回收站 | Trash |
| `trashEmpty` | 回收站为空 | Trash is empty |
| `trashEmptyHint` | 删除的笔记会出现在这里 | Deleted notes will appear here |
| `trashRetentionHint` | 已删除的笔记将在当前保留期后自动清除 | Deleted notes will be automatically removed after the selected retention period |
| `trashRemainingDays` | 剩余 {days} 天 | {days} days remaining |
| `restoreNote` | 恢复 | Restore |
| `permanentlyDelete` | 永久删除 | Permanently Delete |
| `permanentlyDeleteConfirmation` | 此操作无法撤销，笔记将被永久删除。 | This cannot be undone. The note will be permanently deleted. |
| `emptyTrash` | 清空回收站 | Empty Trash |
| `emptyTrashConfirmation` | 确定要永久删除回收站中的所有笔记吗？此操作无法撤销。 | Permanently delete all notes in trash? This cannot be undone. |
| `noteMovedToTrash` | 笔记已移至回收站，可在回收站恢复 | Note moved to trash. You can restore it from Trash |
| `noteRestored` | 笔记已恢复 | Note restored |
| `trashEmptied` | 回收站已清空 | Trash emptied |
| `deletedAt` | 删除于 {date} | Deleted on {date} |
| `trashCount` | 回收站 ({count}) | Trash ({count}) |
| `trashRetentionPeriod` | 回收站保留时间 | Trash retention period |
| `trashRetentionOption7Days` | 7 天 | 7 days |
| `trashRetentionOption30Days` | 30 天 | 30 days |
| `trashRetentionOption90Days` | 90 天 | 90 days |

---

## 10. 文件变更清单

### 修改文件

| 文件 | 变更 |
|------|------|
| `lib/models/quote_model.dart` | +`isDeleted`/`deletedAt` 字段 + toJson/fromJson/copyWith/validated |
| `lib/models/app_settings.dart` | +`trashRetentionDays` / `trashRetentionLastModified` 字段 + JSON/copyWith |
| `lib/services/database_schema_manager.dart` | version 20 + `createTables()` 加列 + `quote_tombstones` 表 + 迁移分支 + `checkAndFixDatabaseStructure()` + `_removeTagIdsColumnSafely()` 的 `quotes_new` 补列 |
| `lib/services/database_service.dart` | 声明回收站抽象方法 + `part` 引入 trash mixin + 现有接口加 `includeDeleted` 参数 + 导入模式支持 |
| `lib/services/database/database_quote_crud_mixin.dart` | `deleteQuote()` 改软删除 + `getQuoteById`/`getAllQuotes`/`searchQuotesByContent` 加过滤 |
| `lib/services/database/database_query_mixin.dart` | `getUserQuotes()`/`_performDatabaseQuery()` 加 `is_deleted` 过滤 |
| `lib/services/database/database_query_helpers_mixin.dart` | `_directGetQuotes()`/`getQuotesForSmartPush()`/`getQuotesCount()` 加过滤 |
| `lib/services/database/database_favorite_mixin.dart` | `getMostFavoritedQuotesThisWeek()` 排除已删除 + `increment`/`reset` 防御性检查 |
| `lib/services/database/database_hidden_tag_mixin.dart` | `getHiddenQuoteIds()` SQL 改 JOIN quotes + Web 分支过滤 |
| `lib/services/database/database_migration_mixin.dart` | `getHourDistributionForSmartPush()` SQL + Web 排除已删除 |
| `lib/services/database_health_service.dart` | `getLocalDailyQuote()` 两段 SQL 加过滤 + `_getLocalQuoteFromMemory()` 过滤 + 统计口径拆分 |
| `lib/services/database_backup_service.dart` | `importDataFromMap()` 字段映射 `isDeleted`→`is_deleted`、`deletedAt`→`deleted_at` + tombstones 导出/导入 + `_applyTombstones()` 按时间比较 + `_mergeQuotes()` 处理旧 tombstone + `trash_settings` LWW |
| `lib/services/backup_service.dart` | 流式导出/导入同时处理 `quotes`、`tombstones`、`trash_settings` |
| `lib/services/media_reference_service.dart` | L417/451/895 三处加 `includeDeleted: true` |
| `lib/services/media_cleanup_service.dart` | `verifyMediaIntegrity()` L238 加 `includeDeleted: true` |
| `lib/services/settings_service.dart` | 持久化保留时间设置 + 参与全量备份恢复 |
| `lib/pages/home_page.dart` | 删除流程 → 确认弹窗后移入回收站 + AppBar overflow 回收站入口 |
| `lib/pages/settings_page.dart` | 数据管理区域回收站入口 + 保留时间设置入口 |
| `lib/l10n/app_zh.arb` | 新增回收站文案 |
| `lib/l10n/app_en.arb` | 同上 |
| `lib/l10n/app_ja.arb` / `app_ko.arb` / `app_fr.arb` | 同上 |

### 新增文件

| 文件 | 说明 |
|------|------|
| `lib/services/database/database_trash_mixin.dart` | 回收站 CRUD（part of database_service） |
| `lib/pages/trash_page.dart` | 回收站页面 UI |

---

## 11. 实施步骤

### Phase 1：数据层（无 UI 变更，可独立测试）
1. `quote_model.dart` — 新增字段
2. `app_settings.dart` / `settings_service.dart` — 新增 `trashRetentionDays` / `trashRetentionLastModified`，默认 30 天
3. `database_schema_manager.dart` — createTables + version 20 迁移 + `quote_tombstones` 建表 + `checkAndFixDatabaseStructure()` + quotes_new 补列
4. `database_trash_mixin.dart` — 新建回收站 CRUD（含 `_hardDeleteQuotes` 共享方法，硬删除时写入 tombstone）
5. `database_service.dart` — 声明抽象方法 + part 引入 + 接口加 `includeDeleted` + 区分 full restore / merge sync
6. `database_quote_crud_mixin.dart` — deleteQuote 改软删除 + 恢复时统一刷新流 + 查询加过滤
7. 其他 mixin 逐个加过滤 — query_mixin、query_helpers_mixin、favorite_mixin、hidden_tag_mixin、migration_mixin
8. `database_health_service.dart` — getLocalDailyQuote + 统计口径
9. `media_reference_service.dart` — 3 处加 `includeDeleted: true`
10. `media_cleanup_service.dart` — verifyMediaIntegrity 加 `includeDeleted: true`
11. `database_backup_service.dart` — 字段映射 + `exportDataAsMap()` 导出 tombstones + `_applyTombstones()` 改为版本比较 + `_mergeQuotes()` 处理恢复覆盖旧 tombstone + `trash_settings` 合并
12. `backup_service.dart` — 流式导出/导入同步支持 `tombstones` 与 `trash_settings`
13. 单元测试 / 合并测试

### Phase 2：UI 层
14. i18n 文案 — 所有 ARB 文件 + `flutter gen-l10n`
15. `trash_page.dart` — 新建页面
16. `home_page.dart` — 删除确认后移入回收站，并提示"可在回收站恢复"
17. `settings_page.dart` — 回收站入口 + 保留时间选择器

### Phase 3：集成与收尾
18. 自动清理逻辑集成到 `init()`（读取同步后的保留时间）
19. 备份导入/导出兼容性测试（含 tombstone / trash_settings 的新旧版本互操作）
20. LWW 同步测试（软删除/恢复传播 + 永久删除传播 + 恢复覆盖旧 tombstone）
21. 回收站保留时间同步测试（7/30/90 三档切换）
22. Web 平台 `_memoryStore` 全量验证
23. `dart format` + `flutter analyze`

---

## 12. 风险与缓解

| 风险 | 严重程度 | 缓解措施 |
|------|---------|---------|
| `searchQuotesByContent` 误排除回收站 → 媒体文件被误删 | **🔴 高** | 默认 `includeDeleted: true` |
| 自动清理用裸 SQL → 媒体物理文件泄漏 | **🔴 高** | 复用 `_hardDeleteQuotes` 完整流程，先读媒体路径再 DELETE |
| 旧 tombstone 压过更新后的恢复/编辑 | **🔴 高** | tombstone 与 `quote.last_modified` 比较，严格执行"最新操作优先" |
| 流式备份/同步漏导出 tombstones 或 `trash_settings` | **🔴 高** | 同时修改 `database_backup_service.dart` 与 `backup_service.dart` 两条链路 |
| 恢复后列表不刷新 / 恢复项不显示 | **🔴 高** | 删除/恢复/永久删除后统一 `refreshQuotesStreamForParts()` |
| 迁移后 schema 不一致 | 🟡 中 | 同时改 `createTables()` + 迁移 v20 + `checkAndFixDatabaseStructure()` + `_removeTagIdsColumnSafely()` 的 quotes_new |
| 回收站入口过深 | 🟡 中 | 首页 AppBar + 设置页双入口 |
| 回收站保留时间不同步 | 🟡 中 | `trashRetentionLastModified` + LWW 合并 |
| 旧备份无 `is_deleted` 字段 | 🟢 低 | `fromJson` 容错默认 false |
| 回收站占用存储 | 🟢 低 | 7/30/90 天自动清理 + 手动清空 |
