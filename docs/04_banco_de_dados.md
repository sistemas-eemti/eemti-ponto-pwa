# 04 — Banco de dados (schema e migrations)

> Índice: [README](../README.md) · [01 — Visão geral](01_visao_geral.md) · [02 — Arquitetura](02_arquitetura.md) · [03 — Implantação](03_implantacao.md) · **04 — Banco de dados** · [05 — Funções RPC](05_funcoes_rpc.md) · [06 — Frontend](06_frontend.md) · [07 — Segurança](07_seguranca.md) · [08 — Operação](08_operacao.md)

Banco: **PostgreSQL (Supabase)**, schema `public`. Todas as migrations estão em
`supabase/migrations/` e devem ser aplicadas em ordem.

---

## 1. Lista de migrations

| # | Arquivo | O que faz |
|---|---|---|
| 001 | `20260812_001_initial_schema.sql` | Cria todas as tabelas (`pgcrypto`, triggers de `updated_at`, RLS sem políticas). |
| 002 | `20260812_002_sync_punch.sql` | `sync_punch`: registro transacional de batida (validação, PIN bcrypt, token 72 h, geocerca, cadeia de hash). |
| 003 | `20260812_003_seed_test_data.sql` | Dados de homologação: departamentos, cargo, jornada, 4 funcionários (PIN `1234`) e geocerca de teste. |
| 004 | `20260812_004_sync_punch_api.sql` | `sync_punch_api(jsonb)`: ponte JSON da API (Worker). |
| 005 | `20260812_005_fix_pgcrypto_schema.sql` | Ajusta `search_path` do `sync_punch` para resolver `extensions.*`. |
| 006 | `20260812_006_clear_homologation_data.sql` | `TRUNCATE` das tabelas (limpa dados de homologação, preserva schema). |
| 007 | `20260812_007_admin_access.sql` | `admin_profiles`, `is_admin()`, políticas de RLS, vínculo do e-mail administrador. |
| 008 | `20260812_008_admin_employee_rpc.sql` | `admin_save_employee` (primeira versão). |
| 009 | `20260812_009_grant_admin_table_access.sql` | GRANTs de tabela para `authenticated` (limitados por RLS). |
| 010 | `20260812_010_admin_dashboard_rpcs.sql` | Dashboard, listagem de funcionários, opções (deptos/cargos/jornadas), geocercas. |
| 011 | `20260813_011_admin_catalog_rpcs.sql` | CRUD de departamentos, cargos, jornadas; ativar/inativar funcionário. |
| 012 | `20260813_012_admin_reports_rpcs.sql` | Espelho, resumo mensal, atrasos, faltas, monitor offline. |
| 013 | `20260813_013_admin_holidays_rpcs.sql` | CRUD de feriados. |
| 014 | `20260813_014_admin_punches_rpcs.sql` | Listagem e exclusão de batidas (com ajuste). |
| 015 | `20260813_015_admin_profiles_rpcs.sql` | CRUD de perfis de acesso (admin/operador). |
| 016 | `20260813_016_admin_geofence_employee_fixes.sql` | Ativar/excluir geocerca; listagem completa de funcionários; PIN opcional na edição. |
| 017 | `20260813_017_admin_report_fixes.sql` | Espelho detalhado, dashboard/monitor com fuso Fortaleza. |
| 018 | `20260813_018_admin_schedule_break.sql` | Jornadas com intervalo (`break_start`/`break_end`). |
| 019 | `20260813_019_admin_absences_reports.sql` | CRUD de ausências; relatórios completos de atrasos e faltas. |
| 020 | `20260813_020_admin_outside_attendance.sql` | Relatório "fora da cerca" e assiduidade por funcionário. |
| 021 | `20260813_021_admin_occurrences_reasons_settings.sql` | CRUD de ocorrências, motivos (`reasons`) e opções (`settings`); resumo por departamento; `aviso` na batida. |
| 022 | `20260813_022_admin_manual_punch.sql` | Batida manual + lista de batidas por funcionário (manutenção de ponto). |
| 023 | `20260813_023_admin_employee_details.sql` | Campos adicionais do funcionário (sexo, nascimento, salário, código de barras, endereço, CEP, telefones) e RPCs de salvar/listar completas. |
| 024 | `20260813_024_fix_punch_message_null.sql` | Corrige retorno nulo da batida quando a mensagem ao funcionário está vazia. |
| 025 | `20260813_025_employee_punch_history.sql` | Consulta autenticada das últimas marcações do próprio funcionário no Mobile. |

