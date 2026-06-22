import mqtt from "mqtt";

export const DEFAULT_MQTT_CONFIG = {
  // O ESP32 pode continuar publicando em mqtt://test.mosquitto.org:1883.
  // O dashboard web assina o mesmo tópico pelo listener WebSocket seguro.
  url: "wss://test.mosquitto.org:8081",
  topic: "emetrics/pzem",
  username: "",
  password: "",
};

const REQUIRED_FIELDS = [
  "voltage",
  "current",
  "power",
  "pf",
  "frequency",
  "energy",
];

export function parseTelemetry(payload) {
  const decoded = JSON.parse(payload.toString());

  if (
    !decoded ||
    REQUIRED_FIELDS.some((field) => !Number.isFinite(Number(decoded[field])))
  ) {
    throw new Error("Payload MQTT incompleto ou inválido.");
  }

  const voltage = Number(decoded.voltage);
  const current = Number(decoded.current);
  const power = Number(decoded.power);
  const apparentPower = voltage * current;
  const reactivePower = Math.sqrt(Math.max(0, apparentPower ** 2 - power ** 2));

  return {
    voltage,
    current,
    power,
    apparentPower,
    // O payload não diferencia carga indutiva de capacitiva; portanto Q é módulo.
    reactivePower,
    pf: Number(decoded.pf),
    frequency: Number(decoded.frequency),
    energy: Number(decoded.energy),
    temperature: decoded.temperature != null ? Number(decoded.temperature) : null,
    crcErrors: decoded.crcErrors != null ? Number(decoded.crcErrors) : null,
    storage: decoded.storage ?? null,
    receivedAt: new Date(),
  };
}

export function connectMqtt(config, handlers) {
  const url = config.url.trim();
  const topic = config.topic.trim();
  const clientSuffix = globalThis.crypto?.randomUUID?.() ?? Math.random().toString(16).slice(2);

  if (!/^wss?:\/\//i.test(url)) {
    throw new Error("Use uma URL MQTT WebSocket iniciada por ws:// ou wss://.");
  }

  if (!topic) {
    throw new Error("Informe o tópico de telemetria.");
  }

  const client = mqtt.connect(url, {
    clientId: `emetrics-dashboard-${clientSuffix}`,
    username: config.username.trim() || undefined,
    password: config.password || undefined,
    reconnectPeriod: 3000,
    connectTimeout: 8000,
    clean: true,
  });

  client.on("connect", () => {
    client.subscribe(topic, { qos: 0 }, (error) => {
      if (error) handlers.onError(error);
      else handlers.onConnected();
    });
  });

  client.on("message", (messageTopic, payload) => {
    if (messageTopic !== topic) return;

    try {
      handlers.onTelemetry(parseTelemetry(payload));
    } catch (error) {
      handlers.onPayloadError(error);
    }
  });

  client.on("reconnect", handlers.onReconnecting);
  client.on("offline", handlers.onOffline);
  client.on("close", handlers.onClosed);
  client.on("error", handlers.onError);

  return client;
}
