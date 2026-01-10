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
/// 交互逻辑：
/// - 按下立即显示，显示"正在初始化"
/// - 初始化完成后自动切换到"正在录音"
/// - 松开手指（在 FAB 中处理）：停止录音并填入文字
/// - 上滑（在 FAB 中处理）：进入 OCR 模式
///
/// 注意：手势控制完全由 LocalAIFab 处理，此组件只负责显示状态。
class VoiceInputOverlay extends StatefulWidget {
  /// 实时转写的文本
  final String? transcribedText;
  
  /// 当前阶段
  final VoiceOverlayPhase phase;
  
  /// 错误消息（当 phase == error 时使用）
  final String? errorMessage;

  const VoiceInputOverlay({
    super.key,
    this.transcribedText,
    this.phase = VoiceOverlayPhase.initializing,
    this.errorMessage,
  });

  @override
  State<VoiceInputOverlay> createState() => _VoiceInputOverlayState();
}

class _VoiceInputOverlayState extends State<VoiceInputOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

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
    
    final isRecording = widget.phase == VoiceOverlayPhase.recording;

    return IgnorePointer(
      // 让手势穿透到 FAB 的 GestureDetector
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
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
            ),
            
            // 主要内容
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  
                  const Spacer(flex: 2),

                  // 麦克风动画区域
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

                  // 内容区域（根据阶段显示不同内容）
                  _buildContentArea(context, l10n, theme),

                  const Spacer(flex: 3),

                  // 底部上滑提示（仅在录音阶段显示）
                  if (isRecording)
                    Column(
                      children: [
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white.withOpacity(0.7),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.voiceRecordingHint,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                  
                  // 松开提示
                  if (isRecording)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        l10n.releaseToFinish,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withOpacity(0.5),
                        ),
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
  Widget _buildContentArea(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    switch (widget.phase) {
      case VoiceOverlayPhase.initializing:
        return Text(
          l10n.voiceInitializingHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        );
      
      case VoiceOverlayPhase.recording:
        if (widget.transcribedText != null && widget.transcribedText!.isNotEmpty) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
          );
        } else {
          return Text(
            l10n.listening,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.6),
            ),
          );
        }
      
      case VoiceOverlayPhase.processing:
        return Text(
          l10n.voiceProcessing,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white.withOpacity(0.6),
          ),
        );
      
      case VoiceOverlayPhase.error:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: Colors.red.withOpacity(0.3),
            ),
          ),
          child: Text(
            widget.errorMessage ?? l10n.featureNotAvailable,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        );
    }
  }
  
  /// 构建中心内容（根据阶段不同显示不同动画）
  Widget _buildCenterContent(BuildContext context, ColorScheme colorScheme) {
    if (widget.phase == VoiceOverlayPhase.initializing) {
      // 初始化阶段显示加载指示器
      return Stack(
        alignment: Alignment.center,
        children: [
          // 外圈旋转
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                colorScheme.primary.withOpacity(0.5),
              ),
            ),
          ),
          // 核心图标
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withOpacity(0.8),
                  colorScheme.primaryContainer.withOpacity(0.8),
                ],
              ),
            ),
            child: Icon(
              Icons.mic_rounded,
              size: 40,
              color: colorScheme.onPrimary.withOpacity(0.7),
            ),
          ),
        ],
      );
    }
    
    if (widget.phase == VoiceOverlayPhase.error) {
      // 错误状态显示红色图标
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.withOpacity(0.2),
        ),
        child: const Icon(
          Icons.error_outline_rounded,
          size: 50,
          color: Colors.white,
        ),
      );
    }
    
    if (widget.phase == VoiceOverlayPhase.processing) {
      // 处理中显示加载动画
      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                colorScheme.primary.withOpacity(0.7),
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
    }
    
    // 录音阶段显示呼吸动画
    return AnimatedBuilder(
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
                    color: colorScheme.primary.withOpacity(opacity),
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
    );
  }
}
