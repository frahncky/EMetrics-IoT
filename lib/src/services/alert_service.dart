import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Serviço de notificações locais do app (flutter_local_notifications).
///
/// Deve ser inicializado uma única vez em `main()` via [init()] antes de
/// [runApp]. As permissões são solicitadas sob demanda por [ensurePermissionGranted].
class AlertService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static int _nextId = 1;

  /// Inicializa o plugin com ícone padrão do launcher (Android/iOS).
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notifications.initialize(settings);
  }

  /// Solicita permissão de notificações ao usuário.
  ///
  /// Retorna `true` se a permissão foi concedida ou se a plataforma não
  /// requer solicitação explícita.
  static Future<bool> ensurePermissionGranted() async {
    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final iosImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    final androidGranted = await androidImplementation
        ?.requestNotificationsPermission();
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

  /// Exibe uma notificação local com [title] e [body].
  ///
  /// Usa o canal `main_channel` (fixo) criado na instalação. Futuros tipos de
  /// alerta poderão usar canais distintos para prioridades diferenciadas.
  static Future<void> showAlert(String title, String body) async {
    const android = AndroidNotificationDetails(
      // ID fixo do canal único do app. Alterar exige recriação do canal no Android.
      'main_channel',
      'Alertas',
      channelDescription: 'Notificações de alertas do E-Metrics IoT',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _notifications.show(_nextId++, title, body, details);
  }
}
