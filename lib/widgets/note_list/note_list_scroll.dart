part of '../note_list_view.dart';

/// Scroll-related methods for NoteListViewState.
extension _NoteListScrollExtension on NoteListViewState {
  String _quoteContentCacheStatsText() {
    return QuoteContent.debugCompactCacheStats();
  }

  String _flutterImageCacheStatsText({int? baselineCount, int? baselineBytes}) {
    final imageCache = PaintingBinding.instance.imageCache;
    final deltaCount =
        baselineCount == null ? null : imageCache.currentSize - baselineCount;
    final deltaBytes = baselineBytes == null
        ? null
        : imageCache.currentSizeBytes - baselineBytes;
    return 'img=${imageCache.currentSize}/${imageCache.maximumSize}, '
        'live=${imageCache.liveImageCount}, pending=${imageCache.pendingImageCount}, '
        'bytes=${_formatBytes(imageCache.currentSizeBytes)}/${_formatBytes(imageCache.maximumSizeBytes)}'
        '${deltaCount == null ? '' : ',Δimg${_formatSignedInt(deltaCount)}'}'
        '${deltaBytes == null ? '' : ',Δbytes${_formatSignedBytes(deltaBytes)}'}';
  }

  String _quoteItemCacheStatsText({Map<String, int>? baseline}) {
    final stats = QuoteItemWidget.getCacheStats();
    final cacheSize = stats['cacheSize'] ?? 0;
    final cacheHits = stats['cacheHits'] ?? 0;
    final baselineHits = baseline?['cacheHits'];
    return 'item=$cacheSize,hit=$cacheHits'
        '${baselineHits == null ? '' : ',Δhit+${cacheHits - baselineHits}'}';
  }

  String _formatSignedInt(int value) {
    if (value >= 0) {
      return '+$value';
    }
    return value.toString();
  }

  String _formatSignedBytes(int bytes) {
    final sign = bytes >= 0 ? '+' : '-';
    return '$sign${_formatBytes(bytes.abs())}';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${bytes}B';
  }

  String _quoteMixStatsText() {
    final total = _quotes.length;
    var rich = 0;
    var media = 0;
    var expandable = 0;
    var expanded = 0;

    for (final quote in _quotes) {
      final quoteId = quote.id;
      if (quoteId != null && (_expandedItems[quoteId] ?? false)) {
        expanded++;
      }
      final deltaContent = quote.deltaContent;
      if (deltaContent != null && quote.editSource == 'fullscreen') {
        rich++;
        if (deltaContent.contains('"image"') ||
            deltaContent.contains('"video"') ||
            deltaContent.contains('"audio"')) {
          media++;
        }
      }
      if (QuoteItemWidget.needsExpansionFor(quote)) {
        expandable++;
      }
    }

    return 'total=$total, rich=$rich, media=$media, expandable=$expandable, '
        'expanded=$expanded, tracked=${_expandedItems.length}';
  }

  void _logNoteListPerfSnapshot(String reason) {
    if (!_firstOpenScrollPerfEnabled) {
      return;
    }

    logDebug(
      '$reason: quotes={${_quoteMixStatsText()}}, '
      'quoteContent={${_quoteContentCacheStatsText()}}, '
      'quoteItem={${_quoteItemCacheStatsText()}}, '
      'imageCache={${_flutterImageCacheStatsText()}}',
      source: 'NoteListView.Perf',
    );
  }

