import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/mqtt_settings_provider.dart';
import '../../services/esp_local_host_store.dart';
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
  final _wifiUsernameController = TextEditingController();
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
  bool _isLoadingNetworks = false;
  bool _isSavingNetwork = false;
  bool _isScanning = false;
  bool _wifiPasswordVisible = false;
  bool _mqttPasswordVisible = false;
  String? _editingNetworkSsid;
  String? _deletingNetworkSsid;
  String _appMqttClientId = '';
  List<EspWifiNetwork> _savedNetworks = const [];
  final EspProvisioningService _service = const EspProvisioningService();
  final EspLocalHostStore _espHostStore = const EspLocalHostStore();

  @override
  void initState() {
    super.initState();
    _prefillFromSettings();
  }

  Future<void> _prefillFromSettings() async {
    _espHostController.text = await _espHostStore.loadHost();
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
    _appMqttClientId = settings.clientId.trim();
    _mqttClientIdController.text =
        EspProvisioningService.buildDefaultEspClientId(_appMqttClientId);
    setState(() => _useTls = settings.useTls);
  }

  Future<void> _saveCurrentEspHost() async {
    await _espHostStore.saveHost(_espHostController.text);
  }

  Future<void> _loadSavedNetworks({bool silent = false}) async {
    setState(() => _isLoadingNetworks = true);
    try {
      await _saveCurrentEspHost();
      final networks = await _service.loadWifiNetworks(
        espHost: _espHostController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedNetworks = networks;
        _isLoadingNetworks = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingNetworks = false);
      if (silent) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível carregar redes salvas: ${_message(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _saveWifiNetwork() async {
    FocusScope.of(context).unfocus();
    final ssid = _wifiSsidController.text.trim();
    if (_espHostController.text.trim().isEmpty || ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o IP do ESP32 e o SSID Wi-Fi.')),
      );
      return;
    }

    setState(() => _isSavingNetwork = true);
    final editing = _editingNetworkSsid;
    await _saveCurrentEspHost();
    final result = await _service.saveWifiNetwork(
      espHost: _espHostController.text,
      ssid: ssid,
      wifiUsername: _wifiUsernameController.text,
      wifiPassword: _wifiPasswordController.text.trim(),
      oldSsid: editing,
      keepUsername:
          editing != null && _wifiUsernameController.text.trim().isEmpty,
      keepPassword:
          editing != null && _wifiPasswordController.text.trim().isEmpty,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isSavingNetwork = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? null : Colors.redAccent,
      ),
    );

    if (result.ok) {
      setState(() {
        _editingNetworkSsid = null;
        _wifiUsernameController.clear();
        _wifiPasswordController.clear();
      });
      await _loadSavedNetworks();
    }
  }

  Future<void> _deleteWifiNetwork(EspWifiNetwork network) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir rede Wi-Fi'),
        content: Text('Excluir "${network.ssid}" das redes salvas no ESP32?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _deletingNetworkSsid = network.ssid);
    await _saveCurrentEspHost();
    final result = await _service.deleteWifiNetwork(
      espHost: _espHostController.text,
      ssid: network.ssid,
    );
    if (!mounted) {
      return;
    }
    setState(() => _deletingNetworkSsid = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? null : Colors.redAccent,
      ),
    );
    if (result.ok) {
      if (_editingNetworkSsid == network.ssid) {
        _cancelWifiNetworkEdit();
      }
      await _loadSavedNetworks();
    }
  }

  void _editWifiNetwork(EspWifiNetwork network) {
    setState(() {
      _editingNetworkSsid = network.ssid;
      _wifiSsidController.text = network.ssid;
      _wifiUsernameController.clear();
      _wifiPasswordController.clear();
    });
  }

  void _cancelWifiNetworkEdit() {
    setState(() {
      _editingNetworkSsid = null;
      _wifiSsidController.clear();
      _wifiUsernameController.clear();
      _wifiPasswordController.clear();
    });
  }

  Future<void> _scanWifiNetworks() async {
    if (_espHostController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o IP do ESP32 antes de buscar redes.'),
        ),
      );
      return;
    }
    setState(() => _isScanning = true);
    await _saveCurrentEspHost();
    try {
      final networks = await _service.scanWifiNetworks(
        espHost: _espHostController.text,
      );
      if (!mounted) return;
      setState(() => _isScanning = false);
      if (networks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma rede Wi-Fi encontrada.')),
        );
        return;
      }
      _showNetworkSheet(networks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_message(e))),
      );
    }
  }

  void _showNetworkSheet(List<WifiScanResult> networks) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          builder: (context, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_find),
                    const SizedBox(width: 8),
                    Text(
                      'Redes disponíveis',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: networks.length,
                  itemBuilder: (context, i) {
                    final n = networks[i];
                    return ListTile(
                      leading: Icon(_rssiIcon(n.rssi)),
                      title: Text(n.ssid),
                      subtitle: Text(
                        '${_rssiLabel(n.rssi)} (${n.rssi} dBm)'
                        '${n.open ? ' · Aberta' : ''}',
                      ),
                      trailing: n.open
                          ? null
                          : const Icon(Icons.lock_outline, size: 18),
                      onTap: () {
                        _wifiSsidController.text = n.ssid;
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _rssiIcon(int rssi) {
    if (rssi >= -50) return Icons.signal_wifi_4_bar;
    if (rssi >= -65) return Icons.wifi;
    if (rssi >= -80) return Icons.wifi_2_bar;
    return Icons.wifi_1_bar;
  }

  String _rssiLabel(int rssi) {
    if (rssi >= -50) return 'Ótimo';
    if (rssi >= -65) return 'Bom';
    if (rssi >= -80) return 'Fraco';
    return 'Muito fraco';
  }

  String? _validateEspClientId(String? value) {
    final error = SettingsValidators.validateClientId(value);
    if (error != null) {
      return error;
    }

    if (value?.trim() == _appMqttClientId) {
      return 'Use um Client ID diferente do app para o ESP32.';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    await _saveCurrentEspHost();

    final result = await _service.provision(
      espHost: _espHostController.text,
      wifiSsid: _wifiSsidController.text,
      wifiUsername: _wifiUsernameController.text,
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

  String _message(Object error) {
    const exceptionPrefix = 'Exception: ';
    final text = error.toString();
    if (text.startsWith(exceptionPrefix)) {
      return text.substring(exceptionPrefix.length);
    }
    return text;
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
                'Conecte o celular ao AP do ESP32 ou informe o IP do ESP na rede local.',
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _isLoadingNetworks ? null : _loadSavedNetworks,
                  icon: _isLoadingNetworks
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _isLoadingNetworks
                        ? 'Carregando...'
                        : 'Carregar redes salvas',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SavedNetworksPanel(
                networks: _savedNetworks,
                editingSsid: _editingNetworkSsid,
                deletingSsid: _deletingNetworkSsid,
                onEdit: _editWifiNetwork,
                onDelete: _deleteWifiNetwork,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _wifiSsidController,
                      decoration: InputDecoration(
                        labelText: _editingNetworkSsid == null
                            ? 'SSID Wi-Fi'
                            : 'SSID Wi-Fi em edição',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Informe o SSID da rede Wi-Fi.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _isScanning ? null : _scanWifiNetworks,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: _isScanning
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _wifiUsernameController,
                decoration: const InputDecoration(
                  labelText: 'Usuário Wi-Fi (opcional)',
                  helperText: 'Preencha apenas para redes que exigem usuário.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _wifiPasswordController,
                obscureText: !_wifiPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Senha Wi-Fi',
                  helperText:
                      'Ao editar, deixe em branco para manter a senha salva.',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _wifiPasswordVisible
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () => setState(
                      () => _wifiPasswordVisible = !_wifiPasswordVisible,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSavingNetwork ? null : _saveWifiNetwork,
                      icon: _isSavingNetwork
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _isSavingNetwork
                            ? 'Salvando...'
                            : _editingNetworkSsid == null
                            ? 'Salvar rede'
                            : 'Atualizar rede',
                      ),
                    ),
                  ),
                  if (_editingNetworkSsid != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _cancelWifiNetworkEdit,
                      child: const Text('Cancelar'),
                    ),
                  ],
                ],
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
                  labelText: 'Usuário MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttPasswordController,
                obscureText: !_mqttPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Senha MQTT',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _mqttPasswordVisible
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () => setState(
                      () => _mqttPasswordVisible = !_mqttPasswordVisible,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttTopicController,
                validator: (value) => SettingsValidators.validateTopic(
                  value,
                  fieldLabel: 'o tópico MQTT',
                ),
                decoration: const InputDecoration(
                  labelText: 'Tópico MQTT',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttRequestTopicController,
                validator: (value) => SettingsValidators.validateTopic(
                  value,
                  fieldLabel: 'o tópico de solicitação',
                ),
                decoration: const InputDecoration(
                  labelText: 'Tópico de solicitação de histórico',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mqttClientIdController,
                validator: _validateEspClientId,
                decoration: const InputDecoration(
                  labelText: 'Client ID do ESP32',
                  helperText: 'Deve ser diferente do Client ID usado pelo app.',
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
                label: Text(
                  _isSubmitting ? 'Enviando...' : 'Enviar para ESP32',
                ),
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
    _wifiUsernameController.dispose();
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

class _SavedNetworksPanel extends StatelessWidget {
  final List<EspWifiNetwork> networks;
  final String? editingSsid;
  final String? deletingSsid;
  final ValueChanged<EspWifiNetwork> onEdit;
  final ValueChanged<EspWifiNetwork> onDelete;

  const _SavedNetworksPanel({
    required this.networks,
    required this.editingSsid,
    required this.deletingSsid,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Redes salvas no ESP32',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (networks.isEmpty)
            Text('Nenhuma rede carregada.', style: theme.textTheme.bodySmall)
          else
            ...networks.map((network) {
              final deleting = deletingSsid == network.ssid;
              final editing = editingSsid == network.ssid;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  network.active
                      ? Icons.check_circle_outline
                      : Icons.wifi_outlined,
                  color: network.active ? theme.colorScheme.primary : null,
                ),
                title: Text(network.ssid, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  editing
                      ? 'Editando'
                      : network.active
                      ? 'Rede em uso'
                      : 'Salva no ESP32',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Editar rede',
                      onPressed: deleting ? null : () => onEdit(network),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Excluir rede',
                      onPressed: deleting ? null : () => onDelete(network),
                      icon: deleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
