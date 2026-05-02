import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/mqtt_settings_provider.dart';
import '../../services/esp_provisioning_service.dart';
import 'settings_validators.dart';

class EspProvisioningPage extends ConsumerStatefulWidget {
  const EspProvisioningPage({super.key});

  @override
  ConsumerState<EspProvisioningPage> createState() =>
      _EspProvisioningPageState();
}

class _EspProvisioningPageState extends ConsumerState<EspProvisioningPage> {
  final _formKey = GlobalKey<FormState>();
  final _espHostController = TextEditingController(text: '192.168.4.1');
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  final _mqttHostController = TextEditingController();
  final _mqttPortController = TextEditingController(text: '1883');
  final _mqttUserController = TextEditingController();
  final _mqttPasswordController = TextEditingController();
  final _mqttTopicController = TextEditingController();
  final _mqttRequestTopicController = TextEditingController();
  final _mqttClientIdController = TextEditingController();
  bool _useTls = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _prefillFromSettings();
  }

  Future<void> _prefillFromSettings() async {
    final settings = await ref.read(mqttSettingsProvider.notifier).load();
    if (!mounted) {
      return;
    }

    _mqttHostController.text = settings.broker;
    _mqttPortController.text = settings.port.toString();
    _mqttUserController.text = settings.username;
    _mqttPasswordController.text = settings.password;
    _mqttTopicController.text = settings.topic;
    _mqttRequestTopicController.text = settings.requestTopic;
    _mqttClientIdController.text = settings.clientId;
    setState(() => _useTls = settings.useTls);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    final service = const EspProvisioningService();
    final result = await service.provision(
      espHost: _espHostController.text,
      wifiSsid: _wifiSsidController.text,
      wifiPassword: _wifiPasswordController.text,
      mqttHost: _mqttHostController.text,
      mqttPort: int.parse(_mqttPortController.text.trim()),
      mqttUser: _mqttUserController.text,
      mqttPassword: _mqttPasswordController.text,
      mqttTopic: _mqttTopicController.text,
      mqttRequestTopic: _mqttRequestTopicController.text,
      mqttClientId: _mqttClientIdController.text,
      useTls: _useTls,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? null : Colors.redAccent,
      ),
    );

    if (result.ok) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Provisionar ESP32')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Conecte o celular na rede AP do ESP32 e envie as configuracoes.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _espHostController,
                decoration: const InputDecoration(
                  labelText: 'IP/URL do ESP32',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Informe o IP/URL do ESP32.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _wifiSsidController,
                decoration: const InputDecoration(
                  labelText: 'SSID Wi-Fi',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Informe o SSID da rede Wi-Fi.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _wifiPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha Wi-Fi',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _mqttHostController,
                validator: SettingsValidators.validateBroker,
                decoration: const InputDecoration(
                  labelText: 'Broker MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttPortController,
                keyboardType: TextInputType.number,
                validator: SettingsValidators.validatePort,
                decoration: const InputDecoration(
                  labelText: 'Porta MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttUserController,
                decoration: const InputDecoration(
                  labelText: 'Usuario MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttTopicController,
                validator: (value) =>
                    SettingsValidators.validateTopic(value, fieldLabel: 'o topico MQTT'),
                decoration: const InputDecoration(
                  labelText: 'Topico MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttRequestTopicController,
                validator: (value) => SettingsValidators.validateTopic(
                  value,
                  fieldLabel: 'o topico de solicitacao',
                ),
                decoration: const InputDecoration(
                  labelText: 'Topico de solicitacao de historico',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttClientIdController,
                validator: SettingsValidators.validateClientId,
                decoration: const InputDecoration(
                  labelText: 'Client ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                value: _useTls,
                onChanged: (value) => setState(() => _useTls = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('Usar TLS/SSL no MQTT'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? 'Enviando...' : 'Enviar para ESP32'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _espHostController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _mqttHostController.dispose();
    _mqttPortController.dispose();
    _mqttUserController.dispose();
    _mqttPasswordController.dispose();
    _mqttTopicController.dispose();
    _mqttRequestTopicController.dispose();
    _mqttClientIdController.dispose();
    super.dispose();
  }
}
