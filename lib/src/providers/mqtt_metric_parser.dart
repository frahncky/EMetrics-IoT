import 'dart:convert';
import '../data/metric_model.dart';

/// Converte um payload JSON recebido via MQTT em um objeto [Metric].
///
/// Espera um objeto JSON com os campos:
/// `voltage`, `current`, `power`, `pf`, `frequency`, `energy`.
/// Campos opcionais: `temperature` (E3), `crcErrors` (E8) e `timestamp`
/// (epoch em milissegundos, produzido pelo ESP para rastreabilidade E13).
/// Retorna `null` se o payload for inválido ou estiver incompleto.
Metric? parseMetricFromMqtt(String payload) {
  try {
    // Exemplo de payload: '{"voltage":220.1,"current":0.51,"power":112,"pf":0.98,"frequency":60,"energy":1.23}'
    final map = json.decode(payload);
    if (map is! Map<String, dynamic>) {
      return null;
    }

    final receivedAt = DateTime.now();
    return Metric(
      // Usa o instante da medição quando o relógio do ESP já foi sincronizado.
      // Isso mantém o replay do histórico na posição temporal correta.
      timestamp: _timestampFromPayload(map) ?? receivedAt,
      receivedAt: receivedAt,
      voltage: (map['voltage'] as num).toDouble(),
      current: (map['current'] as num).toDouble(),
      power: (map['power'] as num).toDouble(),
      pf: (map['pf'] as num).toDouble(),
      frequency: (map['frequency'] as num).toDouble(),
      energy: (map['energy'] as num).toDouble(),
      temperature: map['temperature'] != null
          ? (map['temperature'] as num).toDouble()
          : null,
      crcErrors: map['crcErrors'] != null
          ? (map['crcErrors'] as num).toInt()
          : null,
    );
  } catch (_) {
    return null;
  }
}

DateTime? _timestampFromPayload(Map<String, dynamic> map) {
  final rawTimestamp = map['timestamp'];
  if (rawTimestamp is! num || !rawTimestamp.isFinite) {
    return null;
  }

  final millisecondsSinceEpoch = rawTimestamp.toInt();
  if (millisecondsSinceEpoch <= 0) {
    return null;
  }

  return DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
}
