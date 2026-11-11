# Copie para config.py na memoria da BitDogLab e configure os dados reais.
# NAO publique config.py com credenciais.
WIFI_SSID = "SUA_REDE"
WIFI_PASSWORD = "SUA_SENHA"

# Use o MESMO broker MQTT do E-Metrics IoT (preferencialmente privado).
MQTT_HOST = "192.168.1.10"
MQTT_PORT = 1883
MQTT_USER = ""
MQTT_PASSWORD = ""
MQTT_CLIENT_ID = "emetrics-bitdoglab"
TELEMETRY_TOPIC = "emetrics/pzem"

# Topicos opcionais, para um controlador de motor compativel.
MOTOR_ID = "motor01"
MOTOR_COMMAND_TOPIC = "emetrics/motor/command"
MOTOR_STATUS_TOPIC = "emetrics/motor/status"
MOTOR_ALARM_TOPIC = "emetrics/motor/alarms"

# Deixe FALSE ate existir atuador com permissivos e protecoes verificadas.
ENABLE_MOTOR_COMMANDS = False

# Mapeamento da BitDogLab v6.3 com Raspberry Pi Pico W.
# Verifique a revisao fisica antes de usar com outra versao.
PIN_BUTTON_A = 5
PIN_BUTTON_B = 6
PIN_JOYSTICK_BUTTON = 22
PIN_OLED_SDA = 14
PIN_OLED_SCL = 15
PIN_LED_R = 13
PIN_LED_G = 11
PIN_LED_B = 12
START_HOLD_MS = 1200
TELEMETRY_STALE_MS = 15000
