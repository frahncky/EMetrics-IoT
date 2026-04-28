import 'package:flutter/material.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Consumo')),
      body: Center(
        child: Text('Aqui serão exibidos os dados históricos e relatórios.'),
      ),
    );
  }
}
