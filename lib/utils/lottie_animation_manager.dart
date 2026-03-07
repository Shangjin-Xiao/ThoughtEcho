import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Lottie动画管理器
/// 提供统一的动画资源管理和播放控制
class LottieAnimationManager {
  static const String _basePath = 'assets/lottie/';

  static const Map<LottieAnimationType, String> _animationPaths = {
    LottieAnimationType.loading: '${_basePath}custom_loading.json', // 使用自定义加载动画
    LottieAnimationType.modernLoading:
        '${_basePath}custom_loading.json', // 使用自定义加载动画
    LottieAnimationType.pulseLoading:
        '${_basePath}custom_loading.json', // 使用自定义加载动画
    LottieAnimationType.aiThinking:
        '${_basePath}custom_loading.json', // AI加载用custom_loading
    LottieAnimationType.searchLoading:
        '${_basePath}search_loading.json', // 笔记搜索用search_loading
    LottieAnimationType.customLoading:
        '${_basePath}custom_loading.json', // 自定义加载
    LottieAnimationType.weatherSearchLoading:
        '${_basePath}weather_search_loading.json', // 天气搜索专用
    LottieAnimationType.notFound:
        '${_basePath}not_found.json', // 搜索无结果用not_found
  };

  /// 获取动画资源路径
  static String getAnimationPath(LottieAnimationType type) {
    return _animationPaths[type] ??
        _animationPaths[LottieAnimationType.loading]!;
  }

  /// 预加载动画资源
  static Future<void> preloadAnimations(BuildContext context) async {
    for (final path in _animationPaths.values) {
      try {
        await Future.wait([
          // 预加载动画JSON
          DefaultAssetBundle.of(context).loadString(path),
        ]);
      } catch (e) {
        debugPrint('预加载Lottie动画失败: $path, 错误: $e');
      }
    }
  }

  /// 获取动画配置
  static LottieAnimationConfig getAnimationConfig(LottieAnimationType type) {
    switch (type) {
      case LottieAnimationType.loading:
      case LottieAnimationType.modernLoading:
      case LottieAnimationType.pulseLoading:
      case LottieAnimationType.aiThinking:
      case LottieAnimationType.customLoading:
        return const LottieAnimationConfig(
          repeat: true,
          reverse: false,
          autoPlay: true,
          width: 80,
          height: 80,
        );
      case LottieAnimationType.searchLoading:
        return const LottieAnimationConfig(
          repeat: true,
          reverse: false,
          autoPlay: true,
          width: 360,
          height: 360,
        );
      case LottieAnimationType.weatherSearchLoading:
        return const LottieAnimationConfig(
          repeat: true,
          reverse: false,
          autoPlay: true,
          width: 540,
          height: 540,
        );
      case LottieAnimationType.notFound:
        return const LottieAnimationConfig(
          repeat: true,
          reverse: false,
          autoPlay: true,
          width: 120,
          height: 120,
          semanticLabel: '未找到相关内容',
        );
    }
  }
}

/// Lottie动画类型枚举
enum LottieAnimationType {
  loading, // 三点加载动画
  modernLoading, // 现代加载动画
  pulseLoading, // 脉冲加载动画
  aiThinking, // AI大脑思考动画
  searchLoading, // 搜索笔记专用加载动画
  customLoading, // 用户自定义加载动画
  weatherSearchLoading, // 天气搜索加载动画
  notFound, // 搜索无结果动画
}

/// Lottie动画配置
class LottieAnimationConfig {
  final bool repeat;
  final bool reverse;
  final bool autoPlay;
  final double width;
  final double height;
  final Duration? duration;
  final String? semanticLabel;

  const LottieAnimationConfig({
    this.repeat = false,
    this.reverse = false,
    this.autoPlay = true,
    this.width = 50,
    this.height = 50,
    this.duration,
    this.semanticLabel,
  });
}

/// 增强的Lottie动画组件
/// 提供更好的错误处理、性能优化和可访问性支持
class EnhancedLottieAnimation extends StatefulWidget {
  final LottieAnimationType type;
  final double? width;
  final double? height;
  final bool? repeat;
  final bool? reverse;
  final bool? autoPlay;
  final Duration? duration;
  final VoidCallback? onComplete;
  final String? semanticLabel;

  const EnhancedLottieAnimation({
    super.key,
    required this.type,
    this.width,
    this.height,
    this.repeat,
    this.reverse,
    this.autoPlay,
    this.duration,
    this.onComplete,
    this.semanticLabel,
  });

  @override
  State<EnhancedLottieAnimation> createState() =>
      _EnhancedLottieAnimationState();
}

class _EnhancedLottieAnimationState extends State<EnhancedLottieAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    final config = LottieAnimationManager.getAnimationConfig(widget.type);

    _controller = AnimationController(
      duration: widget.duration ?? const Duration(seconds: 2),
      vsync: this,
    );

    if (widget.autoPlay ?? config.autoPlay) {
      _controller.forward();
    }

    if (widget.repeat ?? config.repeat) {
      _controller.repeat(reverse: widget.reverse ?? config.reverse);
    }

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.onComplete != null) {
        widget.onComplete!();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = LottieAnimationManager.getAnimationConfig(widget.type);
    final finalWidth = widget.width ?? config.width;
    final finalHeight = widget.height ?? config.height;

    if (_hasError) {
      return _buildFallbackWidget();
    }

    return Semantics(
      label: widget.semanticLabel ??
          config.semanticLabel ??
          _getDefaultSemanticLabel(),
      child: SizedBox(
        width: finalWidth,
        height: finalHeight,
        child: Lottie.asset(
          LottieAnimationManager.getAnimationPath(widget.type),
          controller: _controller,
          width: finalWidth,
          height: finalHeight,
          fit: BoxFit.contain,
          repeat: widget.repeat ?? config.repeat,
          reverse: widget.reverse ?? config.reverse,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Lottie动画加载失败: ${widget.type}, 错误: $error');
            setState(() {
              _hasError = true;
            });
            return _buildFallbackWidget();
          },
        ),
      ),
    );
  }

  String _getDefaultSemanticLabel() {
    switch (widget.type) {
      case LottieAnimationType.loading:
      case LottieAnimationType.modernLoading:
      case LottieAnimationType.pulseLoading:
      case LottieAnimationType.aiThinking:
      case LottieAnimationType.customLoading:
        return '正在加载';
      case LottieAnimationType.searchLoading:
        return '正在搜索笔记';
      case LottieAnimationType.weatherSearchLoading:
        return '天气搜索中';
      case LottieAnimationType.notFound:
        return '未找到相关内容';
    }
  }

  Widget _buildFallbackWidget() {
    final config = LottieAnimationManager.getAnimationConfig(widget.type);
    return SizedBox(
      width: widget.width ?? config.width,
      height: widget.height ?? config.height,
      child: Icon(
        _getFallbackIcon(),
        size: (widget.width ?? config.width) * 0.6,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  IconData _getFallbackIcon() {
    switch (widget.type) {
      case LottieAnimationType.loading:
      case LottieAnimationType.modernLoading:
      case LottieAnimationType.pulseLoading:
      case LottieAnimationType.aiThinking:
      case LottieAnimationType.customLoading:
        return Icons.refresh;
      case LottieAnimationType.searchLoading:
        return Icons.search;
      case LottieAnimationType.weatherSearchLoading:
        return Icons.cloud_sync;
      case LottieAnimationType.notFound:
        return Icons.search_off;
    }
  }
}
