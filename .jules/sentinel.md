## 2024-05-27 - Fix SQL Injection Vulnerability in Schema Definitions
**Vulnerability:** Potential SQL Injection via string interpolation in `PRAGMA table_info($tableName)`.
**Learning:** `PRAGMA table_info` does not natively support standard parameterization via `?`. Instead, the table-valued function `pragma_table_info(?)` must be used in a `SELECT` query to safely bind parameters.
**Prevention:** Always use `SELECT * FROM pragma_table_info(?)` with bound arguments instead of `PRAGMA table_info(...)` with string interpolation.
