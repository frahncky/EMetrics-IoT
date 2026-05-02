import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/measurement_settings_provider.dart';
import '../../providers/mqtt_provider.dart';
import '../../providers/mqtt_settings_provider.dart';
import '../../providers/mqtt_status_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/background_mqtt_service.dart';
import 'settings_validators.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _brokerController = TextEditingController();
  final _portController = TextEditingController(text: '1883');
  final _clientIdController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _topicController = TextEditingController();
  final _requestTopicController = TextEditingController();
  final _intervalController = TextEditingController(text: '5');
  final _voltageMinController = TextEditingController();
  final _voltageMaxController = TextEditingController();
  final _energyLimitController = TextEditingController();
  final _tariffController = TextEditingController();
  bool _darkMode = false;
  bool _useTls = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final isDarkMode = ref.read(themeProvider);
    await ref.read(mqttStatusProvider.notifier).syncBackgroundState();
    if (mounted) {
      setState(() => _darkMode = isDarkMode);
    }
  }

  Future<void> _loadSettings() async {
    final settings = await ref.read(mqttSettingsProvider.notifier).load();
    if (!mounted) {
      return;
    }
    _brokerController.text = settings.broker;
    _portController.text = settings.port.toString();
    _clientIdController.text = settings.clientId;
    _usernameController.text = settings.username;
    _passwordController.text = settings.password;
    _topicController.text = settings.topic;
    _requestTopicController.text = settings.requestTopic;
    _useTls = settings.useTls;

    final measurementSettings = await ref
        .read(measurementSettingsProvider.notifier)
        .load();
    if (!mounted) {
      return;
    }
    _voltageMinController.text = _formatDecimal(measurementSettings.voltageMin);
    _voltageMaxController.text = _formatDecimal(measurementSettings.voltageMax);
    _energyLimitController.text = _formatDecimal(
      measurementSettings.energyLimitKwh,
    );
    _tariffController.text = _formatDecimal(measurementSettings.tariffPerKwh);
  }

  Future<void> _saveSettings() async {
    await ref
        .read(mqttSettingsProvider.notifier)
        .update(
          broker: _brokerController.text,
          port: int.parse(_portController.text.trim()),
          clientId: _clientIdController.text,
          username: _usernameController.text,
          password: _passwordController.text,
          topic: _topicController.text,
          requestTopic: _requestTopicController.text,
          useTls: _useTls,
        );
    await ref
        .read(measurementSettingsProvider.notifier)
        .update(
          voltageMin: _parseDecimal(_voltageMinController.text),
          voltageMax: _parseDecimal(_voltageMaxController.text),
          energyLimitKwh: _parseDecimal(_energyLimitController.text),
          tariffPerKwh: _parseDecimal(_tariffController.text),
        );
  }

  double _parseDecimal(String value) {
    return double.parse(value.trim().replaceAll(',', '.'));
  }

  String _formatDecimal(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  String? _validateVoltageMax(String? value) {
    final error = SettingsValidators.validateDecimal(
      value,
      fieldLabel: 'a tensão máxima',
      min: 1,
      max: 1000,
      allowZero: false,
    );
    if (error != null) {
      return error;
    }

    final minVoltage = double.tryParse(
      _voltageMinController.text.trim().replaceAll(',', '.'),
    );
    final maxVoltage = double.tryParse(value!.trim().replaceAll(',', '.'));
    if (minVoltage != null && maxVoltage != null && maxVoltage <= minVoltage) {
      return 'A tensão máxima deve ser maior que a mínima.';
    }
    return null;
  }

  String _toUserMessage(Object error) {
    const prefix = 'Exception: ';
    final text = error.toString();
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length);
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final mqttStatus = ref.watch(mqttStatusProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [
                      const Color(0xFF1A202C),
                      const Color(0xFF0F1419).withValues(alpha: 0.9),
                    ]
                  : [
                      const Color(0xFFFFFFFF),
                      const Color(0xFFF8FAFC).withValues(alpha: 0.9),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text('Configurações'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _MqttStatusCard(status: mqttStatus),
            const SizedBox(height: 28),
            _SettingsSection(
              title: 'MQTT',
              icon: Icons.cloud_outlined,
              children: [
                Semantics(
                  label: 'Campo Broker MQTT',
                  child: TextFormField(
                    controller: _brokerController,
                    validator: SettingsValidators.validateBroker,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.cloud),
                      labelText: 'Broker MQTT',
                      helperText: 'IP ou domínio do broker',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo porta MQTT',
                  child: TextFormField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    validator: SettingsValidators.validatePort,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.settings_ethernet),
                      labelText: 'Porta MQTT',
                      helperText: 'Ex.: 1883 sem TLS, 8883 com TLS',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo Client ID MQTT',
                  child: TextFormField(
                    controller: _clientIdController,
                    validator: SettingsValidators.validateClientId,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.badge),
                      labelText: 'Client ID MQTT',
                      helperText: 'Identificador único do cliente MQTT',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo usuário MQTT',
                  child: TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline),
                      labelText: 'Usuário MQTT',
                      helperText: 'Opcional para brokers autenticados',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo senha MQTT',
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.lock_outline),
                      labelText: 'Senha MQTT',
                      helperText: 'Opcional para brokers autenticados',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo Tópico MQTT',
                  child: TextFormField(
                    controller: _topicController,
                    validator: (value) => SettingsValidators.validateTopic(
                      value,
                      fieldLabel: 'o tópico MQTT',
                    ),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.topic),
                      labelText: 'Tópico MQTT',
                      helperText: 'Tópico para receber dados',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  label: 'Alternar TLS MQTT',
                  toggled: _useTls,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Usar TLS/SSL'),
                    subtitle: const Text('Ative para conexões seguras, como a porta 8883.'),
                    value: _useTls,
                    secondary: const Icon(Icons.security_outlined),
                    onChanged: (value) {
                      setState(() => _useTls = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SettingsSection(
              title: 'Histórico e atualização',
              icon: Icons.history_toggle_off,
              children: [
                Semantics(
                  label: 'Campo tópico de solicitação de histórico',
                  child: TextFormField(
                    controller: _requestTopicController,
                    validator: (value) => SettingsValidators.validateTopic(
                      value,
                      fieldLabel: 'o tópico de solicitação',
                    ),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.history_toggle_off),
                      labelText: 'Tópico de solicitação de histórico',
                      helperText: 'Tópico para publicar pedidos de histórico',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo Intervalo de atualização',
                  child: TextFormField(
                    controller: _intervalController,
                    keyboardType: TextInputType.number,
                    validator: SettingsValidators.validateInterval,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.timer),
                      labelText: 'Intervalo de atualização (s)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SettingsSection(
              title: 'Medição e alertas',
              icon: Icons.tune,
              children: [
                Semantics(
                  label: 'Campo tensão mínima para alerta',
                  child: TextFormField(
                    controller: _voltageMinController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => SettingsValidators.validateDecimal(
                      value,
                      fieldLabel: 'a tensão mínima',
                      min: 0,
                      max: 1000,
                      allowZero: false,
                    ),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.electrical_services),
                      labelText: 'Tensão mínima (V)',
                      helperText: 'Dispara alerta abaixo deste valor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo tensão máxima para alerta',
                  child: TextFormField(
                    controller: _voltageMaxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _validateVoltageMax,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.electrical_services),
                      labelText: 'Tensão máxima (V)',
                      helperText: 'Dispara alerta acima deste valor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo limite de consumo para alerta',
                  child: TextFormField(
                    controller: _energyLimitController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => SettingsValidators.validateDecimal(
                      value,
                      fieldLabel: 'o limite de consumo',
                      min: 0,
                      max: 100000,
                      allowZero: false,
                    ),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.battery_alert_outlined),
                      labelText: 'Limite de consumo (kWh)',
                      helperText:
                          'Dispara alerta quando a energia passar disso',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Semantics(
                  label: 'Campo tarifa por kWh',
                  child: TextFormField(
                    controller: _tariffController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) => SettingsValidators.validateDecimal(
                      value,
                      fieldLabel: 'a tarifa por kWh',
                      min: 0,
                      max: 1000,
                    ),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.attach_money),
                      labelText: 'Tarifa (R\$/kWh)',
                      helperText: 'Usada para estimar custo de consumo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SettingsSection(
              title: 'Aparência',
              icon: _darkMode ? Icons.dark_mode : Icons.light_mode,
              children: [
                Semantics(
                  label: 'Alternar modo escuro',
                  toggled: _darkMode,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_darkMode ? 'Modo escuro' : 'Modo claro'),
                    value: _darkMode,
                    secondary: Icon(
                      _darkMode ? Icons.dark_mode : Icons.light_mode,
                    ),
                    onChanged: (v) async {
                      setState(() => _darkMode = v);
                      await ref.read(themeProvider.notifier).setDarkMode(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SettingsSection(
              title: 'Operação',
              icon: Icons.play_circle_outline,
              children: [
                Semantics(
                  label: 'Botão Salvar configurações',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      onPressed: () async {
                        FocusScope.of(context).unfocus();
                        if (!_formKey.currentState!.validate()) {
                          return;
                        }
                        await _saveSettings();
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Configurações MQTT salvas no dispositivo.',
                            ),
                          ),
                        );
                      },
                      label: const Text('Salvar'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Botão Conectar MQTT',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cloud),
                      onPressed: () async {
                        FocusScope.of(context).unfocus();
                        if (!_formKey.currentState!.validate()) {
                          return;
                        }
                        try {
                          await _saveSettings();
                          final mqttService = ref.read(mqttServiceProvider);
                          await mqttService.connect();
                          mqttService.subscribe();
                          await BackgroundMqttService.start();
                          ref.read(mqttStatusProvider.notifier).setBackgroundActive(true);
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Conectado ao broker MQTT e monitoramento em segundo plano ativado.',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Erro ao conectar: ${_toUserMessage(e)}',
                              ),
                            ),
                          );
                        }
                      },
                      label: const Text('Conectar MQTT'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Botão Parar segundo plano',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.pause_circle_outline),
                      onPressed: () async {
                        await BackgroundMqttService.stop();
                        ref.read(mqttStatusProvider.notifier).setBackgroundActive(false);
                        ref.read(mqttStatusProvider.notifier).markDisconnected(
                          'Monitoramento em segundo plano pausado.',
                        );
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Monitoramento em segundo plano pausado.',
                            ),
                          ),
                        );
                      },
                      label: const Text('Parar segundo plano'),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 140 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _brokerController.dispose();
    _portController.dispose();
    _clientIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _topicController.dispose();
    _requestTopicController.dispose();
    _intervalController.dispose();
    _voltageMinController.dispose();
    _voltageMaxController.dispose();
    _energyLimitController.dispose();
    _tariffController.dispose();
    super.dispose();
  }
}

class _MqttStatusCard extends StatelessWidget {
  final MqttStatusState status;

  const _MqttStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final phaseColor = switch (status.phase) {
      MqttConnectionPhase.connected => const Color(0xFF15803D),
      MqttConnectionPhase.connecting => const Color(0xFFD97706),
      MqttConnectionPhase.error => const Color(0xFFDC2626),
      MqttConnectionPhase.disconnected => colorScheme.outline,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.podcasts, color: phaseColor),
                const SizedBox(width: 8),
                Text(
                  'Status operacional MQTT',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Broker: ${status.broker}:${status.port}'),
            Text('Tópico: ${status.topic}'),
            Text('Segurança: ${status.useTls ? 'TLS/SSL' : 'Sem TLS'}'),
            Text('Conexão: ${_phaseLabel(status.phase)}'),
            Text(
              'Segundo plano: ${status.backgroundActive ? 'ativo' : 'inativo'}',
            ),
            if (status.lastConnectedAt != null)
              Text('Última conexão: ${_formatTimestamp(status.lastConnectedAt!)}'),
            if (status.lastMessage != null) ...[
              const SizedBox(height: 8),
              Text(status.lastMessage!),
            ],
          ],
        ),
      ),
    );
  }

  static String _phaseLabel(MqttConnectionPhase phase) {
    switch (phase) {
      case MqttConnectionPhase.connected:
        return 'conectado';
      case MqttConnectionPhase.connecting:
        return 'conectando';
      case MqttConnectionPhase.error:
        return 'erro';
      case MqttConnectionPhase.disconnected:
        return 'desconectado';
    }
  }

  static String _formatTimestamp(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}