  void _startScrollSessionPerfCapture(ScrollMetrics metrics) {
    if (!_firstOpenScrollPerfEnabled || !_initialDataLoaded) {
      return;
    }

    _scrollSessionPerfRecording = true;
    _scrollSessionPerfPendingFinalize = false;
    _scrollSessionPerfStopTimer?.cancel();
    _scrollSessionStartMicros = DateTime.now().microsecondsSinceEpoch;
    _scrollSessionStartOffset = metrics.pixels;
    _scrollSessionLastOffset = metrics.pixels;
    _scrollSessionMinOffset = metrics.pixels;
    _scrollSessionMaxOffset = metrics.pixels;
    _scrollSessionUpdateMicros.clear();
    _scrollSessionFrameTimings.clear();
    _scrollSessionStartQuoteContentStats = QuoteContent.debugCacheStats();
    _scrollSessionStartQuoteItemStats = QuoteItemWidget.getCacheStats();
    final imageCache = PaintingBinding.instance.imageCache;
    _scrollSessionStartImageCount = imageCache.currentSize;
    _scrollSessionStartImageBytes = imageCache.currentSizeBytes;
    _ensurePerfTimingsCallback();
  }

  void _recordScrollSessionUpdate(ScrollMetrics metrics) {
    if (!_scrollSessionPerfRecording) {
      return;
    }

    _scrollSessionUpdateMicros.add(DateTime.now().microsecondsSinceEpoch);
    _scrollSessionLastOffset = metrics.pixels;
    if (metrics.pixels < _scrollSessionMinOffset) {
      _scrollSessionMinOffset = metrics.pixels;
    }
    if (metrics.pixels > _scrollSessionMaxOffset) {
      _scrollSessionMaxOffset = metrics.pixels;
    }
  }

