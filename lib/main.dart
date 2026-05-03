import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/services/alert_service.dart';
import 'src/services/background_mqtt_service.dart';

Future<void> main() async {
  // Sequência de inicialização antes de runApp:
  // 1. ensureInitialized(): requer binding Flutter para APIs nativas.
  // 2. AlertService.init(): registra o plugin de notificações locais.
  // 3. BackgroundMqttService.initialize(): configura serviço MQTT em segundo plano.
  WidgetsFlutterBinding.ensureInitialized();
  await AlertService.init();
  await BackgroundMqttService.initialize();
  runApp(const EmetricsApp());
}

