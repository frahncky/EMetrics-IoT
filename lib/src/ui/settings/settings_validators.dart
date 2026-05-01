class SettingsValidators {
  static final RegExp _brokerPattern = RegExp(r'^[a-zA-Z0-9.-]+$');

  static String? validateBroker(String? value) {
    final broker = value?.trim() ?? '';
    if (broker.isEmpty) {
      return 'Informe o broker MQTT.';
    }
    if (broker.startsWith('http://') || broker.startsWith('https://')) {
      return 'Informe apenas host/IP do broker, sem http:// ou https://.';
    }
    if (broker.contains('/') || broker.contains(' ')) {
      return 'Broker inválido. Use apenas host ou IP.';
    }
    if (!_brokerPattern.hasMatch(broker)) {
      return 'Broker inválido. Use letras, números, ponto e hífen.';
    }
    return null;
  }

  static String? validateClientId(String? value) {
    final clientId = value?.trim() ?? '';
    if (clientId.isEmpty) {
      return 'Informe o Client ID.';
    }
    if (clientId.contains(' ')) {
      return 'Client ID não pode conter espaços.';
    }
    if (clientId.length > 50) {
      return 'Client ID muito longo (máximo de 50 caracteres).';
    }
    return null;
  }

  static String? validateTopic(String? value, {required String fieldLabel}) {
    final topic = value?.trim() ?? '';
    if (topic.isEmpty) {
      return 'Informe $fieldLabel.';
    }
    if (topic.contains(' ')) {
      return 'O tópico não pode conter espaços.';
    }
    if (topic.startsWith('/') || topic.endsWith('/')) {
      return 'Evite / no início ou no fim do tópico.';
    }
    if (topic.contains('//')) {
      return 'O tópico contém níveis vazios (//).';
    }
    if (topic.contains('#') || topic.contains('+')) {
      return 'Use um tópico específico sem curingas (#/+).';
    }
    return null;
  }

  static String? validateInterval(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Informe o intervalo de atualização.';
    }
    final parsed = int.tryParse(text);
    if (parsed == null) {
      return 'Intervalo inválido. Use apenas números.';
    }
    if (parsed <= 0) {
      return 'O intervalo deve ser maior que zero.';
    }
    if (parsed > 3600) {
      return 'O intervalo máximo permitido é 3600 segundos.';
    }
    return null;
  }
}