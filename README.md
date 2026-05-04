# E-Metrics IoT 📊⚡

Aplicativo Flutter para monitoramento elétrico com MQTT, histórico local e visualização em gráficos.

Projeto pensado para cenários de IoT de energia, com foco em uso prático: conectar, acompanhar leituras e analisar comportamento ao longo do tempo.

## 🎯 Visão Geral

- Dashboard em tempo real com tensão, corrente, potência, energia e fator de potência
- Histórico com filtros por período e gráficos legíveis
- Perfis MQTT por dispositivo
- Indicadores de status no AppBar
- Persistência local com SQLite
- Exportação em CSV e PDF
- Alertas locais
- Integração REST opcional com fila offline

## 🧰 Stack Tecnológica

- Flutter + Dart
- Riverpod para estado e orquestração
- mqtt_client para comunicação MQTT
- sqflite para armazenamento local
- fl_chart para gráficos

## 🏗️ Estrutura do Projeto

```text
lib/
  main.dart
  src/
    app.dart
    data/
    providers/
    services/
    ui/
      dashboard/
      history/
      settings/
      alerts/
```

## 🚀 Como Rodar

1. Clonar repositório

```bash
git clone https://github.com/frahncky/EMetrics-IoT.git
cd e_metrics_iot
```

2. Instalar dependências

```bash
flutter pub get
```

3. Executar

```bash
flutter run
```

## ✅ Qualidade e Validação

```bash
flutter analyze
flutter test
```

## 🔌 Configuração MQTT

No menu de configurações, informe:

- Broker
- Porta
- Client ID
- Tópico de leitura
- Tópico de requisição de histórico
- Usuário/senha (quando exigido)
- TLS (quando exigido)

Exemplo de payload esperado:

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

## 🌟 Principais Recursos

### 📈 Dashboard

- Indicadores principais em destaque
- Card de previsão local (quando habilitado)
- Gráficos com melhor contraste em tema claro e escuro

### 🕓 Histórico

- Consulta por faixa temporal
- Comparação visual de métricas
- Exportação para auditoria e análise externa

### 📡 Conectividade

- Conexão MQTT manual e controlada
- Status de conexão do app separado do status do medidor
- Suporte a monitoramento em segundo plano

## 📦 Build

```bash
flutter build apk
flutter build ios
flutter build windows
```

## 🛠️ Troubleshooting Rápido

### ❌ Não conecta no MQTT

- Confirmar broker/porta
- Verificar se TLS está consistente com a porta
- Validar usuário e senha (ambos preenchidos ou ambos vazios)

### ⚠️ Conecta mas não recebe leitura

- Confirmar tópico correto
- Confirmar formato do payload
- Verificar se o dispositivo está publicando no broker certo

## 🗺️ Roadmap

- [x] Perfis MQTT por dispositivo
- [x] Dashboard com previsão local
- [x] Integração REST com fila offline
- [x] OAuth Device Flow
- [ ] Capturas de tela oficiais no README
- [ ] Guia de deploy para ambiente produtivo

## 🤝 Contribuição

Contribuições são bem-vindas via pull request.

1. Criar branch de feature
2. Implementar alterações
3. Rodar analyze e testes
4. Abrir PR com contexto objetivo

## 🔒 Licença

Projeto privado.
