import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AlertService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notifications.initialize(settings);
  }

  static Future<bool> ensurePermissionGranted() async {
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final iosImplementation =
        _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    final androidGranted =
        await androidImplementation?.requestNotificationsPermission();
    final iosGranted = await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (androidGranted != null) {
      return androidGranted;
    }
    if (iosGranted != null) {
      return iosGranted;
    }
    return true;
  }

  static Future<void> showAlert(String title, String body) async {
    const android = AndroidNotificationDetails(
      'main_channel',
      'Alertas',
      channelDescription: 'Notificações de alertas do E-Metrics IoT',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _notifications.show(0, title, body, details);
  }
}
