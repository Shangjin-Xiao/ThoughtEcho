part of '../ai_periodic_report_page.dart';

extension _AIReportFeaturedCards on _AIPeriodicReportPageState {
  /// 是否还有更多卡片可加载
  bool get _hasMoreCards => _pendingQuotesForCards.isNotEmpty;

  /// 生成精选卡片（首次加载）
  Future<void> _generateFeaturedCards() async {
    if (_aiCardService == null || _periodQuotes.isEmpty || _isGeneratingCards) {
      return;
    }

    _updateState(() {
      _isGeneratingCards = true;
      _featuredCards = []; // 清空现有卡片
    });

    try {
      // 选择所有有代表性的笔记（不限制数量），按多样性排序
      final allSelectedQuotes = _selectRepresentativeQuotes(
        _periodQuotes,
        maxCount: _periodQuotes.length, // 选择所有符合条件的笔记
      );

      // 首批生成 _cardsPerBatch 张
      final firstBatch = allSelectedQuotes
          .take(_AIPeriodicReportPageState._cardsPerBatch)
          .toList();
      _pendingQuotesForCards = allSelectedQuotes
          .skip(_AIPeriodicReportPageState._cardsPerBatch)
          .toList();

      final cards = await _aiCardService!.generateFeaturedCards(
        notes: firstBatch,
        brandName: AppLocalizations.of(context).appTitle,
        maxCards: _AIPeriodicReportPageState._cardsPerBatch,
      );

      _updateState(() {
        _featuredCards = cards;
        _isGeneratingCards = false;
      });
    } catch (e) {
      _updateState(() {
        _isGeneratingCards = false;
      });
      AppLogger.e('Failed to generate featured cards', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.generateCardFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 加载更多卡片
  Future<void> _loadMoreCards() async {
    if (_aiCardService == null ||
        _pendingQuotesForCards.isEmpty ||
        _isLoadingMoreCards ||
        _isGeneratingCards) {
      return;
    }

    _updateState(() {
      _isLoadingMoreCards = true;
    });

    try {
      // 取下一批笔记
      final nextBatch = _pendingQuotesForCards
          .take(_AIPeriodicReportPageState._cardsPerBatch)
          .toList();
      _pendingQuotesForCards = _pendingQuotesForCards
          .skip(_AIPeriodicReportPageState._cardsPerBatch)
          .toList();

      final newCards = await _aiCardService!.generateFeaturedCards(
        notes: nextBatch,
        brandName: AppLocalizations.of(context).appTitle,
        maxCards: _AIPeriodicReportPageState._cardsPerBatch,
      );

      _updateState(() {
        _featuredCards.addAll(newCards);
        _isLoadingMoreCards = false;
      });
    } catch (e) {
      _updateState(() {
        _isLoadingMoreCards = false;
      });
      AppLogger.e('Failed to load more cards', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.generateCardFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 构建精选卡片
  Widget _buildFeaturedCards() {
    final l10n = AppLocalizations.of(context);
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_periodQuotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey('cards_empty1_$_dataKey'),
              duration: _shouldAnimateCards
                  ? const Duration(milliseconds: 800)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateCards ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: Icon(
                      Icons.note_alt_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              key: ValueKey('cards_empty2_$_dataKey'),
              duration: _shouldAnimateCards
                  ? const Duration(milliseconds: 600)
                  : Duration.zero,
              tween: Tween(begin: _shouldAnimateCards ? 0.0 : 1.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: Text(
                      l10n.noNotesInPeriodForPeriod(_getPeriodName(l10n)),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.featuredCards,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_featuredCards.isNotEmpty)
                      Row(
                        children: [
                          Text(
                            l10n.totalCards(_featuredCards.length),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          if (_selectedCardIndex != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                l10n.cardSelected(_selectedCardIndex! + 1),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              if (_isGeneratingCards)
                Container(
                  padding: const EdgeInsets.all(8),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_featuredCards.isEmpty)
                FilledButton.icon(
                  onPressed: _generateFeaturedCards,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(l10n.generateCards),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                )
              else if (_featuredCards.isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    _updateState(() {
                      _featuredCards = [];
                      _pendingQuotesForCards = [];
                    });
                    _generateFeaturedCards();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.regenerate),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _featuredCards.isEmpty
              ? _buildFeaturedCardsEmptyState()
              : _buildFeaturedCardsGrid(),
        ),
      ],
    );
  }

  /// 构建精选卡片空状态
  Widget _buildFeaturedCardsEmptyState() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _aiCardService?.isEnabled == true
                      ? Icons.auto_awesome_outlined
                      : Icons.settings_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _featuredCards.isEmpty
                    ? l10n.noFeaturedCards
                    : l10n.featuredCards,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.featuredCardGenerationTip,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 显示生成卡片按钮（无论AI开关，都会在服务内降级到模板）
              FilledButton.icon(
                onPressed: _periodQuotes.isNotEmpty
                    ? _generateFeaturedCards
                    : null,
                icon: const Icon(Icons.auto_awesome),
                label: Text(l10n.generateCards),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建精选卡片网格
  Widget _buildFeaturedCardsGrid() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // 计算总项数：卡片数 + 可能的"加载更多"按钮
    final hasLoadMore = _hasMoreCards && !_isLoadingMoreCards;
    final isLoadingMore = _isLoadingMoreCards;
    final extraItemCount = (hasLoadMore || isLoadingMore) ? 1 : 0;
    final totalItemCount = _featuredCards.length + extraItemCount;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: totalItemCount,
      itemBuilder: (context, index) {
        // 最后一项显示"加载更多"或加载指示器
        if (index >= _featuredCards.length) {
          if (_isLoadingMoreCards) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.generatingCards,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // "加载更多"按钮
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _loadMoreCards,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.loadMoreCards,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.remainingCards(_pendingQuotesForCards.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final card = _featuredCards[index];
        final isSelected = _selectedCardIndex == index;

        return AnimatedContainer(
          duration: Duration(milliseconds: 200 + (index * 50)),
          curve: Curves.easeOutCubic,
          child: Hero(
            tag: 'card_${card.id}_$index',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showCardDetail(card),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.1),
                        blurRadius: isSelected ? 12 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: GeneratedCardWidget(card: card, showActions: false),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
