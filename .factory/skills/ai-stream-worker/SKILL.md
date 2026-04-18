---
name: ai-stream-worker
description: Implements AI streaming refactoring features using openai_dart. Handles OpenAIStreamService creation, AIService migration, thinking parameter injection, and cleanup.
---

# AI Stream Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features related to AI streaming refactoring:
- Creating OpenAIStreamService infrastructure
- Migrating AIService methods to use openai_dart
- Implementing thinking parameter injection
- Deprecating old AINetworkManager code

## Required Skills

- `flutter-testing-apps` — for writing and running Flutter unit tests
- `systematic-debugging` — for debugging streaming issues if tests fail

## Work Procedure

### Step 1: Understand the Architecture

Read these files BEFORE making any changes:

1. `.factory/library/architecture.md` — Target architecture diagram and data flow
2. `.factory/library/environment.md` — Environment setup and dependencies
3. `lib/services/agent_service.dart` — REFERENCE: how openai_dart is already used in the project
4. `lib/services/ai_service.dart` — The service being refactored (read ALL public method signatures)
5. `lib/models/ai_provider_settings.dart` — Provider configuration model (being extended)
6. `lib/models/multi_ai_settings.dart` — Multi-provider settings
7. `lib/pages/ai_assistant/ai_assistant_page_workflow.dart` — UI integration point for streaming

### Step 2: Write Tests First (TDD)

For EACH feature, write failing tests BEFORE implementing:

1. Create test file: `test/unit/services/openai_stream_service_test.dart`
2. Write tests covering:
   - URL construction for various provider formats (bare host, /v1, /v1/chat/completions)
   - Stream conversion from ChatStreamEvent to String
   - Thinking parameter injection (think:true for Ollama, none for DeepSeek)
   - Error handling (network errors, 405 errors, timeouts)
   - Multi-provider configuration
3. Run `flutter test test/unit/services/openai_stream_service_test.dart` — tests MUST FAIL (red)

### Step 3: Implement

Follow the architecture in `.factory/library/architecture.md`:

**For `openai-stream-service-core` feature:**
1. Create `lib/services/openai_stream_service.dart`
2. Build `OpenAIClient` from `AIProviderSettings` (baseUrl, apiKey, model)
3. Implement `streamChat()` — convert `Stream<ChatStreamEvent>` to `Stream<String>`
4. Implement `streamChatWithThinking()` — same but with thinking params
5. Implement `chatCompletion()` — non-streaming request
6. Register in `main.dart` Provider tree

**For `aiservice-streaming-migration` feature:**
1. Modify `AIService` methods to delegate to `OpenAIStreamService`
2. Preserve ALL public method signatures
3. Handle CancelToken integration (openai_dart uses different cancellation)
4. Test each migrated method individually

**For `thinking-parameter-injection` feature:**
1. Add `enableThinking` field to `AIProviderSettings`
2. Update `toJson()`/`fromJson()` for persistence
3. Modify `supportsThinking` to be more permissive
4. Implement passive detection (always parse reasoning_content)
5. Update AI assistant page to pass thinking state

**For `cleanup-and-integration` feature:**
1. Add `@deprecated` annotations to unused `AINetworkManager`/`AIRequestHelper` methods
2. Verify no direct Dio calls remain for AI requests
3. Run `flutter analyze --no-fatal-infos`
4. Run `dart format --set-exit-if-changed .`

### Step 4: Verify

1. Run ALL tests: `flutter test test/all_tests.dart --concurrency=1`
2. Run new tests: `flutter test test/unit/services/openai_stream_service_test.dart`
3. Run static analysis: `flutter analyze --no-fatal-infos`
4. Run format check: `dart format --set-exit-if-changed .`
5. If ANY step fails, debug and fix before proceeding

### Step 5: Manual Verification (if Ollama available)

1. Start Ollama: `ollama serve`
2. Pull a model: `ollama pull llama3` (or any available)
3. Run the app and test AI chat with streaming
4. Verify tokens appear incrementally (not all at once)
5. Test thinking toggle visibility and function
6. Test cancel/stop button during streaming
7. Test error handling (stop Ollama, try to chat)

### Step 6: Commit

Commit with clear message describing what was implemented and tested.

## Example Handoff

```json
{
  "salientSummary": "Created OpenAIStreamService using openai_dart v4.0.1, migrated AIService streaming methods to delegate internally while preserving public API. Fixed 405 errors via proper URL construction. Added enableThinking field to AIProviderSettings with Ollama think:true injection. All 24 unit tests pass.",
  "whatWasImplemented": "OpenAIStreamService with streamChat(), streamChatWithThinking(), chatCompletion() methods. Migrated streamAskQuestion, streamGeneralConversation, streamMessageChunks, generateSessionTitle, and 7 other methods. Added enableThinking bool? field to AIProviderSettings with persistence. Deprecated 12 methods in AINetworkManager.",
  "whatWasLeftUndone": "streamReportInsight still uses old path via AIRequestHelper — it has a double-controller pattern that needs special handling for backward compatibility.",
  "verification": {
    "commandsRun": [
      {"command": "flutter test test/unit/services/openai_stream_service_test.dart", "exitCode": 0, "observation": "24 tests pass"},
      {"command": "flutter test test/all_tests.dart --concurrency=1", "exitCode": 0, "observation": "All existing tests pass"},
      {"command": "flutter analyze --no-fatal-infos", "exitCode": 0, "observation": "No new errors"},
      {"command": "dart format --set-exit-if-changed .", "exitCode": 0, "observation": "All files formatted"}
    ],
    "interactiveChecks": [
      {"action": "AI chat with Ollama llama3 model", "observed": "Tokens stream incrementally, no buffering"},
      {"action": "Stop button during streaming", "observed": "Partial response stays, streaming stops"},
      {"action": "generateSessionTitle with Ollama", "observed": "No 405 error, title generated"}
    ]
  },
  "tests": {
    "added": [
      {"file": "test/unit/services/openai_stream_service_test.dart", "cases": [
        {"name": "builds OpenAIConfig from AIProviderSettings", "verifies": "URL construction"},
        {"name": "streamChat returns incremental String chunks", "verifies": "streaming not buffered"},
        {"name": "chatCompletion returns full response", "verifies": "non-streaming works"},
        {"name": "think parameter injected for Ollama", "verifies": "thinking injection"},
        {"name": "no think parameter for DeepSeek R1", "verifies": "auto reasoning models"},
        {"name": "handles connection refused gracefully", "verifies": "error handling"}
      ]}
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- Feature depends on a model or interface that doesn't exist yet (e.g., `AIProviderSettings` hasn't been extended yet)
- `openai_dart` package API doesn't support a needed feature
- Cannot resolve a conflict between preserving `AIService` public API and using `openai_dart`
- Tests fail due to pre-existing issues unrelated to the refactoring
- Ollama is not available for manual testing (note this in handoff)
