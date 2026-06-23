// ═══════════════════════════════════════════════════════════════════════════
// CHANGELOG — REVISAO DE OTIMIZACAO (sem mudanca de funcionalidade)
// ---------------------------------------------------------------------------
// Todas as funcionalidades originais foram mantidas: provisionamento, fallback
// AP, OTA, historico SD/SPIFFS, fila offline, modo hibrido Wi-Fi, WPA2-Ent,
// comandos MQTT (resetEnergy, setPublishInterval, setSelfConsumption,
// setHybridWifi, configureStorage), endpoints HTTP e rotacao do LCD.
// O SCHEMA do JSON publicado e' byte-a-byte identico ao original.
//
// [1] LEITURA UNICA DO PZEM POR CICLO
//     Antes o PZEM era lido em buildMetricsPayload() e, separadamente, em
//     updateLcdDisplay(), podendo exibir/publicar frames diferentes. Agora
//     ha um unico frame compartilhado (latestReading) consumido pelos dois.
//     LCD e MQTT passam a refletir SEMPRE a mesma leitura. Cadencia de leitura
//     limitada (200-500 ms) -> elimina transacoes Modbus redundantes.
//
// [2] CACHE DE SD.usedBytes()/totalBytes()
//     Antes calculado em CADA payload (a cada ~2 s) e em cada GET /metrics;
//     em FAT isso varre a tabela de alocacao (dezenas/centenas de ms). Agora
//     cacheado e atualizado a cada 30 s. Campos do JSON inalterados.
//
// [3] REPLAY DE HISTORICO NAO-BLOQUEANTE
//     Antes replayHistoryRange() bloqueava ate' ~3 s (delay por linha) dentro
//     do callback MQTT, congelando LCD/OTA/mqttClient.loop(). Agora e' uma
//     maquina de estados (startHistoryReplay + pumpHistoryReplay) acionada
//     pelo loop(); mesmas linhas, mesmo topico, mesmo retain. Um novo pedido
//     durante um replay em andamento REINICIA com o novo intervalo.
//
// [4] LCD COM DIRTY-CHECK
//     printLcdLine() so reescreve a linha no barramento I2C quando o conteudo
//     muda (cache por linha) -> menos trafego I2C e fim do flicker. Marquee de
//     SSID longo continua rolando normalmente.
//
// [5] setBufferSize() MOVIDO PARA O setup()
//     Antes era chamado a cada tentativa de reconexao MQTT, realocando o
//     buffer (fragmenta o heap em quedas longas). Agora definido uma vez.
//
// [6] COMPACTACAO/PRUNE DO HISTORICO VIA ARQUIVO TEMPORARIO
//     Antes carregava ate' 256 KB do arquivo num String em RAM (arriscado no
//     ESP32). Agora faz streaming linha-a-linha para /history.tmp e troca por
//     rename() atomico; o original so' e' removido apos o temporario existir.
//     Mesmas linhas mantidas/descartadas; RAM de pico minima.
//
// [7] PAYLOAD MQTT CONVERTIDO UMA UNICA VEZ
//     onMqttMessage() montava o payload em String ate' 3x (no proprio handler
//     e de novo em parseStorageConfigCommand/parseHistoryRequest). Agora monta
//     1x e repassa por referencia.
// ═══════════════════════════════════════════════════════════════════════════

#if !defined(ESP32)
#error Este firmware requer placa ESP32. No Arduino IDE, selecione uma placa ESP32 (ex.: ESP32 Dev Module).
#endif

// ═══════════════════════════════════════════════════════════════════════════
// INCLUDES
// ═══════════════════════════════════════════════════════════════════════════
#include <ArduinoOTA.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <esp_eap_client.h>
#include <PZEM004Tv30.h>
#include <FS.h>
#include <SD.h>
#include <SPIFFS.h>
#include <SPI.h>
#include <Update.h>
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
  char otaPassword[65];
  bool useTls;
  uint16_t sdRetentionDays;
  uint16_t wifiInitialConnectTimeoutSeconds;
  uint16_t wifiRetryIntervalSeconds;
  uint16_t wifiFallbackApDelaySeconds;
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
  "",
  false,
  30,
  20,
  15,
  60,
  false,
};

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTES E VARIAVEIS GLOBAIS
// ═══════════════════════════════════════════════════════════════════════════
constexpr unsigned long PUBLISH_INTERVAL_MS_DEFAULT = 2000; // intervalo padrao entre leituras PZEM
constexpr uint16_t DEFAULT_WIFI_INITIAL_CONNECT_TIMEOUT_SECONDS = 20;
constexpr uint16_t DEFAULT_WIFI_RETRY_INTERVAL_SECONDS = 15;
constexpr uint16_t DEFAULT_WIFI_FALLBACK_AP_DELAY_SECONDS = 60;
constexpr uint16_t MIN_WIFI_CONNECTION_DELAY_SECONDS = 5;
constexpr uint16_t MAX_WIFI_CONNECTION_DELAY_SECONDS = 600;
constexpr const char* OTA_AUTH_HEADER = "X-EMetrics-OTA-Key";
const char* OTA_REQUEST_HEADERS[] = {OTA_AUTH_HEADER};
constexpr unsigned long MQTT_RETRY_INTERVAL_MS = 3000;    // retentativa de reconexao MQTT
constexpr bool MQTT_RETAINED = true;
// O payload inclui metadados de rastreabilidade (E13) e estado do SD. O
// PubSubClient conta tópico e cabeçalhos dentro do próprio buffer, por isso o
// buffer MQTT precisa ser maior que o JSON isolado.
constexpr size_t TELEMETRY_PAYLOAD_SIZE = 512;            // bytes por payload JSON
constexpr size_t MQTT_BUFFER_SIZE = 768;                  // payload + tópico MQTT + cabeçalhos
constexpr size_t TELEMETRY_QUEUE_CAPACITY = 30;           // capacidade do buffer circular offline
constexpr uint8_t FLUSH_BATCH_LIMIT = 5;                  // publicacoes por iteracao do loop
constexpr uint16_t HISTORY_REPLAY_LIMIT = 300;            // linhas maximas por resposta de historico
constexpr size_t HISTORY_FILE_MAX_BYTES = 256 * 1024;     // 256 KB: tamanho maximo do arquivo de historico
constexpr uint16_t DEFAULT_SD_RETENTION_DAYS = 30;        // retencao padrao do historico local
constexpr uint16_t MAX_SD_RETENTION_DAYS = 3650;          // limite para comando vindo do app
constexpr unsigned long HISTORY_RETENTION_PRUNE_INTERVAL_MS = 60UL * 60UL * 1000UL;
constexpr uint8_t WIFI_NETWORK_CAPACITY = 5;              // redes Wi-Fi salvas no ESP
constexpr const char* HISTORY_FILE_PATH = "/history.log";
constexpr const char* HISTORY_TMP_PATH = "/history.tmp";  // arquivo temporario para compactacao/prune
constexpr uint8_t REPLAY_LINES_PER_CALL = 8;             // linhas de replay processadas por iteracao do loop
constexpr unsigned long STORAGE_USAGE_REFRESH_MS = 30000; // intervalo de atualizacao do uso de disco (cache)
constexpr unsigned long PZEM_REFRESH_FLOOR_MS = 200;     // piso de leitura PZEM (cache interno da lib)
constexpr unsigned long PZEM_REFRESH_CEIL_MS = 500;      // teto de leitura PZEM (mantem LCD responsivo)

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
unsigned long publishIntervalMs = PUBLISH_INTERVAL_MS_DEFAULT; // E7: configuravel via MQTT
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
bool firmwareUpdateAuthorized = false;
bool firmwareUpdateSucceeded = false;
String firmwareUpdateError;
uint64_t bootEpochOffsetMs = 0;
bool bootEpochOffsetValid = false;
bool historyStorageReady = false;
bool historyStorageUsesSd = false;
unsigned long lastHistoryRetentionPruneMs = 0;

