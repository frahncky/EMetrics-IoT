import assert from "node:assert/strict";
import test from "node:test";

import { parseTelemetry } from "./mqttService.js";

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

test("preserva angulos fasoriais opcionais do payload", () => {
  const telemetry = parseTelemetry(
    '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,' +
    '"frequency":60,"energy":1.23,"phase_angle_deg":11.48,' +
    '"currentAngleDeg":-11.48}',
  );

  assert.equal(telemetry.phaseAngleDeg, 11.48);
  assert.equal(telemetry.currentAngleDeg, -11.48);
});

test("preserva potencia reativa assinada e tipo de carga", () => {
  const telemetry = parseTelemetry(
    '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,' +
    '"frequency":60,"energy":1.23,"reactivePower":-24.5,' +
    '"loadType":"capacitiva"}',
  );

  assert.equal(telemetry.reactivePower, -24.5);
  assert.equal(telemetry.reactivePowerSource, "payload");
  assert.equal(telemetry.loadType, "capacitiva");
});

test("normaliza fator de potência em percentual no payload", () => {
  const telemetry = parseTelemetry(
    '{"voltage":220.1,"current":0.51,"power":112,"pf":98,' +
    '"frequency":60,"energy":1.23}',
  );

  assert.equal(telemetry.pf, 0.98);
});
