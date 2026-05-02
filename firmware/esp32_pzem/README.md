# ESP32 + PZEM-004T (MQTT)

Exemplo de firmware para publicar no MQTT exatamente no formato esperado pelo app.

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

## Topico recomendado

- emetrics/pzem
- emetrics/pzem/status (status do dispositivo: online/offline via LWT)

## Robustez incluida neste exemplo

- Reconexao nao bloqueante de Wi-Fi e MQTT (sem while infinito no loop principal)
- Last Will and Testament (LWT) no topico de status
- Publicacao de status online quando reconecta
- Publicacao retained configuravel para telemetria
- Fila circular em RAM para segurar amostras durante queda do broker
- Envio em lote apos reconexao (sem travar o loop principal)

## Parametros de buffer (main.ino)

- TELEMETRY_QUEUE_CAPACITY: quantidade maxima de amostras na fila
- FLUSH_BATCH_LIMIT: quantas amostras enviar por iteracao do loop
- TELEMETRY_PAYLOAD_SIZE: tamanho maximo do JSON em bytes

Quando a fila lota, a amostra mais antiga e descartada para abrir espaco.

## Dependencias (Arduino IDE)

- WiFi (ja vem no core do ESP32)
- PubSubClient
- PZEM004Tv30

## Como usar

1. Abra `src/main.ino`.
2. Ajuste Wi-Fi, broker MQTT, usuario/senha e topico.
3. Selecione a placa ESP32 e grave.
4. Configure o app com o mesmo broker e topico.

## Observacao sobre QoS

Nesta implementacao (PubSubClient), a publicacao de payload usa QoS 0.
O app Flutter permanece compativel, pois consome o JSON publicado no topico configurado.