// E8: Contador de erros de comunicacao PZEM
uint32_t pzemCrcErrors = 0;
uint8_t lastWifiFailureStatus = 0;  // WL_NO_SSID_AVAIL=1, WL_CONNECT_FAILED=4, WL_DISCONNECTED=6

// Energias acumuladas calculadas em RAM (aparente e reativa — PZEM nao armazena)
unsigned long lcdLastEnergyUpdateMs = 0;
float lcdApparentEnergyKvah = 0.0f;
float lcdReactiveEnergyKvarh = 0.0f;
uint32_t telemetrySequence = 0;  // E13: sequência reinicia a cada boot do ESP

// E10: Compensacao de consumo proprio
float selfConsumptionWatts = 0.0f; // configuravel via MQTT
bool selfConsumptionEnabled = false;

// E11: Modo hibrido Wi-Fi
bool hybridWifiEnabled = false;       // ativado via comando MQTT
uint32_t hybridAcquireWindowMs = 10000; // janela de aquisicao sem Wi-Fi (ms)
uint32_t hybridTxWindowMs = 3000;       // janela de transmissao com Wi-Fi (ms)
unsigned long hybridPhaseStartMs = 0;
bool hybridAcquiringPhase = true;       // true = PZEM ativo, Wi-Fi OFF

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

// [1] Frame unico de leitura do PZEM, compartilhado entre LCD e MQTT.
// Garante que display e telemetria reflitam SEMPRE a mesma leitura.
struct PzemReading {
  float voltage = 0.0f;
  float current = 0.0f;
  float power = 0.0f;
  float energy = 0.0f;
  float frequency = 0.0f;
  float pf = 0.0f;
  float apparentPower = 0.0f;
  float reactivePower = 0.0f;
  bool valid = false;
};
PzemReading latestReading;
unsigned long lastPzemRefreshMs = 0;

// [2] Cache do uso de disco (SD.usedBytes() e custoso em FAT).
DeviceStorageUsage cachedStorageUsage;
unsigned long lastStorageUsageMs = 0;

// [3] Estado da maquina de replay de historico (substitui o replay bloqueante).
struct ReplayState {
  bool active = false;
  File file;
  uint64_t fromMs = 0;
  uint64_t toMs = 0;
  uint16_t published = 0;
};
ReplayState replay;

uint64_t currentEpochMs();
void appendHistoryRecord(const char* payload, uint64_t timestampMs);
void startHistoryReplay(uint64_t fromMs, uint64_t toMs);
void pumpHistoryReplay();
HistoryRequest parseHistoryRequest(const String& raw);
DeviceStorageUsage readDeviceStorageUsage();
const DeviceStorageUsage& storageUsageCached();
bool refreshPzemReading(bool force = false);
bool parseStorageConfigCommand(const String& raw, uint16_t& sdRetentionDays);
void applyStorageConfigCommand(uint16_t sdRetentionDays);
void pruneHistoryByRetentionIfNeeded(uint64_t nowMs, bool force);
void onMqttMessage(char* topic, byte* payload, unsigned int length);
File openHistoryFile(const char* mode);
File openHistoryPath(const char* path, const char* mode);
bool renameHistoryPath(const char* from, const char* to);
bool removeHistoryPath(const char* path);
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
bool moveWifiNetwork(String ssid, int direction);
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

// [6] Helpers genericos por caminho — usados pela compactacao/prune via
// arquivo temporario, abstraindo SD vs SPIFFS.
File openHistoryPath(const char* path, const char* mode) {
  if (historyStorageUsesSd) {
    return SD.open(path, mode);
  }
  return SPIFFS.open(path, mode);
}

bool renameHistoryPath(const char* from, const char* to) {
  if (historyStorageUsesSd) {
    return SD.rename(from, to);
  }
  return SPIFFS.rename(from, to);
}

