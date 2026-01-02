import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../services/local_ai/local_ai_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import 'ocr_capture_page.dart';
import 'ocr_result_sheet.dart';
import 'voice_input_overlay.dart';
import 'voice_result_sheet.dart';

/// Home 页 FAB 的本地 AI 增强交互（语音转文字 / 上滑 OCR）。
///
/// - 短按：交由外部处理（通常是“新增笔记”）
/// - 长按：开始录音；松手：停止并转写；上滑：进入 OCR 拍照识别
///
/// 设计目标：把 HomePage 的本地 AI 交互逻辑拆出去，避免 UI 页面变成“巨石文件”。
class LocalAIFab extends StatefulWidget {
  final VoidCallback onTap;
  final void Function(String text) onInsertText;
  final String heroTag;

  const LocalAIFab({
    super.key,
    required this.onTap,
    required this.onInsertText,
    required this.heroTag,
  });

  @override
  State<LocalAIFab> createState() => _LocalAIFabState();
}

class _LocalAIFabState extends State<LocalAIFab> {
  bool _voiceOverlayOpen = false;
  bool _isVoiceRecording = false;
  bool _voiceFlowBusy = false;

  Future<void> _onLongPressStart() async {
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    final localAISettings = settingsService.localAISettings;
    final l10n = AppLocalizations.of(context);

    // 未启用则不响应长按，避免误触打断“新增”操作。
    if (!localAISettings.enabled || !localAISettings.speechToTextEnabled) {
      return;
    }

    // 懒初始化：仅在用户触发时初始化。
    try {
      await LocalAIService.instance.initialize(localAISettings);
    } catch (_) {
      // 初始化失败时不直接崩溃，交由后续 startRecording 抛错/提示
    }

    // 若模型未就绪，给出明确提示（不再“无反应”）
    if (!LocalAIService.instance
        .isFeatureAvailable(LocalAIFeature.speechToText)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSwitchToAsrModel),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _startVoiceRecordingAndShowOverlay();
  }

  Future<void> _onLongPressEnd() async {
    await _stopVoiceRecordingAndShowResult();
  }

  Future<void> _startVoiceRecordingAndShowOverlay() async {
    if (_voiceFlowBusy) return;
    _voiceFlowBusy = true;

    final localAI = LocalAIService.instance;
    final l10n = AppLocalizations.of(context);

    try {
      await localAI.startRecording();
      _isVoiceRecording = true;

      if (!mounted) return;
      await _showVoiceInputOverlay();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.featureNotAvailable),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _cancelVoiceRecording();
    } finally {
      _voiceFlowBusy = false;
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isVoiceRecording) return;
    _isVoiceRecording = false;
    try {
      await LocalAIService.instance.speechService.cancelRecording();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _stopVoiceRecordingAndShowResult() async {
    if (_voiceFlowBusy) return;
    if (!_isVoiceRecording) return;

    _voiceFlowBusy = true;

    final localAI = LocalAIService.instance;
    final l10n = AppLocalizations.of(context);

    try {
      // 先关闭浮层（如果还开着）
      if (_voiceOverlayOpen && mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }

      final result = await localAI.stopAndTranscribe();
      _isVoiceRecording = false;

      if (!mounted) return;

      String resultText = result.text;
      if (resultText.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.featureNotAvailable),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) {
          return VoiceResultSheet(
            recognizedText: resultText,
            onTextChanged: (text) {
              resultText = text;
            },
            onInsertToEditor: () {
              Navigator.of(context).pop();
              widget.onInsertText(resultText);
            },
            onRecognizeSource: () {},
          );
        },
      );
    } catch (_) {
      _isVoiceRecording = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.featureNotAvailable),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _cancelVoiceRecording();
    } finally {
      _voiceFlowBusy = false;
    }
  }

  Future<void> _showVoiceInputOverlay() async {
    if (!mounted) return;

    _voiceOverlayOpen = true;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'voice_input_overlay',
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        return VoiceInputOverlay(
          transcribedText: null,
          onSwipeUpForOCR: () async {
            Navigator.of(context).pop();
            await _cancelVoiceRecording();
            await _openOCRFlow();
          },
          onRecordComplete: () {
            Navigator.of(context).pop();
            // 由 onLongPressEnd 负责真正的 stop/transcribe，这里只关闭浮层
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 180),
    );

    _voiceOverlayOpen = false;
    // 如果用户点背景关闭了浮层，但录音还在，立即取消，避免后台继续录音
    await _cancelVoiceRecording();
  }

  Future<void> _openOCRFlow() async {
    if (!mounted) return;

    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    final localAISettings = settingsService.localAISettings;
    final l10n = AppLocalizations.of(context);

    try {
      await LocalAIService.instance.initialize(localAISettings);
    } catch (_) {
      // ignore
    }

    if (!mounted) return;

    if (!localAISettings.enabled || !localAISettings.ocrEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.featureNotAvailable),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!LocalAIService.instance.isFeatureAvailable(LocalAIFeature.ocr)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSwitchToOcrModel),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final navigator = Navigator.of(context);
    final String? imagePath = await navigator.push<String?>(
      MaterialPageRoute<String?>(
        builder: (context) => const OCRCapturePage(),
      ),
    );

    if (!mounted) return;
    if (imagePath == null || imagePath.trim().isEmpty) return;

    String resultText;
    try {
      final result = await LocalAIService.instance.recognizeText(imagePath);
      resultText = result.fullText;
    } catch (_) {
      resultText = '';
    }

    if (!mounted) return;

    if (resultText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.featureNotAvailable),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return OCRResultSheet(
          recognizedText: resultText,
          onTextChanged: (text) {
            resultText = text;
          },
          onInsertToEditor: () {
            Navigator.of(context).pop();
            widget.onInsertText(resultText);
          },
          onRecognizeSource: () {},
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onLongPressStart: (_) => _onLongPressStart(),
      onLongPressEnd: (_) => _onLongPressEnd(),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.accentShadow,
        ),
        child: FloatingActionButton(
          heroTag: widget.heroTag,
          onPressed: widget.onTap,
          elevation: 0,
          backgroundColor: theme.floatingActionButtonTheme.backgroundColor,
          foregroundColor: theme.floatingActionButtonTheme.foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
    );
  }
}
