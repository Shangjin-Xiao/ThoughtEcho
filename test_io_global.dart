import 'dart:io';

base class MyOverrides extends IOOverrides {
  @override
  Future<List<InternetAddress>> lookup(String host, {InternetAddressType type = InternetAddressType.any}) async {
    print("MOCKED LOOKUP: $host");
    if (host == 'dns.google' || host == 'one.one.one.one' || host == 'api.open-meteo.com') {
      throw SocketException('Mocked');
    }
    return [InternetAddress('127.0.0.1')];
  }
}

void main() async {
  IOOverrides.global = MyOverrides();
  try {
    await InternetAddress.lookup('dns.google');
  } catch(e) {
    print(e);
  }
}
