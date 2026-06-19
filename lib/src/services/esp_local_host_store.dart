import 'package:shared_preferences/shared_preferences.dart';

class EspLocalHostStore {
  static const _espLocalHostKey = 'esp_local_host';
  static const defaultHost = '192.168.4.1';

  const EspLocalHostStore();

  Future<String> loadHost() async {
    final prefs = await SharedPreferences.getInstance();
    final host = (prefs.getString(_espLocalHostKey) ?? defaultHost).trim();
    return host.isEmpty ? defaultHost : host;
  }

  Future<void> saveHost(String host) async {
    final normalized = host.trim();
    if (normalized.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_espLocalHostKey, normalized);
  }
}
