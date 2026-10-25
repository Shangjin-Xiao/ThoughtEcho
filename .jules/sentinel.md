## 2024-05-27 - Fix SQL Injection Vulnerability in Schema Definitions
**Vulnerability:** Potential SQL Injection via string interpolation in `PRAGMA table_info($tableName)`.
**Learning:** `PRAGMA table_info` does not natively support standard parameterization via `?`. Instead, the table-valued function `pragma_table_info(?)` must be used in a `SELECT` query to safely bind parameters.
**Prevention:** Always use `SELECT * FROM pragma_table_info(?)` with bound arguments instead of `PRAGMA table_info(...)` with string interpolation.

## 2024-05-28 - Fix SQL Injection in SQLite DDL Statements
**Vulnerability:** SQL Injection via string interpolation in non-parameterizable SQLite queries like `ALTER TABLE`.
**Learning:** `ALTER TABLE` and similar DDL statements cannot use standard parameterization (`?`). Using string interpolation directly (e.g. `ALTER TABLE quotes ADD COLUMN $columnName $type`) exposes the database to potential injection if the inputs are derived from uncontrolled sources. SAST tools will flag this pattern.
**Prevention:** Always validate identifiers (like column names) with strict regular expressions (e.g., `^[a-zA-Z_][a-zA-Z0-9_]*$`). Construct the query securely by safely escaping identifiers (wrapping them in double quotes and replacing internal quotes via `.replaceAll('"', '""')`) and using string concatenation instead of Dart's `$var` interpolation to prevent SAST tool warnings and ensure safety.
## 2026-10-09 - Fix SQL Injection Vulnerability in ALTER TABLE
**Vulnerability:** String interpolation in DDL statements without strict validation.
**Learning:** SQLite DDL does not support parameterization. Column definitions can be complex, containing commas or parenthesis. Validating identifiers accurately and strictly validating column definitions against whitelist formats is critical to prevent injection.
**Prevention:** Use whitelist regex for identifiers and column definitions when interpolating in DDL queries and use parameterized queries for all DML.

## 2026-10-25 - Centralize External Daily Quote API Endpoints
**Vulnerability:** Hardcoded external API URLs scattered directly inside method implementations.
**Learning:** Inlining third-party API endpoint URLs inside raw method bodies reduces visibility, makes endpoint management/auditing error-prone, and hinders domain restriction or environment configuration.
**Prevention:** Always define external API URLs as static constants on service classes (`ApiService.meigenApiUrl`, etc.) and ensure network requests validate domain schemes (HTTPS) and use centralized endpoint definitions.
