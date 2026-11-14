# BitDogLab: painel MQTT do quadro IoT Motor

Terminal MQTT adicional, em paralelo com o painel web e o app. Mostra a
telemetria **real** do quadro de comando (`esp32-01`, PZEM-004T e estado do
motor), lista as partidas gravadas no quadro e envia `start`/`stop` pelo
protocolo do projeto IoT Motor (`iot_motor/docs/mqtt.md`).

Quem aciona os contatores, aplica intertravamentos, limites e desarmes e
confirma o estado e o **quadro**. A BitDogLab so pede; o resultado aparece
pela `command_ack` e pela telemetria.

## Uso

| Botao | Acao |
|---|---|
| A (toque) | Escolhe a proxima partida da lista do quadro |
| A (segurar 1,2 s) | Da a partida escolhida (`ENABLE_MOTOR_COMMANDS = True`) |
| B | Desliga (`stop`); sempre enviado |
| Joystick | Paginas: U/I/P, E/f/FP, temperatura/vibracao, partida |

LED: azul parado, verde ligado, amarelo partindo, vermelho sem MQTT,
quadro offline ou desarme.

A partida e recusada localmente se o quadro estiver sem telemetria, exigir
comando cifrado (`secure`), estiver em modo instrumentacao ou ja estiver ligado.

## Topicos (`IOTMOTOR_PREFIX`/`IOTMOTOR_BOARD`)

| Topico | Uso |
|---|---|
| `iotmotor/esp32-01/telemetry` | Medicoes, `boot`, `ts`, `motor_running`, `relays`, `start_phase`, `trip_alarm` |
| `iotmotor/esp32-01/profiles` | Partidas gravadas (retido) |
| `iotmotor/esp32-01/status` | `online`/`offline` |
| `iotmotor/esp32-01/command` | `{"v":1,"device_id":"esp32-01","seq":"...","action":"start","boot":"...","profile":"direta"}` |
| `iotmotor/esp32-01/command_ack` | Aceite ou motivo da recusa |
| `iotmotor/esp32-02/telemetry` | `temperature`, `vibration_mms`, `vibration_axis`, `alarms_firing` |

O `seq` vem do `ts` da telemetria em microssegundos, compativel com o
`Date.now()*1000` do painel e do app.

## Hardware

- BitDogLab v6.3 com Raspberry Pi Pico W (Wi-Fi), firmware MicroPython.
- Botao A / GPIO5: solicita partida apos pressionar por 1,2 s (habilitacao separada).
- Botao B / GPIO6: solicita parada (habilitacao separada).
- Botao do joystick / GPIO22: alterna paginas do display.
- OLED 128x64: GPIO14 (SDA), GPIO15 (SCL), endereco usual 0x3C.
- LED RGB: vermelho GPIO13, verde GPIO11, azul GPIO12.

Pinos documentados para **v6.3**; confirme o mapeamento em outras revisoes.
Sem Wi-Fi no Pico (modelo sem W), a comunicacao proposta exige modulo de rede.

## Instalacao

1. Grave MicroPython adequado ao seu **Pico W** na BitDogLab.
2. Pelo Thonny, instale/copiei as bibliotecas `umqtt.simple` e `ssd1306`
   para o dispositivo (em algumas builds `umqtt.simple` ja esta disponivel).
3. Copie `config.example.py` para `config.py` no proprio dispositivo;
   ajuste SSID, senha, broker, porta, transporte, credenciais e
   `TELEMETRY_TOPIC` para
   coincidir com o perfil MQTT ja utilizado pelo ESP32/E-Metrics.
4. Copie `main.py` para o dispositivo. Execute e veja o OLED.
5. O botao do joystick alterna tensao/corrente e potencia/energia.
6. Deixe `ENABLE_MOTOR_COMMANDS = False` enquanto nao houver controlador.

O arquivo `config.py` contem segredos: nao o envie ao GitHub.
O exemplo aceita MQTT TCP (`MQTT_USE_TLS = False`, normalmente porta 1883) ou
TLS (`MQTT_USE_TLS = True`, normalmente porta 8883). A implementacao `umqtt.simple`
incluida em algumas builds do MicroPython cifra o transporte, mas pode nao validar
o certificado do broker; em redes reais, instale uma cadeia CA e valide o servidor,
alem de usar broker privado, autenticacao e ACLs por topico.
Para MQTT sobre WebSocket, use `MQTT_USE_WEBSOCKET = True` e configure
`MQTT_WEBSOCKET_PATH` (por exemplo, `/mqtt`). Use porta 8080 sem TLS (`ws`) ou
8081 com TLS (`wss`), conforme o broker.
**Nunca exponha um topico de comando de motor em broker publico de teste.**

## Protecao e limites

- A BitDogLab e um **terminal de operacao**, nao um dispositivo de seguranca.
- O acionamento fisico exige contator/driver isolado, protecao de sobrecarga e
  curto-circuito, permissivos locais e circuito de parada de emergencia **fisico**.
- Partida remota deve ser bloqueada em falha, falta de permissivos, reinicio
  de equipamento, comunicacao invalida ou pendencia de reconhecimento.
- O MQTT atual nao contem mecanismo de permissao de comando do motor.
  O controlador deve autenticar/autorizAR, rejeitar duplicatas, ter timeout
  e nao usar comandos retained. A confirmacao depende do estado medido,
  nunca somente do envio do comando.
- `ENABLE_MOTOR_COMMANDS` nasce `False`: nenhum botao publica comandos
  de acionamento ate configuracao explicita.
- Nao foi feito teste em hardware real.

## Proximos passos

Se o motor ja tem um controlador MQTT de outra parte do sistema, ajuste
`MOTOR_COMMAND_TOPIC`, `MOTOR_STATUS_TOPIC` e
`MOTOR_ALARM_TOPIC` e converta os nomes de comandos ao contrato existente.
Se nao existe, o acionamento fisico e a respectiva protecao sao uma etapa
separada: **nao altere nem substitua o firmware do medidor sem especificacao
da interface eletrica**.
