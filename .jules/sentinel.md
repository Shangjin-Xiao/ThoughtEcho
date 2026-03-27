## 2024-05-24 - SQL Injection in DatabaseHealthService
**Vulnerability:** The `checkColumnExists` and `createIndexSafely` methods in `DatabaseHealthService` directly interpolated dynamic variables (`tableName`, `columnName`, `indexName`) into SQLite commands (e.g., `PRAGMA table_info($tableName)`).
**Learning:** Database schema operations (like `PRAGMA` or `CREATE INDEX`) often cannot use parameterized queries (i.e. `?` arguments), so standard parameterization defenses fail. When variables must be interpolated into schema commands, strict regex validation is necessary.
**Prevention:** All schema identifiers must be validated against a strict allowlist or regex (e.g., `r'^[a-zA-Z_][a-zA-Z0-9_]*$'`) before being used in raw SQL queries.
