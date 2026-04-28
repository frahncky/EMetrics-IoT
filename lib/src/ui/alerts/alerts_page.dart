import 'package:flutter/material.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas')),
      body: Center(
        child: Text('Aqui serão exibidos os alertas de tensão, consumo e status.'),
      ),
    );
  }
}
