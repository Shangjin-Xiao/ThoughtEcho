# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Repository overview
- Name: thoughtecho (ThoughtEcho)
- Type: Flutter application (Dart) targeting Windows, Android, iOS and Web
- Entry point: lib/main.dart
- Primary UI framework: Flutter with provider for state management
- Local storage: sqflite (mobile) and sqflite_common_ffi for desktop; MMKV for high-performance storage; flutter_secure_storage for secrets
- Rich text editor: flutter_quill
- Tests: located under test/ with unit, widget and integration tests; CI configured in .github/workflows/test.yml

Common commands
- Install dependencies: flutter pub get
- Run app (device/emulator attached): flutter run
- Run tests (all): flutter test
- Run a single test file: flutter test test/path/to/file_test.dart
- Run integration tests (desktop/Linux in CI): flutter test integration_test/ -d linux
- Analyze/lint: flutter analyze
- Format check: dart format --set-exit-if-changed .
- Build (examples): flutter build apk --debug, flutter build web, flutter build linux --debug

Testing notes
- CI shards unit tests across two shards using flutter test --shard-index/--total-shards
- Coverage artifacts are produced using --coverage
- Integration tests require enabling desktop support and Xvfb in CI

Project structure (high-level)
- lib/: application code
  - lib/main.dart: app bootstrap, service initialization, Provider wiring (primary entry)
  - lib/pages/: top-level screens (HomePage, OnboardingPage, Backup/Restore, Emergency pages)
  - lib/services/: long-lived services (DatabaseService, NoteSyncService, NetworkService, AI services, BackupService, SettingsService, etc.)
  - lib/utils/: helpers and small utilities (logging, network testing, diagnostics)
  - lib/widgets/: reusable widgets (dialogs, UI components)
  - lib/controllers/: controllers for UI logic (search, etc.)
- test/: unit, widget and integration tests; test/all_tests.dart groups tests
- android/, ios/, linux/, web/: platform-specific code and build artifacts
- pubspec.yaml: dependencies and dev_dependencies
- .github/workflows/: CI definitions for testing and building

Codebase conventions and patterns
- Provider pattern for dependency injection and state management; many services are provided via ChangeNotifier or Provider.value
- Services are split between lightweight (MMKV) initialized at startup and heavier services (Database, AI DB) initialized asynchronously in background
- Platform-specific handling: Windows desktop uses sqflite_common_ffi and has shorter timeouts in main.dart
- Tests use flutter_test + test packages; mockito and fake_async are available for unit tests

Developer workflows for Claude Code
- Always run flutter pub get before making code changes that touch dependencies
- Run flutter analyze and dart format to keep CI happy
- When adding or changing services, update tests in test/unit or relevant integration tests
- When running or writing integration tests, prefer reproducing CI steps locally (enable desktop support for Linux with flutter config --enable-linux-desktop and run under Xvfb if needed)

Files worth checking first when triaging issues
- lib/main.dart: startup/init behavior and service wiring (lib/main.dart:1)
- lib/services/database_service.dart: database lifecycle and migrations
- lib/services/note_sync_service.dart: note sync logic and device discovery
- lib/services/backup_service.dart: backup creation and validation
- test/all_tests.dart: test grouping and execution

CI/automation hints
- Tests run in two shards; if adding long-running tests, mark them to avoid slowing both shards
- Formatting and analysis are enforced in CI; run locally to prevent failures

If CLAUDE.md exists: suggest edits
- If you update this file, avoid repeating README content. Focus on developer commands, architecture, and files to inspect for common tasks.
