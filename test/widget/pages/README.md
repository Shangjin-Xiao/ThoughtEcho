# NoteSyncPage Tests

This directory contains comprehensive unit tests for the NoteSyncPage widget.

## Testing Framework
- **Flutter Test**: Built-in Flutter testing framework
- **Mockito 5.4.4**: For mocking dependencies

## Running the Tests

1. Generate mocks (required before running tests):
   ```bash
   dart run build_runner build
   ```

2. Run all tests:
   ```bash
   flutter test test/widget/pages/note_sync_page_test.dart
   ```

3. Run tests with coverage:
   ```bash
   flutter test --coverage test/widget/pages/note_sync_page_test.dart
   ```

## Test Coverage

The tests cover:

### UI Rendering
- Initial UI elements (AppBar, title, refresh button)
- Scanning state display
- Empty state when no devices found
- Device count display when devices are found

### Device List Display
- Device list rendering with multiple devices
- Correct device icons based on device type
- Device information display (name, IP:port)

### Button States
- Refresh button disabled while scanning
- Refresh button enabled when not scanning
- Loading indicator during note sending

### User Interactions
- Refresh button tap handling
- Send button tap handling
- Verification of service method calls

### Device Icon Method Tests
- Icon mapping for all device types (mobile, desktop, web, server, headless)

### Error Handling
- Service initialization failures
- Device discovery failures
- Note sending failures

### Widget Lifecycle
- Proper resource disposal
- Mounted checks in async operations

### State Management
- Scanning state transitions
- Sending state transitions

### Edge Cases
- Empty device aliases
- Very long device names
- Large device lists
- Null sync service scenarios

### Accessibility
- Semantic labels for screen readers
- Device list accessibility

### Performance
- Rapid state changes
- Simultaneous operations

## Mock Services

The tests use mocked versions of:
- `DatabaseService`
- `SettingsService`
- `AIAnalysisDatabaseService`
- `NoteSyncService`
- `BackupService`

## Test Structure

Tests are organized into logical groups:
- UI Rendering Tests
- Device List Display Tests
- Button State Tests
- Usage Instructions Tests
- User Interaction Tests
- Device Icon Method Tests
- Error Handling Tests
- Widget Lifecycle Tests
- State Management Tests
- Edge Cases
- Accessibility Tests
- Performance Tests

Each test group focuses on a specific aspect of the widget's functionality.