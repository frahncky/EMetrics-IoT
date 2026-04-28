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
                onPressed: () {
                  // Salvar configurações (implementar persistência se necessário)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Configurações salvas!')),
                  );
                },
                label: const Text('Salvar'),
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
    _topicController.dispose();
    _intervalController.dispose();
    super.dispose();
  }
}
