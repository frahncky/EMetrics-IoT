class AppDatabaseException implements Exception {
  final String message;
  final Object? cause;

  const AppDatabaseException(this.message, {this.cause});

  @override
  String toString() => cause != null ? '$message: $cause' : message;
}
