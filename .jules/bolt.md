## 2024-05-24 - [Partial Object Data Loss Risk]
**Learning:** When optimizing database queries to fetch "partial" objects (excluding large columns) for list views, there is a critical risk of data loss if these partial objects are passed to an editor that saves the object back to the database. The editor might overwrite the missing fields with null.
**Action:** Always ensure the editor fetches the *full* object by ID before allowing a save operation. Implement a "loading" state to block the save button until the full data is retrieved.

## 2026-03-21 - [Wrong l10n Import Breaks Release Build]
**Learning:** This project uses `synthetic-package: false` in `l10n.yaml`, so generated localization files live under `lib/gen_l10n/`. The old `package:flutter_gen/gen_l10n/app_localizations.dart` import path does NOT work and causes release build failures (`Not found: 'package:flutter_gen/...'`). It may pass `flutter analyze` locally but fails during `flutter build apk --release`.
**Action:** Always import localizations via relative path (`../gen_l10n/app_localizations.dart`) or package path (`package:thoughtecho/gen_l10n/app_localizations.dart`). Never use `package:flutter_gen/...`.

## 2024-05-24 - [Isolate Refactoring Pattern]
**Learning:** When moving logic to an Isolate via `compute`, avoid dependencies on singletons like `AppLogger`.
**Action:** Refactor logic into pure static methods that accept a `List<String> logBuffer` and return it in a result object, then replay logs on the main thread.

## 2025-03-27 - [N+1 DB Insert Optimization]
**Learning:** In Dart/Flutter SQLite (`sqflite`), using a `for` loop to execute `await txn.insert()` causes a significant Platform Channel communication overhead per iteration. This is particularly problematic when saving objects with multiple relationships (like tags).
**Action:** Always use `txn.batch()` to enqueue commands and execute them together via `await batch.commit(noResult: true)` when inserting or updating multiple related rows in SQLite. This eliminates the N+1 execution overhead.
## 2026-04-03 - [SQLite Pagination Aggregation Pitfall]
**Learning:** In SQLite queries with pagination (`LIMIT`/`OFFSET`), fetching aggregated related data (e.g., tags) via `LEFT JOIN` and `GROUP BY` causes severe performance degradation because it aggregates the entire table *before* applying the limit. This affects functions like `_directGetQuotes`.
**Action:** Use a scalar subquery in the `SELECT` clause (e.g., `(SELECT GROUP_CONCAT(tag_id) FROM quote_tags WHERE quote_id = q.id)`) to only aggregate the limited rows, avoiding full-table aggregation.

## 2026-02-13 - 优化数据库备份合并过程中的批量处理
**Learning:** 在循环中执行大量的数据库插入或更新操作（N+1 问题）会导致显著的 I/O 等待和事务开销。通过 `txn.batch()` 可以将这些操作合并为一个批次提交。此外，在循环开始前预查元数据并使用内存中的 Map 进行匹配，可以消除循环内的查询开销。需要注意在 batch 提交前手动更新内存中的缓存，以处理同一批次中可能出现的重复条目。
**Action:** 在 `lib/services/database_backup_service.dart` 的 `_mergeCategories` 和 `_mergeQuotes` 中实现了 `Batch` 操作和元数据预查。

## 2024-05-30 - [SQLite Many-to-Many Multi-Tag Filtering Optimization]
**Learning:** When fetching data with multiple tag constraints in SQLite, using `IN (...) GROUP BY ... HAVING COUNT(...) = N` causes a severe performance hit because it forces SQLite to join and aggregate the entire table before applying pagination (`LIMIT`).
**Action:** For paginated list queries (e.g., `getUserQuotes`), use multiple `EXISTS` subqueries, one for each tag. For counting queries (e.g., `getQuotesCount`) over the full dataset, multiple `INNER JOIN` clauses perform vastly better than multiple `EXISTS` (~18ms vs ~33s).
