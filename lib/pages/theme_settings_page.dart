import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';

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
      appBar: AppBar(
        title: const Text('主题设置'),
      ),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
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
                    style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold,
                    ),
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
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
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
      onTap: () => appTheme.setCustomColor(color),
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
                color: colorScheme.primary.withOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
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
    final colorScheme = Theme.of(context).colorScheme;
    final Color? result = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择自定义颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: appTheme.customColor ?? Colors.blue,
            onColorChanged: (color) {
              Navigator.of(context).pop(color);
            },
            colorScheme: colorScheme,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (result != null) {
      appTheme.setCustomColor(result);
    }
  }
}

// 简单的颜色选择器组件
class ColorPicker extends StatefulWidget {
  final Color pickerColor;
  final ValueChanged<Color> onColorChanged;
  final ColorScheme colorScheme;

  const ColorPicker({
    super.key,
    required this.pickerColor,
    required this.onColorChanged,
    required this.colorScheme,
  });

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late Color _currentColor;
  
  @override
  void initState() {
    super.initState();
    _currentColor = widget.pickerColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        // 颜色预览
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _currentColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.colorScheme.outline,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _currentColor.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // RGB滑块
        _buildColorSlider(
          label: 'R',
          value: _currentColor.red.toDouble(),
          color: Colors.red,
          onChanged: (value) {
            setState(() {
              _currentColor = _currentColor.withRed(value.toInt());
            });
          },
        ),
        _buildColorSlider(
          label: 'G',
          value: _currentColor.green.toDouble(),
          color: Colors.green,
          onChanged: (value) {
            setState(() {
              _currentColor = _currentColor.withGreen(value.toInt());
            });
          },
        ),
        _buildColorSlider(
          label: 'B',
          value: _currentColor.blue.toDouble(),
          color: Colors.blue,
          onChanged: (value) {
            setState(() {
              _currentColor = _currentColor.withBlue(value.toInt());
            });
          },
        ),
        const SizedBox(height: 16),
        // 确认按钮
        ElevatedButton(
          onPressed: () => widget.onColorChanged(_currentColor),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildColorSlider({
    required String label,
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(label),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(value.toInt().toString()),
        ),
      ],
    );
  }
} 