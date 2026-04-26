# AI Service Architecture

## Current Architecture (Pre-Refactoring)

```
AIService (public API)
  ├─ streamAskQuestion()        → Stream<String>
  ├─ streamGeneralConversation() → Stream<String>
  ├─ streamMessageChunks()      → Stream<String>
  ├─ generateSessionTitle()     → Future<String>
  ├─ summarizeNote()            → Future<String>
  └─ ... other methods
       │
       ▼
AIRequestHelper (request building)
  ├─ createRequestBody()
  ├─ makeRequestWithProvider()
  ├─ makeStreamRequestWithProvider()
  └─ executeStreamOperation()
       │
       ▼
AINetworkManager (Dio HTTP + SSE)
  ├─ makeRequest()        (non-streaming)
  ├─ makeStreamRequest()  (streaming SSE)
  ├─ _makeBaseRequest()   (Dio config)
  └─ _processStreamResponse() (SSE parser)
```

## Target Architecture (Post-Refactoring)

```
AIService (public API — UNCHANGED)
  ├─ streamAskQuestion()        → Stream<String>
  ├─ streamGeneralConversation() → Stream<String>
  ├─ ... (all signatures preserved)
  │
  │  Internally delegates to:
  ▼
OpenAIStreamService (NEW — uses openai_dart)
  ├─ streamChat()              → Stream<String>
  │    └─ OpenAIClient(config).chat.completions.createStream()
  │         └─ Stream<ChatStreamEvent> → converted to Stream<String>
  ├─ streamChatWithThinking()  → Stream<String>
  │    └─ Same as above but injects thinking params per provider
  ├─ chatCompletion()          → Future<String>
  │    └─ OpenAIClient(config).chat.completions.create()
  └─ buildConfig()             → OpenAIConfig
       └─ From AIProviderSettings → baseUrl, apiKey, model

AIProviderSettings (EXTENDED)
  └─ + enableThinking: bool?  (null=auto, true=on, false=off)
```

## Key Design Decisions

1. **OpenAIStreamService is internal**: Not exposed to UI, only used by AIService internally
2. **AIService public API unchanged**: All callers (30+ sites) work without modification
3. **openai_dart handles SSE**: No manual SSE parsing — library handles chunk delimiting, [DONE] sentinel, delta extraction
4. **Thinking is per-provider configurable**: `enableThinking` field on AIProviderSettings, with auto-inference fallback
5. **Passive thinking detection**: If `reasoning_content` appears in stream regardless of toggle, display it
6. **Multi-provider failover preserved**: OpenAIClient is constructed per-provider on each request

## Data Flow: Streaming Chat

```
User types message in AI assistant
  │
  ▼
ai_assistant_page_workflow.dart: _askGeneralChat()
  │  Creates StreamSubscription on AIService.streamGeneralConversation()
  ▼
AIService.streamGeneralConversation()
  │  Internally calls OpenAIStreamService.streamChatWithThinking()
  ▼
OpenAIStreamService.streamChatWithThinking()
  │  1. Build OpenAIConfig from current AIProviderSettings
  │  2. Create OpenAIClient(config)
  │  3. Build ChatCompletionCreateRequest with thinking params
  │  4. Call client.chat.completions.createStream(request)
  │  5. Convert Stream<ChatStreamEvent> → Stream<String>
  │     - TextDeltaEvent.delta → onData callback
  │     - ReasoningDeltaEvent  → onThinking callback
  │     - CompletionEvent     → onComplete
  ▼
AIService returns Stream<String>
  │
  ▼
UI updates via setState per chunk (existing pattern preserved)
```

## Thinking Parameter Mapping

| Provider | Request Parameter | Condition |
|----------|------------------|-----------|
| Ollama | `think: true` | enableThinking == true |
| DeepSeek R1 | None (auto) | reasoning_content comes automatically |
| OpenAI o1/o3/o4 | None (auto) | reasoning handled by model |
| OpenRouter (thinking models) | None | reasoning_content in delta |
| Any (passive) | None | Display reasoning_content if present |

## File Changes Map

| File | Change Type | Description |
|------|------------|-------------|
| `lib/services/openai_stream_service.dart` | NEW | Core streaming service using openai_dart |
| `lib/services/ai_service.dart` | MODIFY | Delegate to OpenAIStreamService internally |
| `lib/models/ai_provider_settings.dart` | MODIFY | Add enableThinking field, relax supportsThinking |
| `lib/models/multi_ai_settings.dart` | MODIFY | Persist enableThinking in toJson/fromJson |
| `lib/pages/ai_assistant/ai_assistant_page_workflow.dart` | MODIFY | Pass thinking state to API request |
| `lib/utils/ai_network_manager.dart` | DEPRECATE | Mark unused methods @deprecated |
| `lib/utils/ai_request_helper.dart` | DEPRECATE | Mark unused methods @deprecated |
| `lib/main.dart` | MODIFY | Register OpenAIStreamService in Provider tree |
| `test/unit/services/openai_stream_service_test.dart` | NEW | Unit tests for OpenAIStreamService |
