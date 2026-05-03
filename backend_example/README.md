# Backend de Exemplo — EMetrics IoT

Servidor Node.js/Express mínimo para receber métricas enviadas pelo app via `IntegrationService`.

## Pré-requisitos

- Node.js 18+

## Instalação e execução

```bash
cd backend_example
npm install
node server.js
```

Por padrão, sobe em `http://localhost:3000`.

## Variáveis de ambiente

| Variável       | Padrão                | Descrição                          |
|----------------|----------------------|------------------------------------|
| `PORT`         | `3000`               | Porta do servidor                  |
| `BEARER_TOKEN` | `meu-token-secreto`  | Token de autenticação Bearer       |

Exemplo com variáveis personalizadas:

```bash
PORT=8080 BEARER_TOKEN=abc123 node server.js
```

## Endpoints

### `GET /health`
Verifica se o servidor está no ar. Sem autenticação.

```
GET http://localhost:3000/health
```

Resposta:
```json
{ "status": "ok", "metrics_count": 42 }
```

---

### `POST /metrics`
Recebe uma métrica enviada pelo app. Requer `Authorization: Bearer <token>`.

**Corpo esperado:**
```json
{
  "timestamp": "2026-05-03T10:00:00.000Z",
  "voltage": 220.5,
  "current": 5.2,
  "power": 1146.6,
  "pf": 0.98,
  "frequency": 60.0,
  "energy": 0.32
}
```

Resposta `201`:
```json
{ "ok": true, "id": 1 }
```

---

### `GET /metrics?page=1&limit=50`
Lista métricas recebidas. Requer `Authorization: Bearer <token>`.

Resposta:
```json
{
  "total": 100,
  "page": 1,
  "limit": 50,
  "data": [ ... ]
}
```

## Configuração no App

Na tela de configurações → aba **Integração**:

- **Base URL**: `http://<IP-do-servidor>:3000`  
  *(use o IP da máquina na rede local, ex.: `http://192.168.1.100:3000`)*
- **Token**: mesmo valor de `BEARER_TOKEN`
- Marque **Ativar integração REST**

> **Nota**: Este servidor armazena métricas em memória. Para produção, substitua o array `metrics` por um banco de dados real (PostgreSQL, MongoDB, etc.).
