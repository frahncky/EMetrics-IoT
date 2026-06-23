import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

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
  final _wifiInitialConnectTimeoutController = TextEditingController(
    text: '${EspWifiConnectionSettings.defaultInitialConnectTimeoutSeconds}',
  );
  final _wifiRetryIntervalController = TextEditingController(
    text: '${EspWifiConnectionSettings.defaultRetryIntervalSeconds}',
  );
  final _wifiFallbackApDelayController = TextEditingController(
    text: '${EspWifiConnectionSettings.defaultFallbackApDelaySeconds}',
  );
  final _otaPasswordController = TextEditingController();
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
  bool _isLoadingWifiConnectionSettings = false;
  bool _isSavingWifiConnectionSettings = false;
  bool _isUploadingFirmware = false;
  bool _isTestingWifi = false;
  bool _isScanning = false;
  bool _wifiPasswordVisible = false;
  bool _otaPasswordVisible = false;
  bool _mqttPasswordVisible = false;
  String? _editingNetworkSsid;
  String? _deletingNetworkSsid;
  String? _movingNetworkSsid;
  String _appMqttClientId = '';
  List<EspWifiNetwork> _savedNetworks = const [];
  PlatformFile? _selectedFirmware;
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

  EspWifiConnectionSettings? _wifiConnectionSettingsFromFields() {
    final initial = int.tryParse(_wifiInitialConnectTimeoutController.text);
    final retry = int.tryParse(_wifiRetryIntervalController.text);
    final fallback = int.tryParse(_wifiFallbackApDelayController.text);
    final values = [initial, retry, fallback];
    final hasInvalidValue = values.any(
      (value) =>
          value == null ||
          value < EspWifiConnectionSettings.minDelaySeconds ||
          value > EspWifiConnectionSettings.maxDelaySeconds,
    );
    if (hasInvalidValue) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Informe os tempos entre ${EspWifiConnectionSettings.minDelaySeconds} e ${EspWifiConnectionSettings.maxDelaySeconds} segundos.',
          ),
        ),
      );
      return null;
    }

    return EspWifiConnectionSettings(
      initialConnectTimeoutSeconds: initial!,
      retryIntervalSeconds: retry!,
      fallbackApDelaySeconds: fallback!,
    );
  }

  Future<void> _loadWifiConnectionSettings() async {
    if (_espHostController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o IP do ESP32 antes de carregar os tempos.'),
        ),
      );
      return;
    }

    setState(() => _isLoadingWifiConnectionSettings = true);
    await _saveCurrentEspHost();
    try {
      final settings = await _service.loadWifiConnectionSettings(
        espHost: _espHostController.text,
      );
      if (!mounted) return;
      setState(() {
        _wifiInitialConnectTimeoutController.text = settings
            .initialConnectTimeoutSeconds
            .toString();
        _wifiRetryIntervalController.text = settings.retryIntervalSeconds
            .toString();
        _wifiFallbackApDelayController.text = settings.fallbackApDelaySeconds
            .toString();
        _isLoadingWifiConnectionSettings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingWifiConnectionSettings = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível carregar os tempos: ${_message(e)}'),
        ),
      );
    }
  }

  Future<void> _saveWifiConnectionSettings() async {
    final settings = _wifiConnectionSettingsFromFields();
    if (settings == null || _espHostController.text.trim().isEmpty) {
      if (_espHostController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe o IP do ESP32 antes de salvar os tempos.'),
          ),
        );
      }
      return;
    }

    setState(() => _isSavingWifiConnectionSettings = true);
    await _saveCurrentEspHost();
    final result = await _service.saveWifiConnectionSettings(
      espHost: _espHostController.text,
      initialConnectTimeoutSeconds: settings.initialConnectTimeoutSeconds,
      retryIntervalSeconds: settings.retryIntervalSeconds,
      fallbackApDelaySeconds: settings.fallbackApDelaySeconds,
    );
    if (!mounted) return;
    setState(() => _isSavingWifiConnectionSettings = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? null : Colors.redAccent,
      ),
    );
  }

  String? _validateOtaPassword(String? value) {
    final password = value?.trim() ?? '';
    if (password.length < 8 || password.length > 64) {
      return 'Defina uma chave OTA entre 8 e 64 caracteres.';
    }
    return null;
  }


  Future<void> _testWifiConnection() async {
    setState(() => _isTestingWifi = true);
    await _saveCurrentEspHost();
    final host = _espHostController.text;
    final reconnect = await _service.triggerWifiReconnect(espHost: host);
    if (!mounted) return;
    setState(() => _isTestingWifi = false);
    if (!reconnect.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reconnect.message), backgroundColor: Colors.redAccent),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WifiTestDialog(service: _service, espHost: host),
    );
  }

  Future<void> _selectFirmware() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['bin'],
      allowMultiple: false,
      withData: true,
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    if (file == null || !mounted) {
      return;
    }
    if (file.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível ler o arquivo .bin selecionado.'),
        ),
      );
      return;
    }
    setState(() => _selectedFirmware = file);
  }

  Future<void> _uploadFirmware() async {
    final file = _selectedFirmware;
    final otaPasswordError = _validateOtaPassword(_otaPasswordController.text);
    if (_espHostController.text.trim().isEmpty ||
        otaPasswordError != null ||
        file == null ||
        file.bytes == null) {
      final message = _espHostController.text.trim().isEmpty
          ? 'Informe o IP do ESP32 antes de enviar o firmware.'
          : otaPasswordError ??
                (file == null
                    ? 'Selecione o arquivo .bin do firmware.'
                    : 'Não foi possível ler o arquivo .bin selecionado.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    setState(() => _isUploadingFirmware = true);
    await _saveCurrentEspHost();
    final result = await _service.uploadFirmware(
      espHost: _espHostController.text,
      otaPassword: _otaPasswordController.text,
      firmwareBytes: file.bytes!,
      fileName: file.name,
    );
    if (!mounted) return;
    setState(() {
      _isUploadingFirmware = false;
      if (result.ok) {
        _selectedFirmware = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? null : Colors.redAccent,
      ),
    );
  }

  Future<void> _moveWifiNetwork(
    EspWifiNetwork network, {
    required bool moveUp,
  }) async {
    setState(() => _movingNetworkSsid = network.ssid);
    await _saveCurrentEspHost();
    final result = await _service.moveWifiNetwork(
      espHost: _espHostController.text,
      ssid: network.ssid,
      moveUp: moveUp,
    );
    if (!mounted) return;
    setState(() => _movingNetworkSsid = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? null : Colors.redAccent,
      ),
    );
    if (result.ok) {
      await _loadSavedNetworks(silent: true);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(e))));
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
                        '${_rssiLabel(n.rssi)} · ${n.rssi} dBm · ${n.authLabel}',
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
    final wifiConnectionSettings = _wifiConnectionSettingsFromFields();
    if (wifiConnectionSettings == null) {
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
      initialConnectTimeoutSeconds:
          wifiConnectionSettings.initialConnectTimeoutSeconds,
      retryIntervalSeconds: wifiConnectionSettings.retryIntervalSeconds,
      fallbackApDelaySeconds: wifiConnectionSettings.fallbackApDelaySeconds,
      otaPassword: _otaPasswordController.text,
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
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoadingNetworks ? null : _loadSavedNetworks,
                    icon: _isLoadingNetworks
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      _isLoadingNetworks ? 'Carregando...' : 'Carregar redes',
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isTestingWifi ? null : _testWifiConnection,
                    icon: _isTestingWifi
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: Text(
                      _isTestingWifi ? 'Aguarde...' : 'Testar conexão',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SavedNetworksPanel(
                networks: _savedNetworks,
                editingSsid: _editingNetworkSsid,
                deletingSsid: _deletingNetworkSsid,
                movingSsid: _movingNetworkSsid,
                onEdit: _editWifiNetwork,
                onDelete: _deleteWifiNetwork,
                onMove: _moveWifiNetwork,
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tentativas de conexão Wi-Fi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Informe valores entre ${EspWifiConnectionSettings.minDelaySeconds} e ${EspWifiConnectionSettings.maxDelaySeconds} segundos.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _wifiInitialConnectTimeoutController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tentativa inicial (segundos)',
                        helperText: 'Tempo aguardado quando o ESP é ligado.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _wifiRetryIntervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Intervalo entre tentativas (segundos)',
                        helperText: 'Pausa antes de tentar a próxima rede.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _wifiFallbackApDelayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText:
                            'Tempo para abrir AP de recuperação (segundos)',
                        helperText:
                            'Após esse período, o AP EMetrics-Setup é ativado.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _isLoadingWifiConnectionSettings ||
                                  _isSavingWifiConnectionSettings
                              ? null
                              : _loadWifiConnectionSettings,
                          icon: _isLoadingWifiConnectionSettings
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_outlined),
                          label: const Text('Carregar tempos do ESP'),
                        ),
                        FilledButton.icon(
                          onPressed:
                              _isLoadingWifiConnectionSettings ||
                                  _isSavingWifiConnectionSettings
                              ? null
                              : _saveWifiConnectionSettings,
                          icon: _isSavingWifiConnectionSettings
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Salvar tempos e reiniciar ESP'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Atualização de firmware por Wi-Fi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Defina a chave durante o provisionamento. Depois, selecione o .bin e envie-o ao ESP32 pela rede local.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _otaPasswordController,
                      obscureText: !_otaPasswordVisible,
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return null;
                        }
                        return _validateOtaPassword(value);
                      },
                      decoration: InputDecoration(
                        labelText: 'Chave OTA',
                        helperText:
                            'Opcional no provisionamento. Para OTA, use 8 a 64 caracteres.',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _otaPasswordVisible
                              ? 'Ocultar chave OTA'
                              : 'Mostrar chave OTA',
                          icon: Icon(
                            _otaPasswordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _otaPasswordVisible = !_otaPasswordVisible,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFirmware == null
                          ? 'Nenhum firmware selecionado.'
                          : '${_selectedFirmware!.name} (${(_selectedFirmware!.size / 1024).toStringAsFixed(1)} KB)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isUploadingFirmware
                              ? null
                              : _selectFirmware,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Selecionar .bin'),
                        ),
                        FilledButton.icon(
                          onPressed: _isUploadingFirmware
                              ? null
                              : _uploadFirmware,
                          icon: _isUploadingFirmware
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.system_update_alt),
                          label: Text(
                            _isUploadingFirmware
                                ? 'Enviando firmware...'
                                : 'Atualizar ESP32',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
    _wifiInitialConnectTimeoutController.dispose();
    _wifiRetryIntervalController.dispose();
    _wifiFallbackApDelayController.dispose();
    _otaPasswordController.dispose();
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
  final String? movingSsid;
  final ValueChanged<EspWifiNetwork> onEdit;
  final ValueChanged<EspWifiNetwork> onDelete;
  final Future<void> Function(EspWifiNetwork network, {required bool moveUp})
  onMove;

  const _SavedNetworksPanel({
    required this.networks,
    required this.editingSsid,
    required this.deletingSsid,
    required this.movingSsid,
    required this.onEdit,
    required this.onDelete,
    required this.onMove,
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
            ...networks.asMap().entries.map((entry) {
              final index = entry.key;
              final network = entry.value;
              final deleting = deletingSsid == network.ssid;
              final editing = editingSsid == network.ssid;
              final moving = movingSsid == network.ssid;
              final isReordering = movingSsid != null;
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
                      ? 'Rede em uso · Prioridade ${index + 1}'
                      : 'Salva no ESP32 · Prioridade ${index + 1}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Aumentar prioridade',
                      onPressed: index == 0 || deleting || isReordering
                          ? null
                          : () => onMove(network, moveUp: true),
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: 'Diminuir prioridade',
                      onPressed:
                          index == networks.length - 1 ||
                              deleting ||
                              isReordering
                          ? null
                          : () => onMove(network, moveUp: false),
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    IconButton(
                      tooltip: 'Editar rede',
                      onPressed: deleting || isReordering
                          ? null
                          : () => onEdit(network),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Excluir rede',
                      onPressed: deleting || isReordering
                          ? null
                          : () => onDelete(network),
                      icon: deleting || moving
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

// ── Diálogo de teste de conexão Wi-Fi ────────────────────────────────────────

class _WifiTestDialog extends StatefulWidget {
  final EspProvisioningService service;
  final String espHost;

  const _WifiTestDialog({required this.service, required this.espHost});

  @override
  State<_WifiTestDialog> createState() => _WifiTestDialogState();
}

class _WifiTestDialogState extends State<_WifiTestDialog> {
  static const _totalSeconds = 20;
  int _remaining = _totalSeconds;
  WifiConnectionStatus? _status;
  bool _unreachable = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    for (var i = _totalSeconds; i >= 1; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _remaining = i - 1);
    }
    await _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final status = await widget.service.getWifiStatus(espHost: widget.espHost);
      if (!mounted) return;
      setState(() {
        _status = status;
        _done = true;
      });
    } catch (_) {
      if (!mounted) return;
      // ESP saiu do AP — conectou à rede alvo com sucesso
      setState(() {
        _unreachable = true;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Teste de conexão Wi-Fi'),
      content: _done ? _buildResult() : _buildWaiting(),
      actions: [
        if (_done)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
      ],
    );
  }

  Widget _buildWaiting() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('Aguardando resultado... $_remaining s'),
        const SizedBox(height: 8),
        const Text(
          'O ESP32 está tentando conectar à rede configurada.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildResult() {
    if (_unreachable) {
      return _ResultContent(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: 'Conexão bem-sucedida',
        lines: const ['O ESP32 conectou à rede e saiu do AP.', 'Reconecte o celular à rede Wi-Fi normal.'],
      );
    }

    final s = _status!;
    if (s.connected) {
      return _ResultContent(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: 'Conectado',
        lines: [
          'Rede: ${s.ssid}',
          if (s.ip != null) 'IP: ${s.ip}',
          if (s.rssi != null) 'Sinal: ${s.rssi} dBm',
          if (s.enterprise) 'Modo: WPA2-Enterprise',
        ],
      );
    }

    String hint = '';
    if (s.statusCode == 1) {
      hint = 'Rede não encontrada. Verifique o nome exato e se é 2.4 GHz.';
    } else if (s.statusCode == 4) {
      hint = s.enterprise
          ? 'Falha de autenticação. Verifique usuário e senha (WPA2-Enterprise).'
          : 'Senha incorreta.';
    } else {
      hint = 'Sem conexão. Verifique as credenciais e a rede.';
    }

    return _ResultContent(
      icon: Icons.error_outline,
      iconColor: Colors.redAccent,
      title: s.description,
      lines: [
        'Rede: ${s.ssid}',
        'Modo: ${s.enterprise ? "WPA2-Enterprise" : "WPA2-Personal"}',
        hint,
      ],
    );
  }
}

class _ResultContent extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> lines;

  const _ResultContent({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 48),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        for (final line in lines) ...[
          Text(line, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
