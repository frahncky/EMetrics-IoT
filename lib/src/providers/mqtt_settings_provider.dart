import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mqtt_credentials_store.dart';

class MqttProfileSummary {
  final String id;
  final String name;
  final String broker;
  final String topic;

  const MqttProfileSummary({
    required this.id,
    required this.name,
    required this.broker,
    required this.topic,
  });
}

class MqttSettings {
  final String profileId;
  final String profileName;
  final String broker;
  final int port;
  final String clientId;
  final String username;
  final String password;
  final String topic;
  final String requestTopic;
  final bool useTls;

  const MqttSettings({
    required this.profileId,
    required this.profileName,
    required this.broker,
    required this.port,
    required this.clientId,
    required this.username,
    required this.password,
    required this.topic,
    required this.requestTopic,
    required this.useTls,
  });

  MqttSettings copyWith({
    String? profileId,
    String? profileName,
    String? broker,
    int? port,
    String? clientId,
    String? username,
    String? password,
    String? topic,
    String? requestTopic,
    bool? useTls,
  }) {
    return MqttSettings(
      profileId: profileId ?? this.profileId,
      profileName: profileName ?? this.profileName,
      broker: broker ?? this.broker,
      port: port ?? this.port,
      clientId: clientId ?? this.clientId,
      username: username ?? this.username,
      password: password ?? this.password,
      topic: topic ?? this.topic,
      requestTopic: requestTopic ?? this.requestTopic,
      useTls: useTls ?? this.useTls,
    );
  }
}

/// Gerenciador de configurações MQTT com suporte a múltiplos perfis.
///
/// Persiste perfis em [SharedPreferences] e credenciais no
/// [MqttCredentialsStore] (keychain/keystore). Inclui migração automática
/// de configurações legacy (chaves antigas `mqtt_username`/`mqtt_password`).
class MqttSettingsNotifier extends StateNotifier<MqttSettings> {
  static const _profilesKey = 'mqtt_profiles_v2';
  static const _activeProfileIdKey = 'mqtt_active_profile_id';
  static const _brokerKey = 'mqtt_broker';
  static const _portKey = 'mqtt_port';
  static const _clientIdKey = 'mqtt_client_id';
  static const _topicKey = 'mqtt_topic';
  static const _requestTopicKey = 'mqtt_request_topic';
  static const _useTlsKey = 'mqtt_use_tls';

  // Legacy keys kept only for one-time migration.
  static const _legacyUsernameKey = 'mqtt_username';
  static const _legacyPasswordKey = 'mqtt_password';

  final MqttCredentialsStore _credentialsStore;

  MqttSettingsNotifier(this._credentialsStore)
      : super(
          const MqttSettings(
            profileId: 'default',
            profileName: 'Dispositivo principal',
            broker: 'test.mosquitto.org',
            port: 1883,
            clientId: 'emetrics_app',
            username: '',
            password: '',
            topic: 'emetrics/pzem',
            requestTopic: 'emetrics/pzem/history/request',
            useTls: false,
          ),
        ) {
    load();
  }

