"""Painel MQTT BitDogLab para o quadro de comando IoT Motor (MicroPython / Pico W).

Le a telemetria real do quadro (PZEM e estado do motor), lista as partidas
gravadas no quadro e envia start/stop pelo protocolo documentado em
iot_motor/docs/mqtt.md. Quem aciona contatores e aplica permissivos,
intertravamentos e desarmes e o quadro; a BitDogLab so pede.

Botoes:
  A (toque)      -> proxima partida da lista
  A (segurar)    -> da a partida escolhida
  B              -> desliga (sempre enviado, mesmo sem partida em andamento)
  Joystick (SW)  -> troca a pagina do display
"""
import json
import time
import network
from machine import Pin, SoftI2C
from umqtt.simple import MQTTClient
import config

PREFIX = getattr(config, "IOTMOTOR_PREFIX", "iotmotor")
BOARD = getattr(config, "IOTMOTOR_BOARD", "esp32-01")
T_TELEMETRY = "%s/%s/telemetry" % (PREFIX, BOARD)
T_PROFILES = "%s/%s/profiles" % (PREFIX, BOARD)
T_STATUS = "%s/%s/status" % (PREFIX, BOARD)
T_COMMAND = "%s/%s/command" % (PREFIX, BOARD)
T_ACK = "%s/%s/command_ack" % (PREFIX, BOARD)
PAGES = 3

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
tele = {}              # ultima telemetria do quadro
tele_ms = None
tele_ts_ms = None      # ticks em que chegou a ultima telemetria com ts
board_online = None
profiles = []          # [(id, nome_sem_acento)]
sel = 0
pending = None         # (seq, action)
pending_at = 0
message = ""
message_at = 0
seq_counter = 0
page = 0
a_start = None
a_long_done = False
was_a = was_b = was_sw = False
last_wifi_attempt = time.ticks_ms() - 5000
last_ping = time.ticks_ms()

ACCENTS = {
    "á": "a", "à": "a", "â": "a", "ã": "a", "é": "e", "ê": "e", "í": "i",
    "ó": "o", "ô": "o", "õ": "o", "ú": "u", "ç": "c", "Á": "A", "À": "A",
    "Â": "A", "Ã": "A", "É": "E", "Ê": "E", "Í": "I", "Ó": "O", "Ô": "O",
    "Õ": "O", "Ú": "U", "Ç": "C",
}

def ascii_text(text):
    return "".join(ACCENTS.get(ch, ch if ord(ch) < 128 else "?") for ch in str(text))

def led(red=0, green=0, blue=0):
    led_r.value(red)
    led_g.value(green)
    led_b.value(blue)

def show(text):
    global message, message_at
    message = ascii_text(text)[:21]
    message_at = time.ticks_ms()
    print(text)

def callback(topic, raw):
    global tele, tele_ms, tele_ts_ms, board_online, profiles, sel, pending
    t = topic.decode() if isinstance(topic, bytes) else topic
    if t == T_STATUS:
        board_online = raw == b"online"
        return
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        return
    if not isinstance(data, dict):
        return
    if t == T_TELEMETRY:
        tele = data
        tele_ms = time.ticks_ms()
        if data.get("ts"):
            tele_ts_ms = tele_ms
    elif t == T_PROFILES:
        current = profiles[sel][0] if profiles else None
        profiles = [(p.get("id"), ascii_text(p.get("name", p.get("id"))))
                    for p in data.get("profiles", []) if p.get("id")]
        ids = [p[0] for p in profiles]
        sel = ids.index(current) if current in ids else 0
    elif t == T_ACK:
        if pending and str(data.get("seq")) == pending[0]:
            pending = None
            if data.get("accepted"):
                show("OK: " + str(data.get("phase") or data.get("action")))
            else:
                show("Recusado: " + str(data.get("reason")))

def wifi_networks():
    nets = getattr(config, "WIFI_NETWORKS", None)
    if nets:
        return list(nets)
    return [(config.WIFI_SSID, config.WIFI_PASSWORD)]

