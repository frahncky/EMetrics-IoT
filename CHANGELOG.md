# Changelog

Todas as mudanças notáveis neste projeto são documentadas aqui.  
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/).  
Versionamento segue [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [1.3.0] — 2026-05-03

### Adicionado
- **Sincronização REST offline**: fila de métricas em SQLite com flush automático periódico para API de terceiros (`IntegrationService`).
- **Perfis MQTT**: suporte a múltiplos brokers/dispositivos com troca rápida de perfil nas configurações.
- **Dashboard personalizável**: preferências dos gráficos (campos selecionados, card de previsão) persistidas entre sessões.
- **Previsão local**: card de tendência e projeção de potência por regressão linear sobre as últimas leituras (`ForecastProvider`).
- **OAuth Device Flow**: autenticação com provedor externo via fluxo Device Authorization (RFC 8628).
- **Backend de exemplo**: servidor Node.js/Express em `backend_example/` pronto para receber métricas via `POST /metrics`.
- **Configurações expandidas**: novas abas "Integração" (REST + OAuth) e seletor de perfil MQTT na aba "MQTT".

### Corrigido
- Overflow em elementos do menu de configurações (dropdown de perfil, campos longos).
- Label do dropdown de perfil MQTT cortado pela barra de abas.

---

## [1.2.0] — 2026-04-xx

### Adicionado
- Provisionamento de ESP32 via AP HTTP diretamente pelo app (`EspProvisioningPage`).
- Três tipos de potência nos gráficos (ativa, reativa, aparente).
- Solicitação de permissão de notificação no fluxo de conexão MQTT.
- Protocolo de ack/timeout para solicitações de histórico em segundo plano.

### Alterado
- Fluxo MQTT unificado; UI de autenticação renomeada para "Perfis locais".
- Credenciais MQTT armazenadas com segurança via `flutter_secure_storage`.

### Corrigido
- Estado de segundo plano do MQTT atualizado corretamente na UI.
- Segurança de notifiers assíncronos no provider de status MQTT.

---

## [1.1.0] — 2026-03-xx

### Adicionado
- Status operacional MQTT com indicador visual no dashboard.
- Histórico de alertas disparados.
- Exportação de histórico em PDF (com fonte Unicode embutida).
- Login opcional com modo visitante e portão de autenticação.
- Configurações de medição personalizáveis (tensão mín/máx, limite de consumo, tarifa).
- Monitoramento MQTT em segundo plano no Android (`flutter_background_service`).
- Pipeline CI com `flutter analyze` e `flutter test`.
- Ícone e splash screen customizados.

### Alterado
- Menu de navegação migrado para `BottomNavigationBar` com bordas arredondadas.
- Dashboard responsivo com `Wrap` para telas menores.

### Corrigido
- Grid do gráfico sempre visível mesmo sem dados.
- Cores hardcoded adaptadas para tema claro/escuro.

---

## [1.0.0] — 2026-02-xx

### Adicionado
- Dashboard com indicadores em tempo real (tensão, corrente, potência, fator de potência, frequência, energia).
- Dois gráficos empilhados com seleção de grandeza por dropdown.
- Página de histórico com gráfico e solicitação de dados via MQTT.
- Configurações MQTT (broker, porta, client ID, usuário, senha, tópico, TLS).
- Persistência de configurações com `shared_preferences`.
- Tema claro/escuro dinâmico com paleta corporativa.
- Exportação de histórico em CSV.
- Alertas locais via `flutter_local_notifications`.
- Formatação SI dinâmica nos valores exibidos.
