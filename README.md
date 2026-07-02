# E-Metrics IoT 📊⚡

Plataforma de monitoramento elétrico com foco em IoT, composta por:

- App Flutter para operação local, histórico, alertas e exportação.
- Dashboard web em tempo real para telemetria MQTT.

## 🚀 Links rápidos

- Repositório: https://github.com/frahncky/EMetrics-IoT
- Dashboard em produção: https://emetricsiot.pages.dev

## 🎯 Visão geral

- Monitoramento em tempo real de tensão, corrente, frequência, energia e potências.
- Dashboard com tendências ao vivo e status de conexão/dispositivo.
- Persistência local com SQLite no app Flutter.
- Exportação de histórico para CSV/PDF e alertas locais.
- Deploy web no Cloudflare Pages com integração GitHub.

## 🧰 Stack tecnológica

- Flutter + Dart
- Riverpod
- MQTT client
- SQLite (sqflite)
- Vite + React (dashboard web)
- Cloudflare Pages

## 🏗️ Estrutura do projeto

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

## 📱 Como rodar o app Flutter

```bash
flutter pub get
flutter run
```

## 🌐 Como rodar o dashboard web

```bash
cd dashboard_e_metrics_iot
npm install
npm run dev
```

## ✅ Qualidade e build

Flutter:

```bash
flutter analyze
flutter test
flutter build apk
```

Dashboard:

```bash
cd dashboard_e_metrics_iot
npm run build
```

## ☁️ Deploy no Cloudflare Pages

Manual (CLI):

```bash
cd dashboard_e_metrics_iot
npm run build:cloudflare
npm run deploy:cloudflare
```

Automático (GitHub + Pages):

- Project: emetricsiot
- Production branch: main
- Root directory: dashboard_e_metrics_iot
- Build command: npm run build
- Build output directory: dist

## 🔌 Payload MQTT esperado

```json
{
  "voltage": 220.5,
  "current": 5.234,
  "frequency": 60.02,
  "power": 1146.25,
  "apparentPower": 1210.4,
  "reactivePower": -386.77,
  "energy": 45.601,
  "pf": 0.98,
  "loadType": "capacitiva"
}
```

Para o diagrama fasorial, envie `reactivePower`/`q` com sinal quando disponível: positivo para carga indutiva e negativo para carga capacitiva. Também é aceito `currentAngleDeg` assinado ou `loadType` (`indutiva`/`capacitiva`).

## 🔒 Licença

Projeto privado.
