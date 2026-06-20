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
#include <Wire.h>
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
  char wifiUsername[65];
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
  char username[65];
  char password[65];
};

DeviceConfig config = {
  "",
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
constexpr unsigned long WIFI_FALLBACK_AP_DELAY_MS = 60UL * 1000UL;
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
#define EMETRICS_SD_CS_PIN 14
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

#ifndef EMETRICS_I2C_SDA_PIN
#define EMETRICS_I2C_SDA_PIN 21
#endif

#ifndef EMETRICS_I2C_SCL_PIN
#define EMETRICS_I2C_SCL_PIN 22
#endif

#ifndef EMETRICS_LCD_I2C_ADDRESS
#define EMETRICS_LCD_I2C_ADDRESS 0x27  // Endereco I2C do LCD (0x27 ou 0x3F comumente)
#endif

#ifndef EMETRICS_LCD_COLS
#define EMETRICS_LCD_COLS 20
#endif

#ifndef EMETRICS_LCD_ROWS
#define EMETRICS_LCD_ROWS 4
#endif

WiFiClient wifiClient;
WiFiClientSecure secureClient;
PubSubClient mqttClient(wifiClient);
WebServer provisionServer(80);
Preferences preferences;

// UART2 (ESP32): RX=16, TX=17
PZEM004Tv30 pzem(Serial2, 16, 17);

// LCD 4x20 I2C Display - Driver simplificado com PCF8574
// Usa apenas Wire para comunicacao, sem bibliotecas externas
class SimpleLCD {
private:
  uint8_t address;
  uint8_t cols;
  uint8_t rows;
  uint8_t currentRow = 0;
  uint8_t currentCol = 0;
  
  // PCF8574 pin mapping (backpack)
  static constexpr uint8_t RS = 0;   // Register Select
  static constexpr uint8_t RW = 1;   // Read/Write
  static constexpr uint8_t EN = 2;   // Enable
  static constexpr uint8_t BL = 3;   // Backlight
  static constexpr uint8_t D4 = 4;   // Data pins
  static constexpr uint8_t D5 = 5;
  static constexpr uint8_t D6 = 6;

  void write4bits(uint8_t value) {
    uint8_t backlightBits = (1 << BL);  // backlight sempre on
    uint8_t data = (value & 0xF0) | backlightBits;
    Wire.beginTransmission(address);
    Wire.write(data | (1 << EN));  // com enable alto
    Wire.endTransmission();
    delayMicroseconds(1);
    Wire.beginTransmission(address);
    Wire.write(data & ~(1 << EN));  // com enable baixo
    Wire.endTransmission();
    delayMicroseconds(100);
  }
  
  void sendCommand(uint8_t cmd) {
    write4bits(cmd & 0xF0);
    write4bits((cmd << 4) & 0xF0);
  }
  
public:
  SimpleLCD(uint8_t addr, uint8_t c, uint8_t r) : address(addr), cols(c), rows(r) {}
  
  void init() {
    delay(500);
    // Inicializacao do LCD em modo 4-bits
    write4bits(0x30);
    delay(5);
    write4bits(0x30);
    delayMicroseconds(100);
    write4bits(0x30);
    delay(5);
    write4bits(0x20);  // modo 4-bits
    delay(5);
    
    sendCommand(0x28);  // 4-bit, 2 linhas, fonte 5x8
    sendCommand(0x0C);  // display on, cursor off, blink off
    sendCommand(0x06);  // auto increment, sem shift
    clear();
  }
  
  void clear() {
    sendCommand(0x01);
    delay(2);
    currentRow = 0;
    currentCol = 0;
  }
  
  void backlight() {
    // Backlight eh ligado por padrao no metodo write4bits
    // Este metodo e chamado por compatibilidade
  }
  
  void setCursor(uint8_t col, uint8_t row) {
    currentCol = col;
    currentRow = row;
    uint8_t addr = 0x80;
    if (row == 1) addr = 0xC0;
    else if (row == 2) addr = 0x94;
    else if (row == 3) addr = 0xD4;
    addr += col;
    sendCommand(addr);
  }
  
  void print(const char* str) {
    while (*str) {
      uint8_t backlightBits = (1 << BL);  // backlight on
      uint8_t data = (*str & 0xF0) | (1 << RS) | backlightBits;  // RS alto para dados
      Wire.beginTransmission(address);
      Wire.write(data | (1 << EN));
      Wire.endTransmission();
      delayMicroseconds(1);
      Wire.beginTransmission(address);
      Wire.write(data & ~(1 << EN));
      Wire.endTransmission();
      delayMicroseconds(100);
      
      data = ((*str << 4) & 0xF0) | (1 << RS) | backlightBits;
      Wire.beginTransmission(address);
      Wire.write(data | (1 << EN));
      Wire.endTransmission();
      delayMicroseconds(1);
      Wire.beginTransmission(address);
      Wire.write(data & ~(1 << EN));
      Wire.endTransmission();
      delayMicroseconds(100);
      
      currentCol++;
      str++;
    }
  }
  
  void print(float value, uint8_t decimals) {
    char buf[16];
    dtostrf(value, 0, decimals, buf);
    print(buf);
  }
  
  void print(const String& str) {
    print(str.c_str());
  }
};

SimpleLCD lcd(EMETRICS_LCD_I2C_ADDRESS, EMETRICS_LCD_COLS, EMETRICS_LCD_ROWS);

unsigned long lastLcdUpdateMs = 0;
uint8_t lcdDisplayIndex = 0;  // indice para rotacao entre diferentes dados
unsigned long lastMetricRotateMs = 0;
size_t networkNameScrollOffset = 0;
String networkNameScrollSource = "";
constexpr unsigned long LCD_UPDATE_INTERVAL_MS = 700;   // atualizacao visual do LCD
constexpr unsigned long LCD_METRIC_ROTATE_INTERVAL_MS = 4000;  // troca de informacao a cada 4 segundos

unsigned long lastPublishMs = 0;
unsigned long lastWifiAttemptMs = 0;
unsigned long wifiDisconnectedSinceMs = 0;
unsigned long lastMqttAttemptMs = 0;
SavedWifiNetwork wifiNetworks[WIFI_NETWORK_CAPACITY];
uint8_t wifiNetworkCount = 0;
uint8_t wifiConnectIndex = 0;
char telemetryQueue[TELEMETRY_QUEUE_CAPACITY][TELEMETRY_PAYLOAD_SIZE];
size_t queueHead = 0;
size_t queueCount = 0;

bool provisioningMode = false;
bool provisionServerStarted = false;
bool fallbackApActive = false;
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

struct DeviceStorageUsage {
  bool sdAvailable = false;
  bool usingSd = false;
  uint64_t usedBytes = 0;
  uint64_t totalBytes = 0;
  float usagePercent = 0.0f;
};

uint64_t currentEpochMs();
void appendHistoryRecord(const char* payload, uint64_t timestampMs);
void replayHistoryRange(uint64_t fromMs, uint64_t toMs);
HistoryRequest parseHistoryRequest(const char* payload, unsigned int length);
DeviceStorageUsage readDeviceStorageUsage();
bool parseStorageConfigCommand(const char* payload, unsigned int length, uint16_t& sdRetentionDays);
void applyStorageConfigCommand(uint16_t sdRetentionDays);
void pruneHistoryByRetentionIfNeeded(uint64_t nowMs, bool force);
void onMqttMessage(char* topic, byte* payload, unsigned int length);
File openHistoryFile(const char* mode);
bool removeHistoryFile();
bool buildMetricsPayload(char* payloadBuffer, size_t payloadBufferSize);
void saveConfig();
void saveWifiNetworks(Preferences& prefs);
void loadWifiNetworks(Preferences& prefs);
bool upsertWifiNetwork(String ssid,
                       String username,
                       String password,
                       String oldSsid = "",
                       bool keepExistingUsername = false,
                       bool keepExistingPassword = false);
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
    wifiNetworks[i].username[0] = '\0';
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
  safeCopy(String(wifiNetworks[index].username), config.wifiUsername, sizeof(config.wifiUsername));
  safeCopy(String(wifiNetworks[index].password), config.wifiPassword, sizeof(config.wifiPassword));
}

