import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// 语音浮层当前阶段
enum VoiceOverlayPhase {
  /// 初始化中（准备模型、申请权限等）
  initializing,

  /// 录音中
  recording,

  /// 处理中（转写）
  processing,

  /// 出错
  error,
}

/// 语音录制浮层组件
///
/// 长按 FAB 时显示，提供录音状态显示。
///
/// 录音阶段使用微信风格声浪波形动画，
/// 波形条高度跟随 [volumeLevel] 实时响应。
class VoiceInputOverlay extends StatefulWidget {
  /// 实时转写的文本
  final String? transcribedText;

  /// 当前阶段
  final VoiceOverlayPhase phase;

  /// 错误消息（当 phase == error 时使用）
  final String? errorMessage;

  /// 当前音量级别 (0.0 - 1.0)
  final double volumeLevel;

  const VoiceInputOverlay({
    super.key,
    this.transcribedText,
    this.phase = VoiceOverlayPhase.initializing,
    this.errorMessage,
    this.volumeLevel = 0.0,
  });

  @override
  State<VoiceInputOverlay> createState() => _VoiceInputOverlayState();
}

class _VoiceInputOverlayState extends State<VoiceInputOverlay>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _breathController;

  /// 波形条高度历史（模拟多条柱状声浪）
  final List<double> _barHeights = List.filled(_barCount, 0.15);

  /// 波形条数量
  static const int _barCount = 28;

  @override
  void initState() {
    super.initState();
    // 波浪动画控制器 - 持续循环驱动波形更新
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    )..addListener(_updateBars);
    _waveController.repeat();

    // 呼吸动画（用于初始化/处理阶段）
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveController.removeListener(_updateBars);
    _waveController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  /// 更新声浪条高度
  void _updateBars() {
    if (widget.phase != VoiceOverlayPhase.recording) return;

    final vol = widget.volumeLevel.clamp(0.0, 1.0);
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;

    for (int i = 0; i < _barCount; i++) {
      // 每根柱子基于不同相位的正弦波叠加，营造自然波浪感
      final phase1 = math.sin(time * 5.0 + i * 0.45) * 0.3;
      final phase2 = math.sin(time * 3.2 + i * 0.8) * 0.2;
      final phase3 = math.sin(time * 7.1 + i * 0.25) * 0.1;

      // 基础高度 + 音量驱动 + 波浪叠加
      final base = 0.08 + vol * 0.6;
      final wave = (phase1 + phase2 + phase3) * (0.3 + vol * 0.7);
      final target = (base + wave).clamp(0.05, 1.0);

      // 平滑插值（柱子不要跳变）
      _barHeights[i] = _barHeights[i] + (target - _barHeights[i]) * 0.35;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isRecording = widget.phase == VoiceOverlayPhase.recording;

    return IgnorePointer(
      ignoring: true,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 背景模糊
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ),

            // 主要内容
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  const Spacer(flex: 2),

                  // 中心动画区域
                  _buildCenterContent(context, colorScheme),

                  const SizedBox(height: 32),

                  // 状态文本
                  Text(
                    _getStatusText(l10n),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 内容区域（转写文本 / 提示 / 错误）
                  _buildContentArea(context, l10n, theme),

                  const Spacer(flex: 3),

                  // 底部上滑提示（仅在录音阶段显示）
                  if (isRecording) ...[
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.voiceRecordingHint,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 松开提示
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        l10n.releaseToFinish,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取状态文本
  String _getStatusText(AppLocalizations l10n) {
    switch (widget.phase) {
      case VoiceOverlayPhase.initializing:
        return l10n.voiceInitializing;
      case VoiceOverlayPhase.recording:
        return l10n.voiceRecording;
      case VoiceOverlayPhase.processing:
        return l10n.voiceProcessing;
      case VoiceOverlayPhase.error:
        return l10n.featureNotAvailable;
    }
  }

  /// 构建内容区域
  Widget _buildContentArea(
      BuildContext context, AppLocalizations l10n, ThemeData theme) {
    switch (widget.phase) {
      case VoiceOverlayPhase.initializing:
        return Text(
          l10n.voiceInitializingHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.6),
          ),
        );

      case VoiceOverlayPhase.recording:
        if (widget.transcribedText != null &&
            widget.transcribedText!.isNotEmpty) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Text(
              widget.transcribedText!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                height: 1.5,
              ),
            ),
          );
        } else {
          return Text(
            l10n.listening,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
            ),
          );
        }

      case VoiceOverlayPhase.processing:
        return Text(
          l10n.voiceProcessing,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.6),
          ),
        );

      case VoiceOverlayPhase.error:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            widget.errorMessage ?? l10n.featureNotAvailable,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        );
    }
  }

  /// 构建中心内容（根据阶段不同显示不同动画）
  Widget _buildCenterContent(BuildContext context, ColorScheme colorScheme) {
    if (widget.phase == VoiceOverlayPhase.initializing) {
      return _buildInitializingContent(colorScheme);
    }
    if (widget.phase == VoiceOverlayPhase.error) {
      return _buildErrorContent();
    }
    if (widget.phase == VoiceOverlayPhase.processing) {
      return _buildProcessingContent(colorScheme);
    }
    // ========== 录音阶段：微信风格声浪动画 ==========
    return _buildWaveformContent(colorScheme);
  }

  /// 声浪波形 + 麦克风图标
  Widget _buildWaveformContent(ColorScheme colorScheme) {
    return SizedBox(
      width: 260,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 波形条
          CustomPaint(
            size: const Size(260, 140),
            painter: _WaveformPainter(
              barHeights: _barHeights,
              color: colorScheme.primary,
              glowColor: colorScheme.primaryContainer,
            ),
          ),
          // 中心麦克风圆形
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
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
                  color: colorScheme.primary.withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.mic_rounded,
              size: 32,
              color: colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 初始化阶段
  Widget _buildInitializingContent(ColorScheme colorScheme) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
        ),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary.withValues(alpha: 0.8),
                colorScheme.primaryContainer.withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Icon(
            Icons.mic_rounded,
            size: 40,
            color: colorScheme.onPrimary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  /// 错误状态
  Widget _buildErrorContent() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.red.withValues(alpha: 0.2),
      ),
      child: const Icon(
        Icons.error_outline_rounded,
        size: 50,
        color: Colors.white,
      ),
    );
  }

  /// 处理中
  Widget _buildProcessingContent(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _breathController,
      builder: (context, child) {
        final t = _breathController.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colorScheme.primary.withValues(alpha: 0.5 + t * 0.3),
                ),
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.primaryContainer,
                  ],
                ),
              ),
              child: Icon(
                Icons.sync_rounded,
                size: 40,
                color: colorScheme.onPrimary,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 声浪波形绘制器
///
/// 绘制类似微信语音消息的波形条，从中心向两侧展开，
/// 每根条带有圆角和渐变荧光效果。
class _WaveformPainter extends CustomPainter {
  final List<double> barHeights;
  final Color color;
  final Color glowColor;

  _WaveformPainter({
    required this.barHeights,
    required this.color,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = barHeights.length;
    const barWidth = 3.5;
    final gap = (size.width - barCount * barWidth) / (barCount + 1);
    final maxBarHeight = size.height * 0.85;
    final centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final x = gap + i * (barWidth + gap);
      final h = barHeights[i].clamp(0.05, 1.0) * maxBarHeight;
      final halfH = h / 2;

      // 中间位置的条更亮
      final distFromCenter = (i - barCount / 2).abs() / (barCount / 2);
      final alpha = 1.0 - distFromCenter * 0.3;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x, centerY - halfH, x + barWidth, centerY + halfH),
        const Radius.circular(2.0),
      );

      // 荧光层（模糊阴影）
      final glowPaint = Paint()
        ..color = glowColor.withValues(alpha: alpha * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(rect, glowPaint);

      // 实体条
      final barPaint = Paint()
        ..color = color.withValues(alpha: alpha * 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}
