# Async Traps

- FutureBuilder triggers on every rebuild — cache Future in initState or field
- StreamBuilder — same issue, cache stream or use BehaviorSubject for replay
- `mounted` check — always before setState after await
- Dispose before async completes — subscription/timer fires on disposed widget
- CancelToken in dispose — cancel ongoing HTTP requests
- Error handling in FutureBuilder — provide builder for error state
- RefreshIndicator with FutureBuilder — tricky combo, manage state separately
- Timer.periodic — must cancel in dispose, or keeps firing
- AnimationController — must dispose, vsync requires TickerProviderStateMixin