---

## 2. Tabelas

### 2.1 `departments`
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK, default `gen_random_uuid()` |
| name | text | NOT NULL, UNIQUE |
| created_at | timestamptz | default `now()` |

### 2.2 `positions`
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK, default `gen_random_uuid()` |
| name | text | NOT NULL, UNIQUE |
| created_at | timestamptz | default `now()` |

### 2.3 `schedules` (jornadas)
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK, default `gen_random_uuid()` |
| name | text | NOT NULL, UNIQUE |
| entry_time | time | horário de entrada previsto |
| exit_time | time | horário de saída previsto |
| break_start | time | início do intervalo |
| break_end | time | fim do intervalo |
| daily_minutes | integer | NOT NULL default 0, CHECK `>= 0` (carga diária) |
| weekdays | smallint[] | default `{1,2,3,4,5}` (seg–sex) |
| tolerance_minutes | integer | NOT NULL default 0, CHECK `>= 0` |
| active | boolean | default `true` |
| created_at / updated_at | timestamptz | trigger atualiza `updated_at` |

### 2.4 `employees`
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK, default `gen_random_uuid()` |
| enrollment | text | NOT NULL, UNIQUE (matrícula ou CPF) |
| name | text | NOT NULL |
| cpf | text | UNIQUE (opcional) |
| pis | text | opcional |
| department_id | uuid | FK → `departments(id)` |
| position_id | uuid | FK → `positions(id)` |
| schedule_id | uuid | FK → `schedules(id)` |
| pin_hash | text | bcrypt (nunca retornado ao navegador) |
| active | boolean | default `true` |
| admitted_on | date | data de admissão |
| sex | text | Masculino / Feminino / Outro (opcional) |
| birth_date | date | data de nascimento (opcional) |
| salary | numeric(12,2) | salário (opcional) |
| barcode | text | código de barras da carteirinha (opcional) |
| address | text | endereço (opcional) |
| neighborhood | text | bairro (opcional) |
| city | text | cidade (opcional) |
| cep | text | CEP (opcional) |
| phone | text | telefone fixo (opcional) |
| mobile | text | celular (opcional) |
| created_at / updated_at | timestamptz | trigger atualiza `updated_at` |

### 2.5 `geofences`
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK |
| name | text | NOT NULL |
| latitude | numeric(10,7) | NOT NULL |
| longitude | numeric(10,7) | NOT NULL |
| radius_meters | integer | NOT NULL, CHECK `> 0` |
| active | boolean | default `true` |
| created_at / updated_at | timestamptz | trigger atualiza `updated_at` |

### 2.6 `devices`
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK |
| client_device_id | text | NOT NULL, UNIQUE (device id gerado no navegador) |
| channel | text | CHECK `in ('mobile','kiosk')` |
| label | text | opcional |
| active | boolean | default `true` |
| first_seen_at / last_seen_at | timestamptz | atualizado a cada batida |

### 2.7 `device_tokens`
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK |
| employee_id | uuid | FK → `employees(id)` |
| device_id | uuid | FK → `devices(id)` |
| token_hash | text | NOT NULL, UNIQUE (SHA-256 do token) |
| expires_at | timestamptz | NOT NULL (72 h) |
| last_used_at | timestamptz | default `now()` |
| created_at | timestamptz | default `now()` |
| | | UNIQUE `(employee_id, device_id, token_hash)` |

