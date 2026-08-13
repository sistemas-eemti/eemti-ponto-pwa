# 06 — Frontend (Mobile, Quiosque e Admin)

> Índice: [README](../README.md) · [01 — Visão geral](01_visao_geral.md) · [02 — Arquitetura](02_arquitetura.md) · [03 — Implantação](03_implantacao.md) · [04 — Banco de dados](04_banco_de_dados.md) · [05 — Funções RPC](05_funcoes_rpc.md) · **06 — Frontend** · [07 — Segurança](07_seguranca.md) · [08 — Operação](08_operacao.md)

## 1. Arquivos

```
index.html             redireciona para mobile.html
mobile.html            página do funcionário (data-channel="mobile")
quiosque.html          tablet da recepção (data-channel="kiosk")
admin.html             painel de gestão
app/config.js          window.PONTO_CONFIG.API_URL (URL do Worker)
app/admin-config.js    window.ADMIN_CONFIG (URL + chave publicável do Supabase)
app/app.js             lógica comum de Mobile e Quiosque (bater ponto, offline, tema)
app/ponto.js           comunicação com a API, fila e tokens
app/db.js              camada IndexedDB
app/admin.js           lógica completa do Admin
app/styles.css         CSS do Mobile/Quiosque
app/admin.css          CSS do Admin
sw.js                  Service Worker (cache offline)
manifest.webmanifest   manifesto PWA
```

As páginas Mobile/Quiosque carregam `config.js` → `db.js` → `ponto.js` → `app.js`.
O `app.js` identifica o canal pelo atributo `data-channel` do `<body>`.

---

## 2. Mobile e Quiosque (`app.js`, `ponto.js`, `db.js`)

### 2.1 Batida (fluxo online)

1. `punch()` exige matrícula e PIN.
2. Mobile: solicita geolocalização (`enableHighAccuracy: true`, `timeout: 12000`,
   `maximumAge: 0`). Falha → mensagem "Não foi possível obter a localização."
3. `queuePunch()` monta `{ id, channel, matricula, deviceId, capturedAt, offline }`
   (+ latitude/longitude/accuracy no mobile) e grava na fila do IndexedDB.
4. `syncFor()`:
   - Se `!navigator.onLine` → retorna `{offline:true}`.
   - Envia cada item pendente do **mesmo funcionário** via `api()` (POST ao Worker).
   - Sucesso: remove da fila, salva o novo token se vier.
   - Erro controlado (ex.: PIN errado): mantém na fila com `error` e devolve a mensagem.
   - `NETWORK`: marca o item como offline e devolve `{offline:true}`.
5. Resposta final exibe `message` (com horário em Fortaleza) e, se houver,
   **`aviso`** (mensagem da escola, configurada no Admin → Opções).

### 2.2 Offline

- A batida é salva no IndexedDB **antes** de tentar a rede → nunca se perde.
- A barra de status mostra "Sem conexão · N batida(s) pendente(s)."
- Sincronização acontece automaticamente:
  - evento `online` (`autoSync()`),
  - botão "Sincronizar batidas pendentes" (mobile),
  - a cada 30 s no quiosque,
  - ao carregar a página.
- Para autossincronizar sem pedir PIN de novo, o aparelho usa o **token offline de 72 h**
  salvo no IndexedDB. Expirou → mensagem orientando informar matrícula + PIN novamente.
- `navigator.storage.persist()` tenta deixar o armazenamento persistente (não é limpo por
  liberação automática de espaço do navegador).

### 2.3 IndexedDB (`db.js`)

Banco `eemti-ponto-pwa`, versão 1, com três stores:

| Store | Key | Conteúdo |
|---|---|---|
| `queue` | `id` | batidas pendentes (registro completo + `error`/`offline` quando preciso) |
| `tokens` | `key` (`<canal>:<matrícula>`) | token offline por funcionário |
| `meta` | `key` (`device:<canal>`) | device id persistente |

### 2.4 Identificação e tokens (`ponto.js`)

- `normalizarMatricula()` remove zeros à esquerda quando é numérica.
- `novoId()` gera id único (`L<timestamp base36>-<aleatório>`).
- `deviceId(channel)` gera e guarda em `meta` (`device:<canal>`).
- `tokenFor()/saveToken()` guardam o token por canal+matrícula.

### 2.5 Quiosque (diferenças)

- `needsGeo = false`: não pede localização.
- Enter passa da matrícula para o PIN e, no PIN, registra.
- `setInterval(autoSync, 30000)` sincroniza sozinho.
- Autofocus na matrícula ao carregar.

---

## 3. Admin (`admin.js`)

### 3.1 Login e sessão

