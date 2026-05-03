# Política de Segurança

## Versões Suportadas

| Versão | Suportada |
|--------|-----------|
| 1.3.x  | ✅ Sim    |
| 1.2.x  | ⚠️ Correções críticas apenas |
| < 1.2  | ❌ Não    |

## Reportando uma Vulnerabilidade

Se você descobriu uma vulnerabilidade de segurança neste projeto, **não abra uma issue pública**.

Entre em contato de forma privada:

1. Abra uma [Security Advisory](https://github.com/frahncky/EMetrics-IoT/security/advisories/new) no GitHub (privada por padrão).
2. Descreva o problema com o máximo de detalhes possível:
   - Versão afetada
   - Passos para reproduzir
   - Impacto potencial
   - Sugestão de correção (opcional)

**Prazo de resposta:** até 7 dias úteis para confirmação do recebimento.

## Boas Práticas de Segurança para Uso

- **Credenciais MQTT**: armazenadas com `flutter_secure_storage` (Keychain/Keystore). Não compartilhe backups do app.
- **API Key REST**: transmitida via header `Authorization: Bearer`. Use sempre HTTPS em produção.
- **OAuth**: tokens armazenados em secure storage. Configure escopos mínimos necessários.
- **Broker MQTT**: prefira brokers com autenticação e TLS ativados. Evite brokers públicos sem senha em produção.
- **Rede local**: o app não expõe portas nem serviços. O tráfego é sempre de saída (cliente MQTT/HTTP).
