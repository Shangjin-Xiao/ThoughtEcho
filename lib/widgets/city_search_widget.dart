import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/location_service.dart';

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
  
  @override
  void initState() {
    super.initState();
    if (widget.initialCity != null) {
      _searchController.text = widget.initialCity!;
    }
  }
  
  @override
  void dispose() {
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
              setState(() {
                _isSearchActive = value.isNotEmpty;
              });
              if (value.isNotEmpty) {
                locationService.searchCity(value);
              }
            },
          ),
        ),
        
        // 搜索结果或热门城市
        Expanded(
          child: _isSearchActive || locationService.isSearching
              ? _buildSearchResults(locationService)
              : _buildPopularCities(locationService, theme),
        ),
        
        // 当前位置按钮
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.my_location),
            label: const Text('使用当前位置'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () async {
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
                  const SnackBar(content: Text('无法获取当前位置，请检查位置权限')),
                );
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
    
    if (locationService.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('没有找到匹配的城市'),
            const SizedBox(height: 8),
            Text(
              '尝试使用不同的关键词或城市名称',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
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
          onTap: () {
            locationService.setSelectedCity(city);
            widget.onCitySelected(city);
            Navigator.of(context).pop();
          },
        );
      },
    );
  }
  
  Widget _buildPopularCities(LocationService locationService, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            '热门城市',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2.5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: locationService.popularCities.length,
            itemBuilder: (context, index) {
              final city = locationService.popularCities[index];
              return InkWell(
                onTap: () {
                  locationService.setSelectedCity(city);
                  widget.onCitySelected(city);
                  Navigator.of(context).pop();
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    city.name,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}