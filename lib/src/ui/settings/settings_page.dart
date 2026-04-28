import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Broker MQTT'),
            subtitle: const Text('IP ou domínio do broker'),
            trailing: Icon(Icons.edit),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Tópico MQTT'),
            subtitle: const Text('Tópico para receber dados'),
            trailing: Icon(Icons.edit),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Intervalo de atualização'),
            subtitle: const Text('Em segundos'),
            trailing: Icon(Icons.edit),
            onTap: () {},
          ),
          SwitchListTile(
            title: const Text('Modo escuro'),
            value: true,
            onChanged: (v) {},
          ),
        ],
      ),
    );
  }
}
