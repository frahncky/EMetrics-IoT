import assert from "node:assert/strict";
import test from "node:test";

import {
  parseTelemetry,
  publishResetEnergy,
  resetEnergyCommandTopic,
} from "./mqttService.js";

test("preserva a hora de medição sincronizada do ESP", () => {
  const telemetry = parseTelemetry(
    '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,' +
    '"frequency":60,"energy":1.23,"timestamp":1746316850000,' +
    '"sequence":7,"timeSynced":true}',
  );

  assert.equal(telemetry.measuredAt?.getTime(), 1746316850000);
  assert.equal(telemetry.sequence, 7);
});

test("não trata timestamp sem sincronização como uma medição atual", () => {
  const telemetry = parseTelemetry(
    '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,' +
    '"frequency":60,"energy":1.23,"timestamp":0,"timeSynced":false}',
  );

  assert.equal(telemetry.measuredAt, null);
});

test("publica o reset no tópico de comandos do ESP32", async () => {
  const published = [];
  const client = {
    connected: true,
    publish(topic, payload, options, callback) {
      published.push({ topic, payload, options });
      callback();
    },
  };

  const requestTopic = await publishResetEnergy(client, "emetrics/pzem/");

  assert.equal(requestTopic, "emetrics/pzem/history/request");
  assert.deepEqual(published, [{
    topic: "emetrics/pzem/history/request",
    payload: '{"command":"resetEnergy"}',
    options: { qos: 0 },
  }]);
  assert.equal(
    resetEnergyCommandTopic("emetrics/pzem"),
    "emetrics/pzem/history/request",
  );
});
