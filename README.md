# E-Metrics IoT

Aplicativo Flutter para monitoramento eletrico com MQTT, historico local e visualizacao em graficos.

Projeto pensado para cenarios de IoT de energia, com foco em uso pratico: conectar, acompanhar leituras e analisar comportamento ao longo do tempo.

## Visao Geral

- Dashboard em tempo real com tensao, corrente, potencia, energia e fator de potencia
- Historico com filtros por periodo e graficos legiveis
- Perfis MQTT por dispositivo
- Indicadores de status no AppBar
- Persistencia local com SQLite
- Exportacao em CSV e PDF
- Alertas locais
- Integracao REST opcional com fila offline

## Stack Tecnologica

- Flutter + Dart
- Riverpod para estado e orquestracao
- mqtt_client para comunicacao MQTT
- sqflite para armazenamento local
- fl_chart para graficos

## Estrutura do Projeto

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

## Como Rodar

1. Clonar repositorio

```bash
git clone https://github.com/frahncky/EMetrics-IoT.git
cd e_metrics_iot
```

2. Instalar dependencias

```bash
flutter pub get
```

3. Executar

```bash
flutter run
```

## Qualidade e Validacao

```bash
flutter analyze
flutter test
```

## Configuracao MQTT

No menu de configuracoes, informe:

- Broker
- Porta
- Client ID
- Topico de leitura
- Topico de requisicao de historico
- Usuario/senha (quando exigido)
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

## Principais Recursos

### Dashboard

- Indicadores principais em destaque
- Card de previsao local (quando habilitado)
- Graficos com melhor contraste em tema claro e escuro

### Historico

- Consulta por faixa temporal
- Comparacao visual de metricas
- Exportacao para auditoria e analise externa

### Conectividade

- Conexao MQTT manual e controlada
- Status de conexao do app separado do status do medidor
- Suporte a monitoramento em segundo plano

## Build

```bash
flutter build apk
flutter build ios
flutter build windows
```

## Troubleshooting Rapido

### Nao conecta no MQTT

- Confirmar broker/porta
- Verificar se TLS esta consistente com a porta
- Validar usuario e senha (ambos preenchidos ou ambos vazios)

### Conecta mas nao recebe leitura

- Confirmar topico correto
- Confirmar formato do payload
- Verificar se o dispositivo esta publicando no broker certo

## Roadmap

- [x] Perfis MQTT por dispositivo
- [x] Dashboard com previsao local
- [x] Integracao REST com fila offline
- [x] OAuth Device Flow
- [ ] Capturas de tela oficiais no README
- [ ] Guia de deploy para ambiente produtivo

## Contribuicao

Contribuicoes sao bem-vindas via pull request.

1. Criar branch de feature
2. Implementar alteracoes
3. Rodar analyze e testes
4. Abrir PR com contexto objetivo

## Licenca

Projeto privado.