bool upsertWifiNetwork(String ssid,
                       String username,
                       String password,
                       String oldSsid,
                       bool keepExistingUsername,
                       bool keepExistingPassword) {
  ssid.trim();
  username.trim();
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
  if (!keepExistingUsername || wifiNetworks[targetIndex].username[0] == '\0') {
    safeCopy(username, wifiNetworks[targetIndex].username, sizeof(wifiNetworks[targetIndex].username));
  }
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
  wifiNetworks[wifiNetworkCount].username[0] = '\0';
  wifiNetworks[wifiNetworkCount].password[0] = '\0';

  if (wifiNetworkCount > 0) {
    applyWifiNetworkToConfig(0);
  } else {
    config.wifiSsid[0] = '\0';
    config.wifiUsername[0] = '\0';
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
    char usernameKey[16];
    char passwordKey[16];
    snprintf(ssidKey, sizeof(ssidKey), "wifi_ssid_%u", i);
    snprintf(usernameKey, sizeof(usernameKey), "wifi_user_%u", i);
    snprintf(passwordKey, sizeof(passwordKey), "wifi_pwd_%u", i);
    const String ssid = prefs.getString(ssidKey, "");
    if (ssid.length() == 0) {
      continue;
    }
    safeCopy(ssid, wifiNetworks[wifiNetworkCount].ssid, sizeof(wifiNetworks[wifiNetworkCount].ssid));
    safeCopy(prefs.getString(usernameKey, ""), wifiNetworks[wifiNetworkCount].username,
             sizeof(wifiNetworks[wifiNetworkCount].username));
    safeCopy(prefs.getString(passwordKey, ""), wifiNetworks[wifiNetworkCount].password,
             sizeof(wifiNetworks[wifiNetworkCount].password));
    wifiNetworkCount++;
  }

  if (wifiNetworkCount == 0 && strlen(config.wifiSsid) > 0) {
    safeCopy(String(config.wifiSsid), wifiNetworks[0].ssid, sizeof(wifiNetworks[0].ssid));
    safeCopy(String(config.wifiUsername), wifiNetworks[0].username, sizeof(wifiNetworks[0].username));
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
    char usernameKey[16];
    char passwordKey[16];
    snprintf(ssidKey, sizeof(ssidKey), "wifi_ssid_%u", i);
    snprintf(usernameKey, sizeof(usernameKey), "wifi_user_%u", i);
    snprintf(passwordKey, sizeof(passwordKey), "wifi_pwd_%u", i);
    if (i < wifiNetworkCount) {
      prefs.putString(ssidKey, wifiNetworks[i].ssid);
      prefs.putString(usernameKey, wifiNetworks[i].username);
      prefs.putString(passwordKey, wifiNetworks[i].password);
    } else {
      prefs.remove(ssidKey);
      prefs.remove(usernameKey);
      prefs.remove(passwordKey);
    }
  }
}

