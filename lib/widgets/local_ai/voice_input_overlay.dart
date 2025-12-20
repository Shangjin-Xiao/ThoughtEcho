import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../gen_l10n/app_localizations.dart';

/// 语音录制浮层组件
/// 
/// 长按 FAB 时显示，提供录音状态显示和手势交互
class VoiceInputOverlay extends StatefulWidget {
  final VoidCallback? onSwipeUpForOCR;
  final VoidCallback? onRecordComplete;
  final String? transcribedText;

  const VoiceInputOverlay({
    super.key,
    this.onSwipeUpForOCR,
    this.onRecordComplete,
    this.transcribedText,
  });

  @override
  State<VoiceInputOverlay> createState() => _VoiceInputOverlayState();
}

class _VoiceInputOverlayState extends State<VoiceInputOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  double _swipeOffset = 0.0;
  bool _ocrTriggered = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _swipeOffset += details.delta.dy;
          if (_swipeOffset < -100 && !_ocrTriggered) {
            // 触发 OCR 模式（只触发一次）
            _ocrTriggered = true;
            HapticFeedback.selectionClick();
            widget.onSwipeUpForOCR?.call();
          }
        });
      },
      onVerticalDragEnd: (details) {
        final shouldCompleteRecord = !_ocrTriggered && _swipeOffset > -100;
        setState(() {
          _swipeOffset = 0.0;
          _ocrTriggered = false;
        });
        if (shouldCompleteRecord) {
          widget.onRecordComplete?.call();
        }
      },
      child: Container(
        width: size.width,
        height: size.height,
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    ),
                  ],
                ),
              ),
              // 波形动画或麦克风图标
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Container(
                    width: 100 + (_animationController.value * 20),
                    height: 100 + (_animationController.value * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withOpacity(0.3),
                    ),
                    child: Icon(
                      Icons.mic,
                      size: 50,
                      color: theme.colorScheme.onPrimary,
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // 录音状态文本
              Text(
                l10n.voiceRecording,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // 实时转写文字
              if (widget.transcribedText != null &&
                  widget.transcribedText!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.transcribedText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 16,
                    ),
                  ),
                )
              else
                Text(
                  l10n.voiceTranscribing,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              const SizedBox(height: 28),

              // 手势提示（更明确，且不会额外新增 l10n 文案）
              Column(
                children: [
                  Icon(
                    Icons.arrow_upward,
                    color: Colors.white.withOpacity(0.75),
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.voiceRecordingHint,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
