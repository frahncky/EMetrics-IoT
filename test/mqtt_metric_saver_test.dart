import 'dart:async';

import 'package:e_metrics_iot/src/data/metric_model.dart';
import 'package:e_metrics_iot/src/data/metric_repository.dart';
import 'package:e_metrics_iot/src/providers/metric_provider.dart';
import 'package:e_metrics_iot/src/providers/mqtt_metric_saver.dart';
import 'package:e_metrics_iot/src/providers/mqtt_stream_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';

class _SpyMetricRepository extends MetricRepository {
  int insertCalls = 0;

  @override
  Future<void> insertMetric(Metric metric) async {
    insertCalls++;
  }
}

MqttReceivedMessage<MqttMessage> _buildMessage(String payload) {
  final builder = MqttClientPayloadBuilder()..addString(payload);
  final publish = MqttPublishMessage().toTopic('emetrics/pzem').publishData(builder.payload!);
  return MqttReceivedMessage<MqttMessage>('emetrics/pzem', publish);
}

void main() {
  test('mqttMetricSaver nao persiste no foreground com background ativo', () async {
    final spyRepo = _SpyMetricRepository();
    final controller = StreamController<List<MqttReceivedMessage<MqttMessage>>>();
    final message = _buildMessage(
      '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,"frequency":60,"energy":1.23}',
    );

    final container = ProviderContainer(
      overrides: [
        metricRepositoryProvider.overrideWithValue(spyRepo),
        mqttStreamProvider.overrideWith((ref) => controller.stream),
        backgroundRunningCheckProvider.overrideWithValue(() async => true),
      ],
    );
    addTearDown(controller.close);
    addTearDown(container.dispose);

    final saverSub = container.listen(mqttMetricSaverProvider, (previous, next) {});
    addTearDown(saverSub.close);
    controller.add([message]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(spyRepo.insertCalls, 0);
  });

  test('mqttMetricSaver persiste no foreground com background inativo', () async {
    final spyRepo = _SpyMetricRepository();
    final controller = StreamController<List<MqttReceivedMessage<MqttMessage>>>();
    final message = _buildMessage(
      '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,"frequency":60,"energy":1.23}',
    );

    final container = ProviderContainer(
      overrides: [
        metricRepositoryProvider.overrideWithValue(spyRepo),
        mqttStreamProvider.overrideWith((ref) => controller.stream),
        backgroundRunningCheckProvider.overrideWithValue(() async => false),
      ],
    );
    addTearDown(controller.close);
    addTearDown(container.dispose);

    final saverSub = container.listen(mqttMetricSaverProvider, (previous, next) {});
    addTearDown(saverSub.close);
    controller.add([message]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(spyRepo.insertCalls, 1);
  });
}
