# Integracao BitDogLab ao E-Metrics IoT

Adicao **nao invasiva**: um terceiro terminal MQTT, em paralelo com o dashboard web e
o aplicativo Flutter. Os codigos atuais do ESP32/PZEM, do dashboard, do app, o
armazenamento local e a infraestrutura MQTT nao sao alterados nesta entrega.

## Fluxo

```
ESP32 + PZEM --telemetria--> broker MQTT --+--> App Flutter atual
                                           +--> Dashboard web atual
                                           +--> BitDogLab (este firmware)

BitDogLab --solicitacao de comando--> MQTT --> controlador de motor COMPATIVEL
controlador --estado confirmado/alarmes--> MQTT --> BitDogLab
```

**Importante:** o firmware atual `esp32_pzem.ino` publica grandezas e trata
configuracao e historico MQTT, mas **nao implementa acionamento de motor**.
Este novo cliente ja pode **ler as medicoes** sem alterar nada. Os botoes de
partida/parada so podem funcionar apos existir um controlador de motor que
aceite o contrato MQTT abaixo. O exemplo nao aciona GPIO de potencia/contator.

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
   ajuste SSID, senha, broker, credenciais e `TELEMETRY_TOPIC` para
   coincidir com o perfil MQTT ja utilizado pelo ESP32/E-Metrics.
4. Copie `main.py` para o dispositivo. Execute e veja o OLED.
5. O botao do joystick alterna tensao/corrente e potencia/energia.
6. Deixe `ENABLE_MOTOR_COMMANDS = False` enquanto nao houver controlador.

O arquivo `config.py` contem segredos: nao o envie ao GitHub.
O exemplo utiliza MQTT TCP; em redes reais, use broker privado, autenticao,
ACLs por topico e transporte criptografado em versao adaptada/validada.
**Nunca exponha um topico de comando de motor em broker publico de teste.**

## Topicos

A configuracao padrao acompanha a telemetria MQTT existente:

| Direcao | Topico | Funcao |
|---|---|---|
| ESP32 → broker → BitDogLab | `emetrics/pzem` | JSON de metrica atual |
| BitDogLab → broker | `emetrics/motor/command` | Solicitacao de comando (nao retained) |
| Controlador → broker | `emetrics/motor/status` | Estado real confirmado |
| Controlador → broker | `emetrics/motor/alarms` | Alarmes e falhas |

Exemplo de partida **solicitada** (nao representa partida fisica confirmada):

```json
{"deviceId":"motor01","command":"startMotor","source":"bitdoglab","commandId":"bitdog-123456"}
```

Exemplo de resposta que o controlador devera publicar:

```json
{"deviceId":"motor01","state":"running","alarm":""}
```

Valores de `state`: `starting`, `running`, `stopping`,
`stopped`, `fault`. Para uso com varios motores, separe topicos por
identificador de motor ou filtre `deviceId` em todas as mensagens.

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
