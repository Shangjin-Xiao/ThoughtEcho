import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_style.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../utils/color_utils.dart'; // 导入颜色工具
import '../gen_l10n/app_localizations.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  final List<Color> _presetColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.amber,
    Colors.cyan,
  ];

  ThemeMode _themeMode = ThemeMode.system;
  bool _useCustomColor = false;
  bool _useDynamicColor = true;
  Color? _customColor;
  bool _hasSyncedFromTheme = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appTheme = context.watch<AppTheme>();

    if (!_hasSyncedFromTheme) {
      _themeMode = appTheme.themeMode;
      _useCustomColor = appTheme.useCustomColor;
      _useDynamicColor = appTheme.useDynamicColor;
      _customColor = appTheme.customColor;
      _hasSyncedFromTheme = true;
      return;
    }

    // 主题状态被外部更新时同步到本地，确保UI立即反映变化
    if (_themeMode != appTheme.themeMode ||
        _useCustomColor != appTheme.useCustomColor ||
        _useDynamicColor != appTheme.useDynamicColor ||
        _customColor != appTheme.customColor) {
      setState(() {
        _themeMode = appTheme.themeMode;
        _useCustomColor = appTheme.useCustomColor;
        _useDynamicColor = appTheme.useDynamicColor;
        _customColor = appTheme.customColor;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = Provider.of<AppTheme>(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.themeSettings)),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(AppShapeTokens.of(context).cardRadius),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.themeStyle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final style in ThemeStyle.values)
                    _buildThemeStyleOption(context, appTheme, style, l10n),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(AppShapeTokens.of(context).cardRadius),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline,
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.themeMode,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildThemeModeOption(
                        context,
                        ThemeMode.light,
                        l10n.themeModeLight,
                        Icons.light_mode,
                      ),
                      _buildThemeModeOption(
                        context,
                        ThemeMode.dark,
                        l10n.themeModeDark,
                        Icons.dark_mode,
                      ),
                      _buildThemeModeOption(
                        context,
                        ThemeMode.system,
                        l10n.followSystem,
                        Icons.brightness_auto,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 自定义色和动态取色只对 material 生效，手工色板下藏起来，
          // 免得用户以为开关坏了。
          if (appTheme.themeStyle.isGenerated)
            Card(
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                    AppShapeTokens.of(context).cardRadius),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.useCustomThemeColor,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Switch(
                          value: _useCustomColor,
                          onChanged: (value) {
                            setState(() {
                              _useCustomColor = value;
                            });
                            appTheme.setUseCustomColor(value);
                          },
                        ),
                      ],
                    ),
                    if (_useCustomColor) ...[
                      const SizedBox(height: 16),
                      Text(l10n.selectThemeColor),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final color in _presetColors)
                            _buildColorOption(context, appTheme, color),
                          _buildCustomColorPicker(context, appTheme),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (appTheme.themeStyle.isGenerated)
            Card(
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                    AppShapeTokens.of(context).cardRadius),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.dynamicColor,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.dynamicColorDesc,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _useDynamicColor && !_useCustomColor,
                          onChanged: (value) {
                            setState(() {
                              _useDynamicColor = value;
                              if (value) {
                                _useCustomColor = false;
                              }
                            });
                            // 如果启用动态取色，需要禁用自定义主题色
                            if (value) {
                              appTheme.setUseCustomColor(false);
                            }
                            appTheme.setUseDynamicColor(value);
                          },
                          // 当使用自定义颜色时禁用此开关
                          activeThumbColor: _useCustomColor
                              ? Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_useCustomColor)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.errorContainer.applyOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.customColorEnabledHint,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!_useCustomColor && !_useDynamicColor)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          )
                              .colorScheme
                              .surfaceContainerHighest
                              .applyOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.dynamicColorDisabledHint,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 风格选项：左边一小片色板预览，右边名称和一句说明。
  ///
  /// 预览直接取该风格的真实色值（material 没有固定色板，取当前生效的
  /// ColorScheme），所以加新风格时这里不需要跟着改。
  Widget _buildThemeStyleOption(
    BuildContext context,
    AppTheme appTheme,
    ThemeStyle style,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final selected = appTheme.themeStyle == style;
    final brightness = theme.brightness;

    final (String name, String description) = switch (style) {
      ThemeStyle.material => (
          l10n.themeStyleMaterial,
          l10n.themeStyleMaterialDesc
        ),
      ThemeStyle.paper => (l10n.themeStylePaper, l10n.themeStylePaperDesc),
      ThemeStyle.plain => (l10n.themeStylePlain, l10n.themeStylePlainDesc),
    };

    final colors = style.palette?.forBrightness(brightness);
    final swatch = colors == null
        ? <Color>[
            theme.colorScheme.surface,
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ]
        : <Color>[colors.card, colors.accent, colors.secondary];
    // 色板预览展示的是「style 这个风格长什么样」，不是当前生效的风格，
    // 所以圆角要按 style.form 取值，不能读 AppShapeTokens.of(context)
    // （那个是当前主题的令牌，会导致纸墨/素笺的预览卡片在 material 主题下显示成圆角）。
    final previewTokens = AppShapeTokens.fromForm(style.form, brightness);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // 选中态原本只靠背景色和对勾图标表达，屏幕阅读器读不到。
      // onTap 也保持可用：置 null 会让选中项被读成「已停用」，语义正好反了；
      // 重复选中由 setThemeStyle 内部的相等判断吃掉。
      child: Semantics(
        selected: selected,
        button: true,
        // 三个风格是互斥的单选项。不声明的话屏幕阅读器会把它们读成三个独立按钮，
        // 用户不知道选了一个就等于取消了另外两个。
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius:
              BorderRadius.circular(AppShapeTokens.of(context).cardRadius),
          child: InkWell(
            borderRadius:
                BorderRadius.circular(AppShapeTokens.of(context).cardRadius),
            onTap: () => appTheme.setThemeStyle(style),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // 色板预览：三片纵向叠放的色块，纸、墨、辅助各一片。
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(previewTokens.buttonRadius),
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final color in swatch)
                          Expanded(child: Container(color: color)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeModeOption(
    BuildContext context,
    ThemeMode mode,
    String label,
    IconData icon,
  ) {
    final isSelected = _themeMode == mode;
    final colorScheme = Theme.of(context).colorScheme;
    final buttonRadius = AppShapeTokens.of(context).buttonRadius;

    return InkWell(
      borderRadius: BorderRadius.circular(buttonRadius),
      onTap: () {
        setState(() {
          _themeMode = mode;
        });
        final appTheme = context.read<AppTheme>();
        appTheme.setThemeMode(mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(buttonRadius),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorOption(
    BuildContext context,
    AppTheme appTheme,
    Color color,
  ) {
    final isSelected = _customColor == color;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius:
          BorderRadius.circular(AppShapeTokens.of(context).buttonRadius),
      onTap: () async {
        setState(() {
          _customColor = color;
          _useCustomColor = true;
          _useDynamicColor = false;
        });
        await appTheme.setCustomColor(color);
        await appTheme.setUseCustomColor(true);
        await appTheme.setUseDynamicColor(false);
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: colorScheme.primary.applyOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.light
                    ? Colors.black
                    : Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildCustomColorPicker(BuildContext context, AppTheme appTheme) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(AppShapeTokens.of(context).buttonRadius),
      onTap: () => _showColorPicker(context, appTheme),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 1,
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showColorPicker(BuildContext context, AppTheme appTheme) async {
    // 获取当前选择的颜色作为对话框的初始颜色
    final Color initialColor = _customColor ?? Colors.blue;
    // 创建一个变量来跟踪当前选择的颜色
    Color selectedColor = initialColor;

    // 使用ColorPicker的showPickerDialog方法
    // 注意：showPickerDialog返回bool值表示用户是否点击了确认按钮
    final bool colorSelected = await ColorPicker(
      color: initialColor,
      onColorChanged: (Color color) {
        // 保存用户当前选择的颜色
        selectedColor = color;
      },
      width: 40,
      height: 40,
      spacing: 10,
      runSpacing: 10,
      borderRadius: 20,
      wheelDiameter: 200,
      enableShadesSelection: true,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.primary: true,
        ColorPickerType.accent: false,
        ColorPickerType.wheel: true,
      },
    ).showPickerDialog(context);

    // 如果用户点击了确认按钮，则应用选择的颜色
    if (colorSelected) {
      setState(() {
        _customColor = selectedColor;
        _useCustomColor = true;
        _useDynamicColor = false;
      });
      await appTheme.setCustomColor(selectedColor);
      await appTheme.setUseCustomColor(true);
      await appTheme.setUseDynamicColor(false);
    }
  }
}

// 这里移除了自定义的ColorPicker组件，使用flex_color_picker包提供的组件
