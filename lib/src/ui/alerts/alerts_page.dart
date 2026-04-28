import 'package:flutter/material.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas')),
      body: Center(
        child: Card(
          color: Colors.red.shade50,
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade400, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Aqui serão exibidos os alertas de tensão, consumo e status.',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Você receberá notificações em tempo real caso algum parâmetro esteja fora do esperado.',
                  style: TextStyle(fontSize: 15, color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
