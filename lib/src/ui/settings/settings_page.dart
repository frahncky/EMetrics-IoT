import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _brokerController = TextEditingController(text: 'test.mosquitto.org');
  final _topicController = TextEditingController(text: 'emetrics/pzem');
  final _intervalController = TextEditingController(text: '5');
  bool _darkMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _brokerController,
            decoration: const InputDecoration(
              labelText: 'Broker MQTT',
              helperText: 'IP ou domínio do broker',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _topicController,
            decoration: const InputDecoration(
              labelText: 'Tópico MQTT',
              helperText: 'Tópico para receber dados',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _intervalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Intervalo de atualização (s)',
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Modo escuro'),
            value: _darkMode,
            onChanged: (v) => setState(() => _darkMode = v),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // Salvar configurações (implementar persistência se necessário)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Configurações salvas!')),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _brokerController.dispose();
    _topicController.dispose();
    _intervalController.dispose();
    super.dispose();
  }
}
