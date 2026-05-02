#if !defined(ESP32)
#error Este firmware requer placa ESP32. No Arduino IDE, selecione uma placa ESP32 (ex.: ESP32 Dev Module).
#endif

#include <Preferences.h>
#include <PubSubClient.h>
#include <PZEM004Tv30.h>
#include <WebServer.h>
#include <WiFi.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

// -------------------------
// Provisionamento AP
// -------------------------
const char* PROVISION_AP_SSID = "EMetrics-Setup";
const char* PROVISION_AP_PASSWORD = "12345678";

// -------------------------
// Configuracao runtime
// -------------------------
struct DeviceConfig {
  char wifiSsid[33];
  char wifiPassword[65];
  char mqttHost[65];
  uint16_t mqttPort;
  char mqttUser[65];
  char mqttPassword[65];
  char mqttTopic[129];
  char mqttRequestTopic[129];
  char mqttClientId[65];
  bool useTls;
  bool valid;
};

DeviceConfig config = {
  "",
  "",
  "test.mosquitto.org",
  1883,
  "",
  "",
  "emetrics/pzem",
  "emetrics/pzem/history/request",
  "esp32_pzem_001",
  false,
  false,
};

constexpr unsigned long PUBLISH_INTERVAL_MS = 2000;
constexpr unsigned long WIFI_RETRY_INTERVAL_MS = 5000;
constexpr unsigned long MQTT_RETRY_INTERVAL_MS = 3000;
constexpr bool MQTT_RETAINED = true;
constexpr size_t TELEMETRY_PAYLOAD_SIZE = 220;
constexpr size_t TELEMETRY_QUEUE_CAPACITY = 30;
constexpr uint8_t FLUSH_BATCH_LIMIT = 5;

WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);
WebServer provisionServer(80);
Preferences preferences;

// UART2 (ESP32): RX=16, TX=17
PZEM004Tv30 pzem(Serial2, 16, 17);

unsigned long lastPublishMs = 0;
unsigned long lastWifiAttemptMs = 0;
unsigned long lastMqttAttemptMs = 0;
char telemetryQueue[TELEMETRY_QUEUE_CAPACITY][TELEMETRY_PAYLOAD_SIZE];
size_t queueHead = 0;
size_t queueCount = 0;

bool provisioningMode = false;
bool restartScheduled = false;
unsigned long restartScheduledAtMs = 0;

void safeCopy(String value, char* destination, size_t destinationSize) {
  value.trim();
  const size_t maxLen = destinationSize - 1;
  strncpy(destination, value.c_str(), maxLen);
  destination[maxLen] = '\0';
}

void loadConfig() {
  preferences.begin("emetrics", true);
  const bool valid = preferences.getBool("cfg_valid", false);

  if (valid) {
    const String wifiSsid = preferences.getString("wifi_ssid", "");
    const String wifiPassword = preferences.getString("wifi_pwd", "");
    const String mqttHost = preferences.getString("mqtt_host", "test.mosquitto.org");
    const uint16_t mqttPort = preferences.getUShort("mqtt_port", 1883);
    const String mqttUser = preferences.getString("mqtt_user", "");
    const String mqttPassword = preferences.getString("mqtt_pwd", "");
    const String mqttTopic = preferences.getString("mqtt_topic", "emetrics/pzem");
    const String mqttRequestTopic =
        preferences.getString("mqtt_req_topic", "emetrics/pzem/history/request");
    const String mqttClientId = preferences.getString("mqtt_client_id", "esp32_pzem_001");
    const bool useTls = preferences.getBool("mqtt_tls", false);

    safeCopy(wifiSsid, config.wifiSsid, sizeof(config.wifiSsid));
    safeCopy(wifiPassword, config.wifiPassword, sizeof(config.wifiPassword));
    safeCopy(mqttHost, config.mqttHost, sizeof(config.mqttHost));
    config.mqttPort = mqttPort;
    safeCopy(mqttUser, config.mqttUser, sizeof(config.mqttUser));
    safeCopy(mqttPassword, config.mqttPassword, sizeof(config.mqttPassword));
    safeCopy(mqttTopic, config.mqttTopic, sizeof(config.mqttTopic));
    safeCopy(mqttRequestTopic, config.mqttRequestTopic, sizeof(config.mqttRequestTopic));
    safeCopy(mqttClientId, config.mqttClientId, sizeof(config.mqttClientId));
    config.useTls = useTls;
    config.valid = strlen(config.wifiSsid) > 0 && strlen(config.mqttHost) > 0;
  }

  preferences.end();
}

void saveConfig() {
  preferences.begin("emetrics", false);
  preferences.putString("wifi_ssid", config.wifiSsid);
  preferences.putString("wifi_pwd", config.wifiPassword);
  preferences.putString("mqtt_host", config.mqttHost);
  preferences.putUShort("mqtt_port", config.mqttPort);
  preferences.putString("mqtt_user", config.mqttUser);
  preferences.putString("mqtt_pwd", config.mqttPassword);
  preferences.putString("mqtt_topic", config.mqttTopic);
  preferences.putString("mqtt_req_topic", config.mqttRequestTopic);
  preferences.putString("mqtt_client_id", config.mqttClientId);
  preferences.putBool("mqtt_tls", config.useTls);
  preferences.putBool("cfg_valid", true);
  preferences.end();
}

void scheduleRestart() {
  restartScheduled = true;
  restartScheduledAtMs = millis();
}

