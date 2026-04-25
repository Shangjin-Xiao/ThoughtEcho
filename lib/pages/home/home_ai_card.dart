part of '../home_page.dart';

/// Extension for AI card generation features
extension _HomeAICard on _HomePageState {
  /// 生成AI卡片
  void _generateAICard(Quote quote) async {
    if (_aiCardService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).aiCardServiceNotInitialized,
          ),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CardGenerationLoadingDialog(),
    );

    try {
      // 生成卡片
      final card = await _aiCardService!.generateCard(
        note: quote,
        brandName: AppLocalizations.of(context).appTitle,
      );

      // 关闭加载对话框
      if (mounted) Navigator.of(context).pop();

      // 显示卡片预览对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => CardPreviewDialog(
            card: card,
            onShare: (selected) => _shareCard(selected),
            onSave: (selected) => _saveCard(selected),
            onRegenerate: () => _aiCardService!.generateCard(
              note: quote,
              isRegeneration: true,
              brandName: AppLocalizations.of(context).appTitle,
            ),
          ),
        );
      }
    } catch (e) {
      // 关闭加载对话框
      if (mounted) Navigator.of(context).pop();

      // 显示错误信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).generateCardFailed(e.toString()),
            ),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 分享卡片
  Future<void> _shareCard(GeneratedCard card) async {
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
                Text(AppLocalizations.of(context).generatingShareImage),
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
      final fileName = '心迹_Card_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);

      // 分享文件
      await SharePlus.instance.share(
        ShareParams(
          text:
              '来自心迹的精美卡片\n\n"${card.originalContent.length > 50 ? '${card.originalContent.substring(0, 50)}...' : card.originalContent}"',
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
                Text(AppLocalizations.of(context).cardSharedSuccessfully),
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
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).shareFailed(e.toString()),
                  ),
                ),
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
                Text(AppLocalizations.of(context).savingCardToGallery),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // 保存高质量图片
      final filePath = await _aiCardService!.saveCardAsImage(
        card,
        width: 800,
        height: 1200,
        scaleFactor: 2.0,
        renderMode: ExportRenderMode.contain,
        context: context,
        fileNamePrefix: AppLocalizations.of(context).cardFileNamePrefix,
      );

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
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
            action: SnackBarAction(
              label: l10n.view,
              textColor: Colors.white,
              onPressed: () {
                // 这里可以添加打开相册的逻辑
              },
            ),
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
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).saveFailed(e.toString()),
                  ),
                ),
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
