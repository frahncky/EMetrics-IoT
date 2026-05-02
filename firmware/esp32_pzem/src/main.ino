#if !defined(ESP32)
#error Este firmware requer placa ESP32. No Arduino IDE, selecione uma placa ESP32 (ex.: ESP32 Dev Module).
#endif

#include <WiFi.h>
#include <PubSubClient.h>
#include <PZEM004Tv30.h>
#include <string.h>

// -------------------------
// Configuracao de rede/MQTT
// -------------------------
const char* WIFI_SSID = "SEU_WIFI";
const char* WIFI_PASSWORD = "SUA_SENHA_WIFI";

const char* MQTT_HOST = "test.mosquitto.org";
const uint16_t MQTT_PORT = 1883;
const char* MQTT_USER = "";
const char* MQTT_PASSWORD = "";
const char* MQTT_TOPIC = "emetrics/pzem";
const char* MQTT_STATUS_TOPIC = "emetrics/pzem/status";

const char* MQTT_CLIENT_ID = "esp32_pzem_001";
constexpr unsigned long PUBLISH_INTERVAL_MS = 2000;
constexpr unsigned long WIFI_RETRY_INTERVAL_MS = 5000;
constexpr unsigned long MQTT_RETRY_INTERVAL_MS = 3000;
constexpr bool MQTT_RETAINED = true;
constexpr size_t TELEMETRY_PAYLOAD_SIZE = 220;
constexpr size_t TELEMETRY_QUEUE_CAPACITY = 30;
constexpr uint8_t FLUSH_BATCH_LIMIT = 5;

WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

// UART2 (ESP32): RX=16, TX=17
PZEM004Tv30 pzem(Serial2, 16, 17);

unsigned long lastPublishMs = 0;
unsigned long lastWifiAttemptMs = 0;
unsigned long lastMqttAttemptMs = 0;
char telemetryQueue[TELEMETRY_QUEUE_CAPACITY][TELEMETRY_PAYLOAD_SIZE];
size_t queueHead = 0;
size_t queueCount = 0;

void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void ensureWiFiConnected() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  const unsigned long now = millis();
  if (now - lastWifiAttemptMs < WIFI_RETRY_INTERVAL_MS) {
    return;
  }

  lastWifiAttemptMs = now;
  connectWiFi();
}

void ensureMqttConnected() {
  if (WiFi.status() != WL_CONNECTED || mqttClient.connected()) {
    return;
  }

  const unsigned long now = millis();
  if (now - lastMqttAttemptMs < MQTT_RETRY_INTERVAL_MS) {
    return;
  }

  lastMqttAttemptMs = now;
  const bool useAuth = strlen(MQTT_USER) > 0;
  bool connected = false;

  if (useAuth) {
    connected = mqttClient.connect(MQTT_CLIENT_ID, MQTT_USER, MQTT_PASSWORD);
  } else {
    connected = mqttClient.connect(MQTT_CLIENT_ID);
  }

  if (connected) {
    mqttClient.publish(MQTT_STATUS_TOPIC, "online", true);
  }
}

bool readPzem(float& voltage, float& current, float& power, float& energy, float& frequency, float& pf) {
  voltage = pzem.voltage();
  current = pzem.current();
  power = pzem.power();
  energy = pzem.energy();
  frequency = pzem.frequency();
  pf = pzem.pf();

  if (isnan(voltage) || isnan(current) || isnan(power) || isnan(energy) || isnan(frequency) || isnan(pf)) {
    return false;
  }

  return true;
}

void enqueuePayload(const char* payload) {
  if (queueCount == TELEMETRY_QUEUE_CAPACITY) {
    queueHead = (queueHead + 1) % TELEMETRY_QUEUE_CAPACITY;
    queueCount--;
  }

  const size_t writeIndex = (queueHead + queueCount) % TELEMETRY_QUEUE_CAPACITY;
  strncpy(telemetryQueue[writeIndex], payload, TELEMETRY_PAYLOAD_SIZE - 1);
  telemetryQueue[writeIndex][TELEMETRY_PAYLOAD_SIZE - 1] = '\0';
  queueCount++;
}

bool buildMetricsPayload(char* payloadBuffer, size_t payloadBufferSize) {
  float voltage = 0.0f;
  float current = 0.0f;
  float power = 0.0f;
  float energy = 0.0f;
  float frequency = 0.0f;
  float pf = 0.0f;

  if (!readPzem(voltage, current, power, energy, frequency, pf)) {
    return false;
  }

  snprintf(
    payloadBuffer,
    payloadBufferSize,
    "{\"voltage\":%.2f,\"current\":%.3f,\"power\":%.2f,\"pf\":%.3f,\"frequency\":%.2f,\"energy\":%.3f}",
    voltage,
    current,
    power,
    pf,
    frequency,
    energy
  );

  return true;
}

void queueLatestMetrics() {
  char payload[TELEMETRY_PAYLOAD_SIZE];
  if (!buildMetricsPayload(payload, sizeof(payload))) {
    return;
  }

  enqueuePayload(payload);
}

bool publishFrontPayload() {
  if (queueCount == 0 || !mqttClient.connected()) {
    return false;
  }

  if (!mqttClient.publish(MQTT_TOPIC, telemetryQueue[queueHead], MQTT_RETAINED)) {
    return false;
  }

  queueHead = (queueHead + 1) % TELEMETRY_QUEUE_CAPACITY;
  queueCount--;
  return true;
}

void flushQueuedMetrics() {
  if (!mqttClient.connected() || queueCount == 0) {
    return;
  }

  uint8_t publishedInThisLoop = 0;
  while (queueCount > 0 && publishedInThisLoop < FLUSH_BATCH_LIMIT) {
    if (!publishFrontPayload()) {
      break;
    }
    publishedInThisLoop++;
  }
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, 16, 17);

  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  connectWiFi();
}

void loop() {
  ensureWiFiConnected();
  ensureMqttConnected();

  if (mqttClient.connected()) {
    mqttClient.loop();
  }

  const unsigned long now = millis();
  if (now - lastPublishMs >= PUBLISH_INTERVAL_MS) {
    lastPublishMs = now;
    queueLatestMetrics();
  }

  if (WiFi.status() == WL_CONNECTED && mqttClient.connected()) {
    flushQueuedMetrics();
  }
}
