part of '../ai_periodic_report_page.dart';

extension _AIReportCardActions on _AIPeriodicReportPageState {
  /// 显示卡片详情
  void _showCardDetail(GeneratedCard card) {
    // 添加触觉反馈
    HapticFeedback.lightImpact();

    // 设置选中状态
    final cardIndex = _featuredCards.indexOf(card);
    _updateState(() {
      _selectedCardIndex = cardIndex;
    });

    Quote? quoteForCard;
    for (final quote in _periodQuotes) {
      if (quote.id == card.noteId) {
        quoteForCard = quote;
        break;
      }
    }

    Future<GeneratedCard> Function()? regenerateCallback;
    if (_aiCardService != null && quoteForCard != null) {
      regenerateCallback = () async {
        final newCard = await _aiCardService!.generateCard(
          note: quoteForCard!,
          isRegeneration: true,
          brandName: AppLocalizations.of(context).appTitle,
        );
        if (mounted) {
          _updateState(() {
            final index = _featuredCards.indexWhere(
              (existing) => existing.id == card.id,
            );
            if (index != -1) {
              _featuredCards[index] = newCard;
            }
          });
        }
        return newCard;
      };
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => CardPreviewDialog(
        card: card,
        onShare: (selected) => _shareCard(selected),
        onSave: (selected) => _saveCard(selected),
        onRegenerate: regenerateCallback,
      ),
    ).then((_) {
      // 对话框关闭后清除选中状态
      _updateState(() {
        _selectedCardIndex = null;
      });
    });
  }

  /// 分享卡片
  Future<void> _shareCard(GeneratedCard card) async {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).pop(); // 关闭对话框

    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(l10n.generatingShareImage),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 生成高质量图片
      final imageBytes = await card.toImageBytes(
        width: 800,
        height: 1200,
        context: context,
        scaleFactor: 2.0,
        renderMode: ExportRenderMode.contain,
      );

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'ThoughtEcho_Report_Card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // 分享文件
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${l10n.cardFromReport}\n\n"${card.originalContent.length > 50 ? '${card.originalContent.substring(0, 50)}...' : card.originalContent}"',
          files: [XFile(file.path)],
        ),
      );

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(l10n.cardSharedSuccessfully),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.shareFailed(e.toString()))),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 保存卡片
  Future<void> _saveCard(GeneratedCard card) async {
    final l10n = AppLocalizations.of(context);
    // 关键修复：在关闭对话框之前，先获取外层scaffold的context
    final scaffoldContext = context;

    Navigator.of(context).pop(); // 关闭对话框

    if (_aiCardService == null) return;

    try {
      // 显示加载指示器
      if (mounted) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(l10n.savingCardToGallery),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 保存高质量图片，使用外层scaffold的context
      final filePath = await _aiCardService!.saveCardAsImage(
        card,
        width: 800,
        height: 1200,
        customName:
            'ThoughtEcho_Report_Card_${DateTime.now().millisecondsSinceEpoch}',
        context: scaffoldContext,
      );

      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(scaffoldContext).hideCurrentSnackBar();
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.cardSavedToGallery(filePath))),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(scaffoldContext).hideCurrentSnackBar();
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.saveFailed(e.toString()))),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