  Future<List<MqttProfileSummary>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await _readProfiles(prefs);
    return profiles.map((profile) {
      return MqttProfileSummary(
        id: profile.profileId,
        name: profile.profileName,
        broker: profile.broker,
        topic: profile.topic,
      );
    }).toList();
  }

  Future<MqttSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await _readProfiles(prefs);
    final activeId = prefs.getString(_activeProfileIdKey) ?? profiles.first.profileId;
    final baseState = profiles.firstWhere(
      (profile) => profile.profileId == activeId,
      orElse: () => profiles.first,
    );

    String username = await _credentialsStore.readUsernameForProfile(baseState.profileId);
    String password = await _credentialsStore.readPasswordForProfile(baseState.profileId);

    if (baseState.profileId == 'default' && username.isEmpty && password.isEmpty) {
      // Migração legacy: move credenciais das SharedPreferences antigas
      // (chaves 'mqtt_username'/'mqtt_password') para o MqttCredentialsStore
      // seguro e remove as chaves legadas para não serem lidas novamente.
      final legacyUsername = prefs.getString(_legacyUsernameKey) ?? '';
      final legacyPassword = prefs.getString(_legacyPasswordKey) ?? '';
      if (legacyUsername.isNotEmpty || legacyPassword.isNotEmpty) {
        username = legacyUsername;
        password = legacyPassword;
        await _credentialsStore.writeCredentialsForProfile(
          profileId: baseState.profileId,
          username: legacyUsername,
          password: legacyPassword,
        );
        await _credentialsStore.writeCredentials(
          username: legacyUsername,
          password: legacyPassword,
        );
        await prefs.remove(_legacyUsernameKey);
        await prefs.remove(_legacyPasswordKey);
      }
    }

    final loadedState = baseState.copyWith(username: username, password: password);
    await _persistActiveSnapshot(prefs, loadedState);

    if (mounted) {
      state = loadedState;
    }
    return loadedState;
  }

  Future<void> update({
    required String broker,
    required int port,
    required String clientId,
    required String username,
    required String password,
    required String topic,
    required String requestTopic,
    required bool useTls,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nextState = state.copyWith(
      broker: broker.trim(),
      port: port,
      clientId: clientId.trim(),
      username: username.trim(),
      password: password,
      topic: topic.trim(),
      requestTopic: requestTopic.trim(),
      useTls: useTls,
    );
    state = nextState;

    final profiles = await _readProfiles(prefs);
    final updatedProfiles = profiles.map((profile) {
      if (profile.profileId != nextState.profileId) {
        return profile;
      }
      return nextState.copyWith(username: '', password: '');
    }).toList();
    await _writeProfiles(prefs, updatedProfiles);
    await _credentialsStore.writeCredentialsForProfile(
      profileId: nextState.profileId,
      username: nextState.username,
      password: nextState.password,
    );
    await _persistActiveSnapshot(prefs, nextState);

    state = nextState;
  }

  Future<MqttSettings> createProfile({required String name}) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmedName = name.trim();
    final profileId = DateTime.now().microsecondsSinceEpoch.toString();
    final profile = state.copyWith(
      profileId: profileId,
      profileName: trimmedName.isEmpty ? 'Novo dispositivo' : trimmedName,
      username: '',
      password: '',
    );
    final profiles = await _readProfiles(prefs);
    profiles.add(profile.copyWith(username: '', password: ''));
    await _writeProfiles(prefs, profiles);
    await prefs.setString(_activeProfileIdKey, profileId);
    await _credentialsStore.writeCredentialsForProfile(
      profileId: profileId,
      username: state.username,
      password: state.password,
    );
    final loadedProfile = profile.copyWith(
      username: state.username,
      password: state.password,
    );
    await _persistActiveSnapshot(prefs, loadedProfile);
    state = loadedProfile;
    return loadedProfile;
  }

  Future<MqttSettings> selectProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await _readProfiles(prefs);
    final profile = profiles.firstWhere((item) => item.profileId == profileId);
    final username = await _credentialsStore.readUsernameForProfile(profile.profileId);
    final password = await _credentialsStore.readPasswordForProfile(profile.profileId);
    final loadedProfile = profile.copyWith(username: username, password: password);
    await prefs.setString(_activeProfileIdKey, profileId);
    await _persistActiveSnapshot(prefs, loadedProfile);
    state = loadedProfile;
    return loadedProfile;
  }

  Future<MqttSettings> renameActiveProfile(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final nextState = state.copyWith(
      profileName: name.trim().isEmpty ? state.profileName : name.trim(),
    );
    final profiles = await _readProfiles(prefs);
    final updatedProfiles = profiles.map((profile) {
      if (profile.profileId != nextState.profileId) {
        return profile;
      }
      return nextState.copyWith(username: '', password: '');
    }).toList();
    await _writeProfiles(prefs, updatedProfiles);
    await _persistActiveSnapshot(prefs, nextState);
    state = nextState;
    return nextState;
  }

  Future<MqttSettings> deleteProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await _readProfiles(prefs);
    if (profiles.length == 1) {
      throw StateError('Mantenha ao menos um perfil de dispositivo.');
    }
    profiles.removeWhere((profile) => profile.profileId == profileId);
    await _writeProfiles(prefs, profiles);
    await _credentialsStore.clearProfile(profileId);
    final fallbackProfile = profiles.first;
    await prefs.setString(_activeProfileIdKey, fallbackProfile.profileId);
    return selectProfile(fallbackProfile.profileId);
  }

  Future<List<MqttSettings>> _readProfiles(SharedPreferences prefs) async {
    final rawProfiles = prefs.getString(_profilesKey);
    if (rawProfiles == null || rawProfiles.isEmpty) {
      final migratedProfile = MqttSettings(
        profileId: 'default',
        profileName: 'Dispositivo principal',
        broker: prefs.getString(_brokerKey) ?? state.broker,
        port: prefs.getInt(_portKey) ?? state.port,
        clientId: prefs.getString(_clientIdKey) ?? state.clientId,
        username: '',
        password: '',
        topic: prefs.getString(_topicKey) ?? state.topic,
        requestTopic: prefs.getString(_requestTopicKey) ?? state.requestTopic,
        useTls: prefs.getBool(_useTlsKey) ?? state.useTls,
      );
      await _writeProfiles(prefs, [migratedProfile]);
      await prefs.setString(_activeProfileIdKey, migratedProfile.profileId);
      return [migratedProfile];
    }

    final decoded = jsonDecode(rawProfiles) as List<dynamic>;
    return decoded
        .map((item) => _settingsFromStorage(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeProfiles(
    SharedPreferences prefs,
    List<MqttSettings> profiles,
  ) async {
    final encoded = profiles
        .map((profile) => _settingsToStorage(profile))
        .toList(growable: false);
    await prefs.setString(_profilesKey, jsonEncode(encoded));
  }

  Future<void> _persistActiveSnapshot(
    SharedPreferences prefs,
    MqttSettings settings,
  ) async {
    await prefs.setString(_activeProfileIdKey, settings.profileId);
    await prefs.setString(_brokerKey, settings.broker);
    await prefs.setInt(_portKey, settings.port);
    await prefs.setString(_clientIdKey, settings.clientId);
    await prefs.setString(_topicKey, settings.topic);
    await prefs.setString(_requestTopicKey, settings.requestTopic);
    await prefs.setBool(_useTlsKey, settings.useTls);
    await _credentialsStore.writeCredentials(
      username: settings.username,
      password: settings.password,
    );
  }

  Map<String, dynamic> _settingsToStorage(MqttSettings settings) {
    return {
      'profileId': settings.profileId,
      'profileName': settings.profileName,
      'broker': settings.broker,
      'port': settings.port,
      'clientId': settings.clientId,
      'topic': settings.topic,
      'requestTopic': settings.requestTopic,
      'useTls': settings.useTls,
    };
  }

  MqttSettings _settingsFromStorage(Map<String, dynamic> map) {
    return MqttSettings(
      profileId: map['profileId'] as String? ?? 'default',
      profileName: map['profileName'] as String? ?? 'Dispositivo principal',
      broker: map['broker'] as String? ?? state.broker,
      port: map['port'] as int? ?? state.port,
      clientId: map['clientId'] as String? ?? state.clientId,
      username: '',
      password: '',
      topic: map['topic'] as String? ?? state.topic,
      requestTopic: map['requestTopic'] as String? ?? state.requestTopic,
      useTls: map['useTls'] as bool? ?? state.useTls,
    );
  }
}

final mqttCredentialsStoreProvider = Provider<MqttCredentialsStore>(
  (ref) => SecureMqttCredentialsStore(),
);

final mqttSettingsProvider =
    StateNotifierProvider<MqttSettingsNotifier, MqttSettings>(
  (ref) => MqttSettingsNotifier(ref.watch(mqttCredentialsStoreProvider)),
);