def connect_wifi():
    known = wifi_networks()
    try:
        visible = set(n[0].decode() for n in nic.scan())
    except Exception as exc:
        print("Falha no scan Wi-Fi:", exc)
        visible = None
    candidates = [n for n in known if visible is None or n[0] in visible] or known
    for ssid, password in candidates:
        print("Conectando ao Wi-Fi:", ssid)
        try:
            nic.disconnect()
        except Exception:
            pass
        nic.connect(ssid, password)
        deadline = time.ticks_add(time.ticks_ms(), 12000)
        while not nic.isconnected() and time.ticks_diff(deadline, time.ticks_ms()) > 0:
            time.sleep_ms(200)
        if nic.isconnected():
            print("Wi-Fi conectado:", ssid, nic.ifconfig()[0])
            return
    raise OSError("Wi-Fi indisponivel")

def disconnect():
    global mqtt, pending
    if mqtt:
        try:
            mqtt.disconnect()
        except Exception:
            try:
                mqtt.sock.close()
            except Exception:
                pass
    mqtt = None
    pending = None

def connect():
    global mqtt, last_ping
    if not nic.isconnected():
        connect_wifi()
    mac = nic.config("mac")
    client_id = (config.MQTT_CLIENT_ID + "-%02x%02x%02x" % (mac[-3], mac[-2], mac[-1])).encode()
    user = config.MQTT_USER.encode() if config.MQTT_USER else None
    password = config.MQTT_PASSWORD.encode() if config.MQTT_PASSWORD else None
    use_tls = getattr(config, "MQTT_USE_TLS", False)
    use_websocket = getattr(config, "MQTT_USE_WEBSOCKET", False)
    if use_websocket:
        from mqtt_websocket import WebSocketMQTTClient
        c = WebSocketMQTTClient(
            client_id, config.MQTT_HOST, port=config.MQTT_PORT,
            path=getattr(config, "MQTT_WEBSOCKET_PATH", "/mqtt"),
            use_tls=use_tls, user=user, password=password, keepalive=45,
        )
    else:
        ssl_params = {"server_hostname": config.MQTT_HOST} if use_tls else {}
        c = MQTTClient(client_id, config.MQTT_HOST, port=config.MQTT_PORT,
                       user=user, password=password, keepalive=45,
                       ssl=use_tls, ssl_params=ssl_params)
    c.set_callback(callback)
    try:
        c.connect()
        for t in (T_STATUS, T_PROFILES, T_ACK, T_TELEMETRY):
            c.subscribe(t.encode())
    except Exception:
        try:
            c.sock.close()
        except Exception:
            pass
        raise
    mqtt = c
    last_ping = time.ticks_ms()
    print("Conectada ao MQTT: %s:%d, quadro %s" % (config.MQTT_HOST, config.MQTT_PORT, BOARD))

def next_seq():
    # O quadro exige seq crescente; painel e app usam Date.now()*1000.
    # Sem relogio proprio, usa o ts (s UTC) da telemetria mais o tempo decorrido.
    global seq_counter
    seq_counter = (seq_counter + 1) % 1000
    ms = int(tele["ts"]) * 1000 + time.ticks_diff(time.ticks_ms(), tele_ts_ms)
    return str(ms * 1000 + seq_counter)

def telemetry_fresh():
    return tele_ms is not None and time.ticks_diff(time.ticks_ms(), tele_ms) <= config.TELEMETRY_STALE_MS

def send(action, extra=None):
    global pending, pending_at
    if mqtt is None:
        show("Sem MQTT")
        return
    if action != "stop" and (tele_ts_ms is None or not telemetry_fresh()):
        show("Quadro sem telemetria")
        return
    if tele_ts_ms is None:
        seq = str(time.ticks_ms())  # stop aceita qualquer seq
    else:
        seq = next_seq()
    cmd = {"v": 1, "device_id": BOARD, "seq": seq, "action": action}
    if extra:
        cmd.update(extra)
    try:
        mqtt.publish(T_COMMAND.encode(), json.dumps(cmd).encode(), retain=False, qos=0)
        pending = (seq, action)
        pending_at = time.ticks_ms()
        show("Enviado: " + action)
    except OSError as exc:
        print("Erro ao enviar:", exc)
        disconnect()

