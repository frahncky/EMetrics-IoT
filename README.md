# E-Metrics IoT

Plataforma para monitoramento de energia com duas frentes:

- App Flutter para operação local, histórico e alertas.
- Dashboard web para telemetria MQTT em tempo real.

## Status

- Repositório: https://github.com/frahncky/EMetrics-IoT
- Dashboard publicado (Cloudflare Pages): https://emetricsiot.pages.dev

## Principais recursos

- Leitura em tempo real de tensão, corrente, frequência, energia e potências.
- Visualização gráfica de tendência (potências, corrente e fator de potência).
- Configuração de conexão MQTT (broker WebSocket, tópico, credenciais).
- Persistência local no app Flutter via SQLite.
- Exportação de histórico no app (CSV/PDF) e alertas locais.

## Stack

- Flutter + Dart
- Riverpod
- MQTT client
- SQLite (sqflite)
- Vite + React (dashboard web)
- Cloudflare Pages (hosting web)

## Estrutura do repositório

```text
lib/                         # app Flutter
  main.dart
  src/
    app.dart
    data/
    providers/
    services/
    ui/

dashboard_e_metrics_iot/     # dashboard web (Vite/React)
  src/
  package.json
  wrangler.toml

backend_example/             # exemplo opcional de backend Node
firmware/                    # firmware ESP32 (exemplos)
docs/                        # documentação de apoio
```

## Como executar (app Flutter)

```bash
flutter pub get
flutter run
```

## Como executar (dashboard web)

```bash
cd dashboard_e_metrics_iot
npm install
npm run dev
```

## Build e qualidade

App Flutter:

```bash
flutter analyze
flutter test
flutter build apk
```

Dashboard web:

```bash
cd dashboard_e_metrics_iot
npm run build
```

## Deploy do dashboard no Cloudflare

Deploy manual por CLI:

```bash
cd dashboard_e_metrics_iot
npm run build:cloudflare
npm run deploy:cloudflare
```

Deploy automático via GitHub/Cloudflare Pages:

- Project: emetricsiot
- Production branch: main
- Root directory: dashboard_e_metrics_iot
- Build command: npm run build
- Build output directory: dist

## Payload MQTT esperado

```json
{
  "voltage": 220.5,
  "current": 5.234,
  "frequency": 60.02,
  "power": 1146.25,
  "apparentPower": 1210.40,
  "reactivePower": 386.77,
  "energy": 45.601,
  "pf": 0.98
}
```

## Licença

Projeto privado.