### 2.8 `punches` (batidas)
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK |
| client_record_id | text | NOT NULL, UNIQUE (id gerado no navegador / `MAN-...`) |
| employee_id | uuid | NOT NULL, FK → `employees(id)` |
| device_id | uuid | FK → `devices(id)` |
| origin | text | CHECK `in ('mobile','kiosk','mobile_offline','kiosk_offline','manual')` |
| captured_at | timestamptz | NOT NULL (horário da batida) |
| recorded_at | timestamptz | default `now()` (horário do servidor) |
| synced_at | timestamptz | quando chegou ao servidor |
| latitude / longitude | numeric(10,7) | opcionais (mobile) |
| accuracy_meters | numeric(10,2) | precisão do GPS |
| geofence_id | uuid | FK → `geofences(id)` (mais próxima) |
| inside_geofence | boolean | `true` se dentro da geocerca |
| distance_meters | numeric(10,2) | distância até a geocerca |
| captured_offline | boolean | default `false` |
| excluded_at | timestamptz | preenchido quando excluída (soft delete) |
| previous_hash / hash | text | cadeia de hash (anti-adulteração) |
| created_at | timestamptz | default `now()` |

Índices: `(employee_id, captured_at)`, `(recorded_at desc)`, `(device_id)`.

### 2.9 `punch_adjustments` (ajustes/trilha)
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK |
| punch_id | uuid | NOT NULL, FK → `punches(id)` |
| kind | text | CHECK `in ('exclude','include','edit')` |
| reason | text | NOT NULL (motivo do ajuste) |
| before_value | jsonb | estado antes (exclusões) |
| after_value | jsonb | estado depois (inclusões) |
| requested_by | text | NOT NULL (autor) |
| approved_by | text | aprovador |
| created_at | timestamptz | default `now()` |

### 2.10 `absences`
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK |
| employee_id | uuid | NOT NULL, FK → `employees(id)` |
| absence_date | date | NOT NULL |
| type | text | `falta`, `atestado`, `férias`, `folga` (validado na RPC) |
| reason | text | motivo |
| excused | boolean | default `false` (abonada) |
| document_reference | text | referência de documento |
| created_at | timestamptz | default `now()` |
| | | UNIQUE `(employee_id, absence_date, type)` |

### 2.11 `occurrences`
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK |
| employee_id | uuid | NOT NULL, FK → `employees(id)` |
| occurrence_date | date | NOT NULL |
| type | text | NOT NULL (ex.: advertência, elogio; vazio vira `geral`) |
| description | text | NOT NULL |
| recorded_by | text | NOT NULL (e-mail do admin) |
| created_at | timestamptz | default `now()` |

### 2.12 `holidays`
| Coluna | Tipo | Observações |
|---|---|---|
| holiday_date | date | PK |
| description | text | NOT NULL |
| type | text | default `'national'` |

### 2.13 `reasons` (motivos)
| Coluna | Tipo | Observações |
|---|---|---|
| id | uuid | PK |
| description | text | NOT NULL |
| category | text | CHECK `in ('ajuste','falta','abono')` |
| active | boolean | default `true` |
| created_at / updated_at | timestamptz | trigger atualiza `updated_at` |

### 2.14 `settings` (opções)
| Coluna | Tipo | Observações |
|---|---|---|
| key | text | PK |
| value | jsonb | NOT NULL |
| updated_at | timestamptz | default `now()` |

Chaves permitidas (whitelist na RPC `admin_save_setting`):
`mensagem_funcionario` (virada "aviso" na resposta da batida), `tolerancia_padrao`,
`email_alertas`.

### 2.15 `admin_profiles`
| Coluna | Tipo | Observações |
|---|---|---|
| user_id | uuid | PK, FK → `auth.users(id)` ON DELETE CASCADE |
| role | text | CHECK `in ('admin','operator')` |
| display_name | text | opcional |
| active | boolean | default `true` |
| created_at / updated_at | timestamptz | trigger atualiza `updated_at` |

