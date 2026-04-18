# User Testing Guide

## Validation Surface

This is a Flutter mobile/desktop app (Android, Windows, iOS). Testing is done via:

1. **Unit tests** (`flutter test`) — automated verification of service logic
2. **Manual device testing** — running the app and verifying behavior

No browser or TUI automation is available.

## Required Testing Skills/Tools
- `flutter test` for unit tests
- Manual testing on device/emulator for streaming, thinking, and error handling

## Validation Concurrency

- **Machine**: 2 CPU cores, 3.8 GB RAM
- **Max concurrent validators**: 1 (resource-constrained environment)
- **Resource cost**: Each flutter test run uses ~300MB RAM. Manual testing requires running the Flutter app.

## Testing Checklist for Validators

### Stream Testing
1. Start Ollama: `ollama serve`
2. Pull a model: `ollama pull llama3` (or any available model)
3. Open app → AI assistant → send a message → verify tokens stream incrementally
4. Watch for buffering: tokens should appear one by one, NOT all at once after completion
5. Test cancel: send a message → press stop → verify partial response stays

### Thinking Testing
1. Pull thinking model: `ollama pull qwen3` or `deepseek-r1`
2. Enable thinking toggle in AI assistant
3. Send a message → verify thinking area appears with reasoning content
4. Disable thinking → send message → verify no thinking content but response still works
5. Close app → reopen → verify thinking setting persisted

### Error Testing
1. Stop Ollama → send message → verify friendly error (not crash)
2. Enter invalid API key → verify friendly error
3. Test with provider URL ending in /v1 → verify no 405 error
