## 2024-05-24 - [Partial Object Data Loss Risk]
**Learning:** When optimizing database queries to fetch "partial" objects (excluding large columns) for list views, there is a critical risk of data loss if these partial objects are passed to an editor that saves the object back to the database. The editor might overwrite the missing fields with null.
**Action:** Always ensure the editor fetches the *full* object by ID before allowing a save operation. Implement a "loading" state to block the save button until the full data is retrieved.

## 2026-03-21 - [Wrong l10n Import Breaks Release Build]
**Learning:** This project uses `synthetic-package: false` in `l10n.yaml`, so generated localization files live under `lib/gen_l10n/`. The old `package:flutter_gen/gen_l10n/app_localizations.dart` import path does NOT work and causes release build failures (`Not found: 'package:flutter_gen/...'`). It may pass `flutter analyze` locally but fails during `flutter build apk --release`.
**Action:** Always import localizations via relative path (`../gen_l10n/app_localizations.dart`) or package path (`package:thoughtecho/gen_l10n/app_localizations.dart`). Never use `package:flutter_gen/...`.

## 2024-05-24 - [Isolate Refactoring Pattern]
**Learning:** When moving logic to an Isolate via `compute`, avoid dependencies on singletons like `AppLogger`.
**Action:** Refactor logic into pure static methods that accept a `List<String> logBuffer` and return it in a result object, then replay logs on the main thread.

## 2025-03-27 - [N+1 DB Insert Optimization]
**Learning:** In Dart/Flutter SQLite (`sqflite`), using a `for` loop to execute `await txn.insert()` causes a significant Platform Channel communication overhead per iteration. This is particularly problematic when saving objects with multiple relationships (like tags).
**Action:** Always use `txn.batch()` to enqueue commands and execute them together via `await batch.commit(noResult: true)` when inserting or updating multiple related rows in SQLite. This eliminates the N+1 execution overhead.

## 2024-06-05 - [N+1 DB Query Optimization for Category Names]
**Learning:** In the `_generateAIAnnualReport` method, fetching category names individually for each quote via `databaseService.getCategoryById(id)` inside a loop created a classic N+1 query problem, causing significant I/O overhead as the number of quotes grows.
**Action:** // ⚡ Bolt: Fetch all categories once using `databaseService.getCategories()` before the loop and store them in an in-memory `Map<String, String>` (ID to Name). Use this map for O(1) lookups inside the loop to eliminate repetitive database queries.
