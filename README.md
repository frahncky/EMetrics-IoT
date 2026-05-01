# E-Metrics IoT 📊⚡

Uma aplicação Flutter moderna para visualização em tempo real e histórico de métricas elétricas via MQTT. Ideal para monitoramento de painéis solares, medidores inteligentes e sistemas IoT de energia.

## 🌟 Características

- ✅ **Dashboard em Tempo Real** - Visualização instantânea de tensão, corrente, potência e energia
- ✅ **Histórico de Dados** - Gráficos interativos com filtros por período (hora, dia, semana, mês)
- ✅ **Tema Claro/Escuro** - Interface adaptativa com paleta de cores moderna
- ✅ **Persistência Local** - Dados salvos em SQLite para acesso offline
- ✅ **MQTT Integration** - Conexão configurável com brokers MQTT
- ✅ **Exportação** - Exportar dados em CSV e PDF
- ✅ **Notificações** - Alertas locais para eventos críticos
- ✅ **Multi-plataforma** - Android, iOS, Windows, Linux, macOS e Web

## 📋 Requisitos

- Flutter 3.11.5 ou superior
- Dart 3.11.5 ou superior
- Android SDK (para builds Android)
- Xcode 14+ (para builds iOS)

## 🚀 Setup e Instalação

### 1. Clonar repositório
```bash
git clone https://github.com/frahncky/EMetrics-IoT.git
cd e_metrics_iot
```

### 2. Instalar dependências
```bash
flutter pub get
```

### 3. Executar aplicação
```bash
# Debug
flutter run

# Release
flutter run --release

# Específico para plataforma
flutter run -d android
flutter run -d ios
flutter run -d windows
```

## 🏗️ Arquitetura

### Estrutura de Pastas
```
lib/
├── main.dart                 # Ponto de entrada
├── src/
│   ├── app.dart            # Configuração do app + temas
│   ├── data/               # Camada de dados
│   │   ├── metric_model.dart
│   │   ├── metric_repository.dart
│   │   └── local_database.dart
│   ├── providers/          # State management com Riverpod
│   │   ├── metric_provider.dart
│   │   ├── mqtt_provider.dart
│   │   ├── alert_provider.dart
│   │   └── theme_provider.dart
│   ├── services/           # Serviços e integrações
│   │   ├── mqtt_service.dart
│   │   └── alert_service.dart
│   └── ui/                 # Camada de apresentação
│       ├── dashboard/
│       ├── history/
│       └── settings/
```

### Padrões de Design

- **State Management**: Riverpod (FutureProvider, StateNotifierProvider)
- **Repository Pattern**: Abstração de acesso a dados
- **Service Layer**: Lógica de negócio desacoplada
- **Clean Architecture**: Separação clara de responsabilidades

## 🔧 Configuração MQTT

Na aba **Configurações**, configure:

```
Broker MQTT:    seu-broker.com:1883 (ou IP)
Client ID:      emetrics_app
Tópico:         sensor/metrics
Tópico Request: sensor/request
```

### Formato de Payload Esperado
```json
{
  "voltage": 220.5,
  "current": 5.2,
  "power": 1146,
  "energy": 45.6,
  "pf": 0.98,
  "frequency": 60.0
}
```

## 📊 Temas

### Tema Claro
- Cores suaves e azuis cinzentos
- Ideal para ambientes bem iluminados
- Reduz cansaço visual em uso prolongado

### Tema Escuro
- Cores vibrantes em fundo escuro
- Menor consumo de bateria (em telas OLED)
- Confortável em ambientes com pouca luz

## 🧪 Testes

```bash
# Rodar testes unitários
flutter test

# Com cobertura
flutter test --coverage

# Ver cobertura
lcov --list coverage/lcov.info
```

## 📦 Build para Produção

### Android
```bash
flutter build apk --release
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

### Windows
```bash
flutter build windows --release
```

## 🐛 Troubleshooting

### Conexão MQTT falha
- Verifique se o broker está ativo
- Confirme IP/porta corretos
- Teste com MQTT client (ex: MQTT Explorer)

### Dados não aparecem
- Verifique se o formato do payload está correto
- Confirme se o tópico está correto
- Veja logs no console do Flutter

### Erros de build
```bash
# Limpar cache
flutter clean

# Redownload de dependências
flutter pub get

# Atualizar Flutter
flutter upgrade
```

## 🔒 Dependências Principais

- **flutter_riverpod**: State management
- **mqtt_client**: Integração MQTT
- **sqflite**: Base de dados local
- **fl_chart**: Gráficos interativos
- **shared_preferences**: Persistência de preferências
- **flutter_local_notifications**: Alertas
- **csv**: Exportação CSV
- **pdf**: Geração de PDFs

## 📝 Licença

Este projeto é privado. Entre em contato para mais informações.

## 🤝 Contribuindo

Para contribuir:

1. Faça um fork do projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📧 Contato e Suporte

Para bugs, sugestões ou dúvidas:
- Abra uma issue no GitHub
- Consulte a documentação da API
- Verifique o arquivo AGENTS.md para padrões de desenvolvimento

## 🚀 Roadmap

- [ ] Modo offline melhorado com sincronização automática
- [ ] Previsões com machine learning
- [ ] Dashboard personalizável
- [ ] API REST para integração com terceiros
- [ ] Autenticação com OAuth
- [ ] Suporte a múltiplos brokers/dispositivos

---

**Desenvolvido com ❤️ para IoT**
