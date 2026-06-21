# Deploy no Cloudflare Pages

Este dashboard usa Vite e ja esta pronto para publicar no Cloudflare Pages.

## Opcao 1: Deploy rapido pela CLI (recomendado)

1. Entre na pasta do dashboard:

```bash
cd dashboard_e_metrics_iot
```

2. Gere o build:

```bash
npm run build:cloudflare
```

3. Publique no Cloudflare Pages:

```bash
npm run deploy:cloudflare
```

Na primeira execucao, a CLI vai pedir autenticacao e pode solicitar o nome do projeto.
Sugestao de nome: `energy-meter-validation`.

## Opcao 2: Deploy continuo via GitHub + Cloudflare Pages

1. No Cloudflare, acesse `Workers & Pages` > `Create` > `Pages` > `Connect to Git`.
2. Selecione o repositorio `EMetrics-IoT`.
3. Configure:
- Root directory: `dashboard_e_metrics_iot`
- Build command: `npm run build`
- Build output directory: `dist`

Cada push na branch conectada atualiza o dashboard automaticamente.

## Dominio personalizado

Depois de publicar, em `Custom domains`, conecte seu dominio para URL final.
