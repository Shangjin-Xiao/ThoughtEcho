import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../utils/color_utils.dart'; // 导入颜色工具

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

  @override
  Widget build(BuildContext context) {
    final appTheme = Provider.of<AppTheme>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('主题设置')),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
                  const Text(
                    '主题模式',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildThemeModeOption(
                        context,
                        appTheme,
                        ThemeMode.light,
                        '浅色',
                        Icons.light_mode,
                      ),
                      _buildThemeModeOption(
                        context,
                        appTheme,
                        ThemeMode.dark,
                        '深色',
                        Icons.dark_mode,
                      ),
                      _buildThemeModeOption(
                        context,
                        appTheme,
                        ThemeMode.system,
                        '跟随系统',
                        Icons.brightness_auto,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
                      const Text(
                        '使用自定义主题色',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: appTheme.useCustomColor,
                        onChanged: (value) => appTheme.setUseCustomColor(value),
                      ),
                    ],
                  ),
                  if (appTheme.useCustomColor) ...[
                    const SizedBox(height: 16),
                    const Text('选择主题色'),
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
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
                          const Text(
                            '动态取色',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '从系统提取主题颜色',
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
                        value: appTheme.useDynamicColor &&
                            !appTheme.useCustomColor,
                        onChanged: (value) {
                          // 如果启用动态取色，需要禁用自定义主题色
                          if (value) {
                            appTheme.setUseCustomColor(false);
                          }
                          appTheme.setUseDynamicColor(value);
                        },
                        // 当使用自定义颜色时禁用此开关
                        activeColor: appTheme.useCustomColor
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (appTheme.useCustomColor)
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
                              '已启用自定义主题色，动态取色功能已暂时禁用',
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
                  if (!appTheme.useCustomColor && !appTheme.useDynamicColor)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.applyOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '未启用动态取色，将使用默认蓝色主题',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
                  const Text(
                    '主题工具',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '如果主题颜色显示异常，可以尝试刷新主题',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        appTheme.forceRefreshTheme();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('主题已刷新'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('刷新主题'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
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

  Widget _buildThemeModeOption(
    BuildContext context,
    AppTheme appTheme,
    ThemeMode mode,
    String label,
    IconData icon,
  ) {
    final isSelected = appTheme.themeMode == mode;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => appTheme.setThemeMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
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
              style: TextStyle(
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
    final isSelected = appTheme.customColor == color;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
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
      borderRadius: BorderRadius.circular(12),
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
    final Color initialColor = appTheme.customColor ?? Colors.blue;
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
      await appTheme.setCustomColor(selectedColor);
      await appTheme.setUseCustomColor(true);
      await appTheme.setUseDynamicColor(false);
    }
  }
}

// 这里移除了自定义的ColorPicker组件，使用flex_color_picker包提供的组件
