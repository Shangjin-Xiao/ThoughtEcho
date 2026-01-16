## 2024-05-22 - [Critical] Zip Slip Vulnerability Fixed
**Vulnerability:** Found `ZipStreamProcessor` extracting files trusting zip filenames without validation. This allows "Zip Slip" attacks where a malicious zip containing `../../etc/passwd` could overwrite system files.
**Learning:** Archive extraction libraries often don't validate paths by default.
**Prevention:** Always validate that the canonical path of the extraction target starts with the canonical extraction directory.
