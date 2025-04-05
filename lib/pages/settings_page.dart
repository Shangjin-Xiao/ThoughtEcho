import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backup_restore_page.dart';
import 'ai_settings_page.dart';
import 'tag_settings_page.dart';
import 'hitokoto_settings_page.dart';
import 'theme_settings_page.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../widgets/city_search_widget.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final String _projectUrl = 'https://github.com/Shangjin-Xiao/ThoughtEcho';
  final TextEditingController _locationController = TextEditingController();

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    if (!mounted) return;

    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接: $url')),
      );
    }
  }

  Future<void> _handleWeatherRefresh(LocationService locationService, WeatherService weatherService) async {
    if (!mounted) return;

    final position = locationService.currentPosition;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取位置信息')),
      );
      return;
    }

    await weatherService.getWeatherData(
      position.latitude,
      position.longitude,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('天气已更新')),
    );
  }

  Future<void> _handleLocationPermission(LocationService locationService, WeatherService weatherService) async {
    if (!mounted) return;

    final granted = await locationService.requestLocationPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取位置权限')),
      );
      return;
    }

    final position = await locationService.getCurrentLocation();
    if (position == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取当前位置')),
      );
      return;
    }

    await weatherService.getWeatherData(
      position.latitude,
      position.longitude,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('位置服务已启用')),
    );
  }

  void _showCitySearchDialog(BuildContext context) {
    final locationService = Provider.of<LocationService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          width: MediaQuery.of(context).size.width * 0.9,
          padding: const EdgeInsets.all(8.0),
          child: CitySearchWidget(
            initialCity: locationService.city,
            onCitySelected: (city) {
              setState(() {
                _locationController.text = locationService.getFormattedLocation();
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已选择城市: ${city.name}')),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final weatherService = Provider.of<WeatherService>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: const Text('位置与天气设置'),
                  leading: const Icon(Icons.location_on),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                SwitchListTile(
                  title: const Text('使用位置服务'),
                  subtitle: Text(
                    locationService.hasLocationPermission
                        ? '已获得位置权限'
                        : '未获得位置权限',
                    style: TextStyle(
                      fontSize: 12,
                      color: locationService.hasLocationPermission
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                  value: locationService.hasLocationPermission,
                  onChanged: (value) async {
                    if (value) {
                      await _handleLocationPermission(locationService, weatherService);
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设置位置',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text('搜索城市'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () {
                          _showCitySearchDialog(context);
                        },
                      ),
                      const SizedBox(height: 16.0),
                      Text(
                        '或手动输入位置',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      TextField(
                        controller: _locationController,
                        decoration: InputDecoration(
                          hintText: '国家,省份,城市,区县 (使用逗号分隔)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                            vertical: 12.0,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.check),
                            onPressed: () {
                              final locationString = _locationController.text.trim();
                              if (locationString.isNotEmpty) {
                                locationService.parseLocationString(locationString);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('位置已更新')),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        '当前位置: ${locationService.currentAddress ?? '未设置'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (locationService.currentAddress != null)
                  ListTile(
                    title: const Text('刷新天气'),
                    subtitle: Text(
                      '${weatherService.currentWeather ?? ""} ${weatherService.temperature ?? ""}',
                      style: const TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    leading: Icon(weatherService.getWeatherIconData()),
                    trailing: const Icon(Icons.refresh),
                    onTap: () async {
                      await _handleWeatherRefresh(locationService, weatherService);
                    },
                  ),
                const SizedBox(height: 8.0),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: const Text('应用设置'),
                  leading: const Icon(Icons.settings),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                ListTile(
                  title: const Text('主题设置'),
                  subtitle: const Text('自定义应用的外观主题'),
                  leading: const Icon(Icons.color_lens_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ThemeSettingsPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: const Text('AI设置'),
                  subtitle: const Text('配置AI分析功能'),
                  leading: const Icon(Icons.psychology_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AISettingsPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: const Text('一言设置'),
                  subtitle: const Text('自定义"每日一言"的类型'),
                  leading: const Icon(Icons.format_quote_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HitokotoSettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: const Text('内容管理'),
                  leading: const Icon(Icons.category),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                ListTile(
                  title: const Text('标签管理'),
                  subtitle: const Text('添加和编辑标签'),
                  leading: const Icon(Icons.tag),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TagSettingsPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: const Text('备份与恢复'),
                  subtitle: const Text('备份数据或从备份中恢复'),
                  leading: const Icon(Icons.backup_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BackupRestorePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                ListTile(
                  title: const Text('关于'),
                  leading: const Icon(Icons.info_outline),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: '心迹',
                      applicationVersion: '1.0.0',
                      applicationIcon: const FlutterLogo(),
                      applicationLegalese: '© 2025 Shangjin\n一款帮助你记录和分析思想的应用',
                      children: [
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () => _launchUrl(_projectUrl),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.code, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'GitHub: $_projectUrl',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}