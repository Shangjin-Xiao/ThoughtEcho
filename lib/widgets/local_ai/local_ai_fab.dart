import 'package:flutter/material.dart';
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
/// 交互逻辑：
/// - 短按：交由外部处理（通常是"新增笔记"）
/// - 长按：立即显示语音界面（初始化状态），初始化完成后自动开始录音
/// - 松手：停止录音并将识别文字填入编辑框
/// - 长按后上滑（手指不松开）：进入 OCR 拍照识别
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
  /// 浮层是否打开
  bool _voiceOverlayOpen = false;

  /// 是否正在录音
  bool _isVoiceRecording = false;

  /// 当前浮层阶段
  VoiceOverlayPhase _currentPhase = VoiceOverlayPhase.initializing;

  /// 错误消息
  String? _errorMessage;

  /// 用于通知浮层更新的 ValueNotifier
  final ValueNotifier<int> _overlayUpdateNotifier = ValueNotifier(0);

  /// 是否手指已松开（用于判断松开后是否应该直接结束录音）
  bool _fingerLifted = false;

  /// 是否应该进入 OCR（上滑触发）
  bool _shouldEnterOCR = false;

  /// 长按起始位置
  Offset? _longPressStartPosition;

  /// 上滑阈值（像素）
  static const double _swipeUpThreshold = 80.0;

  @override
  void dispose() {
    _overlayUpdateNotifier.dispose();
    super.dispose();
  }

  /// 关闭语音浮层（如果已打开）
  void _closeOverlayIfOpen() {
    if (_voiceOverlayOpen && mounted) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  /// 通知浮层更新
  void _notifyOverlayUpdate() {
    _overlayUpdateNotifier.value++;
  }

  /// 长按开始：立即显示浮层（初始化状态），然后在后台初始化并开始录音
  Future<void> _onLongPressStart(LongPressStartDetails details) async {
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    final localAISettings = settingsService.localAISettings;

    // 未启用则不响应长按
    if (!localAISettings.enabled || !localAISettings.speechToTextEnabled) {
      return;
    }

    // 记录起始位置和状态
    _longPressStartPosition = details.globalPosition;
    _fingerLifted = false;
    _shouldEnterOCR = false;
    _currentPhase = VoiceOverlayPhase.initializing;
    _errorMessage = null;

    // 立即显示浮层（初始化状态）
    _showVoiceInputOverlay();

    // 在后台进行初始化和开始录音
    await _initializeAndStartRecording();
  }

  /// 长按移动：检测上滑进入 OCR
  void _onLongPressUpdate(LongPressMoveUpdateDetails details) {
    if (_fingerLifted || _shouldEnterOCR) return;
    if (_longPressStartPosition == null) return;

    final dy = _longPressStartPosition!.dy - details.globalPosition.dy;
    if (dy > _swipeUpThreshold) {
      _shouldEnterOCR = true;
      _handleSwipeUpToOCR();
    }
  }

  /// 长按结束：松手时停止录音并填入文字
  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    _fingerLifted = true;
    _longPressStartPosition = null;

    // 如果已经触发 OCR，不再处理录音
    if (_shouldEnterOCR) {
      return;
    }

    // 关闭浮层并停止录音
    await _stopRecordingAndInsertText();
  }

  /// 上滑进入 OCR
  Future<void> _handleSwipeUpToOCR() async {
    // 先关闭浮层
    _closeOverlayIfOpen();

    // 取消录音（如果正在录音）
    await _cancelVoiceRecording();

    // 打开 OCR 流程
    await _openOCRFlow();
  }

  /// 初始化并开始录音
  Future<void> _initializeAndStartRecording() async {
    final localAI = LocalAIService.instance;
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    final localAISettings = settingsService.localAISettings;
    final l10n = AppLocalizations.of(context);

    try {
      // 初始化服务
      await localAI.initialize(localAISettings, eagerLoadModels: false);

      // 检查功能是否可用
      if (!localAI.isFeatureAvailable(LocalAIFeature.speechToText)) {
        _currentPhase = VoiceOverlayPhase.error;
        _errorMessage = l10n.pleaseSwitchToAsrModel;
        _notifyOverlayUpdate();
        return;
      }

      // 如果用户已松开手指或要进入 OCR，不再开始录音
      if (_fingerLifted || _shouldEnterOCR) {
        _closeOverlayIfOpen();
        return;
      }

      // 开始录音
      await localAI.startRecording();
      _isVoiceRecording = true;
      _currentPhase = VoiceOverlayPhase.recording;
      _notifyOverlayUpdate();

      // 如果在录音开始后用户已松开手指，立即停止并转录
      if (_fingerLifted && !_shouldEnterOCR) {
        await _stopRecordingAndInsertText();
      }
    } catch (e) {
      _currentPhase = VoiceOverlayPhase.error;
      _errorMessage = _localizeLocalAIError(l10n, e);
      _notifyOverlayUpdate();
    }
  }

  /// 停止录音并将文字填入编辑框
  Future<void> _stopRecordingAndInsertText() async {
    if (!_isVoiceRecording) {
      // 如果未在录音，直接关闭浮层
      _closeOverlayIfOpen();
      return;
    }

    final localAI = LocalAIService.instance;
    final l10n = AppLocalizations.of(context);

    // 先更新浮层为处理中状态
    _currentPhase = VoiceOverlayPhase.processing;
    _notifyOverlayUpdate();

    try {
      final result = await localAI.stopAndTranscribe();
      _isVoiceRecording = false;

      if (!mounted) return;

      final resultText = result.text.trim();

      // 关闭浮层
      _closeOverlayIfOpen();

      if (resultText.isEmpty) {
        // 未识别到文字，显示提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.voiceNoTextRecognized),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // 将识别结果填入编辑框
      widget.onInsertText(resultText);
    } catch (e) {
      _isVoiceRecording = false;

      // 关闭浮层
      _closeOverlayIfOpen();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizeLocalAIError(l10n, e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 取消录音
  Future<void> _cancelVoiceRecording() async {
    if (!_isVoiceRecording) return;
    _isVoiceRecording = false;
    try {
      await LocalAIService.instance.speechService.cancelRecording();
    } catch (_) {
      // ignore
    }
  }

  /// 显示语音输入浮层
  void _showVoiceInputOverlay() {
    if (!mounted || _voiceOverlayOpen) return;

    _voiceOverlayOpen = true;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false, // 禁止点击外部关闭，由手势控制
      barrierLabel: 'voice_input_overlay',
      barrierColor: Colors.black54,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return ValueListenableBuilder<int>(
          valueListenable: _overlayUpdateNotifier,
          builder: (context, _, __) {
            final speech = LocalAIService.instance.speechService;
            return ListenableBuilder(
              listenable: speech,
              builder: (context, _) {
                return VoiceInputOverlay(
                  phase: _currentPhase,
                  transcribedText: speech.currentTranscription,
                  errorMessage: _errorMessage,
                  volumeLevel: speech.status.volumeLevel,
                  onStopRecording: () {
                    _stopRecordingAndInsertText();
                  },
                  onCancel: () {
                    _cancelVoiceRecording();
                    _closeOverlayIfOpen();
                  },
                  onTranscriptionComplete: (text) {
                    _closeOverlayIfOpen();
                    if (text.trim().isNotEmpty) {
                      widget.onInsertText(text.trim());
                    }
                  },
                );
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
      transitionDuration: const Duration(milliseconds: 150),
    ).then((_) {
      _voiceOverlayOpen = false;
    });
  }

  /// 打开 OCR 流程
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
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressUpdate,
      onLongPressEnd: _onLongPressEnd,
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
      return l10n.featureNotAvailable;
    }
    return l10n.featureNotAvailable;
  }
}
