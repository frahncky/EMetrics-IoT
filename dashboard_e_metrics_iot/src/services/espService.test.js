import assert from "node:assert/strict";
import test from "node:test";

import { buildResetEnergyUrl, resetEspEnergy } from "./espService.js";

test("monta a rota de reset a partir do IP do ESP32", () => {
  assert.equal(
    buildResetEnergyUrl("192.168.1.55"),
    "http://192.168.1.55/reset-energy",
  );
});

test("mantém porta explícita e substitui qualquer rota existente", () => {
  assert.equal(
    buildResetEnergyUrl("http://192.168.1.55:8080/configuracao?modo=teste"),
    "http://192.168.1.55:8080/reset-energy",
  );
});

test("retorna a confirmação enviada pelo ESP32", async () => {
  const message = await resetEspEnergy("esp32.local", async (url, options) => {
    assert.equal(url, "http://esp32.local/reset-energy");
    assert.equal(options.method, "POST");
    return {
      ok: true,
      json: async () => ({ ok: true, message: "Energia acumulada zerada." }),
    };
  });

  assert.equal(message, "Energia acumulada zerada.");
});