void loadConfig() {
  preferences.begin("emetrics", true);
  const bool valid = preferences.getBool("cfg_valid", false);

  if (valid) {
    const String wifiSsid = preferences.getString("wifi_ssid", "");
    const String wifiUsername = preferences.getString("wifi_user", "");
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
    safeCopy(wifiUsername, config.wifiUsername, sizeof(config.wifiUsername));
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
  preferences.putString("wifi_user", config.wifiUsername);
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
  String body = "{\"ok\":true,\"mode\":\"";
  body += provisioningMode ? "provisioning" : (fallbackApActive ? "fallback_ap" : "normal");
  body += "\",\"fallbackAp\":";
  body += fallbackApActive ? "true" : "false";
  body += ",\"message\":\"ESP pronto para receber configuracao.\"}";
  provisionServer.send(
      200,
      "application/json",
      body);
}

void handleMetrics() {
  char payload[TELEMETRY_PAYLOAD_SIZE];
  if (!buildMetricsPayload(payload, sizeof(payload))) {
    provisionServer.send(
        503,
        "application/json",
        "{\"ok\":false,\"message\":\"Falha ao ler medicao local do PZEM.\"}");
    return;
  }

  provisionServer.send(200, "application/json", payload);
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
  if (!upsertWifiNetwork(ssid,
                         provisionServer.arg("wifiUsername"),
                         provisionServer.arg("wifiPassword"))) {
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
    body += "\",\"hasUsername\":";
    body += wifiNetworks[i].username[0] == '\0' ? "false" : "true";
    body += ",\"active\":";
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
  const String username =
      provisionServer.hasArg("wifiUsername") ? provisionServer.arg("wifiUsername") : "";
  const String password =
      provisionServer.hasArg("wifiPassword") ? provisionServer.arg("wifiPassword") : "";
    const bool keepUsername = provisionServer.arg("keepUsername") == "1";
  const bool keepPassword = provisionServer.arg("keepPassword") == "1";

    if (!upsertWifiNetwork(ssid, username, password, oldSsid, keepUsername, keepPassword)) {
    provisionServer.send(
        400,
        "application/json",
        "{\"ok\":false,\"message\":\"Nao foi possivel salvar a rede. Verifique duplicidade ou limite.\"}");
    return;
  }

  saveConfig();

  if (provisioningMode) {
    provisionServer.send(
        200,
        "application/json",
        "{\"ok\":true,\"message\":\"Rede Wi-Fi salva. ESP32 vai reconectar.\"}");
    scheduleRestart();
  } else {
    provisionServer.send(
        200, "application/json", "{\"ok\":true,\"message\":\"Rede Wi-Fi salva no ESP32.\"}");
  }
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
  provisionServer.on("/metrics", HTTP_GET, handleMetrics);
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

void startFallbackAccessPoint() {
  if (provisioningMode || fallbackApActive) {
    return;
  }

  fallbackApActive = true;
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(PROVISION_AP_SSID, PROVISION_AP_PASSWORD);
  startProvisioningServer();
}

void stopFallbackAccessPoint() {
  if (provisioningMode || !fallbackApActive) {
    return;
  }

  WiFi.softAPdisconnect(true);
  fallbackApActive = false;
  WiFi.mode(WIFI_STA);
  wifiDisconnectedSinceMs = 0;
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
  WiFi.mode(fallbackApActive ? WIFI_AP_STA : WIFI_STA);
  if (wifiDisconnectedSinceMs == 0) {
    wifiDisconnectedSinceMs = millis();
  }
  WiFi.begin(config.wifiSsid, config.wifiPassword);
}

void ensureFallbackAccessPoint() {
  if (provisioningMode) {
    return;
  }

  if (!config.valid || wifiNetworkCount == 0) {
    wifiDisconnectedSinceMs = 0;
    startFallbackAccessPoint();
    return;
  }

  if (WiFi.status() == WL_CONNECTED) {
    stopFallbackAccessPoint();
    return;
  }

  const unsigned long now = millis();
  if (wifiDisconnectedSinceMs == 0) {
    wifiDisconnectedSinceMs = now;
  }

  if (now - wifiDisconnectedSinceMs >= WIFI_FALLBACK_AP_DELAY_MS) {
    startFallbackAccessPoint();
  }
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

void printLcdLine(uint8_t row, String text) {
  if (text.length() > 20) {
    text = text.substring(0, 20);
  }

  lcd.setCursor(0, row);
  lcd.print(text);
  for (size_t i = text.length(); i < 20; i++) {
    lcd.print(" ");
  }
}

String currentWifiTypeLabel() {
  if (provisioningMode || fallbackApActive) {
    return "AP";
  }
  if (WiFi.status() == WL_CONNECTED) {
    return "STA";
  }
  return "OFF";
}

String currentNetworkNameLabel() {
  const String prefix = "Rede: ";

  if (provisioningMode || fallbackApActive) {
    return prefix + String(PROVISION_AP_SSID);
  }
  if (WiFi.status() == WL_CONNECTED) {
    return prefix + WiFi.SSID();
  }
  return "Rede: sem conexao";
}

String currentNetworkLineForLcd() {
  const size_t maxLineLen = 20;
  const String base = currentNetworkNameLabel();

  if (base != networkNameScrollSource) {
    networkNameScrollSource = base;
    networkNameScrollOffset = 0;
  }

  if (base.length() <= maxLineLen) {
    return base;
  }

  const String marquee = base + "   ";
  if (networkNameScrollOffset >= marquee.length()) {
    networkNameScrollOffset = 0;
  }

  String line = "";
  for (size_t i = 0; i < maxLineLen; i++) {
    const size_t idx = (networkNameScrollOffset + i) % marquee.length();
    line += marquee[idx];
  }

  networkNameScrollOffset = (networkNameScrollOffset + 1) % marquee.length();
  return line;
}

String formatMetricLine(const String& label, const String& value) {
  return label + ": " + value;
}

// ═══════════════════════════════════════════════════════════════════════════
// LCD 4x20 I2C - ATUALIZACAO DE DISPLAY
// Rotacao entre diferentes dados de medicao em intervalos fixos
// ═══════════════════════════════════════════════════════════════════════════

void updateLcdDisplay() {
  const unsigned long now = millis();
  if (now - lastLcdUpdateMs < LCD_UPDATE_INTERVAL_MS) {
    return;  // nao e hora de atualizar ainda
  }
  lastLcdUpdateMs = now;

  if (lastMetricRotateMs == 0) {
    lastMetricRotateMs = now;
  } else if (now - lastMetricRotateMs >= LCD_METRIC_ROTATE_INTERVAL_MS) {
    lastMetricRotateMs = now;
    lcdDisplayIndex = (lcdDisplayIndex + 1) % 4;
  }

  // Le os dados atuais do PZEM
  float voltage = pzem.voltage();
  float current = pzem.current();
  float power = pzem.power();
  float energy = pzem.energy();
  float frequency = pzem.frequency();
  float pf = pzem.pf();
  float apparentPower = voltage * current;
  float reactivePowerSquared = apparentPower * apparentPower - power * power;
  float reactivePower = reactivePowerSquared > 0.0f ? sqrtf(reactivePowerSquared) : 0.0f;
  static unsigned long lastEnergyUpdateMs = 0;
  static float apparentEnergyKvah = 0.0f;
  static float reactiveEnergyKvarh = 0.0f;

  if (lcdDisplayIndex == 3) {
    String wifiStatus = WiFi.status() == WL_CONNECTED ? "STA OK" :
                        (provisioningMode || fallbackApActive ? "AP ativo" : "sem conexao");
    printLcdLine(0, String("WiFi: ") + wifiStatus);
    printLcdLine(1, currentNetworkLineForLcd());
    printLcdLine(2, String("MQTT:") + (mqttClient.connected() ? "OK" : "OFF") + " Fila:" + queueCount);
    printLcdLine(3, String("Broker:") + String(config.mqttHost).substring(0, 13));
    return;
  }

  // Verifica se leitura foi bem-sucedida
  if (isnan(voltage) || isnan(current) || isnan(power)) {
    printLcdLine(0, "Erro ao ler PZEM");
    printLcdLine(1, "Verifique conexao");
    printLcdLine(2, "");
    printLcdLine(3, String("MQTT: ") + (mqttClient.connected() ? "ON" : "OFF"));
    return;
  }

  if (lastEnergyUpdateMs != 0 && now > lastEnergyUpdateMs) {
    const float elapsedHours = static_cast<float>(now - lastEnergyUpdateMs) / 3600000.0f;
    apparentEnergyKvah += apparentPower * elapsedHours;
    reactiveEnergyKvarh += reactivePower * elapsedHours;
  }
  lastEnergyUpdateMs = now;

  if (lcdDisplayIndex == 0) {
    printLcdLine(0, formatMetricLine("Tensao", String(voltage, 1) + " V"));
    printLcdLine(1, formatMetricLine("Corrente", String(current, 3) + " A"));
    printLcdLine(2, formatMetricLine("Frequencia", String(frequency, 2) + " Hz"));
    printLcdLine(3, "");
    return;
  }

  if (lcdDisplayIndex == 1) {
    printLcdLine(0, formatMetricLine("P.Ativa", String(power, 2) + " W"));
    printLcdLine(1, formatMetricLine("P.Apte.", String(apparentPower, 2) + " VA"));
    printLcdLine(2, formatMetricLine("P.Reat.", String(reactivePower, 2) + " VAr"));
    printLcdLine(3, formatMetricLine("FP", isnan(pf) ? String("N/A") : String(pf, 3)));
    return;
  }

  if (lcdDisplayIndex == 2) {
    printLcdLine(0, formatMetricLine("E.Ativa", String(energy, 2) + " kWh"));
    printLcdLine(1, formatMetricLine("E.Apte.", String(apparentEnergyKvah, 2) + " kVAh"));
    printLcdLine(2, formatMetricLine("E.Reat.", String(reactiveEnergyKvarh, 2) + " kVArh"));
    printLcdLine(3, "");
    return;
  }

  {
    String wifiStatus = WiFi.status() == WL_CONNECTED ? "STA OK" :
                        (provisioningMode || fallbackApActive ? "AP ativo" : "sem conexao");
    printLcdLine(0, String("WiFi: ") + wifiStatus);
    printLcdLine(1, currentNetworkLineForLcd());
    printLcdLine(2, String("MQTT:") + (mqttClient.connected() ? "OK" : "OFF") + " Fila:" + queueCount);
    printLcdLine(3, String("Broker:") + String(config.mqttHost).substring(0, 13));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SETUP E LOOP PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, 16, 17);

  // ═══════════════════════════════════════════════════════════════════════════
  // INICIALIZACAO I2C PARA DISPLAY LCD 4x20 (GPIO21/22)
  // ═══════════════════════════════════════════════════════════════════════════
  Wire.begin(EMETRICS_I2C_SDA_PIN, EMETRICS_I2C_SCL_PIN, 100000);
  delay(500);  // aguarda estabilizacao I2C
  
  // Inicializa LCD: set the LCD address to 0x27 for a 20 chars 4 line display
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("EMetrics IoT");
  lcd.setCursor(0, 1);
  lcd.print("Display 4x20 OK");
  delay(2000);  // mostra mensagem inicial por 2 segundos
  lcd.clear();

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

  if (restartScheduled && millis() - restartScheduledAtMs >= 1500) {
    ESP.restart();
  }

  if (provisioningMode) {
    updateLcdDisplay();
    return;
  }

  ensureFallbackAccessPoint();
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

  // Atualiza display LCD com dados de medicao alternando
  updateLcdDisplay();
}
