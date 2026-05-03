import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class MqttCredentialsStore {
  Future<String> readUsername();
  Future<String> readPassword();
  Future<void> writeCredentials({required String username, required String password});
  Future<void> clear();
  Future<String> readUsernameForProfile(String profileId);
  Future<String> readPasswordForProfile(String profileId);
  Future<void> writeCredentialsForProfile({
    required String profileId,
    required String username,
    required String password,
  });
  Future<void> clearProfile(String profileId);
}

class SecureMqttCredentialsStore implements MqttCredentialsStore {
  static const _usernameKey = 'mqtt_username_secure';
  static const _passwordKey = 'mqtt_password_secure';

  final FlutterSecureStorage _storage;

  SecureMqttCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  String _usernameKeyForProfile(String profileId) => '${_usernameKey}_$profileId';

  String _passwordKeyForProfile(String profileId) => '${_passwordKey}_$profileId';

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

  @override
  Future<String> readUsernameForProfile(String profileId) async {
    return await _storage.read(key: _usernameKeyForProfile(profileId)) ?? '';
  }

  @override
  Future<String> readPasswordForProfile(String profileId) async {
    return await _storage.read(key: _passwordKeyForProfile(profileId)) ?? '';
  }

  @override
  Future<void> writeCredentialsForProfile({
    required String profileId,
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _usernameKeyForProfile(profileId), value: username);
    await _storage.write(key: _passwordKeyForProfile(profileId), value: password);
  }

  @override
  Future<void> clearProfile(String profileId) async {
    await _storage.delete(key: _usernameKeyForProfile(profileId));
    await _storage.delete(key: _passwordKeyForProfile(profileId));
  }
}
