class IntegrationSyncItem {
  final int id;
  final DateTime createdAt;
  final DateTime metricTimestamp;
  final String payload;
  final String? profileId;
  final int attempts;
  final String? lastError;

  const IntegrationSyncItem({
    required this.id,
    required this.createdAt,
    required this.metricTimestamp,
    required this.payload,
    required this.profileId,
    required this.attempts,
    required this.lastError,
  });

  factory IntegrationSyncItem.fromMap(Map<String, dynamic> map) {
    return IntegrationSyncItem(
      id: map['id'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      metricTimestamp: DateTime.fromMillisecondsSinceEpoch(
        map['metric_timestamp'] as int,
      ),
      payload: map['payload'] as String,
      profileId: map['profile_id'] as String?,
      attempts: map['attempts'] as int? ?? 0,
      lastError: map['last_error'] as String?,
    );
  }
}