- Login: `POST {SUPABASE_URL}/auth/v1/token?grant_type=password` com e-mail/senha.
  A resposta (com `access_token` e `refresh_token`) é salva em `localStorage`
  (`eemti-admin-session`).
- `requireAdmin()`: valida a sessão e chama `is_admin()`. Sem perfil `admin` ativo →
  mensagem "Esta conta não possui acesso administrativo." e sessão encerrada.
- "Sair" apaga a sessão.

### 3.2 Cliente Supabase leve

`app/admin.js` implementa `request()` e `supabase.rpc()` com `fetch` — sem bibliotecas
externas. Todas as operações vão para RPCs (`security definer`). Ver [05 — Funções RPC](05_funcoes_rpc.md).

### 3.3 Navegação e estado

- `showPage(page)` alterna `.nav`/`.page` ativos, define o título e chama o loader da página.
- Botão **Atualizar** recarrega a página atual (`refresh`).
- Mensagens de feedback em `#app-message` (verde = sucesso, vermelho = erro).

### 3.4 Listagem das páginas e RPCs usadas

| Página | RPCs principais |
|---|---|
| Visão geral | `admin_dashboard` |
| Funcionários | `admin_list_employees`, `admin_save_employee`, `admin_set_employee_active`, `admin_employee_options` |
| Departamentos | `admin_list_departments`, `admin_save_department`, `admin_delete_department` |
| Cargos | `admin_list_positions`, `admin_save_position`, `admin_delete_position` |
| Jornadas | `admin_list_schedules`, `admin_save_schedule`, `admin_delete_schedule` |
| Geocercas | `admin_list_geofences`, `admin_create_geofence`, `admin_set_geofence_active`, `admin_delete_geofence` |
| Espelho de ponto | `admin_list_employees`, `admin_espelho` |
| Resumo mensal | `admin_resumo_mensal` |
| Atrasos | `admin_rel_atrasos` |
| Faltas | `admin_rel_faltas` |
| Assiduidade | `admin_list_employees`, `admin_assiduidade` |
| Fora da cerca | `admin_rel_fora_cerca` |
| Ausências | `admin_list_absences`, `admin_save_absence`, `admin_delete_absence` |
| Ocorrências | `admin_list_occurrences`, `admin_save_occurrence`, `admin_delete_occurrence` |
| Monitor offline | `admin_monitor_offline` |
| Batidas | `admin_list_punches`, `admin_delete_punch` |
| Manutenção de ponto | `admin_add_manual_punch`, `admin_list_employee_punches`, `admin_delete_punch` |
| Feriados | `admin_list_holidays`, `admin_save_holiday`, `admin_delete_holiday` |
| Motivos | `admin_list_reasons`, `admin_save_reason`, `admin_delete_reason` |
| Acessos | `admin_list_profiles`, `admin_save_profile`, `admin_delete_profile` |
| Opções | `admin_list_settings`, `admin_save_setting` |

### 3.5 Acessos (criar conta)

A página Acessos pode criar a conta no Supabase Auth informando e-mail + senha inicial
(`POST /auth/v1/signup`), e depois vincula o perfil com `admin_save_profile`. Se a conta já
existir, apenas vincula o perfil. A função `admin_save_profile` bloqueia que o próprio admin
se rebaixe ou se desative.

### 3.6 Trocar minha senha

`PUT {SUPABASE_URL}/auth/v1/user` com o `access_token` da sessão atual. Exige nova senha
(6+ caracteres) e confirmação.

### 3.7 Relatórios: imprimir e CSV

- **Imprimir / PDF**: `window.print()` com CSS que oculta o menu na impressão (a tela mostra
  apenas o relatório da tabela ativa).
- **Exportar CSV**: monta o CSV a partir das células da tabela (`;` como separador, valores
  com quebra/aspas entre aspas) e baixa com BOM UTF-8 para abrir no Excel.

### 3.8 Tema claro/escuro

- Botão no login e no menu; preferência em `localStorage` (`eemti-admin-theme`).
- Implementado com atributo `data-theme` em `<html>` + variáveis CSS em `admin.css`.
- Mobile/Quiosque têm botão equivalente (`ponto_tema` no `localStorage` e `styles.css`).

---

## 4. Service Worker (`sw.js`)

- Cache `eemti-ponto-vN` com os assets fixos (HTMLs, CSS, JS, manifesto, logo).
- Navegação: tenta rede, atualiza o cache, e **cai para o cache** se offline.
- `config.js` é sempre buscado na rede quando possível (permite trocar a URL da API).
- Demais GETs: cache-first com atualização em segundo plano.
- `skipWaiting()` + `clients.claim()` para que uma nova versão assuma rápido.

> Quando publicar mudanças: **aumente a versão do cache** em `sw.js` e faça *bump* do
> query string dos assets alterados (ver [08 — Operação](08_operacao.md)).
