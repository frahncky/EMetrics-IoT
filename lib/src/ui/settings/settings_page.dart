import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/mqtt_provider.dart';
import '../../providers/mqtt_settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Configurações Gerais', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          Semantics(
            label: 'Campo Broker MQTT',
            child: TextField(
              controller: _brokerController,
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
            child: TextField(
              controller: _clientIdController,
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
            child: TextField(
              controller: _topicController,
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
            child: TextField(
              controller: _requestTopicController,
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
            child: TextField(
              controller: _intervalController,
              keyboardType: TextInputType.number,
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
              title: const Text('Modo escuro'),
              value: _darkMode,
              secondary: const Icon(Icons.dark_mode),
              onChanged: (v) => setState(() => _darkMode = v),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  try {
                    await _saveSettings();
                    final mqttService = ref.read(mqttServiceProvider);
                    await mqttService.connect();
                    mqttService.subscribe();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Conectado ao broker MQTT!')),
                    );
                  } catch (e) {
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao conectar: $e')),
                    );
                  }
                },
                label: const Text('Conectar MQTT'),
              ),
            ),
          ),
        ],
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
