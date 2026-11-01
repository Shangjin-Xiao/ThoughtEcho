## 2025-05-18 - [Stability & Availability] Safe numeric reading for SQLite aggregate functions
**Learning:** SQLite query results for `COUNT(*)` or numeric aggregates can return varying types (`int`, `int64`, `num`) depending on the driver or underlying SQLite library behavior across platforms. Directly using `as int` on `Map<String, dynamic>` rawQuery results introduces dangerous `TypeError` crash risks during startup database health checks.
**Action:** Always use safe helper methods like `_readCount` or `(row[key] as num?)?.toInt() ?? 0` when parsing aggregate query fields from sqflite.

## 2025-05-19 - [Data Integrity & Integration] Symmetric metadata repair across both replace and merge import pipelines
**Learning:** When multi-device synchronization (LWW merge) and whole-database replacement (restore) co-exist, domain metadata repairs (such as backfilling missing `deleted_at` timestamps for soft-deleted items) can easily be applied to one pipeline while forgotten in the other. Incomplete trash metadata (`is_deleted = 1` with `deleted_at IS NULL`) prevents expired notes from ever being purged by retention janitors (`autoCleanupExpiredTrash`), permanently bloating local storage.
**Action:** Always extract shared row-level integrity normalization helpers and apply them symmetrically across both replace and merge import paths.
