1. **Analyze the Security Issue**:
   The current implementation of `_secureLegacyApiKey` leaves sensitive API keys exposed in plain text in `SharedPreferences` in two ways:
   - When clearing the key, it sets the value to `""` and saves the JSON back to `SharedPreferences` via `setString`. This is less secure than completely removing the entry and can leave traces on the disk.
   - If `saveProviderApiKey` (the migration to secure storage) fails, it catches the error and deliberately chooses *not* to clear the plain text key from storage (`shouldClear = false`), prioritizing data preservation over security. This violates the "fail secure" principle.

2. **Fix the Vulnerability**:
   Modify `_secureLegacyApiKey` in `lib/services/settings_service.dart` to:
   - Always extract the legacy API key, checking both `_aiSettings` and `_prefs`.
   - Attempt to migrate the key to `SecureStorage`.
   - **Crucially**: Enforce `fail secure` by unconditionally clearing the plain text API key from memory, `MMKV`, and completely removing the `_aiSettingsKey` entry from `SharedPreferences` via `_prefs.remove()`, regardless of whether the migration succeeded or failed.

3. **Verify the Fix**:
   - Format the file.
   - Run `flutter analyze` to ensure there are no compilation or syntax errors.
   - Run the test suite to ensure no existing tests are broken.

4. **Complete Pre Commit Steps**:
   - Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done.

5. **Submit**:
   - Submit the PR with the title `🔒 [Security] Fix API key leakage in SharedPreferences`.
