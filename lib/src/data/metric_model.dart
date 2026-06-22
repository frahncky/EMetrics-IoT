/// Representa uma leitura elétrica instantânea capturada pelo sensor PZEM004T.
///
/// Unidades de cada campo:
/// - [voltage]: Volts (V)
/// - [current]: Ampères (A)
/// - [power]: Watts (W) — potência ativa
/// - [pf]: adimensional — fator de potência (0..1)
/// - [frequency]: Hertz (Hz)
/// - [energy]: Quilowatt-hora (kWh)
/// - [temperature]: Celsius (°C) — temperatura interna do ESP32 (E3)
/// - [crcErrors]: contagem acumulada de erros de CRC na UART PZEM (E8)
/// - [receivedAt]: instante em que o app recebeu a telemetria; usado para
///   indicar a saúde da comunicação, independentemente da hora da medição.
class Metric {
  final int? id;
  final DateTime timestamp;
  final DateTime? receivedAt;
  final double voltage;
  final double current;
  final double power;
  final double pf;
  final double frequency;
  final double energy;
  final double? temperature;
  final int? crcErrors;

  Metric({
    this.id,
    required this.timestamp,
    this.receivedAt,
    required this.voltage,
    required this.current,
    required this.power,
    required this.pf,
    required this.frequency,
    required this.energy,
    this.temperature,
    this.crcErrors,
  });

  factory Metric.fromMap(Map<String, dynamic> map) => Metric(
    id: map['id'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    receivedAt: map['received_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['received_at'] as int)
        : null,
    voltage: map['voltage'],
    current: map['current'],
    power: map['power'],
    pf: map['pf'],
    frequency: map['frequency'],
    energy: map['energy'],
    temperature: map['temperature'] != null
        ? (map['temperature'] as num).toDouble()
        : null,
    crcErrors: map['crc_errors'] as int?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'received_at': receivedAt?.millisecondsSinceEpoch,
    'voltage': voltage,
    'current': current,
    'power': power,
    'pf': pf,
    'frequency': frequency,
    'energy': energy,
    'temperature': temperature,
    'crc_errors': crcErrors,
  };
}
