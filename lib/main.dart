import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/services/background_mqtt_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundMqttService.initialize();
  runApp(const EmetricsApp());
}

