# 05 — Funções RPC

> Índice: [README](../README.md) · [01 — Visão geral](01_visao_geral.md) · [02 — Arquitetura](02_arquitetura.md) · [03 — Implantação](03_implantacao.md) · [04 — Banco de dados](04_banco_de_dados.md) · **05 — Funções RPC** · [06 — Frontend](06_frontend.md) · [07 — Segurança](07_seguranca.md) · [08 — Operação](08_operacao.md)

Convenção: quase todas as funções administrativas são `security definer`, checam
`is_admin()` (senão `raise 'Acesso administrativo negado.'`), são revogadas de
`public`/`anon` e concedidas a `authenticated`. O Admin chama essas RPCs via
`POST /rest/v1/rpc/<nome>`.

---

## 1. Funções de serviço (somente `service_role`)

Chamadas **somente** pelo Cloudflare Worker. `authenticated` e `anon` não têm acesso.

### `sync_punch(p_client_record_id text, p_channel text, p_device_id text, p_enrollment text, p_captured_at timestamptz, p_offline boolean default false, p_latitude numeric default null, p_longitude numeric default null, p_accuracy_meters numeric default null, p_pin text default null, p_token text default null)` → `jsonb`

Registro transacional da batida. Valida identificadores, canal (`mobile`/`kiosk`),
`captured_at` (não nulo e não no futuro além de 5 min), exige lat/lon no canal mobile.
Etapas:

1. `pg_advisory_xact_lock(186792024)` (serializa a cadeia de hash).
2. Retorna `{ok:true, already_synced:true}` se `client_record_id` já existe.
3. Localiza o funcionário **ativo** por `trim(enrollment)`.
4. Upsert em `devices` (`client_device_id` → `id`).
5. Autenticação:
   - Com PIN: `extensions.crypt(p_pin, pin_hash)`; emite token de 32 bytes (hash SHA-256
     no banco), validade **72 h**.
   - Sem PIN: valida o token offline contra `device_tokens` (hash, não expirado).
6. `captured_at` efetivo = horário do aparelho se offline, senão horário do servidor.
7. Rejeita batida repetida (menos de 2 minutos após a última não excluída).
8. Mobile: calcula a geocerca ativa mais próxima (haversine) e `inside_geofence`.
9. Monta `origin` (`mobile`/`kiosk`/`mobile_offline`/`kiosk_offline`), calcula a cadeia de
   hash e insere em `punches`; grava `audit_events`.
10. Retorna `{ok, message, token, outside_geofence}` com horário em `America/Fortaleza`.

### `sync_punch_api(p_payload jsonb)` → `jsonb`

Ponte JSON para o Worker. Desempacota `client_record_id`, `channel`, `device_id`,
`enrollment`, `captured_at`, `offline`, `latitude`, `longitude`, `accuracy_meters`, `pin`,
`token` e chama `sync_punch`.

Na versão atual (migration 021), se `ok = true` também injeta o campo **`aviso`** com o valor
de `settings.mensagem_funcionario` — o Mobile/Quiosque exibe essa mensagem após a batida.

Grants: revogada de `public`, `anon`; concedida **somente** a `service_role`.

---

## 2. `is_admin()` → `boolean`

```sql
select exists (select 1 from public.admin_profiles
  where user_id = auth.uid() and role = 'admin' and active);
```

`language sql, stable, security definer`, concedida a `authenticated`. É a base de todas as
checagens de acesso.

---

## 3. Catálogo de RPCs administrativas

> Todas `security definer`, revogadas de `public`/`anon`, concedidas a `authenticated`,
> e checam `is_admin()`. "CRUD" = listar/criar/editar/excluir.

### Cadastros

| Função | Assinatura | Descrição |
|---|---|---|
| `admin_list_departments` | `()` → jsonb | Lista `{id, name, employees}` |
| `admin_save_department` | `(p_id uuid, p_name text)` → void | Cria/edita (trima nome) |
| `admin_delete_department` | `(p_id uuid)` → void | Recusa se houver funcionários vinculados |
| `admin_list_positions` | `()` → jsonb | Lista `{id, name, employees}` |
| `admin_save_position` | `(p_id uuid, p_name text)` → void | Cria/edita |
| `admin_delete_position` | `(p_id uuid)` → void | Recusa se houver vínculos |
| `admin_list_schedules` | `()` → jsonb | Lista com entrada/saída/intervalo/carga/tolerância |
| `admin_save_schedule` | `(p_id uuid, p_name text, p_entry_time text, p_exit_time text, p_break_start text, p_break_end text, p_daily_minutes int, p_tolerance_minutes int)` → void | Cria/edita; valida intervalo |
| `admin_delete_schedule` | `(p_id uuid)` → void | Recusa se houver vínculos |
| `admin_list_employees` | `()` → jsonb | Lista completa de funcionários (ativos/inativos) |
| `admin_save_employee` | `(p_enrollment text, p_name text, p_pin text default null, p_department_id uuid default null, p_position_id uuid default null, p_schedule_id uuid default null)` → employees | Cria/edita; PIN obrigatório só na criação; vazio mantém o PIN atual |
| `admin_set_employee_active` | `(p_enrollment text, p_active boolean)` → void | Ativa/inativa |
| `admin_list_geofences` | `()` → jsonb | Lista geocercas |
| `admin_create_geofence` | `(p_name text, p_latitude numeric, p_longitude numeric, p_radius_meters int)` → void | Cria |
| `admin_set_geofence_active` | `(p_id uuid, p_active boolean)` → void | Ativa/inativa |
| `admin_delete_geofence` | `(p_id uuid)` → void | Exclui |
| `admin_employee_options` | `()` → jsonb | `{departments, positions, schedules}` para formulários |
| `admin_list_holidays` | `()` → jsonb | Lista feriados |
| `admin_save_holiday` | `(p_date date, p_description text, p_type text)` → void | Upsert por data |
| `admin_delete_holiday` | `(p_date date)` → void | Exclui |
| `admin_list_reasons` | `()` → jsonb | Lista motivos |
| `admin_save_reason` | `(p_id uuid default null, p_description text default null, p_category text default 'ajuste', p_active boolean default true)` → void | Cria/edita; categorias `ajuste`/`falta`/`abono` |
| `admin_delete_reason` | `(p_id uuid)` → void | Exclui |

