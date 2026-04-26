# AIService Streaming Migration

## What was done

Migrated all streaming methods in `AIService` to delegate to `OpenAIStreamService` internally, replacing the old `AIRequestHelper` → `AINetworkManager` (Dio-based) path with `openai_dart`-based streaming.

## Migrated Methods

### Streaming methods (now use `_streamViaOpenAI`):
- `streamSummarizeNote` — note analysis
- `streamReportInsight` — periodic report insight generation
- `streamGenerateDailyPrompt` — daily prompt generation (with fallback)
- `streamGenerateInsights` — insight generation
- `streamAnalyzeSource` — source analysis
- `streamPolishText` — text polishing
- `streamContinueText` — text continuation
- `streamAskQuestion` — note Q&A (with `onThinking` callback)
- `streamGeneralConversation` — general chat (with `onThinking` callback)
- `streamMessageChunks` — advanced streaming chat
- `streamFetchWebContent` — web content fetching + summarization

### Non-streaming method migrated:
- `generateSessionTitle` — session title generation (now uses `_chatCompletionViaOpenAI`)

## New Internal Helper Methods

### `_streamViaOpenAI`
Common streaming delegation method that:
1. Validates API key and settings
2. Gets current provider with API key
3. Builds ChatMessage list from system/user prompt
4. Delegates to `OpenAIStreamService.streamChatWithThinking()`
5. Returns `Stream<String>` to callers (unchanged interface)

### `_chatCompletionViaOpenAI`
Common non-streaming delegation method that:
1. Validates API key and settings
2. Gets current provider with API key
3. Builds ChatMessage list
4. Delegates to `OpenAIStreamService.chatCompletion()`
5. Returns `Future<String>` to callers (unchanged interface)

### `_buildChatMessages`
Converts (systemPrompt, userMessage, history) into `List<openai.ChatMessage>`, handling:
- System message as first message
- History context messages (token budget truncation)
- Current user message as last message

## Key Design Decisions

1. **Public API unchanged**: All method signatures (return types, parameter names) are preserved exactly
2. **StreamController for cancellation**: When the UI cancels a stream, the StreamController is closed, which stops the underlying `openai_dart` stream
3. **Error handling preserved**: `_streamViaOpenAI` wraps errors via try-catch and adds them to the controller
4. **onThinking callback supported**: `streamAskQuestion` and `streamGeneralConversation` pass through `onThinking` to `streamChatWithThinking()`
5. **Fallback preserved**: `streamGenerateDailyPrompt` still falls back to `DailyPromptGenerator` when API key is invalid
6. **Pre-stream validation preserved**: Early returns for invalid API key, empty content, etc.

## Cancel/Stop Button Integration

The UI cancels streams by calling `_streamSubscription?.cancel()`. When the subscription is cancelled:
- `_streamViaOpenAI` creates a `StreamController(sync: true)` 
- The downstream listener cancels, causing the `await for` loop to stop
- The `controller.isClosed` check prevents writes to closed controllers
- The underlying `openai_dart` stream is cancelled when no one is listening

## Non-migrated methods (still use old path)

The following non-streaming methods still use `AIRequestHelper` / `AINetworkManager`:
- `summarizeNote`, `generateInsights`, `analyzeSource`
- `generateAnnualReportHTML` / `_generateFallbackHtml`
- `polishText`, `continueText`, `askQuestion`
- `testConnection` / `testConnectionWithMultiProvider`
- `summarizeNoteWithMultiProvider`, `fetchWebContent`

These will be migrated in a future feature (cleanup-and-integration).
