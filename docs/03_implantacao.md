# 03 — Implantação

> Índice: [README](../README.md) · [01 — Visão geral](01_visao_geral.md) · [02 — Arquitetura](02_arquitetura.md) · **03 — Implantação** · [04 — Banco de dados](04_banco_de_dados.md) · [05 — Funções RPC](05_funcoes_rpc.md) · [06 — Frontend](06_frontend.md) · [07 — Segurança](07_seguranca.md) · [08 — Operação](08_operacao.md)

## Visão geral dos passos

1. Criar o projeto Supabase e aplicar as migrations (SQL).
2. Criar a conta do administrador no Supabase Auth.
3. Criar e configurar o Cloudflare Worker.
4. Ajustar `app/config.js` e `app/admin-config.js`.
5. Publicar no GitHub Pages.
6. Homologar (ver [CHECKLIST_TESTES.md](../CHECKLIST_TESTES.md)).

---

## 1. Supabase

### 1.1 Criar o projeto

1. Em https://supabase.com, crie um projeto (região próxima, ex. São Paulo).
2. Anote a **URL do projeto** (`https://<ref>.supabase.co`) e a **chave publicável**
   (`sb_publishable_...`). Ambas ficam em **Settings → API**.

### 1.2 Aplicar as migrations

No painel, abra **SQL Editor** e rode cada arquivo, **em ordem**, copiando o conteúdo
de `supabase/migrations/`:

```
01. 20260812_001_initial_schema.sql
02. 20260812_002_sync_punch.sql
03. 20260812_003_seed_test_data.sql        (dados de homologação)
04. 20260812_004_sync_punch_api.sql
05. 20260812_005_fix_pgcrypto_schema.sql
06. 20260812_006_clear_homologation_data.sql  (limpa dados de teste — opcional)
07. 20260812_007_admin_access.sql
08. 20260812_008_admin_employee_rpc.sql
09. 20260812_009_grant_admin_table_access.sql
10. 20260812_010_admin_dashboard_rpcs.sql
11. 20260813_011_admin_catalog_rpcs.sql
12. 20260813_012_admin_reports_rpcs.sql
13. 20260813_013_admin_holidays_rpcs.sql
14. 20260813_014_admin_punches_rpcs.sql
15. 20260813_015_admin_profiles_rpcs.sql
16. 20260813_016_admin_geofence_employee_fixes.sql
17. 20260813_017_admin_report_fixes.sql
18. 20260813_018_admin_schedule_break.sql
19. 20260813_019_admin_absences_reports.sql
20. 20260813_020_admin_outside_attendance.sql
21. 20260813_021_admin_occurrences_reasons_settings.sql
22. 20260813_022_admin_manual_punch.sql
```

> Observações:
> - O migration **007** exige que a conta `sistemas.eemti@gmail.com` já exista no
>   **Authentication → Users** (ver 1.3). Rode-o depois de criar a conta.
> - **003** cria dados de teste (funcionários com PIN `1234`, geocerca de teste).
>   Antes de produção, rode **006** (apaga os dados de homologação, preserva schema) ou
>   limpe manualmente.
> - Todos os arquivos a partir do 010 terminam com `select pg_notify('pgrst','reload schema')`
>   para recarregar o schema no PostgREST.
> - Erros comuns de SQL e como resolver: [08 — Operação](08_operacao.md).

### 1.3 Criar o administrador

1. **Authentication → Users → Add user** com e-mail `sistemas.eemti@gmail.com` e uma senha forte.
2. Rode o migration **007** (ele vincula esse e-mail como perfil `admin` ativo). Se a conta
   ainda não existir, o migration falha com a mensagem orientando a criá-la antes.
3. O usuário entra no Admin em `admin.html`. Perfis adicionais são criados pela página
   **Acessos** (a própria página cria a conta no Auth se informar a senha inicial).

> Se "Confirm email" estiver habilitado em **Auth → Providers → Email**, contas criadas
> pelo Admin precisam confirmar o e-mail antes do primeiro login.

### 1.4 Chaves usadas pelo projeto

