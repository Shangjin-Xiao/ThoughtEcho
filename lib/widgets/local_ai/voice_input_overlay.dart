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

  static const double _ocrTriggerDistance = 120.0;
  static const double _maxDragDistance = 180.0;

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

    final drag = (-_swipeOffset).clamp(0.0, _maxDragDistance);
    final swipeProgress = (drag / _ocrTriggerDistance).clamp(0.0, 1.0);
    final willTriggerOCR = drag >= _ocrTriggerDistance;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _swipeOffset += details.delta.dy;
          // 仅在跨过阈值时触发一次，让用户有“拉到位”的明确反馈
          if (!_ocrTriggered && _swipeOffset <= -_ocrTriggerDistance) {
            _ocrTriggered = true;
            HapticFeedback.mediumImpact();
          }
        });
      },
      onVerticalDragEnd: (details) {
        // 松手判定：达到阈值就进 OCR，否则视为录音完成
        final shouldTriggerOCR = _swipeOffset <= -_ocrTriggerDistance;
        setState(() {
          _swipeOffset = 0.0;
          _ocrTriggered = false;
        });

        if (shouldTriggerOCR) {
          widget.onSwipeUpForOCR?.call();
          return;
        }
        widget.onRecordComplete?.call();
      },
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.60),
              Colors.black.withOpacity(0.72),
            ],
          ),
        ),
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
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                    ),
                  ],
                ),
              ),
              // 波形动画或麦克风图标
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final t = _animationController.value;
                  final base = 108.0;
                  final pulse = (t * 18.0);

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 外圈脉冲 1
                      Container(
                        width: base + pulse * 2.2,
                        height: base + pulse * 2.2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary
                              .withOpacity(0.08 + (1 - t) * 0.06),
                        ),
                      ),
                      // 外圈脉冲 2
                      Container(
                        width: base + pulse * 1.2,
                        height: base + pulse * 1.2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary
                              .withOpacity(0.12 + (1 - t) * 0.06),
                        ),
                      ),
                      // 主圆：渐变 + 轻微高光
                      Container(
                        width: base,
                        height: base,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary.withOpacity(0.95),
                              theme.colorScheme.primaryContainer
                                  .withOpacity(0.95),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  theme.colorScheme.primary.withOpacity(0.35),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.mic,
                              size: 52,
                              color: theme.colorScheme.onPrimary,
                            ),
                            Positioned(
                              top: 18,
                              left: 22,
                              child: Container(
                                width: 22,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.onSurface.withOpacity(0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.transcribedText!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.35,
                      letterSpacing: 0.2,
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
                  // 上滑引导：进度条 + 提示
                  Container(
                    width: 220,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.14),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              willTriggerOCR
                                  ? Icons.camera_alt
                                  : Icons.arrow_upward,
                              color: Colors.white.withOpacity(0.82),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.voiceRecordingHint,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 6,
                            value: swipeProgress,
                            backgroundColor: Colors.white.withOpacity(0.10),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              willTriggerOCR
                                  ? Colors.white
                                  : theme.colorScheme.primary.withOpacity(0.95),
                            ),
                          ),
                        ),
                      ],
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
