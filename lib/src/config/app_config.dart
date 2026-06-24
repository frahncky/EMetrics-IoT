abstract final class AppConfig {
  // Intervalo de debounce para invalidar providers após salvar uma métrica MQTT.
  static const mqttSaverDebounce = Duration(milliseconds: 100);

  // Intervalo entre verificações de limpeza de retenção de métricas locais.
  static const retentionCleanupInterval = Duration(hours: 1);

  // Intervalo de sincronização com a integração externa.
  static const integrationSyncInterval = Duration(seconds: 45);

  // Intervalo de coleta local do ESP32 quando o MQTT não está conectado.
  static const localCollectorInterval = Duration(seconds: 2);

  // Configurações padrão do broker MQTT.
  static const defaultBroker = 'test.mosquitto.org';
  static const defaultPort = 1883;
  static const defaultTopic = 'emetrics/pzem';
  static const defaultRequestTopic = 'emetrics/pzem/history/request';
}
