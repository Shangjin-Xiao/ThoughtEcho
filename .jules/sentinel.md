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
