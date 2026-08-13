# 07 — Segurança

> Índice: [README](../README.md) · [01 — Visão geral](01_visao_geral.md) · [02 — Arquitetura](02_arquitetura.md) · [03 — Implantação](03_implantacao.md) · [04 — Banco de dados](04_banco_de_dados.md) · [05 — Funções RPC](05_funcoes_rpc.md) · [06 — Frontend](06_frontend.md) · **07 — Segurança** · [08 — Operação](08_operacao.md)

## 1. Modelo de confiança (camadas)

| Camada | O que protege | Mecanismo |
|---|---|---|
| Navegador (Mobile/Quiosque) | Acesso à API | Nenhuma chave sensível; só a URL pública do Worker |
| Cloudflare Worker | Acesso ao Supabase | `SUPABASE_SERVICE_ROLE_KEY` como variável secreta; validação de Origem (CORS) |
| Supabase Auth | Login do Admin | E-mail + senha; sessão em `localStorage`; `is_admin()` decide autorização |
| Banco (PostgreSQL) | Dados | RLS + RPCs `security definer` com checagem `is_admin()` |
| Dados das batidas | Integridade | Cadeia de hash + `punch_adjustments` (trilha de auditoria) |

## 2. Credenciais — o que pode e o que nunca pode ir ao repositório

| Segredo | Repositório? | Onde fica |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | **NUNCA** | Variável secreta do Worker (`SUPABASE_SERVICE_ROLE_KEY`) |
| Senha do admin (Auth) | **NUNCA** | Supabase Auth |
| Chave publicável (`sb_publishable_...`) | Pode | `app/admin-config.js` (feita para navegador) |
| `SUPABASE_URL` | Pode | `admin-config.js` e variável do Worker |
| URL do Worker | Pode | `app/config.js` |

A chave publicável sozinha **não dá acesso administrativo**: ela só permite chamar RPCs e,
no banco, tudo é barrado por `is_admin()`.

## 3. Autenticação e autorização do Admin

1. **Autenticação**: Supabase Auth (e-mail/senha). O `access_token` fica no
   `localStorage` (`eemti-admin-session`).
2. **Autorização**: cada RPC `security definer` executa `if not public.is_admin() then
   raise exception 'Acesso administrativo negado.'`. `is_admin()` exige perfil em
   `admin_profiles` com `role='admin'` e `active=true`.
3. **Self-protection**: `admin_save_profile`/`admin_delete_profile` impedem que o próprio
   admin remova ou desative o próprio acesso (evita "trancar" a gestão).
4. Perfis `operator` existem mas **não passam em `is_admin()`** (reservado para uso futuro).

## 4. PIN e tokens

- O PIN do funcionário é guardado **somente como hash bcrypt** (`pin_hash`); nunca é
  retornado ao navegador.
- A validação ocorre dentro do banco (`extensions.crypt(p_pin, pin_hash)`).
- Token offline: 32 bytes aleatórios gerados no servidor; o banco guarda apenas o
  hash SHA-256 (`token_hash`); validade 72 h; `last_used_at` é atualizado a cada uso.
- O token em texto vive apenas na IndexedDB do aparelho (não em cookies nem logs).

## 5. API (Worker)

- Só aceita `Origin = https://sistemas-eemti.github.io`; caso contrário `403`.
- Só `POST` (e preflight `OPTIONS`); outros métodos → `405`.
- Só `body.action === 'sync'` com `body.record`; senão `400`.
- Repassa o payload para `sync_punch_api` com a `SERVICE_ROLE`. `sync_punch` valida
  canal, matrícula/PIN/token, duplicidade e futuro antes de gravar.

## 6. Banco (RLS e RPCs)

- **RLS habilitada** em todas as tabelas de negócio, **sem políticas públicas**. Apenas
  `service_role` (que ignora RLS) e as RPCs `security definer` acessam os dados.
- Políticas para `authenticated` exigem `is_admin()` (ver [04 — Banco de dados](04_banco_de_dados.md)).
- As RPCs `sync_punch`/`sync_punch_api` são revogadas de `public`, `anon` **e**
  `authenticated`; só `service_role` as executa.
- Funções de admin são revogadas de `public`/`anon`; só `authenticated` executa (e mesmo
  assim barradas por `is_admin()` dentro do corpo).

## 7. Integridade e auditoria

- **Cadeia de hash** em `punches`: cada hash depende do anterior + id + matrícula +
  horário + origem → alterar uma batida antiga quebra a cadeia.
- **`punch_adjustments`**: exclusões (`exclude`) guardam `before_value`; inclusões manuais
  (`include`) guardam `after_value`; sempre com `reason`, `requested_by`, `approved_by`.
- **`audit_events`**: registro de eventos (`punch_registered`, `punch_included_manual`,
  `employee_saved`, …) com ator e detalhes.
- Exclusão de batida é **soft delete** (`excluded_at`), nunca `DELETE`.

## 8. Boas práticas / checklist

- [ ] `SUPABASE_SERVICE_ROLE_KEY` nunca em commits, logs, screenshots ou mensagens.
- [ ] Sempre aplicar novas migrations antes de testar versões novas do Admin.
- [ ] Recarregar com Ctrl+F5 após publicação (cache do Service Worker).
- [ ] Não desabilitar RLS nem adicionar políticas `anon`/`public` nas tabelas.
- [ ] Ao publicar o Worker, conferir `Origin` permitida e os segredos.
- [ ] Conferir periodicamente `auth.users` e `admin_profiles` (acessos vinculados).
