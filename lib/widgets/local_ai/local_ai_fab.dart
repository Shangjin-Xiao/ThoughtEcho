import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../services/local_ai/local_ai_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import 'ocr_capture_page.dart';
import 'ocr_result_sheet.dart';
import 'voice_input_overlay.dart';

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
  bool _stopRequestedByOverlay = false;
  bool _stopRequestedBeforeRecordingStarted = false;

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
      await LocalAIService.instance.initialize(
        localAISettings,
        eagerLoadModels: false,
      );
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

    _stopRequestedBeforeRecordingStarted = false;
    await _startVoiceRecordingAndShowOverlay();
  }

  Future<void> _onLongPressEnd() async {
    // 手机端如果“开始录音”在准备模型/申请权限阶段耗时较久，
    // 用户可能已经松手，此时 onLongPressEnd 会早于 startRecording 完成。
    // 记录一次“松手请求”，等录音真正开始后自动 stop+transcribe，避免录音卡住或被当作取消。
    if (_voiceFlowBusy && !_isVoiceRecording) {
      _stopRequestedBeforeRecordingStarted = true;
      return;
    }

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

      // 如果用户在录音真正开始前就已松手：直接走 stop+transcribe，不再强制展示浮层。
      if (_stopRequestedBeforeRecordingStarted) {
        _stopRequestedBeforeRecordingStarted = false;
        await _stopVoiceRecordingAndShowResultWhileBusy();
        return;
      }

      if (!mounted) return;
      await _showVoiceInputOverlay();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizeLocalAIError(l10n, e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _cancelVoiceRecording();
    } finally {
      _voiceFlowBusy = false;
    }
  }

  /// 在 `_voiceFlowBusy == true` 的前提下执行 stop+transcribe 并展示结果。
  ///
  /// 用于处理“startRecording 尚在进行，但用户已松手”的场景，避免被 `_stopVoiceRecordingAndShowResult` 的忙碌保护直接 return。
  Future<void> _stopVoiceRecordingAndShowResultWhileBusy() async {
    if (!_isVoiceRecording) return;

    final localAI = LocalAIService.instance;
    final l10n = AppLocalizations.of(context);

    try {
      // 若浮层已打开，先关掉
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

      // 目标交互：像键盘/微信一样，松手就把识别结果直接插入。
      widget.onInsertText(resultText);
    } catch (e) {
      _isVoiceRecording = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizeLocalAIError(l10n, e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _cancelVoiceRecording();
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

      // 目标交互：松手即停止录音并直接插入文字。
      widget.onInsertText(resultText);
    } catch (e) {
      _isVoiceRecording = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizeLocalAIError(l10n, e)),
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
    _stopRequestedByOverlay = false;
    await showGeneralDialog<void>(
      context: context,
      // 桌面端（鼠标/触控板）在长按结束抬起时，可能被系统识别为“点击 barrier”，
      // 从而立刻关闭浮层并触发 cancelRecording。
      // 移动端允许点空白区域取消；桌面端禁用以避免误触。
      barrierDismissible: defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS,
      barrierLabel: 'voice_input_overlay',
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) {
        final speech = LocalAIService.instance.speechService;
        return AnimatedBuilder(
          animation: speech,
          builder: (context, _) {
            return VoiceInputOverlay(
              transcribedText: speech.currentTranscription,
              onSwipeUpForOCR: () async {
                Navigator.of(context).pop();
                await _cancelVoiceRecording();
                await _openOCRFlow();
              },
              onRecordComplete: () {
                // 用户在浮层里完成录音（松手/结束手势）时，可能不会触发 FAB 的 onLongPressEnd。
                // 因此这里标记一次“需要停止并转写”，在浮层关闭后由 _showVoiceInputOverlay 统一触发。
                _stopRequestedByOverlay = true;
                Navigator.of(context).pop();
              },
            );
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

    // 若浮层内触发了“录音完成”，这里主动走 stop+transcribe，避免被当作取消。
    if (_stopRequestedByOverlay && _isVoiceRecording) {
      _stopRequestedByOverlay = false;
      await _stopVoiceRecordingAndShowResult();
      return;
    }

    // 只有在“用户手动关闭浮层且未进入 stop/transcribe 流程”时才取消。
    // 否则会与 onLongPressEnd 的 stopAndTranscribe 竞争，导致录音被提前置为 idle，最终无结果。
    if (_isVoiceRecording && !_voiceFlowBusy) {
      await _cancelVoiceRecording();
    }
  }

  Future<void> _openOCRFlow() async {
    if (!mounted) return;

    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    final localAISettings = settingsService.localAISettings;
    final l10n = AppLocalizations.of(context);

    try {
      await LocalAIService.instance.initialize(
        localAISettings,
        eagerLoadModels: false,
      );
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
    } catch (e) {
      // OCR 模型缺失/不可用时给出明确提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizeLocalAIError(l10n, e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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

  String _localizeLocalAIError(AppLocalizations l10n, Object error) {
    final msg = error.toString();
    if (msg.contains('asr_model_required')) {
      return l10n.pleaseSwitchToAsrModel;
    }
    if (msg.contains('ocr_model_required')) {
      return l10n.pleaseSwitchToOcrModel;
    }
    if (msg.contains('extract_failed')) {
      return l10n.modelExtractFailed;
    }
    if (msg.contains('record_permission_denied')) {
      // 项目当前缺少统一的“麦克风权限被拒绝”本地化文案，先退化为通用提示。
      return l10n.featureNotAvailable;
    }
    return l10n.featureNotAvailable;
  }
}