bool removeHistoryPath(const char* path) {
  if (historyStorageUsesSd) {
    return SD.remove(path);
  }
  return SPIFFS.remove(path);
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

// [2] Devolve o uso de disco a partir de cache; recalcula no maximo a cada
// STORAGE_USAGE_REFRESH_MS para nao varrer a FAT em todo payload.
const DeviceStorageUsage& storageUsageCached() {
  const unsigned long now = millis();
  if (lastStorageUsageMs == 0 || now - lastStorageUsageMs >= STORAGE_USAGE_REFRESH_MS) {
    cachedStorageUsage = readDeviceStorageUsage();
    lastStorageUsageMs = now;
  }
  return cachedStorageUsage;
}

/**
 * [6] Remove a metade mais antiga do arquivo de historico quando ele ultrapassa
 * HISTORY_FILE_MAX_BYTES. Faz streaming linha-a-linha para um arquivo
 * temporario e troca por rename() — evita carregar ate' 128 KB em RAM. O
 * arquivo original so' e' removido apos o temporario ser escrito.
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

  File tmp = openHistoryPath(HISTORY_TMP_PATH, FILE_WRITE);
  if (!tmp) {
    historyFile.close();
    return;
  }

  while (historyFile.available()) {
    tmp.print(historyFile.readStringUntil('\n'));
    tmp.print('\n');
  }
  historyFile.close();
  tmp.close();

  // Troca atomica: remove o original e renomeia o temporario.
  if (!removeHistoryFile()) {
    removeHistoryPath(HISTORY_TMP_PATH);
    return;
  }
  renameHistoryPath(HISTORY_TMP_PATH, HISTORY_FILE_PATH);
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

  // [6] Streaming para arquivo temporario (mesmas linhas mantidas/descartadas).
  File tmp = openHistoryPath(HISTORY_TMP_PATH, FILE_WRITE);
  if (!tmp) {
    historyFile.close();
    return;
  }

  bool dropped = false;
  while (historyFile.available()) {
    const String line = historyFile.readStringUntil('\n');
    const int sep = line.indexOf(';');
    if (sep <= 0 || sep >= line.length() - 1) {
      tmp.print(line);
      tmp.print('\n');
      continue;
    }

    const uint64_t timestampMs = strtoull(line.substring(0, sep).c_str(), nullptr, 10);
    if (timestampMs >= cutoffMs) {
      tmp.print(line);
      tmp.print('\n');
    } else {
      dropped = true;
    }
  }
  historyFile.close();
  tmp.close();

  if (!dropped) {
    removeHistoryPath(HISTORY_TMP_PATH);  // nada mudou; descarta o temporario
    return;
  }

  if (!removeHistoryFile()) {
    removeHistoryPath(HISTORY_TMP_PATH);
    return;
  }
  renameHistoryPath(HISTORY_TMP_PATH, HISTORY_FILE_PATH);
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
HistoryRequest parseHistoryRequest(const String& raw) {
  HistoryRequest request;

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

bool parseStorageConfigCommand(const String& raw, uint16_t& sdRetentionDays) {
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
 * [3] Inicia o replay de historico no intervalo [fromMs, toMs]. NAO bloqueia:
 * apenas abre o arquivo e arma o estado; pumpHistoryReplay() publica em lotes
 * a cada iteracao do loop(). Um novo pedido durante um replay em andamento
 * reinicia com o novo intervalo.
 */
void startHistoryReplay(uint64_t fromMs, uint64_t toMs) {
  if (replay.active && replay.file) {
    replay.file.close();
  }
  replay.active = false;
  replay.published = 0;

  if (!mqttClient.connected() || !ensureHistoryStorageReady()) {
    return;
  }

  replay.file = openHistoryFile(FILE_READ);
  if (!replay.file) {
    return;
  }

  replay.fromMs = fromMs;
  replay.toMs = toMs;
  replay.active = true;
}

/**
 * [3] Avanca o replay em andamento: processa ate' REPLAY_LINES_PER_CALL linhas
 * por chamada e republica as elegiveis no topico principal (mesmo retain). Sem
 * delay() bloqueante — o pacing vem da cadencia natural do loop(), que mantem
 * mqttClient.loop()/OTA/LCD vivos entre os lotes. Respeita HISTORY_REPLAY_LIMIT.
 */
void pumpHistoryReplay() {
  if (!replay.active) {
    return;
  }
  if (!mqttClient.connected()) {  // conexao caiu no meio do replay -> aborta
    replay.file.close();
    replay.active = false;
    return;
  }

  uint8_t processed = 0;
  while (replay.file.available() && replay.published < HISTORY_REPLAY_LIMIT &&
         processed < REPLAY_LINES_PER_CALL) {
    processed++;
    const String line = replay.file.readStringUntil('\n');
    if (line.length() < 5) {
      continue;
    }

    const int sep = line.indexOf(';');
    if (sep <= 0 || sep >= line.length() - 1) {
      continue;
    }

    const uint64_t timestampMs = strtoull(line.substring(0, sep).c_str(), nullptr, 10);
    if (timestampMs < replay.fromMs || timestampMs > replay.toMs) {
      continue;
    }

    const String payload = line.substring(sep + 1);
    if (mqttClient.publish(config.mqttTopic, payload.c_str(), MQTT_RETAINED)) {
      replay.published++;
    }
  }

  if (!replay.file.available() || replay.published >= HISTORY_REPLAY_LIMIT) {
    replay.file.close();
    replay.active = false;
  }
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  if (strcmp(topic, config.mqttRequestTopic) != 0) {
    return;
  }

  // [7] Converte o payload em String uma unica vez e reutiliza abaixo.
  String raw;
  raw.reserve(length + 1);
  for (unsigned int i = 0; i < length; i++) {
    raw += static_cast<char>(payload[i]);
  }

  // E10: configura compensacao de consumo proprio
  // payload: {"command":"setSelfConsumption","watts":1.5,"enabled":true}
  if (raw.indexOf("\"setSelfConsumption\"") >= 0) {
    uint64_t enabledVal = 0;
    const bool hasEnabled = extractUInt64Field(raw, "enabled", enabledVal);
    selfConsumptionEnabled = hasEnabled ? (enabledVal != 0) : selfConsumptionEnabled;
    // watts pode ser float; parse manual simples
    const int wIdx = raw.indexOf("\"watts\"");
    if (wIdx >= 0) {
      const int colonIdx = raw.indexOf(':', wIdx);
      if (colonIdx >= 0) {
        selfConsumptionWatts = atof(raw.c_str() + colonIdx + 1);
      }
    }
    return;
  }

  // E7: configura intervalo de publicacao
  // payload: {"command":"setPublishInterval","intervalMs":500}
  if (raw.indexOf("\"setPublishInterval\"") >= 0) {
    uint64_t intervalVal = 0;
    if (extractUInt64Field(raw, "intervalMs", intervalVal) && intervalVal >= 100 && intervalVal <= 60000) {
      publishIntervalMs = static_cast<unsigned long>(intervalVal);
    }
    return;
  }

  // E11: configura modo hibrido Wi-Fi
  // payload: {"command":"setHybridWifi","enabled":true,"acquireMs":10000,"txMs":3000}
  if (raw.indexOf("\"setHybridWifi\"") >= 0) {
    uint64_t enabledVal = 0;
    extractUInt64Field(raw, "enabled", enabledVal);
    hybridWifiEnabled = (enabledVal != 0);
    uint64_t acqMs = 0, txMs = 0;
    if (extractUInt64Field(raw, "acquireMs", acqMs) && acqMs >= 1000 && acqMs <= 120000) {
      hybridAcquireWindowMs = static_cast<uint32_t>(acqMs);
    }
    if (extractUInt64Field(raw, "txMs", txMs) && txMs >= 500 && txMs <= 30000) {
      hybridTxWindowMs = static_cast<uint32_t>(txMs);
    }
    if (!hybridWifiEnabled) {
      // reativa Wi-Fi ao desligar modo hibrido
      WiFi.mode(fallbackApActive ? WIFI_AP_STA : WIFI_STA);
      hybridAcquiringPhase = true;
    }
    hybridPhaseStartMs = millis();
    return;
  }

  // Zera energia acumulada do PZEM
  // payload: {"command":"resetEnergy"}
  if (raw.indexOf("\"resetEnergy\"") >= 0) {
    resetAllEnergy();
    return;
  }

  uint16_t sdRetentionDays = 0;
  if (parseStorageConfigCommand(raw, sdRetentionDays)) {
    applyStorageConfigCommand(sdRetentionDays);
    return;
  }

  const HistoryRequest request = parseHistoryRequest(raw);
  if (!request.valid) {
    return;
  }

  startHistoryReplay(request.from, request.to);  // [3] nao-bloqueante
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

bool moveWifiNetwork(String ssid, int direction) {
  const int index = findWifiNetworkIndex(ssid);
  const int targetIndex = index + direction;
  if (index < 0 || targetIndex < 0 || targetIndex >= wifiNetworkCount) {
    return false;
  }

  const SavedWifiNetwork movedNetwork = wifiNetworks[index];
  wifiNetworks[index] = wifiNetworks[targetIndex];
  wifiNetworks[targetIndex] = movedNetwork;
  // A proxima tentativa sempre comeca pela maior prioridade da lista editada.
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
    const String otaPassword = preferences.getString("ota_pwd", "");
    const bool useTls = preferences.getBool("mqtt_tls", false);
    const uint16_t sdRetentionDays =
        preferences.getUShort("sd_ret_days", DEFAULT_SD_RETENTION_DAYS);
    const uint16_t wifiInitialConnectTimeoutSeconds = preferences.getUShort(
        "wifi_init_s", DEFAULT_WIFI_INITIAL_CONNECT_TIMEOUT_SECONDS);
    const uint16_t wifiRetryIntervalSeconds = preferences.getUShort(
        "wifi_retry_s", DEFAULT_WIFI_RETRY_INTERVAL_SECONDS);
    const uint16_t wifiFallbackApDelaySeconds = preferences.getUShort(
        "wifi_fallback_s", DEFAULT_WIFI_FALLBACK_AP_DELAY_SECONDS);

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
    safeCopy(otaPassword, config.otaPassword, sizeof(config.otaPassword));
    config.useTls = useTls;
    config.sdRetentionDays = sdRetentionDays == 0 || sdRetentionDays > MAX_SD_RETENTION_DAYS
                                 ? DEFAULT_SD_RETENTION_DAYS
                                 : sdRetentionDays;
    config.wifiInitialConnectTimeoutSeconds =
        wifiInitialConnectTimeoutSeconds < MIN_WIFI_CONNECTION_DELAY_SECONDS ||
                wifiInitialConnectTimeoutSeconds > MAX_WIFI_CONNECTION_DELAY_SECONDS
            ? DEFAULT_WIFI_INITIAL_CONNECT_TIMEOUT_SECONDS
            : wifiInitialConnectTimeoutSeconds;
    config.wifiRetryIntervalSeconds =
        wifiRetryIntervalSeconds < MIN_WIFI_CONNECTION_DELAY_SECONDS ||
                wifiRetryIntervalSeconds > MAX_WIFI_CONNECTION_DELAY_SECONDS
            ? DEFAULT_WIFI_RETRY_INTERVAL_SECONDS
            : wifiRetryIntervalSeconds;
    config.wifiFallbackApDelaySeconds =
        wifiFallbackApDelaySeconds < MIN_WIFI_CONNECTION_DELAY_SECONDS ||
                wifiFallbackApDelaySeconds > MAX_WIFI_CONNECTION_DELAY_SECONDS
            ? DEFAULT_WIFI_FALLBACK_AP_DELAY_SECONDS
            : wifiFallbackApDelaySeconds;
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
  preferences.putString("ota_pwd", config.otaPassword);
  preferences.putBool("mqtt_tls", config.useTls);
  preferences.putUShort("sd_ret_days", config.sdRetentionDays);
  preferences.putUShort("wifi_init_s", config.wifiInitialConnectTimeoutSeconds);
  preferences.putUShort("wifi_retry_s", config.wifiRetryIntervalSeconds);
  preferences.putUShort("wifi_fallback_s", config.wifiFallbackApDelaySeconds);
  saveWifiNetworks(preferences);
  preferences.putBool("cfg_valid", config.valid);
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
  refreshPzemReading(true);  // [1] leitura fresca sob demanda (mantem comportamento do endpoint)
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

bool applyWifiConnectionSettings(long initialConnectTimeoutSeconds,
                                 long retryIntervalSeconds,
                                 long fallbackApDelaySeconds) {
  if (initialConnectTimeoutSeconds < MIN_WIFI_CONNECTION_DELAY_SECONDS ||
      initialConnectTimeoutSeconds > MAX_WIFI_CONNECTION_DELAY_SECONDS ||
      retryIntervalSeconds < MIN_WIFI_CONNECTION_DELAY_SECONDS ||
      retryIntervalSeconds > MAX_WIFI_CONNECTION_DELAY_SECONDS ||
      fallbackApDelaySeconds < MIN_WIFI_CONNECTION_DELAY_SECONDS ||
      fallbackApDelaySeconds > MAX_WIFI_CONNECTION_DELAY_SECONDS) {
    return false;
  }

  config.wifiInitialConnectTimeoutSeconds = static_cast<uint16_t>(initialConnectTimeoutSeconds);
  config.wifiRetryIntervalSeconds = static_cast<uint16_t>(retryIntervalSeconds);
  config.wifiFallbackApDelaySeconds = static_cast<uint16_t>(fallbackApDelaySeconds);
  return true;
}

bool applyWifiConnectionSettingsFromRequest(bool allowMissingSettings) {
  const bool hasInitial = provisionServer.hasArg("initialConnectTimeoutSeconds");
  const bool hasRetry = provisionServer.hasArg("retryIntervalSeconds");
  const bool hasFallback = provisionServer.hasArg("fallbackApDelaySeconds");
  if (!hasInitial && !hasRetry && !hasFallback && allowMissingSettings) {
    return true;
  }
  if (!hasInitial || !hasRetry || !hasFallback) {
    return false;
  }

  return applyWifiConnectionSettings(
      provisionServer.arg("initialConnectTimeoutSeconds").toInt(),
      provisionServer.arg("retryIntervalSeconds").toInt(),
      provisionServer.arg("fallbackApDelaySeconds").toInt());
}

void handleWifiConnectionSettings() {
  String body = "{\"ok\":true,\"initialConnectTimeoutSeconds\":";
  body += config.wifiInitialConnectTimeoutSeconds;
  body += ",\"retryIntervalSeconds\":";
  body += config.wifiRetryIntervalSeconds;
  body += ",\"fallbackApDelaySeconds\":";
  body += config.wifiFallbackApDelaySeconds;
  body += "}";
  provisionServer.send(200, "application/json", body);
}

void handleWifiConnectionSettingsSave() {
  if (!applyWifiConnectionSettingsFromRequest(false)) {
    provisionServer.send(
        400,
        "application/json",
        "{\"ok\":false,\"message\":\"Informe os tres tempos entre 5 e 600 segundos.\"}");
    return;
  }

  saveConfig();
  provisionServer.send(
      200,
      "application/json",
      "{\"ok\":true,\"message\":\"Tempos de conexao Wi-Fi salvos. ESP32 sera reiniciado.\"}");
  scheduleRestart();
}

bool hasValidOtaPassword() {
  const String providedPassword = provisionServer.header(OTA_AUTH_HEADER);
  const size_t expectedLength = strlen(config.otaPassword);
  if (expectedLength == 0 || providedPassword.length() != expectedLength) {
    return false;
  }

  uint8_t differences = 0;
  for (size_t i = 0; i < expectedLength; i++) {
    differences |= static_cast<uint8_t>(providedPassword[i] ^ config.otaPassword[i]);
  }
  return differences == 0;
}

void handleFirmwareUpdateUpload() {
  HTTPUpload& upload = provisionServer.upload();
  if (upload.status == UPLOAD_FILE_START) {
    firmwareUpdateAuthorized = hasValidOtaPassword();
    firmwareUpdateSucceeded = false;
    firmwareUpdateError = "";
    if (!firmwareUpdateAuthorized) {
      firmwareUpdateError = "Chave OTA invalida ou nao configurada.";
      return;
    }
    if (!Update.begin(UPDATE_SIZE_UNKNOWN, U_FLASH)) {
      firmwareUpdateError = Update.errorString();
    }
    return;
  }

  if (!firmwareUpdateAuthorized || firmwareUpdateError.length() > 0) {
    return;
  }

  if (upload.status == UPLOAD_FILE_WRITE) {
    if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
      firmwareUpdateError = Update.errorString();
      Update.abort();
    }
    return;
  }

  if (upload.status == UPLOAD_FILE_END) {
    if (!Update.end(true)) {
      firmwareUpdateError = Update.errorString();
      return;
    }
    firmwareUpdateSucceeded = true;
    return;
  }

  if (upload.status == UPLOAD_FILE_ABORTED) {
    if (Update.isRunning()) {
      Update.abort();
    }
    firmwareUpdateError = "Atualizacao de firmware cancelada.";
  }
}

void handleFirmwareUpdate() {
  if (!firmwareUpdateAuthorized) {
    provisionServer.send(
        401,
        "application/json",
        "{\"ok\":false,\"message\":\"Chave OTA invalida ou nao configurada.\"}");
    return;
  }
  if (!firmwareUpdateSucceeded) {
    String body = "{\"ok\":false,\"message\":\"Falha ao atualizar firmware";
    if (firmwareUpdateError.length() > 0) {
      body += ": ";
      body += jsonEscape(firmwareUpdateError.c_str());
    }
    body += ".\"}";
    provisionServer.send(500, "application/json", body);
    return;
  }

  provisionServer.send(
      200,
      "application/json",
      "{\"ok\":true,\"message\":\"Firmware atualizado. ESP32 sera reiniciado.\"}");
  scheduleRestart();
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
  if (provisionServer.hasArg("otaPassword")) {
    const String otaPassword = provisionServer.arg("otaPassword");
    if (otaPassword.length() < 8 || otaPassword.length() >= sizeof(config.otaPassword)) {
      return false;
    }
    safeCopy(otaPassword, config.otaPassword, sizeof(config.otaPassword));
  }
  if (!applyWifiConnectionSettingsFromRequest(true)) {
    return false;
  }
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
    body += ",\"priority\":";
    body += String(i + 1);
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

void handleWifiNetworkReorder() {
  if (!provisionServer.hasArg("ssid") || !provisionServer.hasArg("direction")) {
    provisionServer.send(
        400,
        "application/json",
        "{\"ok\":false,\"message\":\"Informe a rede e a direcao da movimentacao.\"}");
    return;
  }

  const String direction = provisionServer.arg("direction");
  const int movement = direction == "up" ? -1 : direction == "down" ? 1 : 0;
  if (movement == 0 || !moveWifiNetwork(provisionServer.arg("ssid"), movement)) {
    provisionServer.send(
        400,
        "application/json",
        "{\"ok\":false,\"message\":\"Nao foi possivel alterar a prioridade da rede.\"}");
    return;
  }

  saveConfig();
  provisionServer.send(
      200,
      "application/json",
      "{\"ok\":true,\"message\":\"Prioridade da rede atualizada no ESP32.\"}");
}

void handleWifiScan() {
  const wifi_mode_t prevMode = WiFi.getMode();
  if (prevMode == WIFI_AP) {
    WiFi.mode(WIFI_AP_STA);
  }

  const int n = WiFi.scanNetworks();

  String body = "{\"ok\":true,\"networks\":[";
  bool first = true;
  for (int i = 0; i < n && i < 20; i++) {
    const String ssid = WiFi.SSID(i);
    if (ssid.length() == 0) {
      continue;
    }
    if (!first) {
      body += ",";
    }
    first = false;
    body += "{\"ssid\":\"";
    body += jsonEscape(ssid.c_str());
    body += "\",\"rssi\":";
    body += WiFi.RSSI(i);
    body += ",\"open\":";
    body += (WiFi.encryptionType(i) == WIFI_AUTH_OPEN) ? "true" : "false";
    body += ",\"authType\":";
    body += static_cast<int>(WiFi.encryptionType(i));
    const char* authLabel = "WPA2";
    switch (WiFi.encryptionType(i)) {
      case WIFI_AUTH_OPEN:            authLabel = "Aberta"; break;
      case WIFI_AUTH_WEP:             authLabel = "WEP"; break;
      case WIFI_AUTH_WPA_PSK:         authLabel = "WPA"; break;
      case WIFI_AUTH_WPA2_PSK:        authLabel = "WPA2"; break;
      case WIFI_AUTH_WPA_WPA2_PSK:    authLabel = "WPA/WPA2"; break;
      case WIFI_AUTH_WPA2_ENTERPRISE: authLabel = "Enterprise"; break;
      case WIFI_AUTH_WPA3_PSK:        authLabel = "WPA3"; break;
      case WIFI_AUTH_WPA2_WPA3_PSK:   authLabel = "WPA2/WPA3"; break;
      default: break;
    }
    body += ",\"authLabel\":\"";
    body += authLabel;
    body += "\"";
    body += "}";
  }
  body += "]}";

  WiFi.scanDelete();
  if (prevMode == WIFI_AP) {
    WiFi.mode(WIFI_AP);
  }
  provisionServer.send(200, "application/json", body);
}

bool resetAllEnergy() {
  if (!pzem.resetEnergy()) {
    return false;
  }
  lcdApparentEnergyKvah = 0.0f;
  lcdReactiveEnergyKvarh = 0.0f;
  lcdLastEnergyUpdateMs = 0;
  return true;
}

void handleWifiStatus() {
  const wl_status_t wlStatus = WiFi.status();
  const bool connected = (wlStatus == WL_CONNECTED);

  const char* desc = "Aguardando";
  switch (wlStatus) {
    case WL_CONNECTED:        desc = "Conectado"; break;
    case WL_NO_SSID_AVAIL:   desc = "SSID nao encontrado (verifique o nome ou se e 2.4 GHz)"; break;
    case WL_CONNECT_FAILED:   desc = "Falha de autenticacao (usuario ou senha incorretos)"; break;
    case WL_CONNECTION_LOST:  desc = "Conexao perdida"; break;
    case WL_DISCONNECTED:     desc = "Desconectado"; break;
    default: break;
  }

  String body = "{\"connected\":";
  body += connected ? "true" : "false";
  body += ",\"status\":";
  body += static_cast<int>(wlStatus);
  body += ",\"description\":\"";
  body += desc;
  body += "\",\"ssid\":\"";
  body += jsonEscape(connected ? WiFi.SSID().c_str() : config.wifiSsid);
  body += "\",\"enterprise\":";
  body += strlen(config.wifiUsername) > 0 ? "true" : "false";
  if (connected) {
    body += ",\"ip\":\"";
    body += WiFi.localIP().toString();
    body += "\",\"rssi\":";
    body += WiFi.RSSI();
  }
  body += "}";

  provisionServer.send(200, "application/json", body);
}

void handleWifiReconnect() {
  if (provisioningMode) {
    provisionServer.send(
        400,
        "application/json",
        "{\"ok\":false,\"message\":\"ESP em modo provisionamento. Use /provision para configurar.\"}");
    return;
  }
  lastWifiAttemptMs = 0;
  wifiDisconnectedSinceMs = millis();
  provisionServer.send(
      200,
      "application/json",
      "{\"ok\":true,\"message\":\"Tentativa de conexao iniciada.\"}");
}

void handleResetEnergy() {
  if (!resetAllEnergy()) {
    provisionServer.send(
        503,
        "application/json",
        "{\"ok\":false,\"message\":\"Falha ao zerar energia no PZEM.\"}");
    return;
  }
  provisionServer.send(
      200,
      "application/json",
      "{\"ok\":true,\"message\":\"Energia acumulada zerada.\"}");
}

void startProvisioningServer() {
  if (provisionServerStarted) {
    return;
  }

  provisionServer.collectHeaders(OTA_REQUEST_HEADERS, 1);
  provisionServer.on("/health", HTTP_GET, handleHealth);
  provisionServer.on("/metrics", HTTP_GET, handleMetrics);
  provisionServer.on("/wifi-scan", HTTP_GET, handleWifiScan);
  provisionServer.on("/provision", HTTP_POST, handleProvision);
  provisionServer.on("/wifi-networks", HTTP_GET, handleWifiNetworksList);
  provisionServer.on("/wifi-networks", HTTP_POST, handleWifiNetworkSave);
  provisionServer.on("/wifi-networks/delete", HTTP_POST, handleWifiNetworkDelete);
  provisionServer.on("/wifi-networks/reorder", HTTP_POST, handleWifiNetworkReorder);
  provisionServer.on("/wifi-connection-settings", HTTP_GET, handleWifiConnectionSettings);
  provisionServer.on("/wifi-connection-settings", HTTP_POST, handleWifiConnectionSettingsSave);
  provisionServer.on("/firmware/update", HTTP_POST, handleFirmwareUpdate, handleFirmwareUpdateUpload);
  provisionServer.on("/reset-energy", HTTP_POST, handleResetEnergy);
  provisionServer.on("/wifi-status", HTTP_GET, handleWifiStatus);
  provisionServer.on("/wifi-reconnect", HTTP_POST, handleWifiReconnect);
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

// Inicia conexao Wi-Fi usando WPA2-Enterprise (PEAP) se wifiUsername estiver
// preenchido, ou WPA2-Personal caso contrario.
void beginWiFiWithConfig() {
  if (strlen(config.wifiUsername) > 0) {
    esp_eap_client_set_identity(
        reinterpret_cast<const uint8_t*>(config.wifiUsername),
        strlen(config.wifiUsername));
    esp_eap_client_set_username(
        reinterpret_cast<const uint8_t*>(config.wifiUsername),
        strlen(config.wifiUsername));
    esp_eap_client_set_password(
        reinterpret_cast<const uint8_t*>(config.wifiPassword),
        strlen(config.wifiPassword));
    esp_wifi_sta_enterprise_enable();
    WiFi.begin(config.wifiSsid);
    Serial.println("[WiFi] Modo WPA2-Enterprise (PEAP)");
  } else {
    esp_wifi_sta_enterprise_disable();
    WiFi.begin(config.wifiSsid, config.wifiPassword);
    Serial.println("[WiFi] Modo WPA2-Personal");
  }
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
  WiFi.setAutoReconnect(false);
  WiFi.mode(fallbackApActive ? WIFI_AP_STA : WIFI_STA);
  WiFi.disconnect(false, true);
  delay(200);
  if (wifiDisconnectedSinceMs == 0) {
    wifiDisconnectedSinceMs = millis();
  }
  Serial.print("[WiFi] SSID=[");
  Serial.print(config.wifiSsid);
  Serial.print("] USER_LEN=");
  Serial.print(strlen(config.wifiUsername));
  Serial.print(" PASS_LEN=");
  Serial.println(strlen(config.wifiPassword));
  beginWiFiWithConfig();
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

  const unsigned long fallbackApDelayMs =
      static_cast<unsigned long>(config.wifiFallbackApDelaySeconds) * 1000UL;
  if (now - wifiDisconnectedSinceMs >= fallbackApDelayMs) {
    startFallbackAccessPoint();
  }
}

void ensureWiFiConnected() {
  if (provisioningMode || WiFi.status() == WL_CONNECTED) {
    return;
  }

  const unsigned long now = millis();
  const unsigned long retryIntervalMs =
      static_cast<unsigned long>(config.wifiRetryIntervalSeconds) * 1000UL;
  if (now - lastWifiAttemptMs < retryIntervalMs) {
    return;
  }

  const uint8_t st = static_cast<uint8_t>(WiFi.status());
  if (st != WL_IDLE_STATUS) {
    lastWifiFailureStatus = st;
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

// [1] Atualiza o frame compartilhado latestReading. Limitado a uma leitura
// real a cada PZEM_REFRESH_FLOOR_MS..CEIL_MS (acompanhando o intervalo de
// publicacao) para nao duplicar transacoes Modbus. Retorna a validade do frame.
// force=true ignora o limite (usado pelo GET /metrics sob demanda).
bool refreshPzemReading(bool force) {
  const unsigned long now = millis();
  if (!force && lastPzemRefreshMs != 0) {
    unsigned long minInterval = publishIntervalMs;
    if (minInterval < PZEM_REFRESH_FLOOR_MS) minInterval = PZEM_REFRESH_FLOOR_MS;
    if (minInterval > PZEM_REFRESH_CEIL_MS) minInterval = PZEM_REFRESH_CEIL_MS;
    if (now - lastPzemRefreshMs < minInterval) {
      return latestReading.valid;
    }
  }
  lastPzemRefreshMs = now;

  PzemReading r;
  r.voltage = pzem.voltage();
  r.current = pzem.current();
  r.power = pzem.power();
  r.energy = pzem.energy();
  r.frequency = pzem.frequency();
  r.pf = pzem.pf();

  // Potencias aparente/reativa derivadas (PZEM nao as fornece).
  r.apparentPower = r.voltage * r.current;
  const float reactiveSquared = r.apparentPower * r.apparentPower - r.power * r.power;
  r.reactivePower = reactiveSquared > 0.0f ? sqrtf(reactiveSquared) : 0.0f;

  // valid = criterio de publicacao IDENTICO ao antigo readPzem (todos finitos).
  // Sob carga zero o PZEM devolve pf=NaN: nesse caso valid=false (frame nao
  // publicado, como no original), mas os campos brutos sao mantidos para o LCD
  // exibir as demais grandezas com "FP: N/A" — preservando o comportamento antigo.
  r.valid = isfinite(r.voltage) && isfinite(r.current) && isfinite(r.power) &&
            isfinite(r.energy) && isfinite(r.frequency) && isfinite(r.pf);
  if (!r.valid) {
    pzemCrcErrors++;  // E8 (igual ao readPzem original: conta qualquer campo nao-finito)
  }

  latestReading = r;
  return r.valid;
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
  // [1] Usa o frame compartilhado (mesma leitura exibida no LCD).
  // O chamador garante que latestReading esteja atualizado.
  if (!latestReading.valid) {
    return false;
  }

  const float voltage = latestReading.voltage;
  const float current = latestReading.current;
  const float energy = latestReading.energy;
  const float frequency = latestReading.frequency;
  const float pf = latestReading.pf;
  float power = latestReading.power;

  // E10: subtrai consumo proprio do sistema se habilitado
  if (selfConsumptionEnabled && selfConsumptionWatts > 0.0f && power >= selfConsumptionWatts) {
    power -= selfConsumptionWatts;
  }

  // E3: temperatura interna do ESP32 (sensor built-in). Nem toda variante
  // do ESP32 oferece esse sensor; nunca publique NaN, pois isso invalida o JSON.
  const float espTemperature = temperatureRead();
  const bool hasTemperature = isfinite(espTemperature);
  char temperatureJson[16] = "null";
  if (hasTemperature) {
    snprintf(temperatureJson, sizeof(temperatureJson), "%.1f", espTemperature);
  }
  const uint64_t timestampMs = currentEpochMs();
  const uint32_t sequence = ++telemetrySequence;

  const DeviceStorageUsage storage = storageUsageCached();  // [2] cache (FAT e' caro)
  const int payloadLength = snprintf(
      payloadBuffer,
      payloadBufferSize,
      "{\"voltage\":%.2f,\"current\":%.3f,\"power\":%.2f,\"pf\":%.3f,\"frequency\":%.2f,\"energy\":%.3f,"
      "\"temperature\":%s,\"crcErrors\":%lu,\"timestamp\":%llu,\"sequence\":%lu,\"timeSynced\":%s,"
      "\"storage\":{\"usingSd\":%s,\"sdAvailable\":%s,\"sdUsedBytes\":%llu,\"sdTotalBytes\":%llu,\"sdUsagePercent\":%.2f}}",
      voltage,
      current,
      power,
      pf,
      frequency,
      energy,
      temperatureJson,
      static_cast<unsigned long>(pzemCrcErrors),
      static_cast<unsigned long long>(timestampMs),
      static_cast<unsigned long>(sequence),
      timestampMs > 0 ? "true" : "false",
      storage.usingSd ? "true" : "false",
      storage.sdAvailable ? "true" : "false",
      static_cast<unsigned long long>(storage.usedBytes),
      static_cast<unsigned long long>(storage.totalBytes),
      storage.usagePercent);

  return payloadLength > 0 && static_cast<size_t>(payloadLength) < payloadBufferSize;
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

  // E13: PubSubClient suporta apenas QoS 0 para publish.
  // Para QoS 1/2 real (ensaio E13 comparativo), substituir PubSubClient por
  // AsyncMqttClient (https://github.com/marvinroger/async-mqtt-client) e usar
  // client.publish(topic, qos, retain, payload).
  // O retain=true garante que o broker preserve a ultima leitura (proxy de persistencia).
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

// [4] Cache do conteudo de cada linha do LCD para evitar reescrever no
// barramento I2C quando nada mudou.
String lcdLineCache[EMETRICS_LCD_ROWS];

void invalidateLcdCache() {
  for (uint8_t i = 0; i < EMETRICS_LCD_ROWS; i++) {
    lcdLineCache[i] = "";
  }
}

void printLcdLine(uint8_t row, const String& text) {
  if (row >= EMETRICS_LCD_ROWS) {
    return;
  }

  String padded = text.length() > 20 ? text.substring(0, 20) : text;
  while (padded.length() < 20) {
    padded += ' ';
  }

  if (padded == lcdLineCache[row]) {
    return;  // conteudo identico -> nao toca no I2C
  }
  lcdLineCache[row] = padded;

  lcd.setCursor(0, row);
  lcd.print(padded);
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
  if (provisioningMode || fallbackApActive) {
    return "Rede: " + String(PROVISION_AP_SSID);
  }
  if (WiFi.status() == WL_CONNECTED) {
    return "Rede: " + WiFi.SSID();
  }
  if (strlen(config.wifiSsid) > 0) {
    return "Tent: " + String(config.wifiSsid);
  }
  return "Rede: sem rede";
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
  // [1] Mantem o frame compartilhado atualizado (limitado internamente). Como
  // o gate respeita PZEM_REFRESH_*_MS, chamadas frequentes nao geram leituras
  // Modbus redundantes; tambem mantem o LCD vivo no modo provisionamento.
  refreshPzemReading();

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

  // [1] Usa o mesmo frame publicado no MQTT (consistencia display x telemetria)
  const float voltage = latestReading.voltage;
  const float current = latestReading.current;
  const float power = latestReading.power;
  const float energy = latestReading.energy;
  const float frequency = latestReading.frequency;
  const float pf = latestReading.pf;
  const float apparentPower = latestReading.apparentPower;
  const float reactivePower = latestReading.reactivePower;
  if (lcdDisplayIndex == 3) {
    String wifiStatus;
    if (WiFi.status() == WL_CONNECTED) {
      wifiStatus = "STA OK";
    } else if (provisioningMode || fallbackApActive) {
      wifiStatus = "AP ativo";
    } else if (lastWifiFailureStatus == WL_NO_SSID_AVAIL) {
      wifiStatus = "SSID nao achado";
    } else if (lastWifiFailureStatus == WL_CONNECT_FAILED) {
      wifiStatus = "Senha incorreta";
    } else {
      wifiStatus = "sem conexao";
    }
    printLcdLine(0, String("WiFi: ") + wifiStatus);
    printLcdLine(1, currentNetworkLineForLcd());
    printLcdLine(2, String("MQTT:") + (mqttClient.connected() ? "OK" : "OFF") + " Fila:" + queueCount);
    printLcdLine(3, String("Broker:") + String(config.mqttHost).substring(0, 13));
    return;
  }

  // Verifica se leitura foi bem-sucedida (criterio do LCD identico ao original:
  // apenas V/I/P; sob carga zero pf=NaN nao deve disparar a tela de erro)
  if (isnan(voltage) || isnan(current) || isnan(power)) {
    printLcdLine(0, "Erro ao ler PZEM");
    printLcdLine(1, "Verifique conexao");
    printLcdLine(2, "");
    printLcdLine(3, String("MQTT: ") + (mqttClient.connected() ? "ON" : "OFF"));
    return;
  }

  if (lcdLastEnergyUpdateMs != 0 && now > lcdLastEnergyUpdateMs) {
    const float elapsedHours = static_cast<float>(now - lcdLastEnergyUpdateMs) / 3600000.0f;
    lcdApparentEnergyKvah += apparentPower * elapsedHours;
    lcdReactiveEnergyKvarh += reactivePower * elapsedHours;
  }
  lcdLastEnergyUpdateMs = now;

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
    printLcdLine(1, formatMetricLine("E.Apte.", String(lcdApparentEnergyKvah, 2) + " kVAh"));
    printLcdLine(2, formatMetricLine("E.Reat.", String(lcdReactiveEnergyKvarh, 2) + " kVArh"));
    printLcdLine(3, "");
    return;
  }

  {
    String wifiStatus;
    if (WiFi.status() == WL_CONNECTED) {
      wifiStatus = "STA OK";
    } else if (provisioningMode || fallbackApActive) {
      wifiStatus = "AP ativo";
    } else if (lastWifiFailureStatus == WL_NO_SSID_AVAIL) {
      wifiStatus = "SSID nao achado";
    } else if (lastWifiFailureStatus == WL_CONNECT_FAILED) {
      wifiStatus = "Senha incorreta";
    } else {
      wifiStatus = "sem conexao";
    }
    printLcdLine(0, String("WiFi: ") + wifiStatus);
    printLcdLine(1, currentNetworkLineForLcd());
    printLcdLine(2, String("MQTT:") + (mqttClient.connected() ? "OK" : "OFF") + " Fila:" + queueCount);
    printLcdLine(3, String("Broker:") + String(config.mqttHost).substring(0, 13));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SETUP E LOOP PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════

void setupArduinoOTA() {
  ArduinoOTA.setHostname(config.mqttClientId);
  if (strlen(config.otaPassword) >= 8) {
    ArduinoOTA.setPassword(config.otaPassword);
  }
  ArduinoOTA.onStart([]() {
    Serial.println("[OTA] Iniciando atualizacao de firmware...");
  });
  ArduinoOTA.onEnd([]() {
    Serial.println("\n[OTA] Concluido. Reiniciando...");
  });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("[OTA] Progresso: %u%%\r", progress * 100 / total);
  });
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("[OTA] Erro [%u]\n", error);
  });
  ArduinoOTA.begin();
  Serial.println("[OTA] ArduinoOTA pronto. IP: " + WiFi.localIP().toString());
}

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
  lcd.setCursor(4, 1);
  lcd.print("EMetrics IoT");
  lcd.setCursor(0, 2);
  lcd.print("IFMA - Monte Castelo");
  lcd.setCursor(0, 3);
  lcd.print("Dep.Eletroeletronica");
  delay(2000);  // mostra mensagem inicial por 2 segundos
  lcd.clear();
  invalidateLcdCache();  // [4] cache coerente com o display recem-limpo

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
  mqttClient.setBufferSize(MQTT_BUFFER_SIZE);  // [5] definido uma unica vez (antes era por reconexao)
  connectWiFi();
  {
    const unsigned long initialConnectTimeoutMs =
        static_cast<unsigned long>(config.wifiInitialConnectTimeoutSeconds) * 1000UL;
    const unsigned long deadline = millis() + initialConnectTimeoutMs;
    unsigned long lastLcdMs = 0;
    while (WiFi.status() != WL_CONNECTED && millis() < deadline) {
      delay(100);
      Serial.print(".");
      const unsigned long now = millis();
      if (now - lastLcdMs >= 500) {
        lastLcdMs = now;
        updateLcdDisplay();
      }
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("[WiFi] Conectado: " + WiFi.localIP().toString());
    } else {
      lastWifiFailureStatus = static_cast<uint8_t>(WiFi.status());
      Serial.print("[WiFi] Timeout inicial - status=");
      Serial.println(lastWifiFailureStatus);
    }
  }
  lastWifiAttemptMs = millis();
  startProvisioningServer();
  setupArduinoOTA();
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

  ArduinoOTA.handle();

  // E11: Modo hibrido Wi-Fi — alterna entre fase de aquisicao (Wi-Fi OFF) e TX (Wi-Fi ON)
  if (hybridWifiEnabled) {
    const unsigned long now = millis();
    if (hybridAcquiringPhase) {
      if (now - hybridPhaseStartMs >= hybridAcquireWindowMs) {
        // transicao para fase TX: liga Wi-Fi
        hybridAcquiringPhase = false;
        hybridPhaseStartMs = now;
        WiFi.setAutoReconnect(false);
        WiFi.mode(fallbackApActive ? WIFI_AP_STA : WIFI_STA);
        WiFi.disconnect(false, true);
        delay(200);
        beginWiFiWithConfig();
      }
    } else {
      // fase TX: aguarda conexao e publica lote
      if (WiFi.status() == WL_CONNECTED) {
        refreshEpochOffsetIfNeeded();
        ensureMqttConnected();
        if (mqttClient.connected()) {
          mqttClient.loop();
          flushQueuedMetrics();
        }
      }
      if (now - hybridPhaseStartMs >= hybridTxWindowMs) {
        // transicao para fase aquisicao: desliga Wi-Fi
        hybridAcquiringPhase = true;
        hybridPhaseStartMs = now;
        mqttClient.disconnect();
        WiFi.mode(WIFI_OFF);
      }
    }
  } else {
    ensureFallbackAccessPoint();
    ensureWiFiConnected();
    if (WiFi.status() == WL_CONNECTED) {
      refreshEpochOffsetIfNeeded();
    }
    ensureMqttConnected();

    if (mqttClient.connected()) {
      mqttClient.loop();
    }
  }

  // [3] Avanca o replay de historico em andamento (auto-protegido: so' age se
  // houver replay ativo e MQTT conectado). Roda nos dois modos de operacao.
  pumpHistoryReplay();

  const unsigned long now = millis();
  if (now - lastPublishMs >= publishIntervalMs) {  // E7: usa intervalo configuravel
    lastPublishMs = now;
    refreshPzemReading();  // [1] garante frame atual (gated; nao gera leitura redundante)
    queueLatestMetrics();
  }

  if (WiFi.status() == WL_CONNECTED && mqttClient.connected() && !hybridWifiEnabled) {
    flushQueuedMetrics();
  }

  // Atualiza display LCD com dados de medicao alternando
  updateLcdDisplay();
}
