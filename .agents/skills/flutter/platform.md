# Platform Channel Traps

- PlatformException — always wrap channel calls in try-catch
- Null from platform — platform returns null, Dart expects non-null, crash
- Main thread only — UI updates from platform must be on main thread
- Binary messenger — raw bytes need codec handling
- Method channel naming — use reverse domain, conflicts with other plugins
- Missing implementation — iOS/Android not implemented, crashes at runtime
- Codec mismatch — JSON encode/decode must match platform expectations
- Background execution — platform channels don't work when app killed
