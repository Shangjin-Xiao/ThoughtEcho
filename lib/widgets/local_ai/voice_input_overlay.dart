import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

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
      duration: const Duration(milliseconds: 1500),
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
    final colorScheme = theme.colorScheme;

    final drag = (-_swipeOffset).clamp(0.0, _maxDragDistance);
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
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 背景模糊
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  color: Colors.black.withOpacity(0.6), // 始终使用深色背景以保证文字清晰
                ),
              ),
            ),

            // 主要内容
            SafeArea(
              child: Column(
                children: [
                  // 顶部关闭按钮
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          highlightColor: Colors.white.withOpacity(0.2),
                        ),
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // 麦克风动画区域
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      final t = _animationController.value;
                      // 呼吸效果
                      final scale = 1.0 + (t * 0.1);
                      final opacity = 0.3 - (t * 0.15);

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // 扩散波纹
                          Transform.scale(
                            scale: 1.0 + (t * 0.5),
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      colorScheme.primary.withOpacity(opacity),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          // 内部光晕
                          Container(
                            width: 100 * scale,
                            height: 100 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary.withOpacity(0.2),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                          ),
                          // 核心图标
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  colorScheme.primary,
                                  colorScheme.primaryContainer,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.5),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.mic_rounded,
                              size: 40,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // 状态文本
                  Text(
                    l10n.voiceRecording,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 实时转写内容展示
                  if (widget.transcribedText != null &&
                      widget.transcribedText!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius:
                            BorderRadius.circular(AppTheme.cardRadius),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Text(
                        widget.transcribedText!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                          height: 1.5,
                        ),
                      ),
                    )
                  else
                    Text(
                      l10n.voiceTranscribing,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),

                  const Spacer(flex: 3),

                  // 底部上滑提示
                  AnimatedOpacity(
                    opacity: willTriggerOCR ? 1.0 : 0.7,
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          transform: Matrix4.translationValues(
                              0, willTriggerOCR ? -10 : 0, 0),
                          child: Icon(
                            willTriggerOCR
                                ? Icons.document_scanner_rounded
                                : Icons.keyboard_arrow_up_rounded,
                            color: willTriggerOCR
                                ? colorScheme.primaryContainer
                                : Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.voiceRecordingHint,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: willTriggerOCR
                                ? colorScheme.primaryContainer
                                : Colors.white.withOpacity(0.8),
                            fontWeight: willTriggerOCR
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 简单的指示条
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
