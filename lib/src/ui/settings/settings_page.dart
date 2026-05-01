import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/mqtt_provider.dart';
import '../../providers/mqtt_settings_provider.dart';
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
  final _clientIdController = TextEditingController();
  final _topicController = TextEditingController();
  final _requestTopicController = TextEditingController();
  final _intervalController = TextEditingController(text: '5');
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final isDarkMode = ref.read(themeProvider);
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
    _clientIdController.text = settings.clientId;
    _topicController.text = settings.topic;
    _requestTopicController.text = settings.requestTopic;
  }

  Future<void> _saveSettings() async {
    await ref.read(mqttSettingsProvider.notifier).update(
          broker: _brokerController.text,
          clientId: _clientIdController.text,
          topic: _topicController.text,
          requestTopic: _requestTopicController.text,
        );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
          Text('Configurações Gerais', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
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
            label: 'Campo Tópico MQTT',
            child: TextFormField(
              controller: _topicController,
              validator: (value) =>
                  SettingsValidators.validateTopic(value, fieldLabel: 'o tópico MQTT'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.topic),
                labelText: 'Tópico MQTT',
                helperText: 'Tópico para receber dados',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Semantics(
            label: 'Campo tópico de solicitação de histórico',
            child: TextFormField(
              controller: _requestTopicController,
              validator: (value) =>
                  SettingsValidators.validateTopic(value, fieldLabel: 'o tópico de solicitação'),
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
          const SizedBox(height: 20),
          Semantics(
            label: 'Alternar modo escuro',
            toggled: _darkMode,
            child: SwitchListTile(
              title: Text(_darkMode ? 'Modo escuro' : 'Modo claro'),
              value: _darkMode,
              secondary: const Icon(Icons.dark_mode),
              onChanged: (v) async {
                setState(() => _darkMode = v);
                await ref.read(themeProvider.notifier).setDarkMode(v);
              },
            ),
          ),
          const SizedBox(height: 32),
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
                    const SnackBar(content: Text('Configurações MQTT salvas no dispositivo.')),
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
                      SnackBar(content: Text('Erro ao conectar: ${_toUserMessage(e)}')),
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
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Monitoramento em segundo plano pausado.')),
                  );
                },
                label: const Text('Parar segundo plano'),
              ),
            ),
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
    _clientIdController.dispose();
    _topicController.dispose();
    _requestTopicController.dispose();
    _intervalController.dispose();
    super.dispose();
  }
}
