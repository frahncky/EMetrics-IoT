class Metric {
  final int? id;
  final DateTime timestamp;
  final double voltage;
  final double current;
  final double power;
  final double pf;
  final double frequency;
  final double energy;

  Metric({
    this.id,
    required this.timestamp,
    required this.voltage,
    required this.current,
    required this.power,
    required this.pf,
    required this.frequency,
    required this.energy,
  });

  factory Metric.fromMap(Map<String, dynamic> map) => Metric(
        id: map['id'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
        voltage: map['voltage'],
        current: map['current'],
        power: map['power'],
        pf: map['pf'],
        frequency: map['frequency'],
        energy: map['energy'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'voltage': voltage,
        'current': current,
        'power': power,
        'pf': pf,
        'frequency': frequency,
        'energy': energy,
      };
}
