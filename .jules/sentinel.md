## 2024-05-22 - [Critical] Zip Slip Vulnerability Fixed
**Vulnerability:** Found `ZipStreamProcessor` extracting files trusting zip filenames without validation. This allows "Zip Slip" attacks where a malicious zip containing `../../etc/passwd` could overwrite system files.
**Learning:** Archive extraction libraries often don't validate paths by default.
**Prevention:** Always validate that the canonical path of the extraction target starts with the canonical extraction directory.

## 2026-01-23 - [Critical] Insecure API Key Storage Fixed
**Vulnerability:** API keys were stored in `SafeMMKV` which uses plaintext SharedPreferences/MMKV.
**Learning:** `SafeMMKV` or similar wrappers might imply safety but default to insecure storage. "Secure" in class names must be verified against implementation. When migrating from insecure to secure storage, ensure legacy data is *always* deleted, even if migration is skipped because new data exists.
**Prevention:** Use `flutter_secure_storage` for sensitive data. Verify storage implementation details.