void handleHealth() {
  provisionServer.send(
      200,
      "application/json",
      "{\"ok\":true,\"mode\":\"provisioning\",\"message\":\"ESP pronto para receber configuracao.\"}");
}

bool parseAndApplyProvisioning() {
  if (!provisionServer.hasArg("ssid") || !provisionServer.hasArg("mqttHost") ||
      !provisionServer.hasArg("mqttPort") || !provisionServer.hasArg("mqttTopic") ||
      !provisionServer.hasArg("mqttRequestTopic") || !provisionServer.hasArg("clientId")) {
    return false;
  }

  const String ssid = provisionServer.arg("ssid");
  const String mqttHost = provisionServer.arg("mqttHost");
  const String mqttPortString = provisionServer.arg("mqttPort");
  const String mqttTopic = provisionServer.arg("mqttTopic");
  const String mqttRequestTopic = provisionServer.arg("mqttRequestTopic");
  const String clientId = provisionServer.arg("clientId");

  if (ssid.length() == 0 || mqttHost.length() == 0 || mqttTopic.length() == 0 ||
      mqttRequestTopic.length() == 0 || clientId.length() == 0) {
    return false;
  }

  const uint16_t mqttPort = (uint16_t)mqttPortString.toInt();
  if (mqttPort == 0) {
    return false;
  }

  safeCopy(ssid, config.wifiSsid, sizeof(config.wifiSsid));
  safeCopy(provisionServer.arg("wifiPassword"), config.wifiPassword, sizeof(config.wifiPassword));
  safeCopy(mqttHost, config.mqttHost, sizeof(config.mqttHost));
  config.mqttPort = mqttPort;
  safeCopy(provisionServer.arg("mqttUser"), config.mqttUser, sizeof(config.mqttUser));
  safeCopy(provisionServer.arg("mqttPassword"), config.mqttPassword, sizeof(config.mqttPassword));
  safeCopy(mqttTopic, config.mqttTopic, sizeof(config.mqttTopic));
  safeCopy(mqttRequestTopic, config.mqttRequestTopic, sizeof(config.mqttRequestTopic));
  safeCopy(clientId, config.mqttClientId, sizeof(config.mqttClientId));
  config.useTls = provisionServer.arg("useTls") == "1";
  config.valid = true;

  saveConfig();
  return true;
}

void handleProvision() {
  if (parseAndApplyProvisioning()) {
    provisionServer.send(200,
                         "application/json",
                         "{\"ok\":true,\"message\":\"Configuracao salva. ESP32 ira reiniciar.\"}");
    scheduleRestart();
    return;
  }

  provisionServer.send(400,
                       "application/json",
                       "{\"ok\":false,\"message\":\"Parametros invalidos para provisionamento.\"}");
}

void startProvisioningMode() {
  provisioningMode = true;
  WiFi.mode(WIFI_AP);
  WiFi.softAP(PROVISION_AP_SSID, PROVISION_AP_PASSWORD);

  provisionServer.on("/health", HTTP_GET, handleHealth);
  provisionServer.on("/provision", HTTP_POST, handleProvision);
  provisionServer.begin();
}

void connectWiFi() {
  if (!config.valid) {
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.begin(config.wifiSsid, config.wifiPassword);
}

void ensureWiFiConnected() {
  if (provisioningMode || WiFi.status() == WL_CONNECTED) {
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
  if (provisioningMode || WiFi.status() != WL_CONNECTED || mqttClient.connected()) {
    return;
  }

  const unsigned long now = millis();
  if (now - lastMqttAttemptMs < MQTT_RETRY_INTERVAL_MS) {
    return;
  }

  lastMqttAttemptMs = now;
  mqttClient.setServer(config.mqttHost, config.mqttPort);

  const bool useAuth = strlen(config.mqttUser) > 0;
  bool connected = false;

  if (useAuth) {
    connected = mqttClient.connect(config.mqttClientId, config.mqttUser, config.mqttPassword);
  } else {
    connected = mqttClient.connect(config.mqttClientId);
  }

  if (connected) {
    const String statusTopic = String(config.mqttTopic) + "/status";
    mqttClient.publish(statusTopic.c_str(), "online", true);
  }
}

bool readPzem(float& voltage, float& current, float& power, float& energy, float& frequency,
              float& pf) {
  voltage = pzem.voltage();
  current = pzem.current();
  power = pzem.power();
  energy = pzem.energy();
  frequency = pzem.frequency();
  pf = pzem.pf();

  if (isnan(voltage) || isnan(current) || isnan(power) || isnan(energy) || isnan(frequency) ||
      isnan(pf)) {
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

  snprintf(payloadBuffer,
           payloadBufferSize,
           "{\"voltage\":%.2f,\"current\":%.3f,\"power\":%.2f,\"pf\":%.3f,\"frequency\":%.2f,\"energy\":%.3f}",
           voltage,
           current,
           power,
           pf,
           frequency,
           energy);

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

  if (!mqttClient.publish(config.mqttTopic, telemetryQueue[queueHead], MQTT_RETAINED)) {
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

  loadConfig();
  if (!config.valid) {
    startProvisioningMode();
    return;
  }

  mqttClient.setServer(config.mqttHost, config.mqttPort);
  connectWiFi();
}

void loop() {
  if (provisioningMode) {
    provisionServer.handleClient();
    if (restartScheduled && millis() - restartScheduledAtMs >= 1500) {
      ESP.restart();
    }
    return;
  }

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
