# EEMTI Ponto PWA

Aplicativo offline para Mobile e Quiosque do Sistema de Ponto.

## Arquitetura

`GitHub Pages (PWA) -> Cloudflare Worker -> Google Apps Script -> Google Sheets`

- A PWA fica disponível offline após o primeiro acesso online.
- Batidas são salvas no IndexedDB e sincronizadas automaticamente ao recuperar a conexão.
- O PIN nunca fica armazenado no navegador.
- O Worker mantém a URL e a chave da API fora do repositório.

## Publicação

1. No GitHub: Settings > Pages > Deploy from a branch > `main` > `/ (root)`.
2. No Cloudflare: crie um Worker usando `worker/src/index.js`.
3. Configure os segredos do Worker:
   - `APPS_SCRIPT_URL`: URL da implantação da API Apps Script.
   - `API_SECRET`: mesma chave definida no Apps Script.
   - `ALLOWED_ORIGIN`: `https://sistemas-eemti.github.io`.
4. Em `app/config.js`, defina a URL pública do Worker.

## Apps Script

1. Cole o `Codigo.txt` atualizado no projeto Apps Script e salve.
2. Execute `_gerarSegredoPwaApi()` uma única vez. Copie o valor retornado, sem publicar ou enviar por e-mail.
3. Faça uma nova implantação do Web App: executar como você e acesso **Qualquer pessoa**. O Worker não tem uma sessão Google; a proteção é feita por `API_SECRET`, que não sai do Cloudflare/Apps Script.
4. Copie a URL `/exec` dessa implantação para o segredo `APPS_SCRIPT_URL` do Worker.

## Cloudflare Worker

No painel Cloudflare Workers, crie o Worker a partir de `worker/src/index.js` e configure:

```text
APPS_SCRIPT_URL = URL /exec da implantação Apps Script
API_SECRET      = retorno de _gerarSegredoPwaApi()
ALLOWED_ORIGIN  = https://sistemas-eemti.github.io
```

Depois de publicar, copie a URL terminada em `/api` para `app/config.js`.

O Worker rejeita qualquer origem diferente do GitHub Pages institucional. Os segredos ficam apenas no Cloudflare e Apps Script.

## Teste offline

1. Abra `mobile.html` ou `quiosque.html` online uma vez.
2. Confirme que o Service Worker foi instalado no DevTools > Application.
3. Desligue a rede e recarregue a página: a tela deve continuar abrindo.
4. Registre uma batida e confirme o status pendente.
5. Restaure a rede e confirme a sincronização no Monitor Offline do Admin.

Não publique `API_SECRET` nem a URL interna do Apps Script neste repositório.
