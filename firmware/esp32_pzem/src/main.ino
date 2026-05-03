#if !defined(ESP32)
#error Este firmware requer placa ESP32. No Arduino IDE, selecione uma placa ESP32 (ex.: ESP32 Dev Module).
#endif

// ═══════════════════════════════════════════════════════════════════════════
// INCLUDES
// ═══════════════════════════════════════════════════════════════════════════
#include <Preferences.h>
#include <PubSubClient.h>
#include <PZEM004Tv30.h>
#include <FS.h>
#include <SD.h>
#include <SPIFFS.h>
#include <SPI.h>
#include <WebServer.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

// ═══════════════════════════════════════════════════════════════════════════
// PROVISIONAMENTO AP
// Credenciais do ponto de acesso criado quando o dispositivo nao possui
// configuracao salva. O usuario se conecta a esta rede e envia as credenciais
// via POST /provision.
// ═══════════════════════════════════════════════════════════════════════════
const char* PROVISION_AP_SSID = "EMetrics-Setup";
const char* PROVISION_AP_PASSWORD = "12345678";

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURACAO RUNTIME
// Estrutura persistida em NVS (Preferences). Carregada em loadConfig() e
// atualizada por provisionamento via AP ou pelo app Flutter via MQTT.
// ═══════════════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTES E VARIAVEIS GLOBAIS
// ═══════════════════════════════════════════════════════════════════════════
constexpr unsigned long PUBLISH_INTERVAL_MS = 2000;       // intervalo entre leituras PZEM
constexpr unsigned long WIFI_RETRY_INTERVAL_MS = 5000;    // retentatida de reconexao WiFi
constexpr unsigned long MQTT_RETRY_INTERVAL_MS = 3000;    // retentativa de reconexao MQTT
constexpr unsigned long HISTORY_PUBLISH_DELAY_MS = 10;    // pausa entre publicacoes de replay
constexpr bool MQTT_RETAINED = true;
constexpr size_t TELEMETRY_PAYLOAD_SIZE = 220;            // bytes por payload JSON
constexpr size_t TELEMETRY_QUEUE_CAPACITY = 30;           // capacidade do buffer circular offline
constexpr uint8_t FLUSH_BATCH_LIMIT = 5;                  // publicacoes por iteracao do loop
constexpr uint16_t HISTORY_REPLAY_LIMIT = 300;            // linhas maximas por resposta de historico
constexpr size_t HISTORY_FILE_MAX_BYTES = 256 * 1024;     // 256 KB: tamanho maximo do arquivo de historico
constexpr const char* HISTORY_FILE_PATH = "/history.log";

#ifndef EMETRICS_SD_CS_PIN
#define EMETRICS_SD_CS_PIN 5
#endif

#ifndef EMETRICS_SD_SCK_PIN
#define EMETRICS_SD_SCK_PIN 18
#endif

#ifndef EMETRICS_SD_MISO_PIN
#define EMETRICS_SD_MISO_PIN 19
#endif

#ifndef EMETRICS_SD_MOSI_PIN
#define EMETRICS_SD_MOSI_PIN 23
#endif

WiFiClient wifiClient;
WiFiClientSecure secureClient;
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
bool sntpConfigured = false;
uint64_t bootEpochOffsetMs = 0;
bool bootEpochOffsetValid = false;
bool historyStorageReady = false;
bool historyStorageUsesSd = false;

struct HistoryRequest {
  uint64_t from = 0;
  uint64_t to = 0;
  bool valid = false;
};

uint64_t currentEpochMs();
void appendHistoryRecord(const char* payload, uint64_t timestampMs);
void replayHistoryRange(uint64_t fromMs, uint64_t toMs);
HistoryRequest parseHistoryRequest(const char* payload, unsigned int length);
void onMqttMessage(char* topic, byte* payload, unsigned int length);
File openHistoryFile(const char* mode);
bool removeHistoryFile();

// ═══════════════════════════════════════════════════════════════════════════
// SINCRONIZACAO DE TEMPO (SNTP / NTP)
// ═══════════════════════════════════════════════════════════════════════════

uint64_t currentEpochMs() {
  if (!bootEpochOffsetValid) {
    return 0;
  }
  return bootEpochOffsetMs + millis();
}

void configureTimeSync() {
  if (sntpConfigured) {
    return;
  }

  configTime(0, 0, "pool.ntp.org", "time.nist.gov", "time.google.com");
  sntpConfigured = true;
}

