## 2025-05-18 - [Stability & Availability] Safe numeric reading for SQLite aggregate functions
**Learning:** SQLite query results for `COUNT(*)` or numeric aggregates can return varying types (`int`, `int64`, `num`) depending on the driver or underlying SQLite library behavior across platforms. Directly using `as int` on `Map<String, dynamic>` rawQuery results introduces dangerous `TypeError` crash risks during startup database health checks.
**Action:** Always use safe helper methods like `_readCount` or `(row[key] as num?)?.toInt() ?? 0` when parsing aggregate query fields from sqflite.