### Funcionários / ajustes

| Função | Assinatura | Descrição |
|---|---|---|
| `admin_list_absences` | `(p_start date, p_end date)` → jsonb | Lista ausências |
| `admin_save_absence` | `(p_id uuid default null, p_enrollment text default null, p_date date default null, p_type text default null, p_reason text default null, p_excused boolean default false)` → void | Cria/edita; tipos: `falta`, `atestado`, `férias`, `folga` |
| `admin_delete_absence` | `(p_id uuid)` → void | Exclui |
| `admin_list_occurrences` | `(p_start date, p_end date)` → jsonb | Lista ocorrências com matrícula/nome/registrado por |
| `admin_save_occurrence` | `(p_id uuid default null, p_enrollment text default null, p_date date default null, p_type text default null, p_description text default null)` → void | Cria/edita; grava `recorded_by` (e-mail do admin) |
| `admin_delete_occurrence` | `(p_id uuid)` → void | Exclui |

### Batidas / manutenção

| Função | Assinatura | Descrição |
|---|---|---|
| `admin_list_punches` | `(p_start date, p_end date)` → jsonb | Lista batidas do período (limite 2000), com status de exclusão |
| `admin_delete_punch` | `(p_id uuid, p_reason text)` → void | Soft delete + ajuste `exclude` (autor = e-mail do admin) |
| `admin_add_manual_punch` | `(p_enrollment text, p_captured_at timestamptz, p_reason text default null)` → jsonb | Batida manual (origem `manual`) + ajuste `include` + auditoria; retorna mensagem |
| `admin_list_employee_punches` | `(p_enrollment text, p_start date, p_end date)` → jsonb | Batidas de um funcionário (limite 1000) |

### Relatórios

| Função | Assinatura | Descrição |
|---|---|---|
| `admin_dashboard` | `()` → jsonb | KPIs (funcionários ativos, batidas hoje, fora da cerca hoje, geocercas) + últimas 12 batidas |
| `admin_espelho` | `(p_enrollment text, p_month date)` → jsonb | Espelho: todas as batidas do mês com previsto (entrada/saída/intervalo da jornada), origem, cerca |
| `admin_resumo_mensal` | `(p_month date)` → jsonb | Dias úteis, resumo por funcionário (trabalhado/esperado/saldo) e bloco `departamentos` (nome, funcionários, trabalhado/esperado, % , saldo) |
| `admin_rel_atrasos` | `(p_start date, p_end date)` → jsonb | `{resumo, por_funcionario, lista}` — atraso sobre entrada + tolerância |
| `admin_rel_faltas` | `(p_start date, p_end date)` → jsonb | `{resumo, por_funcionario, lista}` — faltas automáticas + registradas, abono |
| `admin_assiduidade` | `(p_enrollment text, p_start date, p_end date)` → jsonb | Assiduidade de um funcionário |
| `admin_rel_fora_cerca` | `(p_start date, p_end date)` → jsonb | `{resumo, por_funcionario, lista}` — batidas com `inside_geofence = false` |
| `admin_monitor_offline` | `()` → jsonb | Batidas offline com horários em `America/Fortaleza` |

### Acessos / opções

| Função | Assinatura | Descrição |
|---|---|---|
| `admin_list_profiles` | `()` → jsonb | Lista perfis com e-mail, papel, nome, ativo |
| `admin_save_profile` | `(p_user_email text, p_role text, p_display_name text, p_active boolean)` → void | Vincula/cria perfil; impede auto-remoção |
| `admin_delete_profile` | `(p_user_id uuid)` → void | Remove; impede excluir o próprio acesso |
| `admin_list_settings` | `()` → jsonb | Lista `{key, value, updated_at}` |
| `admin_save_setting` | `(p_key text, p_value text)` → void | Só aceita `mensagem_funcionario`, `tolerancia_padrao`, `email_alertas` |

---

## 4. Como o Admin chama as RPCs

O Admin **não usa a biblioteca supabase-js**. O cliente implementa um `request()` com `fetch`:

```
POST {SUPABASE_URL}/rest/v1/rpc/<nome>
Headers:
  apikey: {chave publicável}
  Authorization: Bearer {access_token da sessão}
  Content-Type: application/json
Body: JSON com os parâmetros (nomes "p_*")
```

Se a sessão expirar, as RPCs retornam "Sessão expirada. Entre novamente." e o usuário
refaz o login.

## 5. Sincronização (fluxo completo do Worker)

```
POST /api  →  valida Origin (sistemas-eemti.github.io), método POST, action="sync"
  →  fetch POST {SUPABASE_URL}/rest/v1/rpc/sync_punch_api
       headers: apikey + Authorization = SUPABASE_SERVICE_ROLE_KEY
       body: { p_payload: { client_record_id, channel, device_id, enrollment,
                             captured_at, offline, latitude, longitude,
                             accuracy_meters, pin, token } }
  →  devolve o JSON da RPC (ok, message, token, aviso, outside_geofence)
```
