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

## 2026-02-13 - [High] Incomplete Zip Slip Protection Fixed
**Vulnerability:** Path validation used `startsWith` to check if the extraction target was within the destination directory. This allowed a sibling directory attack (e.g., `/extract` matches `/extract_evil`). While a secondary `path.relative` check existed, the primary check was logically flawed. Additionally, `ZipStreamProcessor` did not explicitly reject symbolic links, potentially bypassing path validation.
**Learning:** String-based path checks are prone to edge cases (trailing slashes, partial matches). `startsWith` does not respect path boundaries.
**Prevention:** Use semantic path checks like `path.isWithin` from standard libraries which correctly handles directory separators. Ensure archive extraction logic explicitly rejects symbolic links (check `file.isSymbolicLink`) to prevent symlink-based attacks.
