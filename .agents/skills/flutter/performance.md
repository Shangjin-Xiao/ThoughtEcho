# Performance Traps

- Missing `const` — non-const widgets rebuild children even if unchanged
- ListView without builder — loads all items into memory, use `.builder`
- Large list itemExtent — providing fixed height enables optimizations
- Image not cached — use `cached_network_image` package
- setState scope — rebuilds entire widget, extract child widgets
- RepaintBoundary — isolates repaint region, use for animations
- ValueListenableBuilder — better than setState for single value changes
- AutomaticKeepAliveClientMixin — preserves TabBarView/PageView state but uses memory
- Opacity widget expensive — prefer `FadeTransition` or `AnimatedOpacity`
