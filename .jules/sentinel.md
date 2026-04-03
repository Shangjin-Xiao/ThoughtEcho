## 2024-05-22 - [Critical] Zip Slip Vulnerability Fixed 
 **Vulnerability:** Found `ZipStreamProcessor` extracting files trusting zip filenames without validation. This allows "Zip Slip" attacks where a malicious zip containing `../../etc/passwd` could overwrite system files. 
 **Learning:** Archive extraction libraries often don't validate paths by default. 
 **Prevention:** Always validate that the canonical path of the extraction target starts with the canonical extraction directory. 
  
 ## 2026-01-23 - [Critical] Insecure API Key Storage Fixed 
 **Vulnerability:** API keys were stored in `SafeMMKV` which uses plaintext SharedPreferences/MMKV. 
 **Learning:** `SafeMMKV` or similar wrappers might imply safety but default to insecure storage. "Secure" in class names must be verified against implementation. When migrating from insecure to secure storage, ensure legacy data is *always* deleted, even if migration is skipped because new data exists. 
 **Prevention:** Use `flutter_secure_storage` for sensitive data. Verify storage implementation details. 
  
 ## 2026-02-12 - [High] Missing CSP in Generated HTML Fixed 
 **Vulnerability:** Generated HTML reports (AI Annual Report) lacked Content Security Policy (CSP) headers, allowing potential XSS if the content contained malicious scripts (e.g., from AI hallucination or compromised data). 
 **Learning:** Even when generating static HTML for external viewing (browser launch), you must enforce CSP to prevent execution of unwanted scripts. `RegExp` matching for HTML tags must handle attributes (e.g., `<head profile="...">`) to avoid replacing the entire tag and losing attributes. 
 **Prevention:** Use `ContentSanitizer.injectCsp` to automatically inject strict CSP headers into generated HTML. 
  
 ## 2026-02-13 - [High] Legacy Plaintext API Key Migration 
 **Vulnerability:** Legacy `AISettings` (used before `MultiAISettings`) stored API keys in the `apiKey` field, which was serialized to JSON and stored in `MMKV` (insecure plaintext). Although the app migrated to `APIKeyManager`, the old `AISettings` blob remained in storage. 
 **Learning:** Migration logic must not only move data to secure storage but also *sanitize* the old data source. Simple "if exists, migrate" logic often leaves the insecure copy behind. 
 **Prevention:** Implement explicit cleanup logic (`_secureLegacyApiKey`) that checks for and removes sensitive fields from legacy storage structures after successful migration or redundancy check. Enforce empty values for sensitive fields in legacy models' serialization logic (`updateAISettings`). 
 ## 2024-05-24 - SQL Injection in DatabaseHealthService 
 **Vulnerability:** The `checkColumnExists` and `createIndexSafely` methods in `DatabaseHealthService` directly interpolated dynamic variables (`tableName`, `columnName`, `indexName`) into SQLite commands (e.g., `PRAGMA table_info($tableName)`). 
 **Learning:** Database schema operations (like `PRAGMA` or `CREATE INDEX`) often cannot use parameterized queries (i.e. `?` arguments), so standard parameterization defenses fail. When variables must be interpolated into schema commands, strict regex validation is necessary. 
 **Prevention:** All schema identifiers must be validated against a strict allowlist or regex (e.g., `r'^[a-zA-Z_][a-zA-Z0-9_]*$'`) before being used in raw SQL queries.
## 2025-05-18 - Parameterized Table-Valued Functions for SQLite PRAGMA
**Vulnerability:** SQL Injection in `DatabaseHealthService.checkColumnExists` via string interpolation (`PRAGMA table_info($tableName)`). While some protection was attempted with `_isValidIdentifier`, passing unsanitized table names into PRAGMA statements is fundamentally unsafe.
**Learning:** Standard PRAGMA statements do not accept bound parameters (`?`). However, SQLite provides table-valued functions (e.g., `pragma_table_info(?)`) which *do* support parameterization. Using the table-valued function allows for safe binding of the table name without string concatenation.
**Prevention:** Always use SQLite's table-valued functions (e.g., `SELECT * FROM pragma_table_info(?)`) with parameterized queries instead of string interpolation for schema operations where applicable.
