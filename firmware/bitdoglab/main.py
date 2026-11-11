"""Painel MQTT adicional BitDogLab para E-Metrics IoT (MicroPython / Pico W).

Este programa NAO altera o ESP32, o app Flutter ou o dashboard web.
Controle de motor: apenas solicita ao controlador externo; NUNCA aciona rede eletrica.
"""
import json
import time
import network
from machine import Pin, SoftI2C
from umqtt.simple import MQTTClient
import config

a = Pin(config.PIN_BUTTON_A, Pin.IN, Pin.PULL_UP)
b = Pin(config.PIN_BUTTON_B, Pin.IN, Pin.PULL_UP)
sw = Pin(config.PIN_JOYSTICK_BUTTON, Pin.IN, Pin.PULL_UP)
led_r = Pin(config.PIN_LED_R, Pin.OUT)
led_g = Pin(config.PIN_LED_G, Pin.OUT)
led_b = Pin(config.PIN_LED_B, Pin.OUT)

oled = None
try:
    import ssd1306
    i2c = SoftI2C(sda=Pin(config.PIN_OLED_SDA), scl=Pin(config.PIN_OLED_SCL))
    oled = ssd1306.SSD1306_I2C(128, 64, i2c)
except Exception as exc:
    print("Display OLED indisponivel:", exc)

nic = network.WLAN(network.STA_IF)
nic.active(True)
mqtt = None
metrics = {}
last_metrics_ms = None
motor = "desconhecido"
alarm = ""
pending = None
pending_at = 0
page = 0
a_start = None
was_a = False
was_b = False
was_sw = False
last_wifi_attempt = time.ticks_ms() - 5000
last_ping = time.ticks_ms()

def led(red=0, green=0, blue=0):
    led_r.value(red)
    led_g.value(green)
    led_b.value(blue)

def callback(topic, raw):
    global metrics, last_metrics_ms, motor, alarm, pending
    try:
        data = json.loads(raw)
        if not isinstance(data, dict):
            return
    except (ValueError, TypeError):
        return
    t = topic.decode() if isinstance(topic, bytes) else topic
    if t == config.TELEMETRY_TOPIC:
        if all(k in data for k in ("voltage", "current", "power")):
            metrics = data
            last_metrics_ms = time.ticks_ms()
    elif t == config.MOTOR_STATUS_TOPIC:
        state = data.get("state", data.get("status", "desconhecido"))
        if state in ("running", "stopped", "starting", "stopping", "fault"):
            motor = state
            if pending == "startMotor" and state == "running":
                pending = None
            elif pending == "stopMotor" and state == "stopped":
                pending = None
        if "alarm" in data:
            alarm = str(data["alarm"])[:24] if data["alarm"] else ""
        if state == "fault":
            pending = None
    elif t == config.MOTOR_ALARM_TOPIC:
        alarm = str(data.get("message", data.get("alarm", "Falha")))[:24]
        motor = "fault"
        pending = None

def disconnect():
    global mqtt, motor
    if mqtt:
        try:
            mqtt.disconnect()
        except Exception:
            pass
    mqtt = None
    motor = "desconhecido"

def connect():
    global mqtt, last_ping
    if not nic.isconnected():
        nic.connect(config.WIFI_SSID, config.WIFI_PASSWORD)
        deadline = time.ticks_add(time.ticks_ms(), 12000)
        while not nic.isconnected() and time.ticks_diff(deadline, time.ticks_ms()) > 0:
            time.sleep_ms(200)
        if not nic.isconnected():
            raise OSError("Wi-Fi indisponivel")
    mac = nic.config("mac")
    client_id = (config.MQTT_CLIENT_ID + "-%02x%02x%02x" % (mac[-3], mac[-2], mac[-1])).encode()
    user = config.MQTT_USER.encode() if config.MQTT_USER else None
    password = config.MQTT_PASSWORD.encode() if config.MQTT_PASSWORD else None
    c = MQTTClient(client_id, config.MQTT_HOST, port=config.MQTT_PORT,
                   user=user, password=password, keepalive=45)
    c.set_callback(callback)
    c.connect()
    for t in (config.TELEMETRY_TOPIC, config.MOTOR_STATUS_TOPIC, config.MOTOR_ALARM_TOPIC):
        c.subscribe(t.encode())
    mqtt = c
    last_ping = time.ticks_ms()
    print("Conectada ao MQTT:", config.MQTT_HOST)

