import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/location_service.dart';

void main() {
  group('LocationService.formatLocationForDisplay', () {
    test('formats full CSV correctly', () {
      const input = 'China,Beijing,Beijing,Chaoyang';
      expect(
        LocationService.formatLocationForDisplay(input),
        'Beijing·Chaoyang',
      );
    });

    test('formats CSV with missing district correctly', () {
      const input = 'China,Beijing,Beijing,';
      expect(LocationService.formatLocationForDisplay(input), 'Beijing');
    });

    test('formats CSV with missing district (no trailing comma) correctly', () {
      const input = 'China,Beijing,Beijing';
      expect(LocationService.formatLocationForDisplay(input), 'Beijing');
    });

    test(
      'formats CSV with missing district and different province correctly',
      () {
        const input = 'China,Zhejiang,Hangzhou,';
        expect(
          LocationService.formatLocationForDisplay(input),
          'Zhejiang·Hangzhou',
        );
      },
    );

    test('formats CSV with missing city but has district (Japan style)', () {
      const input = 'Japan,Tokyo,,Shinjuku';
      expect(LocationService.formatLocationForDisplay(input), 'Tokyo·Shinjuku');
    });

    test('formats Japan prefecture + ward correctly', () {
      const input = '日本,东京,新宿区,';
      expect(LocationService.formatLocationForDisplay(input), '东京·新宿区');
    });

    test('formats CSV with missing city and district correctly', () {
      const input = 'Japan,Chiba,,';
      expect(LocationService.formatLocationForDisplay(input), 'Japan·Chiba');
    });

    test('formats CSV with missing city, district, province correctly', () {
      const input = 'Japan,,,';
      expect(LocationService.formatLocationForDisplay(input), 'Japan');
    });

    test('returns empty string for empty CSV', () {
      const input = ',,,';
      expect(LocationService.formatLocationForDisplay(input), '');
    });

    test('returns original string for non-CSV', () {
      const input = 'Some Random String';
      expect(
        LocationService.formatLocationForDisplay(input),
        'Some Random String',
      );
    });

    test('returns empty string for null', () {
      expect(LocationService.formatLocationForDisplay(null), '');
    });

    test('returns empty string for empty string', () {
      expect(LocationService.formatLocationForDisplay(''), '');
    });

    test('returns empty string for pending marker', () {
      expect(
        LocationService.formatLocationForDisplay(
          LocationService.kAddressPending,
        ),
        '',
      );
    });

    test('returns empty string for failed marker', () {
      expect(
        LocationService.formatLocationForDisplay(
          LocationService.kAddressFailed,
        ),
        '',
      );
    });
  });

  group('LocationService.getDisplayLocation', () {
    test(
      'keeps English city and district unchanged when locale is English',
      () {
        final service = LocationService();
        service.currentLocaleCode = 'en';
        service.parseLocationString('Japan,Tokyo,Asakusa,Taito');

        expect(service.getDisplayLocation(), 'Asakusa · Taito');
      },
    );

    test('does not append Chinese 市 suffix in English locale', () {
      final service = LocationService();
      service.currentLocaleCode = 'en';
      service.parseLocationString('China,Guangdong,Dongguan,');

      expect(service.getDisplayLocation(), 'Guangdong · Dongguan');
    });

    test('Chinese locale still applies Chinese formatting rules', () {
      final service = LocationService();
      service.currentLocaleCode = 'zh';
      service.parseLocationString('中国,广东,东莞,南城区');

      expect(service.getDisplayLocation(), '东莞市·南城区');
    });

    test('Chinese locale does not append 市 to 都/府/道/自治州 suffixes', () {
      final service = LocationService();
      service.currentLocaleCode = 'zh';

      service.parseLocationString('日本,东京都,东京都,');
      expect(service.getDisplayLocation(), '东京都');

      service.parseLocationString('日本,京都府,京都市,');
      expect(service.getDisplayLocation(), '京都府·京都市');

      service.parseLocationString('日本,北海道,札幌,');
      expect(service.getDisplayLocation(), '北海道·札幌市');

      service.parseLocationString('美国,纽约州,纽约,');
      expect(service.getDisplayLocation(), '纽约州·纽约市');

      service.parseLocationString('中国,浙江省,杭州,');
      expect(service.getDisplayLocation(), '浙江省·杭州市');

      service.parseLocationString('中国,广东省,广州,');
      expect(service.getDisplayLocation(), '广东省·广州市');

      service.parseLocationString('中国,四川省,凉山彝族自治州,');
      expect(service.getDisplayLocation(), '四川省·凉山彝族自治州');
    });

    test('sanitizes Nominatim multi-variant delimiter strings', () {
      final service = LocationService();
      service.currentLocaleCode = 'zh';

      service.parseLocationString('美国;美國,纽约州;紐約州,纽约;紐約,');
      expect(service.getDisplayLocation(), '纽约州·纽约市');
      expect(service.country, '美国');
      expect(service.province, '纽约州');
      expect(service.city, '纽约');

      service.parseLocationString('韩国 / 南韓,,首尔特别市,');
      expect(service.getDisplayLocation(), '首尔特别市');
      expect(service.country, '韩国');
    });
  });

  group('LocationService.cleanGeocodingText', () {
    test('cleans semicolon and slash delimiters', () {
      expect(LocationService.cleanGeocodingText('纽约;紐約'), '纽约');
      expect(LocationService.cleanGeocodingText('大倫敦;大伦敦'), '大倫敦');
      expect(LocationService.cleanGeocodingText('东京都/東京都'), '东京都');
      expect(LocationService.cleanGeocodingText('韩国 / 南韓'), '韩国');
      expect(LocationService.cleanGeocodingText('法国;法國'), '法国');
      expect(LocationService.cleanGeocodingText('澳大利亚;澳洲'), '澳大利亚');
      expect(
        LocationService.cleanGeocodingText('法兰西岛大区 / 法蘭西島大區'),
        '法兰西岛大区',
      );
      expect(
          LocationService.cleanGeocodingText('Grand Londres'), 'Grand Londres');
      expect(LocationService.cleanGeocodingText(''), '');
      expect(LocationService.cleanGeocodingText(null), '');
    });
  });

  group('LocationService.formatPoiForDisplay', () {
    test('拼上最细一级行政区，区县在前地点名在后', () {
      expect(
        LocationService.formatPoiForDisplay('芝公园', '日本,东京都,,港区'),
        '港区·芝公园',
      );
    });

    test('没有区县时退到城市', () {
      expect(
        LocationService.formatPoiForDisplay('西湖音乐喷泉', '中国,浙江省,杭州市,'),
        '杭州市·西湖音乐喷泉',
      );
    });

    test('地点名和行政区同名时不重复', () {
      expect(
        LocationService.formatPoiForDisplay('港区', '日本,东京都,,港区'),
        '港区',
      );
    });

    test('没有地址时只显示地点名', () {
      expect(LocationService.formatPoiForDisplay('故宫博物院', null), '故宫博物院');
      expect(LocationService.formatPoiForDisplay('故宫博物院', ''), '故宫博物院');
    });

    test('地址是待解析/解析失败标记时只显示地点名', () {
      expect(
        LocationService.formatPoiForDisplay(
          '故宫博物院',
          LocationService.kAddressPending,
        ),
        '故宫博物院',
      );
      expect(
        LocationService.formatPoiForDisplay(
          '故宫博物院',
          LocationService.kAddressFailed,
        ),
        '故宫博物院',
      );
    });

    test('没有地点名时退回行政区显示，老笔记显示不变', () {
      expect(
        LocationService.formatPoiForDisplay(
            null, 'China,Beijing,Beijing,Chaoyang'),
        'Beijing·Chaoyang',
      );
      expect(
        LocationService.formatPoiForDisplay(
            '   ', 'China,Beijing,Beijing,Chaoyang'),
        'Beijing·Chaoyang',
      );
    });
  });

  group('LocationService.buildStorageLocation', () {
    test('拼成逗号分隔的入库格式，而不是给人看的 formatted_address', () {
      final address = <String, String?>{
        'country': 'China',
        'province': 'Beijing',
        'city': 'Beijing',
        'district': 'Chaoyang',
        'formatted_address': 'China, Beijing, Beijing, Chaoyang',
      };

      final stored = LocationService.buildStorageLocation(address);

      expect(stored, 'China,Beijing,Beijing,Chaoyang');
      // 拼出来的串必须能被展示函数解析回去
      expect(
          LocationService.formatLocationForDisplay(stored), 'Beijing·Chaoyang');
    });

    test('缺区县时留空位，段数不变', () {
      expect(
        LocationService.buildStorageLocation(<String, String?>{
          'country': '中国',
          'province': '浙江省',
          'city': '杭州市',
        }),
        '中国,浙江省,杭州市,',
      );
    });

    test('没有任何行政区时返回 null，让调用方退回坐标', () {
      expect(LocationService.buildStorageLocation(null), isNull);
      expect(LocationService.buildStorageLocation(const <String, String?>{}),
          isNull);
      expect(
        LocationService.buildStorageLocation(<String, String?>{
          'country': '',
          'province': '',
          'city': '',
          'district': '朝阳区',
        }),
        isNull,
      );
    });
  });
}
