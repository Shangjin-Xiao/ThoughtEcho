# Environment

Environment variables, external dependencies, and setup notes.

**What belongs here:** Required env vars, external API keys/services, dependency quirks, platform-specific notes.
**What does NOT belong here:** Service ports/commands (use `.factory/services.yaml`).

---

## Flutter SDK
- Flutter 3.38.6 (stable channel, Dart 3.10.7)
- DevTools 2.51.1
- Target platforms: Android, Windows, iOS (NOT web)

## External Dependencies
- Ollama: Running on localhost:11434 (optional for integration testing)
- DeepSeek API: Requires valid API key (configurable in app settings)
- OpenRouter API: Requires valid API key
- OpenAI API: Requires valid API key

## Dependency Quirks
- openai_dart v4.0.1 is already in pubspec.yaml and used by AgentService
- openai_dart uses `http` package internally (not Dio), which avoids the streaming buffer issues with Dio
- Ollama's OpenAI-compatible endpoint: `http://localhost:11434/v1/chat/completions`
- Ollama's `think` parameter is passed in the request body (not URL)
- `dart format --set-exit-if-changed .` is enforced by CI

## Machine Resources
- 2 CPU cores, 3.8 GB RAM
- Use `--concurrency=1` for flutter test to avoid resource exhaustion

## Key Files
- `pubspec.yaml` — dependencies
- `lib/services/agent_service.dart` — existing openai_dart usage (reference)
- `lib/services/ai_service.dart` — service being refactored
- `lib/utils/ai_network_manager.dart` — being deprecated
- `lib/utils/ai_request_helper.dart` — being deprecated
- `lib/models/ai_provider_settings.dart` — being extended with enableThinking
- `lib/pages/ai_assistant/` — UI layer for AI chat