def request_motor(command):
    global pending, pending_at
    if not config.ENABLE_MOTOR_COMMANDS:
        print("Solicitacao desativada em config.py")
        return
    if mqtt is None:
        print("Sem MQTT: comando nao enviado")
        return
    if command == "startMotor" and (alarm or motor == "fault"):
        print("Partida bloqueada: alarme/falha reportada")
        return
    # Nao confie no botao para seguranca: controlador precisa validar permissivos.
    payload = {
        "deviceId": config.MOTOR_ID, "command": command,
        "source": "bitdoglab", "commandId": "bitdog-%d" % time.ticks_ms()
    }
    try:
        # Sem retained: um comando antigo nunca deve ser repetido na reconexao.
        mqtt.publish(config.MOTOR_COMMAND_TOPIC.encode(),
                     json.dumps(payload).encode(), retain=False, qos=0)
        pending = command
        pending_at = time.ticks_ms()
        print("Solicitacao enviada:", command)
    except OSError as exc:
        print("Erro ao enviar:", exc)
        disconnect()

def buttons():
    global was_a, was_b, was_sw, a_start, page
    av = a.value() == 0
    bv = b.value() == 0
    sv = sw.value() == 0
    now = time.ticks_ms()
    if av and not was_a:
        a_start = now
    if not av and was_a and a_start is not None:
        if time.ticks_diff(now, a_start) >= config.START_HOLD_MS and not bv:
            request_motor("startMotor")
        a_start = None
    if bv and not was_b:
        request_motor("stopMotor")
    if sv and not was_sw:
        page = (page + 1) % 2
    was_a, was_b, was_sw = av, bv, sv

def number(key, suffix="", places=1):
    try:
        return ("%." + str(places) + "f" + suffix) % float(metrics[key])
    except (KeyError, TypeError, ValueError):
        return "--" + suffix

def render():
    if mqtt is None or motor == "fault" or alarm:
        led(red=1)
    elif motor == "running":
        led(green=1)
    elif motor == "stopped":
        led(blue=1)
    else:
        led(blue=1, green=1)
    if oled is None:
        return
    stale = last_metrics_ms is None or time.ticks_diff(time.ticks_ms(), last_metrics_ms) > config.TELEMETRY_STALE_MS
    oled.fill(0)
    oled.text("E-Metrics IoT", 0, 0)
    oled.text("MQTT:" + ("OK" if mqtt else "OFF") + " Motor:", 0, 10)
    oled.text(motor[:18], 0, 20)
    if stale:
        oled.text("Medicao: offline", 0, 30)
    elif page == 0:
        oled.text("U: " + number("voltage", "V"), 0, 30)
        oled.text("I: " + number("current", "A", 2), 0, 40)
    else:
        oled.text("P: " + number("power", "W"), 0, 30)
        oled.text("E: " + number("energy", "kWh", 2), 0, 40)
    if alarm:
        oled.text(("ALM: " + alarm)[:21], 0, 50)
    elif pending:
        oled.text("Aguardando status", 0, 50)
    else:
        oled.text("SW:ver  A:start B:stop"[:21], 0, 50)
    oled.show()

def main():
    global last_wifi_attempt, last_ping, pending
    print("E-Metrics / BitDogLab: interface adicional.")
    print("Comando de motor habilitado:", config.ENABLE_MOTOR_COMMANDS)
    last_ui = 0
    while True:
        now = time.ticks_ms()
        if mqtt is None and time.ticks_diff(now, last_wifi_attempt) > 5000:
            last_wifi_attempt = now
            try:
                connect()
            except Exception as exc:
                print("Falha de conexao:", exc)
                disconnect()
        buttons()
        if mqtt:
            try:
                mqtt.check_msg()
                if time.ticks_diff(now, last_ping) > 20000:
                    mqtt.ping()
                    last_ping = now
            except OSError as exc:
                print("MQTT caiu:", exc)
                disconnect()
        if pending and time.ticks_diff(now, pending_at) > 10000:
            print("Comando sem confirmacao:", pending)
            pending = None
        if time.ticks_diff(now, last_ui) > 400:
            last_ui = now
            render()
        time.sleep_ms(40)

main()
