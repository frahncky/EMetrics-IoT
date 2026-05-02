import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class MqttCredentialsStore {
  Future<String> readUsername();
  Future<String> readPassword();
  Future<void> writeCredentials({required String username, required String password});
  Future<void> clear();
}

class SecureMqttCredentialsStore implements MqttCredentialsStore {
  static const _usernameKey = 'mqtt_username_secure';
  static const _passwordKey = 'mqtt_password_secure';

  final FlutterSecureStorage _storage;

  SecureMqttCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String> readUsername() async {
    return await _storage.read(key: _usernameKey) ?? '';
  }

  @override
  Future<String> readPassword() async {
    return await _storage.read(key: _passwordKey) ?? '';
  }

  @override
  Future<void> writeCredentials({
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
