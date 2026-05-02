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
  int _selectedTab = 0;

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
    final tabContents = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: _SettingsSection(
          children: [
            Semantics(
              label: 'Campo Broker MQTT',
              child: TextFormField(
                controller: _brokerController,
                validator: SettingsValidators.validateBroker,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.cloud),
                  labelText: 'Broker MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Campo porta MQTT',
              child: TextFormField(
                controller: _portController,
                keyboardType: TextInputType.number,
                validator: SettingsValidators.validatePort,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.settings_ethernet),
                  labelText: 'Porta MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Campo Client ID MQTT',
              child: TextFormField(
                controller: _clientIdController,
                validator: SettingsValidators.validateClientId,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.badge),
                  labelText: 'Client ID MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ResponsiveFieldPair(
              first: Semantics(
                label: 'Campo usuário MQTT',
                child: TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_outline),
                    labelText: 'Usuário MQTT',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              second: Semantics(
                label: 'Campo senha MQTT',
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline),
                    labelText: 'Senha MQTT',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Campo Tópico MQTT',
              child: TextFormField(
                controller: _topicController,
                validator: (value) =>
                    SettingsValidators.validateTopic(value, fieldLabel: 'o tópico MQTT'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.topic),
                  labelText: 'Tópico MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Alternar TLS MQTT',
              toggled: _useTls,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: const Text('Usar TLS/SSL'),
                value: _useTls,
                secondary: const Icon(Icons.security_outlined),
                onChanged: (value) {
                  setState(() => _useTls = value);
                },
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: _SettingsSection(
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
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: _SettingsSection(
          children: [
            _ResponsiveFieldPair(
              first: Semantics(
                label: 'Campo tensão mínima para alerta',
                child: TextFormField(
                  controller: _voltageMinController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              second: Semantics(
                label: 'Campo tensão máxima para alerta',
                child: TextFormField(
                  controller: _voltageMaxController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: _validateVoltageMax,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.electrical_services),
                    labelText: 'Tensão máxima (V)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Campo limite de consumo para alerta',
              child: TextFormField(
                controller: _energyLimitController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Campo tarifa por kWh',
              child: TextFormField(
                controller: _tariffController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => SettingsValidators.validateDecimal(
                  value,
                  fieldLabel: 'a tarifa por kWh',
                  min: 0,
                  max: 1000,
                ),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.attach_money),
                  labelText: 'Tarifa (R\$/kWh)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: _SettingsSection(
          children: [
            Semantics(
              label: 'Alternar modo escuro',
              toggled: _darkMode,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(_darkMode ? 'Modo escuro' : 'Modo claro'),
                value: _darkMode,
                secondary: Icon(_darkMode ? Icons.dark_mode : Icons.light_mode),
                onChanged: (v) async {
                  setState(() => _darkMode = v);
                  await ref.read(themeProvider.notifier).setDarkMode(v);
                },
              ),
            ),
          ],
        ),
      ),
    ];

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
      body: DefaultTabController(
        length: 4,
        initialIndex: _selectedTab,
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Botão Conectar MQTT',
                        button: true,
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.cloud),
                            iconAlignment: IconAlignment.start,
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
                            label: const Text(
                              'Conectar',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        label: 'Botão Parar segundo plano',
                        button: true,
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.pause_circle_outline, size: 18),
                            iconAlignment: IconAlignment.start,
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
                            label: const Text(
                              'Segundo plano',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  onTap: (index) {
                    setState(() => _selectedTab = index);
                  },
                  tabs: const [
                    Tab(icon: Icon(Icons.cloud_outlined), text: 'MQTT'),
                    Tab(icon: Icon(Icons.history_toggle_off), text: 'Histórico'),
                    Tab(icon: Icon(Icons.tune), text: 'Medição'),
                    Tab(icon: Icon(Icons.palette_outlined), text: 'Aparência'),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                        isDense: false,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                    child: tabContents[_selectedTab],
                  ),
                ),
              ],
            ),
          ),
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

class _SettingsSection extends StatelessWidget {
  final List<Widget> children;

  const _SettingsSection({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...children,
      ],
    );
  }
}

class _ResponsiveFieldPair extends StatelessWidget {
  final Widget first;
  final Widget second;

  const _ResponsiveFieldPair({
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              first,
              const SizedBox(height: 12),
              second,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
