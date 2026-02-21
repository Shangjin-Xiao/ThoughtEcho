import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../gen_l10n/app_localizations.dart';

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
/// 全屏覆盖浮层，底部展示海浪动画响应音量，
/// 中央展示转写文本，提供停止/取消/填入编辑器操作。
class VoiceInputOverlay extends StatefulWidget {
  /// 实时转写的文本
  final String? transcribedText;

  /// 当前阶段
  final VoiceOverlayPhase phase;

  /// 错误消息（当 phase == error 时使用）
  final String? errorMessage;

  /// 当前音量级别 (0.0 - 1.0)
  final double volumeLevel;

  /// 取消录音并退出
  final VoidCallback? onCancel;

  /// 转写完成后将文本填入编辑器
  final ValueChanged<String>? onTranscriptionComplete;

  const VoiceInputOverlay({
    super.key,
    this.transcribedText,
    this.phase = VoiceOverlayPhase.initializing,
    this.errorMessage,
    this.volumeLevel = 0.0,
    this.onCancel,
    this.onTranscriptionComplete,
  });

  @override
  State<VoiceInputOverlay> createState() => _VoiceInputOverlayState();
}

class _VoiceInputOverlayState extends State<VoiceInputOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    final hasText = widget.transcribedText != null &&
        widget.transcribedText!.trim().isNotEmpty;
    final isRecording = widget.phase == VoiceOverlayPhase.recording;
    final isProcessing = widget.phase == VoiceOverlayPhase.processing;
    final isError = widget.phase == VoiceOverlayPhase.error;
    final isInitializing = widget.phase == VoiceOverlayPhase.initializing;
    // 转写完成：不在录音/初始化中，且有文本
    final isDone = !isRecording && !isInitializing && hasText && !isError;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 半透明背景 — 点击取消
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onCancel,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ),

          // ====== 底部海浪动画 ======
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: size.height * 0.25,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _OceanWavePainter(
                    phase: _waveController.value,
                    volumeLevel: isRecording ? widget.volumeLevel : 0.0,
                    color: colorScheme.primary,
                  ),
                  size: Size(size.width, size.height * 0.25),
                );
              },
            ),
          ),

          // ====== 主内容 ======
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),

                // ====== 中央区域 ======
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: _buildCenterContent(
                    context,
                    l10n,
                    theme,
                    colorScheme,
                    hasText: hasText,
                    isRecording: isRecording,
                    isProcessing: isProcessing,
                    isError: isError,
                    isInitializing: isInitializing,
                  ),
                ),

                const Spacer(flex: 2),

                // ====== 底部按钮区（在波浪上方）======
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: _buildBottomActions(
                    context,
                    l10n,
                    colorScheme,
                    isDone: isDone,
                  ),
                ),

                // 为波浪区域留出空间
                SizedBox(height: size.height * 0.12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 中央内容：状态指示 + 转写文本
  Widget _buildCenterContent(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme, {
    required bool hasText,
    required bool isRecording,
    required bool isProcessing,
    required bool isError,
    required bool isInitializing,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isRecording) ...[
          // 状态指示器
          _buildStatusIndicator(
            colorScheme,
            isProcessing: isProcessing,
            isError: isError,
            isInitializing: isInitializing,
          ),

          const SizedBox(height: 20),

          // 状态文字
          Text(
            _getStatusText(l10n),
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 24),
        ],

        // 转写文本
        if (hasText)
          AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  widget.transcribedText!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.6,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
          ),

        // 错误详情
        if (isError && widget.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.redAccent.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  /// 状态指示器 — 小而精致
  Widget _buildStatusIndicator(
    ColorScheme colorScheme, {
    required bool isProcessing,
    required bool isError,
    required bool isInitializing,
  }) {
    if (isError) {
      return Icon(
        Icons.error_outline_rounded,
        size: 40,
        color: Colors.redAccent.withValues(alpha: 0.8),
      );
    }

    if (isProcessing || isInitializing) {
      return SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(
            colorScheme.primary.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// 底部操作按钮
  Widget _buildBottomActions(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    required bool isDone,
  }) {
    // 转写完成 — 显示「填入编辑器」按钮
    if (isDone) {
      return FilledButton.icon(
        onPressed: () {
          final text = widget.transcribedText?.trim() ?? '';
          if (text.isNotEmpty) {
            widget.onTranscriptionComplete?.call(text);
          }
        },
        icon: const Icon(Icons.check_rounded, size: 20),
        label: Text(l10n.voiceInsertToEditor),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
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
}

// ---------------------------------------------------------------------------
// 海浪 CustomPainter
// ---------------------------------------------------------------------------

/// 绘制多层正弦海浪，振幅响应音量，
/// 使用 4 层不同相位和透明度的波浪营造深度感。
class _OceanWavePainter extends CustomPainter {
  final double phase; // 0.0 – 1.0 循环
  final double volumeLevel; // 0.0 – 1.0
  final Color color;

  _OceanWavePainter({
    required this.phase,
    required this.volumeLevel,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vol = volumeLevel.clamp(0.0, 1.0);

    // 4 层波浪配置：[频率倍数, 相位偏移, 振幅系数, 透明度]
    const layers = <List<double>>[
      [1.0, 0.0, 1.0, 0.12],
      [1.3, 0.8, 0.8, 0.18],
      [0.7, 2.2, 0.6, 0.25],
      [1.6, 4.0, 0.5, 0.35],
    ];

    for (final cfg in layers) {
      final freq = cfg[0];
      final phaseOffset = cfg[1];
      final ampScale = cfg[2];
      final alpha = cfg[3];

      // 基础振幅 + 音量贡献
      final amplitude = (8.0 + vol * 22.0) * ampScale;
      final wavePhase = phase * math.pi * 2 * freq + phaseOffset;

      final path = Path();
      path.moveTo(0, size.height);

      for (double x = 0; x <= size.width; x += 4) {
        final normalizedX = x / size.width;
        // 两个正弦叠加产生更自然的波形
        final y1 = math.sin(normalizedX * math.pi * 2 * 1.5 + wavePhase);
        final y2 =
            math.sin(normalizedX * math.pi * 2 * 2.8 + wavePhase * 1.3) * 0.4;
        final waveY = size.height * 0.35 - (y1 + y2) * amplitude;
        path.lineTo(x, waveY);
      }

      path.lineTo(size.width, size.height);
      path.close();

      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OceanWavePainter old) {
    return old.phase != phase || old.volumeLevel != volumeLevel;
  }
}
