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
    var expanded = 0;
    var keepAlive = 0;
    final quoteItemStats = QuoteItemWidget.getCacheStats();
    final expandable = quoteItemStats['expandableCount'] ?? 0;

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
      if (NoteListView.shouldKeepAliveQuoteItem(quote)) {
        keepAlive++;
      }
    }

    return 'total=$total, rich=$rich, media=$media, expandable=$expandable, '
        'expanded=$expanded, keepAlive=$keepAlive, '
        'tracked=${_expandedItems.length}';
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
    _scrollSessionPerfFinalizeScheduled = false;
    final previousSessionId = _scrollSessionId;
    if (previousSessionId != null) {
      JankDetector.endSession(previousSessionId);
    }
    _scrollSessionId = 'scroll-${++_scrollSessionSequence}';
    JankDetector.beginSession(_scrollSessionId!);
    _scrollSessionPerfStopTimer?.cancel();
    _scrollSessionStartMicros = DateTime.now().microsecondsSinceEpoch;
    _scrollSessionStartOffset = metrics.pixels;
    _scrollSessionLastOffset = metrics.pixels;
    _scrollSessionMinOffset = metrics.pixels;
    _scrollSessionMaxOffset = metrics.pixels;
    _scrollSessionStartMaxExtent = metrics.maxScrollExtent;
    _scrollSessionLastMaxExtent = metrics.maxScrollExtent;
    _scrollSessionMinMaxExtent = metrics.maxScrollExtent;
    _scrollSessionMaxMaxExtent = metrics.maxScrollExtent;
    _scrollSessionExtentChangeCount = 0;
    _scrollSessionStartStateUpdateCount = _stateUpdateCount;
    _scrollSessionStartNoteListBuildCount = _noteListBuildCount;
    _scrollSessionStartLoadMoreAttemptCount = _loadMoreAttemptCount;
    _scrollSessionStartLoadMoreStartCount = _loadMoreStartCount;
    _scrollSessionStartLoadMoreSkipCount = _loadMoreSkipCount;
    _scrollSessionStartDataEventCount = _dataStreamEventCount;
    _scrollSessionNotificationStarts = 1;
    _scrollSessionNotificationUpdates = 0;
    _scrollSessionNotificationEnds = 0;
    _scrollSessionItemBuildCount = 0;
    _scrollSessionMinBuiltIndex = 1 << 30;
    _scrollSessionMaxBuiltIndex = -1;
    _scrollSessionBuiltPlain = 0;
    _scrollSessionBuiltRich = 0;
    _scrollSessionBuiltMedia = 0;
    _scrollSessionUpdateMicros.clear();
    _scrollSessionFrameTimings.clear();
    _scrollSessionItemLayoutCount = 0;
    _scrollSessionItemLayoutMicros = 0;
    _scrollSessionItemLayoutJank = 0;
    _scrollSessionWorstItemLayoutMicros = 0;
    _scrollSessionSlowItemLayouts.clear();
    _scrollSessionStartQuoteContentStats = QuoteContent.debugCacheStats();
    _scrollSessionStartQuoteItemStats = QuoteItemWidget.getCacheStats();
    _scrollSessionStartImageEmbedStats = QuillImageEmbedPerfStats.snapshot();
    final imageCache = PaintingBinding.instance.imageCache;
    _scrollSessionStartImageCount = imageCache.currentSize;
    _scrollSessionStartImageBytes = imageCache.currentSizeBytes;
    _scrollSessionTracer?.finish();
    _scrollSessionTracer = AppTracer.start(
        'ThoughtEcho.NoteListView.scrollSession',
        operation: 'ui.scroll');
    _ensurePerfTimingsCallback();
  }

  void _recordScrollSessionUpdate(ScrollMetrics metrics) {
    if (!_scrollSessionPerfRecording) {
      return;
    }

    _scrollSessionUpdateMicros.add(DateTime.now().microsecondsSinceEpoch);
    _scrollSessionNotificationUpdates++;
    _scrollSessionLastOffset = metrics.pixels;
    if (metrics.pixels < _scrollSessionMinOffset) {
      _scrollSessionMinOffset = metrics.pixels;
    }
    if (metrics.pixels > _scrollSessionMaxOffset) {
      _scrollSessionMaxOffset = metrics.pixels;
    }
    final maxExtent = metrics.maxScrollExtent;
    if ((maxExtent - _scrollSessionLastMaxExtent).abs() >= 1) {
      _scrollSessionExtentChangeCount++;
    }
    _scrollSessionLastMaxExtent = maxExtent;
    if (maxExtent < _scrollSessionMinMaxExtent) {
      _scrollSessionMinMaxExtent = maxExtent;
    }
    if (maxExtent > _scrollSessionMaxMaxExtent) {
      _scrollSessionMaxMaxExtent = maxExtent;
    }
  }

  void _scheduleScrollSessionPerfFinalize(ScrollMetrics metrics) {
    if (!_scrollSessionPerfRecording || _scrollSessionPerfPendingFinalize) {
      return;
    }

    _scrollSessionPerfPendingFinalize = true;
    _scrollSessionNotificationEnds++;
    _scrollSessionLastOffset = metrics.pixels;
    _scrollSessionPerfStopTimer?.cancel();
    // FrameTiming callbacks may be delivered in batches well after a short
    // scroll ends. Prefer the next delivered batch, with a bounded fallback.
    _scrollSessionPerfStopTimer = Timer(
      const Duration(milliseconds: 1200),
      _finalizeScrollSessionPerfCapture,
    );
  }

  void _finalizeScrollSessionPerfCapture() {
    if (!_scrollSessionPerfRecording) {
      return;
    }

    _scrollSessionPerfStopTimer?.cancel();
    _scrollSessionPerfRecording = false;
    _scrollSessionPerfPendingFinalize = false;
    _scrollSessionPerfFinalizeScheduled = false;

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
    final imageEmbedStats = QuillImageEmbedPerfStats.compact(
      baseline: _scrollSessionStartImageEmbedStats,
    );
    final itemLayoutAvgMs = _scrollSessionItemLayoutCount == 0
        ? 0.0
        : (_scrollSessionItemLayoutMicros / _scrollSessionItemLayoutCount) /
            1000.0;
    final itemLayoutStats =
        'count=$_scrollSessionItemLayoutCount,jank=$_scrollSessionItemLayoutJank,'
        'avg=${itemLayoutAvgMs.toStringAsFixed(1)}ms,'
        'worst=${(_scrollSessionWorstItemLayoutMicros / 1000.0).toStringAsFixed(1)}ms';
    final builtRange = _scrollSessionItemBuildCount == 0
        ? 'none'
        : '$_scrollSessionMinBuiltIndex-$_scrollSessionMaxBuiltIndex';
    final activityStats =
        'stateΔ=${_stateUpdateCount - _scrollSessionStartStateUpdateCount},'
        'buildΔ=${_noteListBuildCount - _scrollSessionStartNoteListBuildCount},'
        'dataΔ=${_dataStreamEventCount - _scrollSessionStartDataEventCount},'
        'loadMoreAttemptΔ=${_loadMoreAttemptCount - _scrollSessionStartLoadMoreAttemptCount},'
        'loadMoreStartΔ=${_loadMoreStartCount - _scrollSessionStartLoadMoreStartCount},'
        'loadMoreSkipΔ=${_loadMoreSkipCount - _scrollSessionStartLoadMoreSkipCount},'
        'notif=$_scrollSessionNotificationStarts/$_scrollSessionNotificationUpdates/$_scrollSessionNotificationEnds,'
        'built=$_scrollSessionItemBuildCount@$builtRange,'
        'builtKind=p$_scrollSessionBuiltPlain/r$_scrollSessionBuiltRich/m$_scrollSessionBuiltMedia';
    final slowLayouts = _scrollSessionSlowItemLayouts
        .map((sample) => sample.toCompactText())
        .join('|');

    logDebug(
      '滚动性能摘要(复制此行): session=$_scrollSessionId, dir=$direction, '
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
      'quoteItem={$quoteItemStats}, imageCache={$imageStats}, '
      'imageEmbed={$imageEmbedStats}, '
      'extent={start=${_scrollSessionStartMaxExtent.round()},'
      'end=${_scrollSessionLastMaxExtent.round()},'
      'range=${_scrollSessionMinMaxExtent.round()}-${_scrollSessionMaxMaxExtent.round()},'
      'changes=$_scrollSessionExtentChangeCount}, '
      'activity={$activityStats}, '
      'itemLayout={$itemLayoutStats}, slowLayouts=[$slowLayouts]',
      source: 'NoteListView.Perf',
    );
    _scrollSessionStartQuoteContentStats = null;
    _scrollSessionStartQuoteItemStats = null;
    _scrollSessionStartImageEmbedStats = null;
    _scrollSessionTracer?.instant(
        'ThoughtEcho.NoteListView.scrollSession.finalize',
        arguments: {
          'frames': frameSamples,
          'frameJank': jankyFrames,
          'worstFrameMs': worstFrameMs.toStringAsFixed(1),
          'avgFrameMs': avgFrameMs.toStringAsFixed(1),
        });
    _scrollSessionTracer?.finish();
    _scrollSessionTracer = null;
    final sessionId = _scrollSessionId;
    if (sessionId != null) {
      JankDetector.endSession(sessionId);
    }
    _scrollSessionId = null;
    _releasePerfTimingsCallbackIfIdle();
  }

  void _recordNoteListItemLayout({
    required int index,
    required String quoteId,
    required String kind,
    required int durationMicros,
    required double height,
    required double? oldHeight,
  }) {
    if (!_scrollSessionPerfRecording) {
      return;
    }

    _scrollSessionItemLayoutCount++;
    _scrollSessionItemLayoutMicros += durationMicros;
    if (durationMicros > _scrollSessionWorstItemLayoutMicros) {
      _scrollSessionWorstItemLayoutMicros = durationMicros;
    }
    if (durationMicros > 8000) {
      _scrollSessionItemLayoutJank++;
    }

    const maxSamples = 8;
    if (durationMicros < 3000 &&
        _scrollSessionSlowItemLayouts.length >= maxSamples) {
      return;
    }

    final sample = _SlowItemLayoutSample(
      index: index,
      quoteId: quoteId,
      kind: kind,
      durationMicros: durationMicros,
      height: height,
      oldHeight: oldHeight,
    );
    _scrollSessionSlowItemLayouts.add(sample);
    _scrollSessionSlowItemLayouts.sort(
      (a, b) => b.durationMicros.compareTo(a.durationMicros),
    );
    if (_scrollSessionSlowItemLayouts.length > maxSamples) {
      _scrollSessionSlowItemLayouts.removeLast();
    }
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
    _firstOpenTracer = AppTracer.start(
        'ThoughtEcho.NoteListView.firstOpenScroll',
        operation: 'ui.scroll.first');
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
      _firstOpenTracer?.instant(
          'ThoughtEcho.NoteListView.firstOpenScroll.finalize',
          arguments: {
            'frames': totalFrames,
            'frameJank': jankyFrames,
            'worstFrameMs': worstFrameMs.toStringAsFixed(1),
            'avgFrameMs': avgFrameMs.toStringAsFixed(1),
          });
    } else {
      if (_firstOpenScrollUpdateMicros.length < 2) {
        logDebug(
          '首次滑动性能结果(滚动事件): 样本不足，updates=${_firstOpenScrollUpdateMicros.length}',
          source: 'NoteListView.Perf',
        );
        _firstOpenTracer?.finish();
        _firstOpenTracer = null;
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
      _firstOpenTracer?.instant(
          'ThoughtEcho.NoteListView.firstOpenScroll.finalize',
          arguments: {
            'samples': sampleCount,
            'jankIntervals': jankyIntervals,
            'avgIntervalMs': avgIntervalMs.toStringAsFixed(1),
            'worstIntervalMs': worstIntervalMs.toStringAsFixed(1),
          });
    }

    _firstOpenTracer?.finish();
    _firstOpenTracer = null;

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
    _loadMoreTracer = AppTracer.start('ThoughtEcho.NoteListView.loadMore',
        operation: 'ui.load');
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
    _loadMoreTracer?.finish();
    _loadMoreTracer = null;
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

  RenderObject? _positioningRenderObject() {
    return _positioningItemKey?.currentContext?.findRenderObject();
  }

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

  Future<bool> _alignPositioningTarget({
    required String quoteId,
    required int index,
    required bool forceAlignToTop,
  }) async {
    final renderObject = _positioningRenderObject();
    if (renderObject == null) {
      return false;
    }

    final position = _scrollController.position;
    final targetOffset = RenderAbstractViewport.of(renderObject)
        .getOffsetToReveal(
          renderObject,
          0.0,
        )
        .offset;

    if (shouldSkipVisibleTargetAlignment(
      targetOffset: targetOffset,
      currentOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      forceAlignToTop: forceAlignToTop,
    )) {
      return true;
    }

    final initialDesiredOffset = _calculateDesiredOffset(renderObject);
    if (initialDesiredOffset == null) {
      return false;
    }
    var desiredOffset = initialDesiredOffset;

    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!mounted || !_scrollController.hasClients) {
          return false;
        }

        if ((_scrollController.offset - desiredOffset).abs() > 2.0) {
          await _scrollController.animateTo(
            desiredOffset,
            duration: attempt == 0
                ? QuoteItemWidget.expandCollapseDuration
                : const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
          );
        }

        await WidgetsBinding.instance.endOfFrame;
        final correctedRenderObject = _positioningRenderObject();
        if (correctedRenderObject == null) {
          return false;
        }
        final correctedOffset = _calculateDesiredOffset(correctedRenderObject);
        if (correctedOffset == null) {
          return false;
        }
        if ((_scrollController.offset - correctedOffset).abs() <= 2.0) {
          logDebug(
            '滚动完成（精确对齐）: $quoteId (index: $index)',
            source: 'NoteListView',
          );
          return true;
        }
        desiredOffset = correctedOffset;
      }
    } catch (e, st) {
      logDebug('滚动失败: $e\n$st', source: 'NoteListView');
    }

    return false;
  }

  Future<bool> _positionAndAlignQuote(
    String quoteId,
    int index, {
    required bool forceAlignToTop,
  }) async {
    if (!mounted || !_scrollController.hasClients) {
      return false;
    }

    final request = ++_positioningRequest;
    var positioned = false;
    _positioningQuoteId = quoteId;
    _positioningItemKey = GlobalKey(debugLabel: 'positioning-$quoteId');
    _isAutoScrolling = true;
    _updateState(() {});
    await WidgetsBinding.instance.endOfFrame;

    try {
      if (await _alignPositioningTarget(
        quoteId: quoteId,
        index: index,
        forceAlignToTop: forceAlignToTop,
      )) {
        positioned = true;
        return true;
      }

      final position = _scrollController.position;
      final itemFraction =
          _quotes.length <= 1 ? 0.0 : index / (_quotes.length - 1);
      final estimatedOffset = position.maxScrollExtent * itemFraction;
      position.jumpTo(estimatedOffset);
      await WidgetsBinding.instance.endOfFrame;
      if (await _alignPositioningTarget(
        quoteId: quoteId,
        index: index,
        forceAlignToTop: forceAlignToTop,
      )) {
        positioned = true;
        return true;
      }

      // Variable-height lazy lists cannot reveal a distant child by context
      // until it has been built. Scan by viewport-sized jumps only as a
      // fallback; the proportional jump above handles the common case.
      var candidateOffset = 0.0;
      var attempts = 0;
      while (mounted && _scrollController.hasClients && attempts < 600) {
        final currentPosition = _scrollController.position;
        final maxOffset = currentPosition.maxScrollExtent;
        if (candidateOffset > maxOffset + 1.0) {
          break;
        }

        currentPosition.jumpTo(candidateOffset.clamp(0.0, maxOffset));
        await WidgetsBinding.instance.endOfFrame;
        if (await _alignPositioningTarget(
          quoteId: quoteId,
          index: index,
          forceAlignToTop: forceAlignToTop,
        )) {
          positioned = true;
          return true;
        }

        final step = (_scrollController.position.viewportDimension * 0.8).clamp(
          240.0,
          800.0,
        );
        candidateOffset += step;
        attempts++;
      }

      logDebug(
        '未能构建并定位目标笔记: $quoteId (index: $index)',
        source: 'NoteListView',
      );
      return false;
    } finally {
      if (_positioningRequest == request) {
        _isAutoScrolling = false;
        if (!positioned && mounted) {
          _updateState(() {
            _positioningQuoteId = null;
            _positioningItemKey = null;
          });
          await WidgetsBinding.instance.endOfFrame;
        }
      }
    }
  }

  Future<void> _loadMore() async {
    _loadMoreAttemptCount++;
    // 防止重复加载
    if (!_hasMore || _isLoading) {
      _loadMoreSkipCount++;
      logDebug(
        '跳过加载更多：_hasMore=$_hasMore, _isLoading=$_isLoading',
        source: 'NoteListView',
      );
      return;
    }

    // 修复：在加载前先同步一次状态，确保 _hasMore 是最新的
    final db = Provider.of<DatabaseService>(context, listen: false);
    if (!db.hasMoreQuotes) {
      _loadMoreSkipCount++;
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
    _loadMoreStartCount++;
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