/**
 * Recalcula o offset epoch_ms - millis() se o NTP ainda nao sincronizou
 * ou se o dispositivo reiniciou. Deve ser chamado periodicamente no loop.
 */
void refreshEpochOffsetIfNeeded() {
  configureTimeSync();
  const time_t now = time(nullptr);
  if (now < 1700000000) {
    return;
  }

  const uint64_t nowMs = static_cast<uint64_t>(now) * 1000ULL;
  bootEpochOffsetMs = nowMs - millis();
  bootEpochOffsetValid = true;
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORICO (SD / SPIFFS)
// Tenta SD primeiro; cai para SPIFFS se SD nao estiver disponivel.
// O arquivo de historico e rotacionado quando atinge HISTORY_FILE_MAX_BYTES.
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Inicializa o storage de historico (SD ou SPIFFS).
 * Retorna true se pelo menos um sistema de arquivos foi montado com sucesso.
 */
bool ensureHistoryStorageReady() {
  if (historyStorageReady) {
    return true;
  }

  SPI.begin(EMETRICS_SD_SCK_PIN, EMETRICS_SD_MISO_PIN, EMETRICS_SD_MOSI_PIN, EMETRICS_SD_CS_PIN);
  if (SD.begin(EMETRICS_SD_CS_PIN) && SD.cardType() != CARD_NONE) {
    historyStorageReady = true;
    historyStorageUsesSd = true;
    return true;
  }

  if (SPIFFS.begin(true)) {
    historyStorageReady = true;
    historyStorageUsesSd = false;
    return true;
  }

  return false;
}

File openHistoryFile(const char* mode) {
  if (historyStorageUsesSd) {
    return SD.open(HISTORY_FILE_PATH, mode);
  }
  return SPIFFS.open(HISTORY_FILE_PATH, mode);
}

bool removeHistoryFile() {
  if (historyStorageUsesSd) {
    return SD.remove(HISTORY_FILE_PATH);
  }
  return SPIFFS.remove(HISTORY_FILE_PATH);
}

/**
 * Remove a metade mais antiga do arquivo de historico quando ele ultrapassa
 * HISTORY_FILE_MAX_BYTES. Usa alocacao String para simplificar o manuseio
 * do sistema de arquivos — aceitavel pois executa raramente e a RAM liberada
 * e suficiente no ESP32 (512 KB SRAM).
 */
void compactHistoryIfNeeded() {
  File historyFile = openHistoryFile(FILE_READ);
  if (!historyFile) {
    return;
  }

  const size_t historySize = historyFile.size();
  if (historySize <= HISTORY_FILE_MAX_BYTES) {
    historyFile.close();
    return;
  }

  const size_t keepSize = HISTORY_FILE_MAX_BYTES / 2;
  const size_t skipBytes = historySize > keepSize ? historySize - keepSize : 0;
  if (!historyFile.seek(skipBytes)) {
    historyFile.close();
    removeHistoryFile();
    return;
  }

  String compacted;
  compacted.reserve(keepSize + 64);

  while (historyFile.available()) {
    compacted += historyFile.readStringUntil('\n');
    compacted += '\n';
  }
  historyFile.close();

  File rewrite = openHistoryFile(FILE_WRITE);
  if (!rewrite) {
    return;
  }
  rewrite.print(compacted);
  rewrite.close();
}

void appendHistoryRecord(const char* payload, uint64_t timestampMs) {
  if (timestampMs == 0 || !ensureHistoryStorageReady()) {
    return;
  }

  File historyFile = openHistoryFile(FILE_APPEND);
  if (!historyFile) {
    return;
  }

  historyFile.printf("%llu;%s\n", timestampMs, payload);
  historyFile.close();
  compactHistoryIfNeeded();
}

bool extractUInt64Field(const String& source, const char* key, uint64_t& outValue) {
  const String quotedKey = String("\"") + key + "\"";
  const int keyIndex = source.indexOf(quotedKey);
  if (keyIndex < 0) {
    return false;
  }

  const int colonIndex = source.indexOf(':', keyIndex + quotedKey.length());
  if (colonIndex < 0) {
    return false;
  }

  int valueStart = colonIndex + 1;
  while (valueStart < source.length() && isspace(source[valueStart])) {
    valueStart++;
  }

  int valueEnd = valueStart;
  while (valueEnd < source.length() && isdigit(source[valueEnd])) {
    valueEnd++;
  }

  if (valueEnd <= valueStart) {
    return false;
  }

  outValue = strtoull(source.substring(valueStart, valueEnd).c_str(), nullptr, 10);
  return outValue > 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// MQTT — MENSAGENS RECEBIDAS E REPLAY DE HISTORICO
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Parseia o payload JSON de solicitacao de historico.
 * Espera os campos "from" e "to" como epoch em milissegundos.
 * Retorna um HistoryRequest invalido (valid=false) em caso de erro.
 */
HistoryRequest parseHistoryRequest(const char* payload, unsigned int length) {
  HistoryRequest request;
  String raw;
  raw.reserve(length + 1);
  for (unsigned int i = 0; i < length; i++) {
    raw += static_cast<char>(payload[i]);
  }

  uint64_t from = 0;
  uint64_t to = 0;
  const bool hasFrom = extractUInt64Field(raw, "from", from);
  const bool hasTo = extractUInt64Field(raw, "to", to);

  if (!hasFrom || !hasTo || from > to) {
    return request;
  }

  request.from = from;
  request.to = to;
  request.valid = true;
  return request;
}

/**
 * Republica no topico principal as entradas do historico cujo timestamp
 * esteja no intervalo [fromMs, toMs]. Respeita HISTORY_REPLAY_LIMIT para
 * evitar saturar o broker e a rede.
 */
void replayHistoryRange(uint64_t fromMs, uint64_t toMs) {
  if (!mqttClient.connected() || !ensureHistoryStorageReady()) {
    return;
  }

  File historyFile = openHistoryFile(FILE_READ);
  if (!historyFile) {
    return;
  }

  uint16_t published = 0;
  while (historyFile.available() && published < HISTORY_REPLAY_LIMIT) {
    const String line = historyFile.readStringUntil('\n');
    if (line.length() < 5) {
      continue;
    }

    const int sep = line.indexOf(';');
    if (sep <= 0 || sep >= line.length() - 1) {
      continue;
    }

    const uint64_t timestampMs = strtoull(line.substring(0, sep).c_str(), nullptr, 10);
    if (timestampMs < fromMs || timestampMs > toMs) {
      continue;
    }

    const String payload = line.substring(sep + 1);
    if (mqttClient.publish(config.mqttTopic, payload.c_str(), MQTT_RETAINED)) {
      published++;
      delay(HISTORY_PUBLISH_DELAY_MS);
    }
  }

  historyFile.close();
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  if (strcmp(topic, config.mqttRequestTopic) != 0) {
    return;
  }

  const HistoryRequest request = parseHistoryRequest(reinterpret_cast<char*>(payload), length);
  if (!request.valid) {
    return;
  }

  replayHistoryRange(request.from, request.to);
}

/**
 * Configura o cliente MQTT para usar TLS (WiFiClientSecure, sem verificacao
 * de certificado) ou TCP simples conforme config.useTls.
 */
void configureMqttTransport() {
  if (config.useTls) {
    secureClient.setInsecure();
    mqttClient.setClient(secureClient);
  } else {
    mqttClient.setClient(wifiClient);
  }
}

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

// ═══════════════════════════════════════════════════════════════════════════
// PROVISIONAMENTO AP — HANDLERS HTTP
// ═══════════════════════════════════════════════════════════════════════════

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
  configureMqttTransport();
  mqttClient.setServer(config.mqttHost, config.mqttPort);
  mqttClient.setCallback(onMqttMessage);

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
    mqttClient.subscribe(config.mqttRequestTopic);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PZEM004T — LEITURA E TELEMETRIA
// Buffer circular offline: quando MQTT esta indisponivel, as leituras sao
// enfileiradas em RAM e publicadas em lotes de FLUSH_BATCH_LIMIT ao reconectar.
// ═══════════════════════════════════════════════════════════════════════════

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
  appendHistoryRecord(payload, currentEpochMs());
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

// ═══════════════════════════════════════════════════════════════════════════
// SETUP E LOOP PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, 16, 17);

  ensureHistoryStorageReady();
  loadConfig();
  if (!config.valid) {
    startProvisioningMode();
    return;
  }

  configureMqttTransport();
  refreshEpochOffsetIfNeeded();
  mqttClient.setServer(config.mqttHost, config.mqttPort);
  mqttClient.setCallback(onMqttMessage);
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
  if (WiFi.status() == WL_CONNECTED) {
    refreshEpochOffsetIfNeeded();
  }
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
