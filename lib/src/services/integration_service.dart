import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:e_metrics_iot/src/data/integration_sync_item.dart';
import 'package:e_metrics_iot/src/data/metric_model.dart';
import 'package:e_metrics_iot/src/data/metric_repository.dart';
import 'package:e_metrics_iot/src/providers/integration_settings_provider.dart';
import 'package:http/http.dart' as http;

class IntegrationSubmitResult {
  final bool delivered;
  final bool queued;

  const IntegrationSubmitResult({required this.delivered, required this.queued});
}

class IntegrationFlushResult {
  final int deliveredCount;
  final int failedCount;

  const IntegrationFlushResult({
    required this.deliveredCount,
    required this.failedCount,
  });
}

class IntegrationService {
  final MetricRepository _repository;
  final Future<IntegrationSettings> Function() _loadSettings;
  final http.Client _client;

  IntegrationService({
    required MetricRepository repository,
    required Future<IntegrationSettings> Function() loadSettings,
    http.Client? client,
  }) : _repository = repository,
       _loadSettings = loadSettings,
       _client = client ?? http.Client();

  Future<IntegrationSubmitResult> submitMetric(
    Metric metric, {
    String? profileId,
  }) async {
    final settings = await _loadSettings();
    if (!_isReady(settings)) {
      return const IntegrationSubmitResult(delivered: false, queued: false);
    }

    final payload = _buildPayload(metric.toMap(), profileId: profileId);
    try {
      await _postPayload(settings, payload);
      return const IntegrationSubmitResult(delivered: true, queued: false);
    } catch (e, st) {
      developer.log(
        'Falha ao enviar métrica; enfileirando para reenvio',
        name: 'IntegrationService',
        error: e,
        stackTrace: st,
      );
      await _repository.enqueueMetricSync(metric, profileId: profileId);
      return const IntegrationSubmitResult(delivered: false, queued: true);
    }
  }

  Future<IntegrationFlushResult> flushPendingQueue() async {
    final settings = await _loadSettings();
    if (!_isReady(settings)) {
      return const IntegrationFlushResult(deliveredCount: 0, failedCount: 0);
    }

    final pendingItems = await _repository.getPendingMetricSyncItems();
    if (pendingItems.isEmpty) {
      return const IntegrationFlushResult(deliveredCount: 0, failedCount: 0);
    }

    var deliveredCount = 0;
    var failedCount = 0;
    final deliveredIds = <int>[];

    for (final item in pendingItems) {
      try {
        await _postPayload(settings, _queueItemPayload(item));
        deliveredIds.add(item.id);
        deliveredCount++;
      } catch (error) {
        failedCount++;
        await _repository.markMetricSyncFailed(item.id, error.toString());
      }
    }

    await _repository.markMetricSyncSucceeded(deliveredIds);
    return IntegrationFlushResult(
      deliveredCount: deliveredCount,
      failedCount: failedCount,
    );
  }

  bool _isReady(IntegrationSettings settings) {
    return settings.enabled && settings.baseUrl.isNotEmpty;
  }

  Uri _buildUri(IntegrationSettings settings) {
    final baseUri = Uri.parse(settings.baseUrl);
    final path = settings.metricsPath.startsWith('/')
        ? settings.metricsPath.substring(1)
        : settings.metricsPath;
    return baseUri.resolve(path);
  }

  Map<String, dynamic> _buildPayload(
    Map<String, dynamic> payload, {
    String? profileId,
  }) {
    return {
      ...payload,
      'source_profile_id': profileId,
      'exported_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _queueItemPayload(IntegrationSyncItem item) {
    final decoded = jsonDecode(item.payload) as Map<String, dynamic>;
    return _buildPayload(decoded, profileId: item.profileId);
  }

  Future<void> _postPayload(
    IntegrationSettings settings,
    Map<String, dynamic> payload,
  ) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (settings.apiKey.isNotEmpty) {
      headers['x-api-key'] = settings.apiKey;
    }
    if (settings.oauthEnabled && settings.oauthAccessToken.isNotEmpty) {
      headers['Authorization'] =
          '${settings.oauthTokenType} ${settings.oauthAccessToken}';
    }

    final response = await _client
        .post(
          _buildUri(settings),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Falha REST ${response.statusCode}: ${response.body}');
    }
  }
}