| Chave | Onde fica | Uso |
|---|---|---|
| `SUPABASE_URL` | `admin-config.js` (Admin) e variável do Worker | REST e RPCs |
| Chave publicável (`sb_publishable_...`) | `admin-config.js` (Admin) | `apikey` do Admin |
| `SUPABASE_SERVICE_ROLE_KEY` | **somente** variável do Worker | chamar `sync_punch_api` |
| Senhas do Auth | Supabase Auth | login do Admin |

**Nunca** coloque a `SERVICE_ROLE_KEY` em arquivo do repositório.

---

## 2. Cloudflare Worker

O Worker é um gateway único: recebe `POST /api`, valida a origem e chama a RPC
`sync_punch_api` com a chave de serviço.

### 2.1 Código e configuração

Arquivos:

- `worker/wrangler.toml` — nome, entry point e `compatibility_date`
- `worker/src/index.js` — handler do Worker

### 2.2 Criar e publicar

Opção A — dashboard:

1. **Workers & Pages → Create → Worker**, nome `eemti-ponto-api`.
2. Cole o conteúdo de `worker/src/index.js`.
3. **Settings → Variables** adicione:
   - `SUPABASE_URL` = `https://<ref>.supabase.co`
   - `SUPABASE_SERVICE_ROLE_KEY` = chave de serviço (secreta)
4. **Deploy**.

Opção B — CLI (Wrangler):

```bash
cd worker
wrangler login
wrangler secret put SUPABASE_URL
wrangler secret put SUPABASE_SERVICE_ROLE_KEY
wrangler deploy
```

### 2.3 Como o Worker valida a origem

O Worker responde `403 Origem não autorizada.` para qualquer `Origin` diferente de
`https://sistemas-eemti.github.io`. Aceita somente `POST` e preflight `OPTIONS`, e exige
`body.action === 'sync'` com `body.record`. Qualquer outro formato retorna `400`.

URL final exposta: `https://eemti-ponto-api.sistemas-eemti.workers.dev/api`.

---

## 3. Configuração do frontend

### `app/config.js` (Mobile/Quiosque)

```js
window.PONTO_CONFIG = {
  API_URL: 'https://eemti-ponto-api.sistemas-eemti.workers.dev/api'
};
```

### `app/admin-config.js` (Admin)

```js
window.ADMIN_CONFIG = {
  SUPABASE_URL: 'https://<ref>.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_...'
};
```

A chave publicável pode ficar versionada (é feita para o navegador); o acesso
administrativo é decidido no banco por `is_admin()`.

---

## 4. GitHub Pages

1. **Settings → Pages** do repositório `sistemas-eemti/eemti-ponto-pwa`.
2. **Source: Deploy from a branch → `main` → `/ (root)` → Save**.
3. Aguarde o build (o mesmo commit que sobe os arquivos publica a mudança).

URLs finais:

- Mobile: `https://sistemas-eemti.github.io/eemti-ponto-pwa/mobile.html`
- Quiosque: `https://sistemas-eemti.github.io/eemti-ponto-pwa/quiosque.html`
- Admin: `https://sistemas-eemti.github.io/eemti-ponto-pwa/admin.html`

> O Worker só aceita origens `https://sistemas-eemti.github.io`. Se o repositório/base
> mudar, ajuste `allowedOrigin` em `worker/src/index.js`.

---

## 5. Cache e versionamento (importante)

O **Service Worker** pré-cacheia os arquivos listados em `sw.js` (`ASSETS`). Quando algo
muda no frontend:

1. Atualize a **versão do cache** em `sw.js` (`CACHE = 'eemti-ponto-vN'`).
2. **Bump do query string** nos assets alterados nos HTMLs (`app.css?v=9`, `app.js?v=12`, …).
3. Publique (push) e, no navegador de teste, recarregue com **Ctrl+F5**.

Detalhes em [08 — Operação](08_operacao.md).

---

## 6. Cadastro inicial em produção

- Obter as coordenadas reais da escola (Camocim/CE) e ajustar/recriar a geocerca.
- Cadastrar departamentos, cargos, jornadas e funcionários no Admin.
- Definir feriados nacionais/municipais/escolares.
- Validar com uma semana de uso real antes de desligar o sistema legado.
