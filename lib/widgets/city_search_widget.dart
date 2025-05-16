import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async'; // 导入 Timer
import '../services/location_service.dart';
import '../utils/color_utils.dart'; // Import color_utils

class CitySearchWidget extends StatefulWidget {
  final Function(CityInfo) onCitySelected;
  final String? initialCity;

  const CitySearchWidget({
    super.key,
    required this.onCitySelected,
    this.initialCity,
  });

  @override
  State<CitySearchWidget> createState() => _CitySearchWidgetState();
}

class _CitySearchWidgetState extends State<CitySearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchActive = false;
  Timer? _debounce; // 添加防抖计时器
  final Duration _debounceDuration = const Duration(milliseconds: 500); // 防抖延迟时间

  @override
  void initState() {
    super.initState();
    if (widget.initialCity != null) {
      _searchController.text = widget.initialCity!;
    }
  }
  
  @override
  void dispose() {
    _debounce?.cancel(); // 取消计时器
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索城市...',
              prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
              suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: theme.colorScheme.primary),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _isSearchActive = false;
                      });
                    },
                  )
                : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.0),
                borderSide: BorderSide(color: theme.colorScheme.primary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.0),
                borderSide: BorderSide(color: theme.colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.0),
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 2.0),
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
            ),
            onChanged: (value) {
              // 取消之前的计时器
              _debounce?.cancel();
              
              // 更新搜索状态，但不立即搜索
              setState(() {
                _isSearchActive = value.isNotEmpty;
                // 如果输入为空，立即清空结果并停止搜索状态
                if (!_isSearchActive) {
                  locationService.clearSearchResults(); // 需要在 LocationService 添加此方法
                }
              });

              // 如果输入不为空，启动新的计时器
              if (_isSearchActive) {
                _debounce = Timer(_debounceDuration, () {
                  // 只有在计时器触发时才执行搜索
                  // 检查 context 是否仍然有效
                  if (mounted) {
                     final currentQuery = _searchController.text;
                     // 再次检查输入是否为空，防止延迟期间用户清空输入
                     if (currentQuery.isNotEmpty) {
                        locationService.searchCity(currentQuery);
                     } else {
                        locationService.clearSearchResults(); // 清空结果
                     }
                  }
                });
              }
            },
          ),
        ),
        
        // 搜索结果
        Expanded(
          child: _buildSearchResults(locationService),
        ),
        
        // 当前位置按钮
        if (locationService.isLocationServiceEnabled)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.my_location),
              label: const Text('使用当前位置'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () async {
                try {
                  final position = await locationService.getCurrentLocation();
                  if (position != null && context.mounted) {
                    Navigator.of(context).pop();
                    widget.onCitySelected(CityInfo(
                      name: locationService.city ?? '未知城市',
                      fullName: locationService.getFormattedLocation(),
                      lat: position.latitude,
                      lon: position.longitude,
                      country: locationService.country ?? '未知国家',
                      province: locationService.province ?? '未知省份',
                    ));
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('无法获取当前位置，请确保已授予位置权限'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('获取位置时发生错误，请稍后重试'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              },
            ),
          ),
      ],
    );
  }
  
  Widget _buildSearchResults(LocationService locationService) {
    if (locationService.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_isSearchActive && locationService.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('没有找到匹配的城市'),
            const SizedBox(height: 8),
            if (!locationService.isLocationServiceEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  '提示：当前设备的定位服务已关闭，但您仍可以手动搜索城市',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.applyOpacity(0.6), // MODIFIED
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Text(
                '尝试使用不同的关键词或城市名称',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.applyOpacity(0.6), // MODIFIED
                ),
              ),
          ],
        ),
      );
    }

    if (!_isSearchActive) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('输入城市名称开始搜索'),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: locationService.searchResults.length,
      itemBuilder: (context, index) {
        final city = locationService.searchResults[index];
        return ListTile(
          title: Text(city.name),
          subtitle: Text(city.fullName),
          leading: const Icon(Icons.location_city),
          onTap: () async {
            // 只调用回调
            await widget.onCitySelected(city);
          },
        );
      },
    );
  }
}