  void _scheduleScrollSessionPerfFinalize(ScrollMetrics metrics) {
    if (!_scrollSessionPerfRecording || _scrollSessionPerfPendingFinalize) {
      return;
    }

    _scrollSessionPerfPendingFinalize = true;
    _scrollSessionLastOffset = metrics.pixels;
    _scrollSessionPerfStopTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollSessionPerfRecording) {
        return;
      }
      _scrollSessionPerfStopTimer = Timer(
        const Duration(milliseconds: 260),
        _finalizeScrollSessionPerfCapture,
      );
    });
  }

  void _finalizeScrollSessionPerfCapture() {
    if (!_scrollSessionPerfRecording) {
      return;
    }

    _scrollSessionPerfStopTimer?.cancel();
    _scrollSessionPerfRecording = false;
    _scrollSessionPerfPendingFinalize = false;

    final elapsedMs =
        (DateTime.now().microsecondsSinceEpoch - _scrollSessionStartMicros) /
            1000.0;
    final distance = _scrollSessionLastOffset - _scrollSessionStartOffset;
    final direction = distance > 0
        ? 'down'
        : distance < 0
            ? 'up'
            : 'still';

    var jankyIntervals = 0;
    var worstIntervalMicros = 0;
    var totalIntervalMicros = 0;
    for (var i = 1; i < _scrollSessionUpdateMicros.length; i++) {
      final interval =
          _scrollSessionUpdateMicros[i] - _scrollSessionUpdateMicros[i - 1];
      totalIntervalMicros += interval;
      if (interval > worstIntervalMicros) {
        worstIntervalMicros = interval;
      }
      if (interval > 20000) {
        jankyIntervals++;
      }
    }

    var jankyFrames = 0;
    var totalFrameMicros = 0;
    var totalBuildMicros = 0;
    var totalRasterMicros = 0;
    var worstFrameMs = 0.0;
    var worstBuildMs = 0.0;
    var worstRasterMs = 0.0;
    for (final timing in _scrollSessionFrameTimings) {
      final buildMicros = timing.buildDuration.inMicroseconds;
      final rasterMicros = timing.rasterDuration.inMicroseconds;
      final totalMicros = buildMicros + rasterMicros;
      totalFrameMicros += totalMicros;
      totalBuildMicros += buildMicros;
      totalRasterMicros += rasterMicros;
      final frameMs = totalMicros / 1000.0;
      final buildMs = buildMicros / 1000.0;
      final rasterMs = rasterMicros / 1000.0;
      if (frameMs > worstFrameMs) {
        worstFrameMs = frameMs;
      }
      if (buildMs > worstBuildMs) {
        worstBuildMs = buildMs;
      }
      if (rasterMs > worstRasterMs) {
        worstRasterMs = rasterMs;
      }
      if (totalMicros > 16600) {
        jankyFrames++;
      }
    }

    final intervalSamples =
        (_scrollSessionUpdateMicros.length - 1).clamp(0, 1 << 30);
    final avgIntervalMs = intervalSamples == 0
        ? 0.0
        : (totalIntervalMicros / intervalSamples) / 1000.0;
    final frameSamples = _scrollSessionFrameTimings.length;
    final avgFrameMs =
        frameSamples == 0 ? 0.0 : (totalFrameMicros / frameSamples) / 1000.0;
    final avgBuildMs =
        frameSamples == 0 ? 0.0 : (totalBuildMicros / frameSamples) / 1000.0;
    final avgRasterMs =
        frameSamples == 0 ? 0.0 : (totalRasterMicros / frameSamples) / 1000.0;

    final cacheBaseline = _scrollSessionStartQuoteContentStats;
    final quoteContentStats = QuoteContent.debugCompactCacheStats(
      baseline: cacheBaseline,
    );
    final quoteItemStats = _quoteItemCacheStatsText(
      baseline: _scrollSessionStartQuoteItemStats,
    );
    final imageStats = _flutterImageCacheStatsText(
      baselineCount: _scrollSessionStartImageCount,
      baselineBytes: _scrollSessionStartImageBytes,
    );

    logDebug(
      '滚动性能摘要(复制此行): dir=$direction, '
      'offset=${_scrollSessionStartOffset.round()}→${_scrollSessionLastOffset.round()}, '
      'dist=${distance.round()}, range=${_scrollSessionMinOffset.round()}-${_scrollSessionMaxOffset.round()}, '
      'elapsed=${elapsedMs.toStringAsFixed(0)}ms, updates=$intervalSamples, '
      'eventJank=$jankyIntervals, eventAvg=${avgIntervalMs.toStringAsFixed(1)}ms, '
      'eventWorst=${(worstIntervalMicros / 1000.0).toStringAsFixed(1)}ms, '
      'frames=$frameSamples, frameJank=$jankyFrames, '
      'avgFrame=${avgFrameMs.toStringAsFixed(1)}ms, worstFrame=${worstFrameMs.toStringAsFixed(1)}ms, '
      'avgBuild=${avgBuildMs.toStringAsFixed(1)}ms, worstBuild=${worstBuildMs.toStringAsFixed(1)}ms, '
      'avgRaster=${avgRasterMs.toStringAsFixed(1)}ms, worstRaster=${worstRasterMs.toStringAsFixed(1)}ms, '
      'quotes={${_quoteMixStatsText()}}, quoteContent={$quoteContentStats}, '
      'quoteItem={$quoteItemStats}, imageCache={$imageStats}',
      source: 'NoteListView.Perf',
    );
    _scrollSessionStartQuoteContentStats = null;
    _scrollSessionStartQuoteItemStats = null;
    _releasePerfTimingsCallbackIfIdle();
  }

  void _startFirstOpenScrollPerfCapture() {
    if (!_firstOpenScrollPerfEnabled ||
        _firstOpenScrollPerfCaptured ||
        _firstOpenScrollPerfRecording ||
        !_initialDataLoaded) {
      return;
    }

    _firstOpenScrollPerfRecording = true;
    _firstOpenScrollFrameTimings.clear();
    _firstOpenScrollUpdateMicros.clear();
    _firstOpenScrollStopTimer?.cancel();
    _ensurePerfTimingsCallback();
    logDebug('首次滑动性能监测开始', source: 'NoteListView.Perf');
  }

  void _stopFirstOpenScrollPerfCapture() {
    if (!_firstOpenScrollPerfRecording) {
      return;
    }

    _firstOpenScrollStopTimer?.cancel();
    _firstOpenScrollStopTimer = Timer(
      const Duration(milliseconds: 180),
      () => _finalizeFirstOpenScrollPerfCapture(),
    );
  }

  void _finalizeFirstOpenScrollPerfCapture() {
    if (!_firstOpenScrollPerfRecording) {
      return;
    }

    _firstOpenScrollPerfRecording = false;
    _firstOpenScrollPerfCaptured = true;
    _releasePerfTimingsCallbackIfIdle();

    if (_firstOpenScrollFrameTimings.isNotEmpty) {
      int jankyFrames = 0;
      double worstFrameMs = 0;
      double worstBuildMs = 0;
      double worstRasterMs = 0;
      int totalFrameMicros = 0;
      int totalBuildMicros = 0;
      int totalRasterMicros = 0;

      for (final timing in _firstOpenScrollFrameTimings) {
        final int buildMicros = timing.buildDuration.inMicroseconds;
        final int rasterMicros = timing.rasterDuration.inMicroseconds;
        final int totalMicros = buildMicros + rasterMicros;
        totalFrameMicros += totalMicros;
        totalBuildMicros += buildMicros;
        totalRasterMicros += rasterMicros;

        final frameMs = totalMicros / 1000.0;
        final buildMs = buildMicros / 1000.0;
        final rasterMs = rasterMicros / 1000.0;
        if (frameMs > worstFrameMs) {
          worstFrameMs = frameMs;
        }
        if (buildMs > worstBuildMs) {
          worstBuildMs = buildMs;
        }
        if (rasterMs > worstRasterMs) {
          worstRasterMs = rasterMs;
        }

        if (totalMicros > 16600) {
          jankyFrames++;
        }
      }

      final totalFrames = _firstOpenScrollFrameTimings.length;
      final avgFrameMs = (totalFrameMicros / totalFrames) / 1000.0;
      final avgBuildMs = (totalBuildMicros / totalFrames) / 1000.0;
      final avgRasterMs = (totalRasterMicros / totalFrames) / 1000.0;

      logDebug(
        '首次滑动性能结果(FrameTiming): total=$totalFrames, jank=$jankyFrames, '
        'avg=${avgFrameMs.toStringAsFixed(1)}ms, '
        'worst=${worstFrameMs.toStringAsFixed(1)}ms, '
        'avgBuild=${avgBuildMs.toStringAsFixed(1)}ms, worstBuild=${worstBuildMs.toStringAsFixed(1)}ms, '
        'avgRaster=${avgRasterMs.toStringAsFixed(1)}ms, worstRaster=${worstRasterMs.toStringAsFixed(1)}ms',
        source: 'NoteListView.Perf',
      );
    } else {
      if (_firstOpenScrollUpdateMicros.length < 2) {
        logDebug(
          '首次滑动性能结果(滚动事件): 样本不足，updates=${_firstOpenScrollUpdateMicros.length}',
          source: 'NoteListView.Perf',
        );
        return;
      }

      int jankyIntervals = 0;
      int worstIntervalMicros = 0;
      int totalIntervalMicros = 0;

      for (int i = 1; i < _firstOpenScrollUpdateMicros.length; i++) {
        final int interval = _firstOpenScrollUpdateMicros[i] -
            _firstOpenScrollUpdateMicros[i - 1];
        if (interval > worstIntervalMicros) {
          worstIntervalMicros = interval;
        }
        totalIntervalMicros += interval;
        if (interval > 20000) {
          jankyIntervals++;
        }
      }

      final int sampleCount = _firstOpenScrollUpdateMicros.length - 1;
      final double avgIntervalMs = (totalIntervalMicros / sampleCount) / 1000.0;
      final double worstIntervalMs = worstIntervalMicros / 1000.0;

      logDebug(
        '首次滑动性能结果(滚动事件回退): samples=$sampleCount, '
        'jankIntervals=$jankyIntervals, '
        'avgInterval=${avgIntervalMs.toStringAsFixed(1)}ms, '
        'worstInterval=${worstIntervalMs.toStringAsFixed(1)}ms',
        source: 'NoteListView.Perf',
      );
    }

    if (!mounted) {
      return;
    }
    _logNoteListPerfSnapshot('首次滑动缓存状态');
  }

  void _startLoadMorePerfCapture() {
    if (!_firstOpenScrollPerfEnabled || _loadMorePerfRecording) {
      return;
    }

    _loadMorePerfRecording = true;
    _loadMorePerfPendingFrameSettle = false;
    _loadMorePerfStartCount = _quotes.length;
    _loadMorePerfTriggerOffset =
        _scrollController.hasClients ? _scrollController.offset.round() : 0;
    _loadMorePerfFrameTimings.clear();
    _loadMorePerfStopTimer?.cancel();
    _loadMorePerfStopwatch
      ..reset()
      ..start();
    _ensurePerfTimingsCallback();

    logDebug(
      '加载更多性能监测开始: startCount=$_loadMorePerfStartCount, '
      'offset=$_loadMorePerfTriggerOffset',
      source: 'NoteListView.Perf',
    );
  }

  void _markLoadMorePerfDataArrived() {
    if (!_loadMorePerfRecording || _loadMorePerfPendingFrameSettle) {
      return;
    }
    _loadMorePerfPendingFrameSettle = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_loadMorePerfRecording) {
        return;
      }
      _loadMorePerfStopTimer?.cancel();
      _loadMorePerfStopTimer = Timer(
        const Duration(milliseconds: 220),
        _finalizeLoadMorePerfCapture,
      );
    });
  }

  void _cancelLoadMorePerfCapture(String reason) {
    if (!_loadMorePerfRecording) {
      return;
    }

    _loadMorePerfStopTimer?.cancel();
    _loadMorePerfStopwatch.stop();
    _loadMorePerfRecording = false;
    _loadMorePerfPendingFrameSettle = false;
    _releasePerfTimingsCallbackIfIdle();

    logDebug(
      '加载更多性能监测取消: $reason, elapsed=${_loadMorePerfStopwatch.elapsedMilliseconds}ms',
      source: 'NoteListView.Perf',
    );
  }

  void _finalizeLoadMorePerfCapture() {
    if (!_loadMorePerfRecording) {
      return;
    }

    _loadMorePerfStopTimer?.cancel();
    _loadMorePerfStopwatch.stop();

    final elapsedMs = _loadMorePerfStopwatch.elapsedMilliseconds;
    final addedCount = (_quotes.length - _loadMorePerfStartCount).clamp(
      0,
      _quotes.length,
    );

    int jankyFrames = 0;
    double worstFrameMs = 0;
    double worstBuildMs = 0;
    double worstRasterMs = 0;
    int totalFrameMicros = 0;
    int totalBuildMicros = 0;
    int totalRasterMicros = 0;

    for (final timing in _loadMorePerfFrameTimings) {
      final int buildMicros = timing.buildDuration.inMicroseconds;
      final int rasterMicros = timing.rasterDuration.inMicroseconds;
      final int totalMicros = buildMicros + rasterMicros;
      totalFrameMicros += totalMicros;
      totalBuildMicros += buildMicros;
      totalRasterMicros += rasterMicros;

      final frameMs = totalMicros / 1000.0;
      final buildMs = buildMicros / 1000.0;
      final rasterMs = rasterMicros / 1000.0;
      if (frameMs > worstFrameMs) {
        worstFrameMs = frameMs;
      }
      if (buildMs > worstBuildMs) {
        worstBuildMs = buildMs;
      }
      if (rasterMs > worstRasterMs) {
        worstRasterMs = rasterMs;
      }
      if (totalMicros > 16600) {
        jankyFrames++;
      }
    }

    final totalFrames = _loadMorePerfFrameTimings.length;
    final avgFrameMs =
        totalFrames == 0 ? 0.0 : (totalFrameMicros / totalFrames) / 1000.0;
    final avgBuildMs =
        totalFrames == 0 ? 0.0 : (totalBuildMicros / totalFrames) / 1000.0;
    final avgRasterMs =
        totalFrames == 0 ? 0.0 : (totalRasterMicros / totalFrames) / 1000.0;

    logDebug(
      '加载更多性能结果: start=$_loadMorePerfStartCount, '
      'current=${_quotes.length}, added=$addedCount, hasMore=$_hasMore, '
      'elapsed=${elapsedMs}ms, frames=$totalFrames, jank=$jankyFrames, '
      'avg=${avgFrameMs.toStringAsFixed(1)}ms, '
      'worst=${worstFrameMs.toStringAsFixed(1)}ms, '
      'avgBuild=${avgBuildMs.toStringAsFixed(1)}ms, worstBuild=${worstBuildMs.toStringAsFixed(1)}ms, '
      'avgRaster=${avgRasterMs.toStringAsFixed(1)}ms, worstRaster=${worstRasterMs.toStringAsFixed(1)}ms',
      source: 'NoteListView.Perf',
    );
    _logNoteListPerfSnapshot('加载更多缓存状态');

    _loadMorePerfRecording = false;
    _loadMorePerfPendingFrameSettle = false;
    _releasePerfTimingsCallbackIfIdle();
  }

  void _settleLoadMoreGateAfterPage() {
    if (!_loadMoreAwaitingPage) {
      return;
    }

    _loadMoreAwaitingPage = false;
    _loadMoreSettleTimer?.cancel();
    _loadMoreSettleTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || !_isLoading) {
        return;
      }
      _updateState(() {
        _isLoading = false;
      });
    });
  }

  void _resetLoadMoreGate() {
    _loadMoreAwaitingPage = false;
    _loadMoreSettleTimer?.cancel();
    _loadMoreSettleTimer = null;
  }

  /// 修复：检测并修复滚动范围异常
  /// 当用户滚动到接近底部但列表提前终止时，尝试强制刷新
  void _checkAndFixScrollExtentAnomaly() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_isLoading || !_hasMore) return;

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final currentOffset = position.pixels;

    // 如果用户滚动到了接近底部（最后 200 像素），但 _hasMore 为 true
    // 且列表似乎没有更多内容可滚动，这可能是异常情况
    if (maxExtent > 0 && currentOffset > maxExtent - 200) {
      // 检查是否实际还有更多数据
      final db = Provider.of<DatabaseService>(context, listen: false);
      final dbHasMore = db.hasMoreQuotes;

      if (dbHasMore && !_isLoading) {
        // 数据库表示还有更多数据，但列表可能没有正确更新
        _scrollExtentCheckCounter++;
        logDebug(
          '检测到可能的滚动范围异常 (第 $_scrollExtentCheckCounter 次): '
          'maxExtent=$maxExtent, offset=$currentOffset, dbHasMore=$dbHasMore',
          source: 'NoteListView',
        );

        if (_scrollExtentCheckCounter >=
            NoteListViewState._maxScrollExtentChecks) {
          // 多次检测到异常，尝试强制加载更多
          logDebug('触发强制加载更多数据以修复滚动范围', source: 'NoteListView');
          _scrollExtentCheckCounter = 0;
          _forceLoadMore();
        }
      } else if (!dbHasMore && _hasMore) {
        // 数据库表示没有更多数据，但本地状态不一致，同步状态
        logDebug('同步 _hasMore 状态: 从 true 改为 false', source: 'NoteListView');
        _updateState(() {
          _hasMore = false;
        });
        _scrollExtentCheckCounter = 0;
      }
    } else {
      // 不在底部区域，重置计数器
      _scrollExtentCheckCounter = 0;
    }
  }

  /// 修复：强制加载更多数据
  Future<void> _forceLoadMore() async {
    if (!mounted || _isLoading) return;

    logDebug('强制加载更多数据开始', source: 'NoteListView');

    _updateState(() {
      _isLoading = true;
    });

    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.loadMoreQuotes();

      if (mounted) {
        _updateState(() {
          _hasMore = db.hasMoreQuotes;
          _isLoading = false;
        });
      }
    } catch (e) {
      logError('强制加载更多数据失败: $e', error: e, source: 'NoteListView');
      if (mounted) {
        _updateState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 滚动到指定笔记的顶部 - 使用 ensureVisible 确保多展开笔记时定位准确
  /// 注意：目前未被使用，因为折叠时的自动滚动被禁用以改善用户体验
  /// 如果将来需要重新启用，可以取消注释相关调用代码
  double? _calculateDesiredOffset(RenderObject renderObject) {
    if (!_scrollController.hasClients) {
      return null;
    }

    final viewport = RenderAbstractViewport.of(renderObject);
    final reveal = viewport.getOffsetToReveal(renderObject, 0.0);
    final position = _scrollController.position;

    return (reveal.offset - 12.0)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  Future<void> _performPreciseItemScroll(
    String quoteId,
    int index, {
    required double desiredOffset,
    required bool forceAlignToTop,
  }) async {
    try {
      logDebug(
        '滚动到笔记: $quoteId (index: $index), target=${desiredOffset.toStringAsFixed(1)}${forceAlignToTop ? ', exact=true' : ''}',
        source: 'NoteListView',
      );

      await _scrollController.animateTo(
        desiredOffset,
        duration: QuoteItemWidget.expandCollapseDuration,
        curve: Curves.easeOutCubic,
      );

      if (!forceAlignToTop) {
        logDebug('滚动完成', source: 'NoteListView');
        return;
      }

      for (var attempt = 0; attempt < 2; attempt++) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }

        await WidgetsBinding.instance.endOfFrame;

        final key = _itemKeys[quoteId];
        final renderObject = key?.currentContext?.findRenderObject();
        if (renderObject == null) {
          return;
        }

        final correctedOffset = _calculateDesiredOffset(renderObject);
        if (correctedOffset == null ||
            (_scrollController.offset - correctedOffset).abs() <= 2.0) {
          logDebug('滚动完成（精确对齐）', source: 'NoteListView');
          return;
        }

        logDebug(
          '执行深跳滚动校准: $quoteId, attempt=${attempt + 1}, target=${correctedOffset.toStringAsFixed(1)}',
          source: 'NoteListView',
        );

        await _scrollController.animateTo(
          correctedOffset,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
        );
      }

      logDebug('滚动完成（达到最大校准次数）', source: 'NoteListView');
    } catch (e, st) {
      logDebug('滚动失败: $e\n$st', source: 'NoteListView');
    } finally {
      _isAutoScrolling = false;
    }
  }

  void _scrollToItem(
    String quoteId,
    int index, {
    bool forceAlignToTop = false,
  }) {
    if (!mounted || !_scrollController.hasClients) return;
    // 多重保护条件
    if (_isInitializing) {
      logDebug('跳过自动滚动：正在初始化', source: 'NoteListView');
      return;
    }
    if (!_autoScrollEnabled) {
      logDebug('跳过自动滚动（未启用 _autoScrollEnabled）', source: 'NoteListView');
      return;
    }
    if (_isUserScrolling) {
      logDebug('跳过自动滚动：用户正在滑动', source: 'NoteListView');
      return;
    }
    if (_lastUserScrollTime != null &&
        DateTime.now().difference(_lastUserScrollTime!) <
            const Duration(milliseconds: 900)) {
      logDebug('跳过自动滚动：用户刚刚滚动 (<900ms)', source: 'NoteListView');
      return;
    }
    if (_isAutoScrolling) {
      logDebug('跳过自动滚动：已有动画', source: 'NoteListView');
      return;
    }

    try {
      final key = _itemKeys[quoteId];
      if (key == null || key.currentContext == null) {
        logDebug('笔记Key或Context不存在，跳过滚动', source: 'NoteListView');
        return;
      }

      final targetContext = key.currentContext;
      if (targetContext == null) {
        logDebug('笔记Context为空，无法滚动', source: 'NoteListView');
        return;
      }

      final renderObject = targetContext.findRenderObject();
      if (renderObject == null) {
        logDebug('找不到RenderObject，跳过滚动', source: 'NoteListView');
        return;
      }

      final position = _scrollController.position;
      final viewportExtent = position.viewportDimension;
      final currentOffset = position.pixels;
      final targetOffset = RenderAbstractViewport.of(renderObject)
          .getOffsetToReveal(
            renderObject,
            0.0,
          )
          .offset;

      if (shouldSkipVisibleTargetAlignment(
        targetOffset: targetOffset,
        currentOffset: currentOffset,
        viewportExtent: viewportExtent,
        forceAlignToTop: forceAlignToTop,
      )) {
        logDebug('笔记顶部已在视口内，跳过自动滚动', source: 'NoteListView');
        return;
      }

      final desiredOffset = _calculateDesiredOffset(renderObject);
      if (desiredOffset == null) {
        logDebug('无法计算目标偏移量，跳过自动滚动', source: 'NoteListView');
        return;
      }

      if ((currentOffset - desiredOffset).abs() <= 4) {
        logDebug('目标偏移量变化较小，跳过自动滚动', source: 'NoteListView');
        return;
      }

      _isAutoScrolling = true;
      unawaited(
        _performPreciseItemScroll(
          quoteId,
          index,
          desiredOffset: desiredOffset,
          forceAlignToTop: forceAlignToTop,
        ),
      );
    } catch (e, st) {
      logDebug('滚动失败: $e\n$st', source: 'NoteListView');
      _isAutoScrolling = false;
    }
  }

  Future<void> _loadMore() async {
    // 防止重复加载
    if (!_hasMore || _isLoading) {
      logDebug(
        '跳过加载更多：_hasMore=$_hasMore, _isLoading=$_isLoading',
        source: 'NoteListView',
      );
      return;
    }

    // 修复：在加载前先同步一次状态，确保 _hasMore 是最新的
    final db = Provider.of<DatabaseService>(context, listen: false);
    if (!db.hasMoreQuotes) {
      logDebug('数据库显示无更多数据，同步 _hasMore 为 false', source: 'NoteListView');
      _cancelLoadMorePerfCapture('数据库显示无更多数据');
      _updateState(() {
        _hasMore = false;
      });
      return;
    }

    // 仅作为并发保护；非首屏加载时 _isLoading 不改变可见 UI，避免多一次列表重建。
    _isLoading = true;
    _loadMoreSettleTimer?.cancel();
    _loadMoreAwaitingPage = true;
    _loadMoreRequestStartCount = _quotes.length;
    _startLoadMorePerfCapture();

    try {
      logDebug('触发加载更多，当前有${_quotes.length}条数据', source: 'NoteListView');
      await db.loadMoreQuotes();
      // 成功路径由 watchQuotes 的流回调统一更新 _quotes/_hasMore/_isLoading，
      // 避免在流事件送达前把 _isLoading 提前置回 false，导致滚动惯性期间
      // 再次触发 loadMore，一次追加两页数据。
    } catch (e) {
      _cancelLoadMorePerfCapture('加载失败: $e');
      _resetLoadMoreGate();
      // 修复：出错时也要重置加载状态
      if (mounted) {
        _updateState(() {
          _isLoading = false;
        });
      }
      logError('加载更多数据失败: $e', error: e, source: 'NoteListView');
      rethrow;
    }
  }
}
