import '../services/location_service.dart';

/// 预置热门城市数据模型
class PopularCity {
  final String name;
  final String englishName;
  final List<String> searchKeywords;
  final String province;
  final String country;
  final double lat;
  final double lon;
  final bool isDomestic;

  const PopularCity({
    required this.name,
    required this.englishName,
    required this.searchKeywords,
    required this.province,
    required this.country,
    required this.lat,
    required this.lon,
    this.isDomestic = true,
  });

  /// 转换为 LocationService 使用的 CityInfo
  CityInfo toCityInfo() {
    final parts =
        [country, province, name].where((part) => part.isNotEmpty).toList();
    // 去除连续重复（如 直辖市：中国, 北京市, 北京 -> 中国, 北京市）
    final deduplicatedParts = <String>[];
    for (final p in parts) {
      if (deduplicatedParts.isEmpty || deduplicatedParts.last != p) {
        deduplicatedParts.add(p);
      }
    }

    return CityInfo(
      name: name,
      fullName: deduplicatedParts.join(', '),
      lat: lat,
      lon: lon,
      country: country,
      province: province,
    );
  }

  /// 检查是否匹配搜索关键词（支持中文、英文、拼音前缀等）
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    if (name.toLowerCase().contains(q)) return true;
    if (englishName.toLowerCase().contains(q)) return true;
    if (province.toLowerCase().contains(q)) return true;
    if (country.toLowerCase().contains(q)) return true;
    for (final kw in searchKeywords) {
      if (kw.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// 常用热门城市预设集
class PopularCitiesData {
  PopularCitiesData._();

  /// 国内主要城市
  static const List<PopularCity> domestic = [
    PopularCity(
      name: '北京',
      englishName: 'Beijing',
      searchKeywords: ['beijing', 'bj', 'peking', '北京', '首都'],
      province: '北京市',
      country: '中国',
      lat: 39.9042,
      lon: 116.4074,
      isDomestic: true,
    ),
    PopularCity(
      name: '上海',
      englishName: 'Shanghai',
      searchKeywords: ['shanghai', 'sh', '上海', '魔都'],
      province: '上海市',
      country: '中国',
      lat: 31.2304,
      lon: 121.4737,
      isDomestic: true,
    ),
    PopularCity(
      name: '广州',
      englishName: 'Guangzhou',
      searchKeywords: ['guangzhou', 'gz', 'canton', '广州', '羊城'],
      province: '广东省',
      country: '中国',
      lat: 23.1291,
      lon: 113.2644,
      isDomestic: true,
    ),
    PopularCity(
      name: '深圳',
      englishName: 'Shenzhen',
      searchKeywords: ['shenzhen', 'sz', '深圳', '鹏城'],
      province: '广东省',
      country: '中国',
      lat: 22.5431,
      lon: 114.0579,
      isDomestic: true,
    ),
    PopularCity(
      name: '杭州',
      englishName: 'Hangzhou',
      searchKeywords: ['hangzhou', 'hz', '杭州'],
      province: '浙江省',
      country: '中国',
      lat: 30.2741,
      lon: 120.1551,
      isDomestic: true,
    ),
    PopularCity(
      name: '成都',
      englishName: 'Chengdu',
      searchKeywords: ['chengdu', 'cd', '成都', '蓉城'],
      province: '四川省',
      country: '中国',
      lat: 30.5728,
      lon: 104.0668,
      isDomestic: true,
    ),
    PopularCity(
      name: '南京',
      englishName: 'Nanjing',
      searchKeywords: ['nanjing', 'nj', '南京', '金陵'],
      province: '江苏省',
      country: '中国',
      lat: 32.0603,
      lon: 118.7969,
      isDomestic: true,
    ),
    PopularCity(
      name: '武汉',
      englishName: 'Wuhan',
      searchKeywords: ['wuhan', 'wh', '武汉', '江城'],
      province: '湖北省',
      country: '中国',
      lat: 30.5928,
      lon: 114.3055,
      isDomestic: true,
    ),
    PopularCity(
      name: '重庆',
      englishName: 'Chongqing',
      searchKeywords: ['chongqing', 'cq', '重庆', '山城'],
      province: '重庆市',
      country: '中国',
      lat: 29.5630,
      lon: 106.5516,
      isDomestic: true,
    ),
    PopularCity(
      name: '西安',
      englishName: 'Xi\'an',
      searchKeywords: ['xian', 'xa', '西安', '长安'],
      province: '陕西省',
      country: '中国',
      lat: 34.3416,
      lon: 108.9398,
      isDomestic: true,
    ),
    PopularCity(
      name: '苏州',
      englishName: 'Suzhou',
      searchKeywords: ['suzhou', 'sz', '苏州', '姑苏'],
      province: '江苏省',
      country: '中国',
      lat: 31.2990,
      lon: 120.5853,
      isDomestic: true,
    ),
    PopularCity(
      name: '天津',
      englishName: 'Tianjin',
      searchKeywords: ['tianjin', 'tj', '天津'],
      province: '天津市',
      country: '中国',
      lat: 39.0842,
      lon: 117.2009,
      isDomestic: true,
    ),
    PopularCity(
      name: '长沙',
      englishName: 'Changsha',
      searchKeywords: ['changsha', 'cs', '长沙', '星城'],
      province: '湖南省',
      country: '中国',
      lat: 28.2282,
      lon: 112.9388,
      isDomestic: true,
    ),
    PopularCity(
      name: '厦门',
      englishName: 'Xiamen',
      searchKeywords: ['xiamen', 'xm', 'amoy', '厦门', '鹭岛'],
      province: '福建省',
      country: '中国',
      lat: 24.4798,
      lon: 118.0894,
      isDomestic: true,
    ),
    PopularCity(
      name: '青岛',
      englishName: 'Qingdao',
      searchKeywords: ['qingdao', 'qd', 'tsingtao', '青岛', '琴岛'],
      province: '山东省',
      country: '中国',
      lat: 36.0671,
      lon: 120.3826,
      isDomestic: true,
    ),
    PopularCity(
      name: '香港',
      englishName: 'Hong Kong',
      searchKeywords: ['hongkong', 'hk', '香港'],
      province: '香港特别行政区',
      country: '中国',
      lat: 22.3193,
      lon: 114.1694,
      isDomestic: true,
    ),
    PopularCity(
      name: '台北',
      englishName: 'Taipei',
      searchKeywords: ['taipei', 'tb', '台北'],
      province: '台湾省',
      country: '中国',
      lat: 25.0330,
      lon: 121.5654,
      isDomestic: true,
    ),
    PopularCity(
      name: '澳门',
      englishName: 'Macau',
      searchKeywords: ['macau', 'mo', 'macao', '澳门'],
      province: '澳门特别行政区',
      country: '中国',
      lat: 22.1987,
      lon: 113.5439,
      isDomestic: true,
    ),
  ];

  /// 国际主要城市
  static const List<PopularCity> international = [
    PopularCity(
      name: '东京',
      englishName: 'Tokyo',
      searchKeywords: ['tokyo', 'japan', '东京', '東京'],
      province: '东京都',
      country: '日本',
      lat: 35.6762,
      lon: 139.6503,
      isDomestic: false,
    ),
    PopularCity(
      name: '伦敦',
      englishName: 'London',
      searchKeywords: ['london', 'uk', 'england', '伦敦'],
      province: '英格兰',
      country: '英国',
      lat: 51.5074,
      lon: -0.1278,
      isDomestic: false,
    ),
    PopularCity(
      name: '纽约',
      englishName: 'New York',
      searchKeywords: ['newyork', 'ny', 'nyc', '纽约'],
      province: '纽约州',
      country: '美国',
      lat: 40.7128,
      lon: -74.0060,
      isDomestic: false,
    ),
    PopularCity(
      name: '巴黎',
      englishName: 'Paris',
      searchKeywords: ['paris', 'france', '巴黎'],
      province: '法兰西岛',
      country: '法国',
      lat: 48.8566,
      lon: 2.3522,
      isDomestic: false,
    ),
    PopularCity(
      name: '新加坡',
      englishName: 'Singapore',
      searchKeywords: ['singapore', 'sg', '新加坡', '狮城'],
      province: '新加坡',
      country: '新加坡',
      lat: 1.3521,
      lon: 103.8198,
      isDomestic: false,
    ),
    PopularCity(
      name: '悉尼',
      englishName: 'Sydney',
      searchKeywords: ['sydney', 'australia', '悉尼'],
      province: '新南威尔士州',
      country: '澳大利亚',
      lat: -33.8688,
      lon: 151.2093,
      isDomestic: false,
    ),
    PopularCity(
      name: '首尔',
      englishName: 'Seoul',
      searchKeywords: ['seoul', 'korea', '首尔', 'ソウル', '汉城'],
      province: '首尔特别市',
      country: '韩国',
      lat: 37.5665,
      lon: 126.9780,
      isDomestic: false,
    ),
    PopularCity(
      name: '旧金山',
      englishName: 'San Francisco',
      searchKeywords: ['sanfrancisco', 'sf', '旧金山', '三藩市'],
      province: '加利福尼亚州',
      country: '美国',
      lat: 37.7749,
      lon: -122.4194,
      isDomestic: false,
    ),
    PopularCity(
      name: '多伦多',
      englishName: 'Toronto',
      searchKeywords: ['toronto', 'canada', '多伦多'],
      province: '安大略省',
      country: '加拿大',
      lat: 43.6532,
      lon: -79.3832,
      isDomestic: false,
    ),
    PopularCity(
      name: '柏林',
      englishName: 'Berlin',
      searchKeywords: ['berlin', 'germany', '柏林'],
      province: '柏林',
      country: '德国',
      lat: 52.5200,
      lon: 13.4050,
      isDomestic: false,
    ),
  ];

  /// 所有热门城市合集
  static List<PopularCity> get all => [...domestic, ...international];

  /// 本地即时模糊搜索
  static List<PopularCity> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return all.where((city) => city.matches(trimmed)).toList();
  }
}
