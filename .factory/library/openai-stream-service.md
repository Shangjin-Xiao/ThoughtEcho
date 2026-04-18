# OpenAI Stream Service Architecture

## Overview

`OpenAIStreamService` is a new service that wraps the `openai_dart` package's `OpenAIClient` 
to handle streaming and non-streaming AI requests for all OpenAI-compatible providers.

## Architecture

```
AIService (public API — UNCHANGED)
  ├─ streamAskQuestion()        → Stream<String>
  ├─ streamGeneralConversation() → Stream<String>
  ├─ streamMessageChunks()      → Stream<String>
  └─ ... (future: delegates internally to OpenAIStreamService)
       │
       ▼ (future milestone)
OpenAIStreamService (NEW — uses openai_dart)
  ├─ streamChat()              → Stream<String>
  │    └─ OpenAIClient(config).chat.completions.createStream()
  │         └─ Stream<ChatStreamEvent> → converted to Stream<String>
  ├─ streamChatWithThinking()  → Stream<String>
  │    └─ Same as above + reasoning_content callback + Ollama think:true
  ├─ chatCompletion()          → Future<String>
  │    └─ OpenAIClient(config).chat.completions.create()
  └─ buildConfig()             → OpenAIConfig
       └─ From AIProviderSettings → baseUrl, apiKey, model
```

## Key Design Decisions

1. **OpenAIStreamService extends ChangeNotifier** — injected in main.dart Provider tree
2. **URL normalization**: `normalizeOpenAIBaseUrl()` strips `/chat/completions` suffix and 
   ensures `/v1` path, letting `openai_dart` append `/chat/completions` automatically
3. **Ollama thinking**: For `enableThinking=true` with Ollama, the `think: true` parameter
   is injected via custom HTTP SSE request since `openai_dart`'s `ChatCompletionCreateRequest` 
   doesn't support it directly
4. **Provider headers**: Custom headers (OpenRouter's HTTP-Referer, X-Title) are preserved
5. **Client lifecycle**: Each streaming request creates a new `OpenAIClient` that's closed 
   after the stream completes

## URL Normalization Rules

| Input URL | Normalized URL | Notes |
|-----------|---------------|-------|
| `https://api.openai.com/v1/chat/completions` | `https://api.openai.com/v1` | Strip endpoint |
| `https://api.openai.com/v1` | `https://api.openai.com/v1` | Already correct |
| `http://localhost:11434` | `http://localhost:11434/v1` | Add /v1 |
| `http://localhost:11434/v1` | `http://localhost:11434/v1` | Already correct |
| `https://openrouter.ai/api/v1` | `https://openrouter.ai/api/v1` | Preserve /api/v1 |
| `https://api.deepseek.com` | `https://api.deepseek.com/v1` | Add /v1 |

## Validation Assertions Fulfilled

- **VAL-NONSTREAM-001**: URL construction handles all provider URL formats without 405 errors
- **VAL-NONSTREAM-003**: Provider URLs ending in /v1 correctly resolve (no double /v1)
- **VAL-ERR-001**: No 405 errors for any provider URL configuration
- **VAL-STREAM-001**: streamChat() returns Stream<String> with incremental text chunks
- **VAL-STREAM-002**: Streaming completes with Ollama (via openai_dart SSE handling)

## File Locations

| File | Description |
|------|-------------|
| `lib/services/openai_stream_service.dart` | Service implementation |
| `test/unit/services/openai_stream_service_test.dart` | Unit tests |
| `lib/main.dart` | Provider registration |
