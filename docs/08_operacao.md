# 08 — Operação (dia a dia e problemas comuns)

> Índice: [README](../README.md) · [01 — Visão geral](01_visao_geral.md) · [02 — Arquitetura](02_arquitetura.md) · [03 — Implantação](03_implantacao.md) · [04 — Banco de dados](04_banco_de_dados.md) · [05 — Funções RPC](05_funcoes_rpc.md) · [06 — Frontend](06_frontend.md) · [07 — Segurança](07_seguranca.md) · **08 — Operação**

## 1. Publicar uma mudança (passo a passo)

1. Altere o código (ex.: `app/admin.js`).
2. **Bump de versão** dos assets alterados nos HTMLs:
   - `admin.html`: `<link href="app/admin.css?v=8">` → `v=9`, `<script src="app/admin.js?v=16">` → `v=17`.
   - `mobile.html`/`quiosque.html`: `styles.css?v=9`, `app.js?v=12`, etc.
3. **Service Worker**: aumente `CACHE = 'eemti-ponto-vN'` em `sw.js` sempre que
   Mobile/Quiosque mudarem, e mantenha a lista `ASSETS` com as mesmas versões.
4. Se mexeu no banco: adicione um novo migration `supabase/migrations/<data>_NNN_*.sql`
   (com `pg_notify('pgrst','reload schema')` no fim, quando aplicável) e rode no SQL Editor.
5. Commit + push → GitHub Pages publica.
6. Teste com **Ctrl+F5** (força recarga ignorando o cache).

> Se o Service Worker antigo estiver em uso, o novo assume no próximo load
> (`skipWaiting` + `clients.claim`); o cache antigo é apagado no `activate`.

## 2. Como adicionar uma migration nova

- Nome: `supabase/migrations/YYYYMMDD_NNN_nome_descritivo.sql`.
- Siga o padrão existente: `create or replace function public.xxx(...) ... security definer`,
  checagem `is_admin()`, `revoke ... from public, anon;` + `grant execute ... to authenticated;`
  e `select pg_notify('pgrst', 'reload schema');`.
- Parâmetros com `default` **devem vir depois** dos sem default (erro `42P13`).
- Após criar o migration, atualize `CHECKLIST_TESTES.md` e esta documentação.

## 3. Erros comuns

### 3.1 `42P13: input parameters after one with a default value must also have defaults`
Parâmetro com `default` seguido de outro sem `default` numa mesma função.
**Correção**: dar `default null` aos parâmetros seguintes (ou reordenar). A assinatura e a
chamada por nome (`p_*`) continuam funcionando.

### 3.2 `42703: column X does not exist` (na linha de um `ORDER BY`)
O subquery usado no `ORDER BY` não seleciona a coluna. **Correção**: incluir a coluna no
`SELECT` interno.

### 3.3 O Admin "esquece" o que mudou
O navegador/Service Worker está com cache antigo. **Correção**: Ctrl+F5; verificar a versão
do `sw.js` e dos assets.

### 3.4 Batida não sincroniza no aparelho
- Confirme a conexão e o status "Conectado".
- Token expirado (72 h) → o aparelho pede matrícula + PIN de novo.
- Verifique no Admin → Monitor offline se a batida está pendente ou com erro.
- Confira `app/config.js` (URL do Worker).

### 3.5 "Origem não autorizada." no Mobile
O Worker só aceita `Origin: https://sistemas-eemti.github.io`. Acontece se a página for
aberta por outro domínio/endereço ou se o `allowedOrigin` foi alterado.

### 3.6 Erro 502 no Mobile (Falha no gateway)
O Worker não conseguiu chamar o Supabase. Verifique as variáveis `SUPABASE_URL` e
`SUPABASE_SERVICE_ROLE_KEY` no Worker e se o projeto está no ar.

### 3.7 Login no Admin falha
- Credenciais do Supabase Auth (não do antigo sistema).
- Perfil em `admin_profiles` precisa existir, `role='admin'`, `active=true`.
- Se "Confirm email" está ligado, contas novas precisam confirmar antes do 1º login.

## 4. Manutenção de dados

- **Exclusão de batida**: usa soft delete + ajuste. Não faça `DELETE` manual em `punches`
  (quebra a trilha de auditoria e os relatórios).
- **Limpeza de homologação**: rode o migration 006 **somente** em ambiente de teste.
- **Backup**: o Supabase faz backup nativo (Painel → Database → Backups). Não há rotina
  própria de backup no sistema.

## 5. Consultas úteis (SQL Editor)

```sql
-- Batidas pendentes de sincronização (nunca deve haver: a fila é o navegador, aqui só o que chegou)
select count(*) from public.punches;

-- Últimas batidas e origem
select p.captured_at, e.name, p.origin, p.inside_geofence
from public.punches p join public.employees e on e.id = p.employee_id
order by p.captured_at desc limit 20;

-- Ajustes (trilha) das batidas
select pa.kind, pa.reason, pa.requested_by, pa.created_at
from public.punch_adjustments pa order by pa.created_at desc limit 50;

-- Eventos de auditoria
select * from public.audit_events order by event_at desc limit 50;

-- Validação da cadeia de hash (esperado: sem linhas)
-- cada hash = sha256(id|matricula|horario|origem|previous_hash do anterior)
```

## 6. Roteiro de testes

Use o [CHECKLIST_TESTES.md](../CHECKLIST_TESTES.md): cobre login, cadastros, mobile
online/offline, quiosque, todos os relatórios, integração e produção.

## 7. Manutenção do Worker

- Para atualizar o código: reimplante `worker/src/index.js` (dashboard ou `wrangler deploy`).
- Segredos: `wrangler secret put SUPABASE_URL` / `wrangler secret put SUPABASE_SERVICE_ROLE_KEY`
  (ou em **Settings → Variables** no painel).
- Ao trocar a URL da API, atualize `app/config.js` e faça bump do cache.
