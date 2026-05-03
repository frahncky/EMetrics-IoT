# Manual do Usuário — E-Metrics IoT

**Versão:** 1.3.0  
**Plataformas:** Android, iOS, Windows  

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Primeiros Passos](#2-primeiros-passos)
3. [Dashboard](#3-dashboard)
4. [Histórico](#4-histórico)
5. [Configurações MQTT](#5-configurações-mqtt)
6. [Perfis de Dispositivo](#6-perfis-de-dispositivo)
7. [Alertas e Medição](#7-alertas-e-medição)
8. [Integração REST](#8-integração-rest)
9. [Aparência e Conta](#9-aparência-e-conta)
10. [Provisionar ESP32](#10-provisionar-esp32)
11. [Solução de Problemas](#11-solução-de-problemas)

---

## 1. Visão Geral

O **E-Metrics IoT** monitora métricas elétricas em tempo real de dispositivos IoT (ex.: módulo PZEM-004T + ESP32) via protocolo MQTT. Os dados são exibidos em gráficos, salvos localmente e podem ser enviados para uma API REST externa.

**Métricas monitoradas:**

| Grandeza | Unidade |
|---|---|
| Tensão | V |
| Corrente | A |
| Potência ativa | W |
| Potência reativa | VAR |
| Potência aparente | VA |
| Fator de potência | — |
| Frequência | Hz |
| Energia acumulada | kWh |

---

## 2. Primeiros Passos

### Requisitos
- Dispositivo Android 6.0+ ou iOS 13+ (ou Windows 10+)
- Broker MQTT acessível na mesma rede (ex.: Mosquitto, HiveMQ, broker público)
- Hardware IoT publicando métricas no tópico MQTT configurado

### Instalação
1. Instale o APK (Android) ou execute o build (Windows/iOS).
2. Abra o app — a tela inicial é o **Dashboard**.
3. Acesse **Configurações** (ícone na barra inferior) e configure o broker MQTT.
4. Toque em **Conectar** para iniciar o monitoramento.

---

## 3. Dashboard

![Dashboard principal](docs/screenshots/dashboard.png)

A tela principal exibe:

- **Cards de indicadores**: valores mais recentes de tensão, corrente, potência, fator de potência, frequência e energia.
- **Dois gráficos**: cada um com dropdown para selecionar a grandeza exibida. A seleção é salva automaticamente.
- **Card de previsão** *(opcional)*: mostra a tendência de potência e projeção para a próxima hora, calculada por regressão linear sobre as últimas leituras. Pode ser ativado/desativado em **Configurações → Aparência**.

### Status da conexão
Um indicador no topo do dashboard mostra o estado atual:
- **Conectado** — recebendo dados em tempo real
- **Monitorando em segundo plano** — serviço Android ativo mesmo com app fechado
- **Desconectado** — nenhum broker ativo

---

## 4. Histórico

![Tela de histórico](docs/screenshots/history.png)

Exibe o histórico de métricas salvas localmente no dispositivo.

- **Gráfico de histórico**: selecione o campo e o período desejado.
- **Solicitar histórico**: envia uma mensagem MQTT ao dispositivo pedindo leituras passadas (requer tópico de solicitação configurado).
- **Exportar CSV**: salva o histórico em arquivo `.csv` para análise externa.
- **Exportar PDF**: gera relatório em PDF com gráfico e tabela de valores.

---

## 5. Configurações MQTT

Acesse **Configurações → aba MQTT**.

![Configurações MQTT](docs/screenshots/settings_mqtt.png)

| Campo | Descrição |
|---|---|
| Broker MQTT | Endereço IP ou hostname do broker (ex.: `192.168.1.10`) |
| Porta MQTT | Padrão `1883`; TLS geralmente usa `8883` |
| Client ID | Identificador único do app no broker |
| Usuário / Senha | Credenciais do broker (opcional) |
| Tópico MQTT | Tópico onde o dispositivo publica as métricas |
| Usar TLS/SSL | Ativa conexão criptografada |

Após preencher, toque em **Conectar**. O app tenta iniciar o monitoramento em segundo plano (Android); se não for possível, conecta no modo foreground.

Para parar, toque em **Desconectar**.

---

## 6. Perfis de Dispositivo

Permite salvar configurações separadas para cada dispositivo/broker.

**Como criar um perfil:**
1. Na aba MQTT, toque em **Novo perfil**.
2. Preencha os dados do novo dispositivo.
3. O perfil é salvo automaticamente ao tocar em **Conectar**.

**Como trocar de perfil:**
- Use o dropdown **"Perfil do dispositivo"** no topo da aba MQTT para selecionar um perfil salvo.

**Como excluir:**
- Selecione o perfil e toque em **Excluir perfil** (disponível somente quando há mais de um perfil).

---

## 7. Alertas e Medição

Acesse **Configurações → aba Medição**.

Configure limites para disparo de notificações locais:

| Campo | Descrição |
|---|---|
| Tensão mínima (V) | Alerta se a tensão cair abaixo desse valor |
| Tensão máxima (V) | Alerta se a tensão ultrapassar esse valor |
| Limite de consumo (kWh) | Alerta ao atingir esse consumo acumulado |
| Tarifa (R$/kWh) | Usado para calcular o custo estimado no dashboard |

Os alertas são exibidos como notificações do sistema. O histórico de alertas disparados pode ser consultado na tela de **Histórico**.

> **Nota:** Permissão de notificações é solicitada automaticamente na primeira conexão MQTT.

---

## 8. Integração REST

Permite enviar as métricas para uma API externa com suporte a fila offline.

Acesse **Configurações → aba Integração**.

![Configurações de integração](docs/screenshots/settings_integration.png)

### Configuração básica

| Campo | Descrição |
|---|---|
| Ativar integração REST | Liga/desliga o envio automático |
| Base URL da API | URL raiz do servidor (ex.: `http://192.168.1.100:3000`) |
| Path de envio | Caminho do endpoint (padrão: `/api/metrics`) |
| API Key | Token Bearer enviado no header `Authorization` |

### Fila offline
Quando o servidor não está disponível, as métricas são salvas em fila local (SQLite). O app tenta reenviar automaticamente a cada 30 segundos. Toque em **Sincronizar agora** para forçar o envio imediato.

### OAuth Device Flow
Para integração com provedores que usam OAuth 2.0:
1. Preencha **OAuth Client ID**, **Scopes**, **Endpoint device authorization** e **Endpoint token**.
2. Ative **Usar OAuth Device Flow**.
3. Toque em **Conectar OAuth** — o app exibirá um código e URL para autenticação no navegador.
4. Após autenticar, o token é salvo e usado automaticamente nos envios.

### Backend de exemplo
O repositório inclui um servidor Node.js pronto em `backend_example/`. Consulte o [README do backend](../backend_example/README.md) para instruções de uso.

---

## 9. Aparência e Conta

Acesse **Configurações → aba Aparência**.

- **Exibir previsão no dashboard**: ativa/desativa o card de tendência e projeção.
- **Modo escuro / Modo claro**: alterna o tema visual do app.
- **Perfil local / Perfil visitante**: o app suporta login com perfil local (dados protegidos) ou modo visitante sem autenticação.

---

## 10. Provisionar ESP32

Disponível em **Configurações → aba MQTT → botão "Provisionar ESP32 (Wi-Fi + MQTT)"**.

Permite configurar as credenciais Wi-Fi e MQTT diretamente no ESP32 via rede AP temporária:

1. Coloque o ESP32 em modo de provisionamento (o firmware deve expor um AP HTTP).
2. Conecte o celular ao Wi-Fi do ESP32.
3. Abra a tela de provisionamento no app, preencha SSID, senha Wi-Fi e dados MQTT.
4. Toque em **Provisionar** — as configurações são enviadas ao ESP32 via HTTP.

---

## 11. Solução de Problemas

### App não conecta ao broker
- Verifique se o IP/hostname do broker está correto e acessível na rede.
- Confirme que a porta está aberta (padrão 1883; TLS 8883).
- Tente desativar TLS se o broker não suportar.
- Verifique usuário/senha se o broker exigir autenticação.

### Nenhum dado aparece no dashboard
- Confirme que o dispositivo IoT está publicando no mesmo tópico configurado.
- Verifique o formato do payload MQTT (JSON com campos `voltage`, `current`, `power`, etc.).
- Cheque se o Client ID não está duplicado (dois clientes com o mesmo ID se desconectam mutuamente).

### Alertas não chegam
- Conceda permissão de notificações ao app nas configurações do sistema.
- Verifique se os limites de alerta estão configurados (tensão mín/máx, limite de consumo).

### Integração REST não envia dados
- Confirme que a Base URL está acessível (teste no navegador: `http://<url>/health`).
- Verifique se a API Key está correta.
- Toque em **Sincronizar agora** para ver se há erros de rede.

### Monitoramento em segundo plano para no Android
- Alguns fabricantes (Xiaomi, Samsung, Huawei) bloqueiam serviços em segundo plano.
- Acesse as configurações do sistema → Bateria → permita que o app rode em segundo plano.
