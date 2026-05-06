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
  uint16_t sdRetentionDays;
  bool valid;
};

struct SavedWifiNetwork {
  char ssid[33];
  char password[65];
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
  30,
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
constexpr size_t TELEMETRY_PAYLOAD_SIZE = 360;            // bytes por payload JSON
constexpr size_t TELEMETRY_QUEUE_CAPACITY = 30;           // capacidade do buffer circular offline
constexpr uint8_t FLUSH_BATCH_LIMIT = 5;                  // publicacoes por iteracao do loop
constexpr uint16_t HISTORY_REPLAY_LIMIT = 300;            // linhas maximas por resposta de historico
constexpr size_t HISTORY_FILE_MAX_BYTES = 256 * 1024;     // 256 KB: tamanho maximo do arquivo de historico
constexpr uint16_t DEFAULT_SD_RETENTION_DAYS = 30;        // retencao padrao do historico local
constexpr uint16_t MAX_SD_RETENTION_DAYS = 3650;          // limite para comando vindo do app
constexpr unsigned long HISTORY_RETENTION_PRUNE_INTERVAL_MS = 60UL * 60UL * 1000UL;
constexpr uint8_t WIFI_NETWORK_CAPACITY = 5;              // redes Wi-Fi salvas no ESP
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
SavedWifiNetwork wifiNetworks[WIFI_NETWORK_CAPACITY];
uint8_t wifiNetworkCount = 0;
uint8_t wifiConnectIndex = 0;
char telemetryQueue[TELEMETRY_QUEUE_CAPACITY][TELEMETRY_PAYLOAD_SIZE];
size_t queueHead = 0;
size_t queueCount = 0;

bool provisioningMode = false;
bool provisionServerStarted = false;
bool restartScheduled = false;
unsigned long restartScheduledAtMs = 0;
bool sntpConfigured = false;
uint64_t bootEpochOffsetMs = 0;
bool bootEpochOffsetValid = false;
bool historyStorageReady = false;
bool historyStorageUsesSd = false;
unsigned long lastHistoryRetentionPruneMs = 0;

struct HistoryRequest {
  uint64_t from = 0;
  uint64_t to = 0;
  bool valid = false;
};

uint64_t currentEpochMs();
void appendHistoryRecord(const char* payload, uint64_t timestampMs);
void replayHistoryRange(uint64_t fromMs, uint64_t toMs);
HistoryRequest parseHistoryRequest(const char* payload, unsigned int length);
bool parseStorageConfigCommand(const char* payload, unsigned int length, uint16_t& sdRetentionDays);
void applyStorageConfigCommand(uint16_t sdRetentionDays);
void pruneHistoryByRetentionIfNeeded(uint64_t nowMs, bool force);
void onMqttMessage(char* topic, byte* payload, unsigned int length);
File openHistoryFile(const char* mode);
bool removeHistoryFile();
void saveConfig();
void saveWifiNetworks(Preferences& prefs);
void loadWifiNetworks(Preferences& prefs);
bool upsertWifiNetwork(String ssid, String password, String oldSsid = "", bool keepExistingPassword = false);
bool deleteWifiNetwork(String ssid);
int findWifiNetworkIndex(const String& ssid);
String jsonEscape(const char* value);

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

struct DeviceStorageUsage {
  bool sdAvailable = false;
  bool usingSd = false;
  uint64_t usedBytes = 0;
  uint64_t totalBytes = 0;
  float usagePercent = 0.0f;
};

DeviceStorageUsage readDeviceStorageUsage() {
  DeviceStorageUsage usage;
  if (!ensureHistoryStorageReady() || !historyStorageUsesSd) {
    return usage;
  }

  usage.sdAvailable = true;
  usage.usingSd = true;
  usage.usedBytes = SD.usedBytes();
  usage.totalBytes = SD.totalBytes();
  if (usage.totalBytes > 0) {
    usage.usagePercent = (static_cast<float>(usage.usedBytes) * 100.0f) /
                         static_cast<float>(usage.totalBytes);
  }
  return usage;
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

void pruneHistoryByRetentionIfNeeded(uint64_t nowMs, bool force) {
  if (nowMs == 0 || !ensureHistoryStorageReady()) {
    return;
  }

  const unsigned long loopNow = millis();
  if (!force && lastHistoryRetentionPruneMs != 0 &&
      loopNow - lastHistoryRetentionPruneMs < HISTORY_RETENTION_PRUNE_INTERVAL_MS) {
    return;
  }
  lastHistoryRetentionPruneMs = loopNow;

  const uint64_t retentionMs =
      static_cast<uint64_t>(config.sdRetentionDays) * 24ULL * 60ULL * 60ULL * 1000ULL;
  if (retentionMs == 0 || nowMs <= retentionMs) {
    return;
  }

  const uint64_t cutoffMs = nowMs - retentionMs;
  File historyFile = openHistoryFile(FILE_READ);
  if (!historyFile) {
    return;
  }

  String kept;
  kept.reserve(HISTORY_FILE_MAX_BYTES + 64);
  bool dropped = false;

  while (historyFile.available()) {
    const String line = historyFile.readStringUntil('\n');
    const int sep = line.indexOf(';');
    if (sep <= 0 || sep >= line.length() - 1) {
      kept += line;
      kept += '\n';
      continue;
    }

    const uint64_t timestampMs = strtoull(line.substring(0, sep).c_str(), nullptr, 10);
    if (timestampMs >= cutoffMs) {
      kept += line;
      kept += '\n';
    } else {
      dropped = true;
    }
  }
  historyFile.close();

  if (!dropped) {
    return;
  }

  File rewrite = openHistoryFile(FILE_WRITE);
  if (!rewrite) {
    return;
  }
  rewrite.print(kept);
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
  pruneHistoryByRetentionIfNeeded(timestampMs, false);
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

bool parseStorageConfigCommand(const char* payload, unsigned int length, uint16_t& sdRetentionDays) {
  String raw;
  raw.reserve(length + 1);
  for (unsigned int i = 0; i < length; i++) {
    raw += static_cast<char>(payload[i]);
  }

  if (raw.indexOf("\"configureStorage\"") < 0 && raw.indexOf("\"sdRetentionDays\"") < 0) {
    return false;
  }

  uint64_t days = 0;
  const bool hasRetention =
      extractUInt64Field(raw, "sdRetentionDays", days) ||
      extractUInt64Field(raw, "storageRetentionDays", days);
  if (!hasRetention || days == 0 || days > MAX_SD_RETENTION_DAYS) {
    return false;
  }

  sdRetentionDays = static_cast<uint16_t>(days);
  return true;
}

void applyStorageConfigCommand(uint16_t sdRetentionDays) {
  config.sdRetentionDays = sdRetentionDays;
  saveConfig();
  pruneHistoryByRetentionIfNeeded(currentEpochMs(), true);
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

  uint16_t sdRetentionDays = 0;
  if (parseStorageConfigCommand(reinterpret_cast<char*>(payload), length, sdRetentionDays)) {
    applyStorageConfigCommand(sdRetentionDays);
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

String jsonEscape(const char* value) {
  String escaped;
  for (size_t i = 0; value[i] != '\0'; i++) {
    const char c = value[i];
    if (c == '"' || c == '\\') {
      escaped += '\\';
    }
    escaped += c;
  }
  return escaped;
}

void clearWifiNetworks() {
  wifiNetworkCount = 0;
  wifiConnectIndex = 0;
  for (uint8_t i = 0; i < WIFI_NETWORK_CAPACITY; i++) {
    wifiNetworks[i].ssid[0] = '\0';
    wifiNetworks[i].password[0] = '\0';
  }
}

int findWifiNetworkIndex(const String& ssid) {
  String target = ssid;
  target.trim();
  for (uint8_t i = 0; i < wifiNetworkCount; i++) {
    if (target == wifiNetworks[i].ssid) {
      return i;
    }
  }
  return -1;
}

void applyWifiNetworkToConfig(uint8_t index) {
  if (index >= wifiNetworkCount) {
    return;
  }
  safeCopy(String(wifiNetworks[index].ssid), config.wifiSsid, sizeof(config.wifiSsid));
  safeCopy(String(wifiNetworks[index].password), config.wifiPassword, sizeof(config.wifiPassword));
}

bool upsertWifiNetwork(String ssid, String password, String oldSsid, bool keepExistingPassword) {
  ssid.trim();
  oldSsid.trim();
  if (ssid.length() == 0 || ssid.length() >= sizeof(config.wifiSsid)) {
    return false;
  }

  int targetIndex = oldSsid.length() > 0 ? findWifiNetworkIndex(oldSsid) : findWifiNetworkIndex(ssid);
  const int duplicateIndex = findWifiNetworkIndex(ssid);
  if (oldSsid.length() > 0 && duplicateIndex >= 0 && duplicateIndex != targetIndex) {
    return false;
  }

  if (targetIndex < 0) {
    if (wifiNetworkCount >= WIFI_NETWORK_CAPACITY) {
      return false;
    }
    targetIndex = wifiNetworkCount;
    wifiNetworkCount++;
  }

  safeCopy(ssid, wifiNetworks[targetIndex].ssid, sizeof(wifiNetworks[targetIndex].ssid));
  if (!keepExistingPassword || wifiNetworks[targetIndex].password[0] == '\0') {
    safeCopy(password, wifiNetworks[targetIndex].password, sizeof(wifiNetworks[targetIndex].password));
  }
  applyWifiNetworkToConfig(static_cast<uint8_t>(targetIndex));
  config.valid = wifiNetworkCount > 0 && strlen(config.mqttHost) > 0;
  return true;
}

bool deleteWifiNetwork(String ssid) {
  const int index = findWifiNetworkIndex(ssid);
  if (index < 0) {
    return false;
  }

  for (uint8_t i = static_cast<uint8_t>(index); i + 1 < wifiNetworkCount; i++) {
    wifiNetworks[i] = wifiNetworks[i + 1];
  }
  wifiNetworkCount--;
  wifiNetworks[wifiNetworkCount].ssid[0] = '\0';
  wifiNetworks[wifiNetworkCount].password[0] = '\0';

  if (wifiNetworkCount > 0) {
    applyWifiNetworkToConfig(0);
  } else {
    config.wifiSsid[0] = '\0';
    config.wifiPassword[0] = '\0';
  }
  config.valid = wifiNetworkCount > 0 && strlen(config.mqttHost) > 0;
  wifiConnectIndex = 0;
  return true;
}

void loadWifiNetworks(Preferences& prefs) {
  clearWifiNetworks();
  const uint8_t storedCount = prefs.getUChar("wifi_net_count", 0);
  for (uint8_t i = 0; i < storedCount && i < WIFI_NETWORK_CAPACITY; i++) {
    char ssidKey[16];
    char passwordKey[16];
    snprintf(ssidKey, sizeof(ssidKey), "wifi_ssid_%u", i);
    snprintf(passwordKey, sizeof(passwordKey), "wifi_pwd_%u", i);
    const String ssid = prefs.getString(ssidKey, "");
    if (ssid.length() == 0) {
      continue;
    }
    safeCopy(ssid, wifiNetworks[wifiNetworkCount].ssid, sizeof(wifiNetworks[wifiNetworkCount].ssid));
    safeCopy(prefs.getString(passwordKey, ""), wifiNetworks[wifiNetworkCount].password,
             sizeof(wifiNetworks[wifiNetworkCount].password));
    wifiNetworkCount++;
  }

  if (wifiNetworkCount == 0 && strlen(config.wifiSsid) > 0) {
    safeCopy(String(config.wifiSsid), wifiNetworks[0].ssid, sizeof(wifiNetworks[0].ssid));
    safeCopy(String(config.wifiPassword), wifiNetworks[0].password, sizeof(wifiNetworks[0].password));
    wifiNetworkCount = 1;
  }
  if (wifiNetworkCount > 0 && strlen(config.wifiSsid) == 0) {
    applyWifiNetworkToConfig(0);
  }
}

void saveWifiNetworks(Preferences& prefs) {
  prefs.putUChar("wifi_net_count", wifiNetworkCount);
  for (uint8_t i = 0; i < WIFI_NETWORK_CAPACITY; i++) {
    char ssidKey[16];
    char passwordKey[16];
    snprintf(ssidKey, sizeof(ssidKey), "wifi_ssid_%u", i);
    snprintf(passwordKey, sizeof(passwordKey), "wifi_pwd_%u", i);
    if (i < wifiNetworkCount) {
      prefs.putString(ssidKey, wifiNetworks[i].ssid);
      prefs.putString(passwordKey, wifiNetworks[i].password);
    } else {
      prefs.remove(ssidKey);
      prefs.remove(passwordKey);
    }
  }
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
    const uint16_t sdRetentionDays =
        preferences.getUShort("sd_ret_days", DEFAULT_SD_RETENTION_DAYS);

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
    config.sdRetentionDays = sdRetentionDays == 0 || sdRetentionDays > MAX_SD_RETENTION_DAYS
                                 ? DEFAULT_SD_RETENTION_DAYS
                                 : sdRetentionDays;
  }
  loadWifiNetworks(preferences);
  config.valid = wifiNetworkCount > 0 && strlen(config.mqttHost) > 0;

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
  preferences.putUShort("sd_ret_days", config.sdRetentionDays);
  saveWifiNetworks(preferences);
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

  safeCopy(mqttHost, config.mqttHost, sizeof(config.mqttHost));
  config.mqttPort = mqttPort;
  safeCopy(provisionServer.arg("mqttUser"), config.mqttUser, sizeof(config.mqttUser));
  safeCopy(provisionServer.arg("mqttPassword"), config.mqttPassword, sizeof(config.mqttPassword));
  safeCopy(mqttTopic, config.mqttTopic, sizeof(config.mqttTopic));
  safeCopy(mqttRequestTopic, config.mqttRequestTopic, sizeof(config.mqttRequestTopic));
  safeCopy(clientId, config.mqttClientId, sizeof(config.mqttClientId));
  config.useTls = provisionServer.arg("useTls") == "1";
  if (!upsertWifiNetwork(ssid, provisionServer.arg("wifiPassword"))) {
    return false;
  }

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

void handleWifiNetworksList() {
  String body = "{\"ok\":true,\"networks\":[";
  for (uint8_t i = 0; i < wifiNetworkCount; i++) {
    if (i > 0) {
      body += ',';
    }
    body += "{\"ssid\":\"";
    body += jsonEscape(wifiNetworks[i].ssid);
    body += "\",\"active\":";
    body += strcmp(wifiNetworks[i].ssid, config.wifiSsid) == 0 ? "true" : "false";
    body += "}";
  }
  body += "]}";
  provisionServer.send(200, "application/json", body);
}

void handleWifiNetworkSave() {
  if (!provisionServer.hasArg("ssid")) {
    provisionServer.send(
        400, "application/json", "{\"ok\":false,\"message\":\"Informe o SSID da rede.\"}");
    return;
  }

  const String ssid = provisionServer.arg("ssid");
  const String oldSsid = provisionServer.hasArg("oldSsid") ? provisionServer.arg("oldSsid") : "";
  const String password =
      provisionServer.hasArg("wifiPassword") ? provisionServer.arg("wifiPassword") : "";
  const bool keepPassword = provisionServer.arg("keepPassword") == "1";

  if (!upsertWifiNetwork(ssid, password, oldSsid, keepPassword)) {
    provisionServer.send(
        400,
        "application/json",
        "{\"ok\":false,\"message\":\"Nao foi possivel salvar a rede. Verifique duplicidade ou limite.\"}");
    return;
  }

  saveConfig();
  provisionServer.send(
      200, "application/json", "{\"ok\":true,\"message\":\"Rede Wi-Fi salva no ESP32.\"}");
}

void handleWifiNetworkDelete() {
  if (!provisionServer.hasArg("ssid")) {
    provisionServer.send(
        400, "application/json", "{\"ok\":false,\"message\":\"Informe o SSID da rede.\"}");
    return;
  }

  if (!deleteWifiNetwork(provisionServer.arg("ssid"))) {
    provisionServer.send(
        404, "application/json", "{\"ok\":false,\"message\":\"Rede Wi-Fi nao encontrada.\"}");
    return;
  }

  saveConfig();
  provisionServer.send(
      200, "application/json", "{\"ok\":true,\"message\":\"Rede Wi-Fi excluida do ESP32.\"}");
}

void startProvisioningServer() {
  if (provisionServerStarted) {
    return;
  }

  provisionServer.on("/health", HTTP_GET, handleHealth);
  provisionServer.on("/provision", HTTP_POST, handleProvision);
  provisionServer.on("/wifi-networks", HTTP_GET, handleWifiNetworksList);
  provisionServer.on("/wifi-networks", HTTP_POST, handleWifiNetworkSave);
  provisionServer.on("/wifi-networks/delete", HTTP_POST, handleWifiNetworkDelete);
  provisionServer.begin();
  provisionServerStarted = true;
}

void startProvisioningMode() {
  provisioningMode = true;
  WiFi.mode(WIFI_AP);
  WiFi.softAP(PROVISION_AP_SSID, PROVISION_AP_PASSWORD);
  startProvisioningServer();
}

void connectWiFi() {
  if (!config.valid || wifiNetworkCount == 0) {
    return;
  }

  if (wifiConnectIndex >= wifiNetworkCount) {
    wifiConnectIndex = 0;
  }
  applyWifiNetworkToConfig(wifiConnectIndex);
  wifiConnectIndex = (wifiConnectIndex + 1) % wifiNetworkCount;
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

  const DeviceStorageUsage storage = readDeviceStorageUsage();
  snprintf(payloadBuffer,
           payloadBufferSize,
           "{\"voltage\":%.2f,\"current\":%.3f,\"power\":%.2f,\"pf\":%.3f,\"frequency\":%.2f,\"energy\":%.3f,"
           "\"storage\":{\"usingSd\":%s,\"sdAvailable\":%s,\"sdUsedBytes\":%llu,\"sdTotalBytes\":%llu,\"sdUsagePercent\":%.2f}}",
           voltage,
           current,
           power,
           pf,
           frequency,
           energy,
           storage.usingSd ? "true" : "false",
           storage.sdAvailable ? "true" : "false",
           static_cast<unsigned long long>(storage.usedBytes),
           static_cast<unsigned long long>(storage.totalBytes),
           storage.usagePercent);

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
  startProvisioningServer();
}

void loop() {
  if (provisionServerStarted) {
    provisionServer.handleClient();
  }

  if (provisioningMode) {
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