def request_start():
    if not config.ENABLE_MOTOR_COMMANDS:
        show("Comandos desativados")
        return
    if not profiles:
        show("Sem lista de partidas")
        return
    if tele.get("secure"):
        show("Quadro exige selo")
        return
    if tele.get("actuation") is False:
        show("Modo instrumentacao")
        return
    if tele.get("motor_running") or any(tele.get("relays") or []):
        show("Motor ja ligado")
        return
    send("start", {"boot": tele.get("boot"), "profile": profiles[sel][0]})

def request_stop():
    # Parar e o lado seguro: vai sempre, mesmo com comandos desativados.
    send("stop")

def buttons():
    global was_a, was_b, was_sw, a_start, a_long_done, page, sel
    av = a.value() == 0
    bv = b.value() == 0
    sv = sw.value() == 0
    now = time.ticks_ms()
    if bv and not was_b:
        request_stop()
    if av and not was_a:
        a_start = now
        a_long_done = False
    if av and a_start is not None and not a_long_done and not bv:
        if time.ticks_diff(now, a_start) >= config.START_HOLD_MS:
            a_long_done = True
            request_start()
    if not av and was_a:
        if not a_long_done and profiles:
            sel = (sel + 1) % len(profiles)
            page = 2
        a_start = None
    if sv and not was_sw:
        page = (page + 1) % PAGES
    was_a, was_b, was_sw = av, bv, sv

def number(key, suffix="", places=1):
    try:
        return ("%." + str(places) + "f" + suffix) % float(tele[key])
    except (KeyError, TypeError, ValueError):
        return "--" + suffix

def motor_text():
    if not telemetry_fresh():
        return "Quadro offline"
    if tele.get("trip_alarm"):
        return "Desarme: " + ascii_text(tele.get("trip_field") or tele["trip_alarm"])
    if tele.get("motor_running"):
        return "Motor LIGADO"
    if any(tele.get("relays") or []):
        return "Partindo..."
    return "Motor parado"

def render():
    fresh = telemetry_fresh()
    if mqtt is None or not fresh or tele.get("trip_alarm"):
        led(red=1)
    elif tele.get("motor_running"):
        led(green=1)
    elif any(tele.get("relays") or []):
        led(green=1, red=1)
    else:
        led(blue=1)
    if oled is None:
        return
    oled.fill(0)
    oled.text("MQTT:" + ("OK" if mqtt else "OFF") + " " + BOARD, 0, 0)
    oled.text(motor_text()[:16], 0, 10)
    if page == 0:
        oled.text("U: " + number("voltage", "V"), 0, 22)
        oled.text("I: " + number("current", "A", 2), 0, 32)
        oled.text("P: " + number("power", "W"), 0, 42)
    elif page == 1:
        oled.text("E: " + number("energy", "kWh", 2), 0, 22)
        oled.text("f: " + number("frequency", "Hz"), 0, 32)
        oled.text("FP: " + number("pf", "", 2), 0, 42)
    else:
        oled.text("Partida:", 0, 22)
        if profiles:
            oled.text("> " + profiles[sel][1][:14], 0, 32)
            oled.text("(%d/%d) A:troca" % (sel + 1, len(profiles)), 0, 42)
        else:
            oled.text("aguardando lista", 0, 32)
    if message and time.ticks_diff(time.ticks_ms(), message_at) < 5000:
        oled.text(message[:16], 0, 54)
    elif pending:
        oled.text("Aguardando quadro", 0, 54)
    elif fresh and tele.get("start_phase"):
        oled.text(ascii_text(tele["start_phase"])[:16], 0, 54)
    else:
        oled.text("SW:pag B:desliga", 0, 54)
    oled.show()

def main():
    global last_wifi_attempt, last_ping, pending
    print("BitDogLab: painel do quadro", BOARD)
    print("Partida habilitada:", config.ENABLE_MOTOR_COMMANDS)
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
            except (OSError, MemoryError) as exc:
                print("MQTT caiu:", exc)
                disconnect()
        if pending and time.ticks_diff(now, pending_at) > 10000:
            show("Sem resposta: " + pending[1])
            pending = None
        if time.ticks_diff(now, last_ui) > 400:
            last_ui = now
            render()
        time.sleep_ms(40)

main()
