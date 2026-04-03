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
<<<<<<< bolt/sqlite-scalar-subquery-optimization-12317187905385071383

## 2025-04-03 - [LEFT JOIN + GROUP BY vs Scalar Subquery in SQLite]
**Learning:** In SQLite queries containing `LIMIT`/`OFFSET` (e.g., pagination), fetching aggregated related data (like tags) using a `LEFT JOIN` and `GROUP BY` forces SQLite to perform a full table aggregation before applying the limit. This leads to a massive degradation in performance when the table size grows.
**Action:** Replace `LEFT JOIN` + `GROUP BY` with a scalar subquery in the `SELECT` clause, such as `(SELECT GROUP_CONCAT(tag_id) FROM quote_tags WHERE quote_id = q.id)`. This ensures that the aggregation is only executed on the already filtered/limited result set, transforming an $O(N \times M)$ operation into an $O(L)$ operation, where $L$ is the limit.
=======
## 2026-04-03 - [SQLite Pagination Aggregation Pitfall]
**Learning:** In SQLite queries with pagination (`LIMIT`/`OFFSET`), fetching aggregated related data (e.g., tags) via `LEFT JOIN` and `GROUP BY` causes severe performance degradation because it aggregates the entire table *before* applying the limit. This affects functions like `_directGetQuotes`.
**Action:** Use a scalar subquery in the `SELECT` clause (e.g., `(SELECT GROUP_CONCAT(tag_id) FROM quote_tags WHERE quote_id = q.id)`) to only aggregate the limited rows, avoiding full-table aggregation.
>>>>>>> main
