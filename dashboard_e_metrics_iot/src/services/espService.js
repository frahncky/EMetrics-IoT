function normalizeEspBaseUrl(hostOrUrl) {
  const value = String(hostOrUrl ?? "").trim();
  if (!value) {
    throw new Error("Informe o endereço IP ou a URL do ESP32.");
  }

  const valueWithProtocol = /^https?:\/\//i.test(value)
    ? value
    : `http://${value}`;
  const url = new URL(valueWithProtocol);

  if (!/^https?:$/.test(url.protocol)) {
    throw new Error("Use um endereço HTTP ou HTTPS válido para o ESP32.");
  }

  return url;
}

export function buildResetEnergyUrl(hostOrUrl) {
  const url = normalizeEspBaseUrl(hostOrUrl);
  url.pathname = "/reset-energy";
  url.search = "";
  url.hash = "";
  return url.toString();
}

export async function resetEspEnergy(hostOrUrl, fetchImpl = fetch) {
  const response = await fetchImpl(buildResetEnergyUrl(hostOrUrl), {
    method: "POST",
  });

  let payload = null;
  try {
    payload = await response.json();
  } catch (_) {
    // A resposta de erro pode não ter corpo JSON; o status HTTP abaixo ainda
    // fornece uma mensagem útil ao operador.
  }

  if (!response.ok || payload?.ok === false) {
    throw new Error(
      payload?.message || `Falha ao zerar a energia (HTTP ${response.status}).`,
    );
  }

  return payload?.message || "Energia acumulada zerada no ESP32.";
}