### 2.16 `audit_events`
| Coluna | Tipo | Observações |
|---|---|---|
| id | bigint | PK, `GENERATED ALWAYS AS IDENTITY` |
| event_at | timestamptz | default `now()` |
| actor | text | NOT NULL (`pwa`, e-mail, `admin`, `auth.uid()::text`) |
| action | text | NOT NULL (`punch_registered`, `punch_included_manual`, `employee_saved`, …) |
| entity | text | NOT NULL |
| entity_id | text | opcional |
| details | jsonb | default `'{}'` |

---

## 3. RLS (Row Level Security)

Todas as tabelas de negócio têm **RLS habilitada** e **nenhuma política pública**: só
`service_role` (que ignora RLS, usado pelo Worker) e as funções `security definer` acessam
os dados. As políticas permitem `authenticated` apenas quando `public.is_admin()`:

| Tabela | Política |
|---|---|
| `admin_profiles` | "admin can read own profile" — SELECT `(user_id = auth.uid())` |
| departamentos, cargos, jornadas, funcionários, geocercas | "admin manage …" — ALL com `is_admin()` |
| `devices`, `device_tokens` | "admin read …" — SELECT com `is_admin()` |
| `punches`, `punch_adjustments`, `absences`, `occurrences`, `holidays`, `settings`, `reasons` | ALL com `is_admin()` |
| `audit_events` | "admin read audit events" — SELECT com `is_admin()` |

> O GRANT de tabelas (migration 009) dá privilégios de escrita a `authenticated`, mas a RLS
> impede qualquer linha fora das políticas — na prática o Admin usa **somente RPCs**.

---

## 4. Triggers

| Trigger | Tabela | Função |
|---|---|---|
| `schedules_updated_at` | `schedules` | `public.set_updated_at()` |
| `employees_updated_at` | `employees` | `public.set_updated_at()` |
| `geofences_updated_at` | `geofences` | `public.set_updated_at()` |
| `admin_profiles_updated_at` | `admin_profiles` | `public.set_updated_at()` |
| `reasons_updated_at` | `reasons` | `public.set_updated_at()` |

`set_updated_at()` apenas define `NEW.updated_at = now()`.

---

## 5. Cadeia de hash das batidas (anti-adulteração)

Cada batida nova calcula:

```sql
hash = encode(digest(
  client_record_id || '|' || enrollment || '|' || effective_at::text || '|' || origin || '|' || previous_hash,
  'sha256'), 'hex');
```

- `previous_hash` é o `hash` da batida mais recente (`order by created_at desc`), ou `''`.
- As escritas são serializadas com `pg_advisory_xact_lock(186792024)` para manter a cadeia
  linear (usado em `sync_punch` e em `admin_add_manual_punch`).

---

## 6. Regras de negócio no banco (resumo)

- **PIN**: bcrypt (`extensions.crypt` + `gen_salt('bf')`); validação só no servidor.
- **Token offline**: 32 bytes aleatórios, hash SHA-256 no banco, validade 72 h; usado para
  autossincronizar a fila sem pedir PIN novamente.
- **Batida repetida**: rejeitada se a nova estiver a menos de 2 minutos da última
  (não excluída) do mesmo funcionário.
- **Futuro**: `captured_at` não pode ser `> now() + 5 minutes`.
- **Geocerca**: distância haversine (raio da Terra 6.371 km) até a geocerca ativa mais
  próxima; `inside_geofence = true` se `distance <= radius`.
- **Exclusão de batida**: soft delete (`excluded_at`) + `punch_adjustments` `kind='exclude'`.
- **Inclusão manual**: origem `manual` + `punch_adjustments` `kind='include'`.
- **Fuso**: relatórios usam `America/Fortaleza`.
- **Dias úteis**: seg–sex, descontando feriados (`holidays`).
