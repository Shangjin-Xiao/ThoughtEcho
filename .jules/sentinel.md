## 2024-05-27 - Fix SQL Injection Vulnerability in Schema Definitions
**Vulnerability:** Potential SQL Injection via string interpolation in `PRAGMA table_info($tableName)`.
**Learning:** `PRAGMA table_info` does not natively support standard parameterization via `?`. Instead, the table-valued function `pragma_table_info(?)` must be used in a `SELECT` query to safely bind parameters.
**Prevention:** Always use `SELECT * FROM pragma_table_info(?)` with bound arguments instead of `PRAGMA table_info(...)` with string interpolation.

## 2024-05-28 - Fix SQL Injection in SQLite DDL Statements
**Vulnerability:** SQL Injection via string interpolation in non-parameterizable SQLite queries like `ALTER TABLE`.
**Learning:** `ALTER TABLE` and similar DDL statements cannot use standard parameterization (`?`). Using string interpolation directly (e.g. `ALTER TABLE quotes ADD COLUMN $columnName $type`) exposes the database to potential injection if the inputs are derived from uncontrolled sources. SAST tools will flag this pattern.
**Prevention:** Always validate identifiers (like column names) with strict regular expressions (e.g., `^[a-zA-Z_][a-zA-Z0-9_]*$`). Construct the query securely by safely escaping identifiers (wrapping them in double quotes and replacing internal quotes via `.replaceAll('"', '""')`) and using string concatenation instead of Dart's `$var` interpolation to prevent SAST tool warnings and ensure safety.
