# ESP32 + PZEM-004T (MQTT)

Exemplo de firmware com provisionamento via AP local para receber Wi-Fi e MQTT direto do app.

## Estrutura

- src/main.ino

## Payload publicado

```json
{
  "voltage": 220.1,
  "current": 0.51,
  "power": 112.0,
  "pf": 0.98,
  "frequency": 60.0,
  "energy": 1.23
}
```

## Provisionamento pelo app

Quando o ESP nao tem configuracao salva, ele sobe em AP:

- SSID: EMetrics-Setup
- Senha: 12345678
- Endpoint de verificacao: GET /health
- Endpoint de configuracao: POST /provision

Campos esperados em /provision (form-urlencoded):

- ssid
- wifiPassword
- mqttHost
- mqttPort
- mqttUser
- mqttPassword
- mqttTopic
- mqttRequestTopic
- clientId
- useTls (1 ou 0)

## Robustez incluida neste exemplo

- Configuracao persistida em NVS (Preferences)
- Reconexao nao bloqueante de Wi-Fi e MQTT
- Fila circular em RAM para segurar amostras durante queda do broker
- Envio em lote apos reconexao
- Historico persistente em cartao microSD (Adafruit) para replay sob demanda
- Fallback automatico para SPIFFS quando o cartao SD nao estiver disponivel
- Assinatura no topico de solicitacao de historico e reenvio por intervalo
- Suporte a MQTT com TLS (WiFiClientSecure)

## Armazenamento local (microSD Adafruit)

Por padrao, o firmware tenta iniciar o cartao SD no barramento SPI com os pinos:

- CS: `5`
- SCK: `18`
- MISO: `19`
- MOSI: `23`

Se sua placa usar outro mapeamento, altere no topo do arquivo `main.ino` via defines:

- `EMETRICS_SD_CS_PIN`
- `EMETRICS_SD_SCK_PIN`
- `EMETRICS_SD_MISO_PIN`
- `EMETRICS_SD_MOSI_PIN`

O arquivo de historico fica em `/history.log` e e usado para responder requisicoes de historico por intervalo.

## Parametros de buffer (main.ino)

- TELEMETRY_QUEUE_CAPACITY: quantidade maxima de amostras na fila
- FLUSH_BATCH_LIMIT: quantas amostras enviar por iteracao do loop
- TELEMETRY_PAYLOAD_SIZE: tamanho maximo do JSON em bytes

Quando a fila lota, a amostra mais antiga e descartada para abrir espaco.

## Dependencias (Arduino IDE)

- WiFi (core ESP32)
- WebServer (core ESP32)
- Preferences (core ESP32)
- PubSubClient
- PZEM004Tv30

## Fluxo de uso

1. Grave o firmware no ESP32.
2. Conecte o celular na rede EMetrics-Setup.
3. No app, abra Configuracoes > MQTT > Provisionar ESP32.
4. Envie SSID/senha da rede final e dados do MQTT.
5. O ESP reinicia e passa a operar no modo normal.

## Observacao sobre QoS

Nesta implementacao (PubSubClient), a publicacao de payload usa QoS 0.
O app Flutter permanece compativel, pois consome o JSON publicado no topico configurado.

## Solicitar historico via MQTT

O firmware assina o topico configurado em `mqttRequestTopic` e espera o payload JSON:

```json
{
  "from": 1746230400000,
  "to": 1746316800000,
  "requestedAt": 1746316850000
}
```

Ao receber essa solicitacao, o ESP32 filtra os registros persistidos no intervalo `from`/`to`
e republica os payloads no topico principal de telemetria (`mqttTopic`).

## Observacao sobre TLS

Com `useTls=1`, o firmware usa `WiFiClientSecure` com `setInsecure()`.
Isso ativa criptografia de transporte, mas sem validacao de certificado do broker.
Para ambiente produtivo com validacao estrita, substitua por CA/certificado apropriado.
