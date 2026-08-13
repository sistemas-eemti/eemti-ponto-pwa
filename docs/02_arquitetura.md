# 02 — Arquitetura

> Índice: [README](../README.md) · [01 — Visão geral](01_visao_geral.md) · **02 — Arquitetura** · [03 — Implantação](03_implantacao.md) · [04 — Banco de dados](04_banco_de_dados.md) · [05 — Funções RPC](05_funcoes_rpc.md) · [06 — Frontend](06_frontend.md) · [07 — Segurança](07_seguranca.md) · [08 — Operação](08_operacao.md)

## Componentes

```
┌────────────────────────────────────────────────────────────────────┐
│                     GITHUB PAGES (https://sistemas-eemti.github.io) │
│                                                                     │
│   mobile.html ──┐   app/app.js (canal "mobile")                    │
│   quiosque.html ─┤   app/app.js (canal "kiosk")                    │
│                 │   IndexedDB (fila offline + tokens + meta)        │
│   admin.html    │   app/admin.js + admin.css + admin-config.js      │
└─────────────────┼──────────────────────────────────────────────────┘
                  │
        POST /api  │ (batidas do Mobile/Quiosque)
                  ▼
┌────────────────────────────────────────────────────────────────────┐
│              CLOUDFLARE WORKER  eemti-ponto-api                     │
│                                                                     │
│   • Valida CORS (só github.io) e POST /api                          │
│   • Envia o payload para RPC sync_punch_api                         │
│   • Guarda SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY (segredos)      │
└────────────────────────────────────────────────────────────────────┘
                  │
        POST /rest/v1/rpc/sync_punch_api   (service_role)
                  ▼
┌────────────────────────────────────────────────────────────────────┐
│            SUPABASE (PostgreSQL + Auth + RLS)                       │
│                                                                     │
│   sync_punch_api ──▶ sync_punch (valida PIN/token, geocerca, hash)  │
│   is_admin() ──▶ admin_profiles                                     │
│   RPCs admin_* (security definer, checam is_admin())                │
│   Auth: sessões, contas de usuários do Admin                        │
└────────────────────────────────────────────────────────────────────┘

Admin (navegador) ────────▶  SUPABASE  (REST /rest/v1 + /auth/v1)
                              • apikey = chave publicável
                              • Authorization: Bearer <token de acesso>
```

## Dois caminhos de dados

### 1. Batida do funcionário (Mobile / Quiosque)

1. O usuário digita matrícula + PIN.
2. Mobile: o navegador obtém a posição (alta precisão).
3. `ponto.js` grava o registro na fila do **IndexedDB** (`queue`) com um `id` único e o
   `deviceId` persistente — **a batida já está salva localmente antes de qualquer rede**.
4. `syncFor()` tenta enviar imediatamente para o Worker (`POST /api`).
5. O Worker valida a origem (CORS), monta o payload e chama a RPC `sync_punch_api` no
   Supabase usando a **chave de serviço** (único ponto que a conhece).
6. `sync_punch` valida PIN (bcrypt) ou token offline, calcula a geocerca mais próxima
   (fórmula haversine), monta a cadeia de hash, grava a batida e o evento de auditoria.
7. O resultado volta com `message`, `token` (novo, se usou PIN) e `aviso`
   (mensagem da escola, lida de `settings`). `ponto.js` remove o item da fila e guarda o
   token se a resposta for `ok:true`.
8. **Sem conexão**: o item permanece na fila; a tela mostra "Batida salva neste aparelho".
   Na volta da rede, o evento `online` dispara `autoSync()`, o botão de sincronização
   manual envia as pendências, e o quiosque ainda sincroniza a cada 30 s.

### 2. Administração (Admin)

1. Login em `/auth/v1/token?grant_type=password` (e-mail + senha). O `access_token` e o
   `refresh_token` ficam no `localStorage` (`eemti-admin-session`).
2. `requireAdmin()` valida a sessão e chama a RPC `is_admin()` (perfil `admin` ativo).
3. Toda operação de leitura/escrita é uma **RPC `security definer`**:
   `POST /rest/v1/rpc/<nome>` com `apikey` (publicável) + `Authorization: Bearer <token>`.
4. Cada RPC checa `is_admin()` dentro do banco e executa com privilégios elevados,
   ignorando a RLS (mas o `security definer` + checagem explícita garante o controle).

## Por que essa divisão

| Decisão | Motivo |
|---|---|
| Mobile/Quiosque passam pelo Worker | O navegador não pode conhecer a `SERVICE_ROLE`. O Worker concentra o único ponto com acesso de serviço e ainda valida CORS. |
| Admin usa chave publicável + RPCs | A chave publicável é segura para o navegador; o acesso real é decidido no banco por `is_admin()` + `security definer`. |
| RLS em todas as tabelas, sem políticas públicas | Apenas o `service_role` (Worker) e as RPCs elevadas acessam os dados; nenhuma tabela é exposta diretamente ao cliente. |
| IndexedDB + Service Worker | O app abre e registra batidas sem internet; a fila garante que nenhuma batida se perca. |
| Timestamps `timestamptz` | Evita ambiguidade de fuso; a exibição converte para `America/Fortaleza`. |

## Fluxo de uma batida offline (linha do tempo)

1. `punch()` → `queuePunch()` grava `{id, channel, matricula, deviceId, capturedAt, offline:true}` no IndexedDB.
2. `syncFor()` vê `!navigator.onLine` e retorna `{offline:true}`; a tela avisa que foi salva no aparelho.
3. A conexão volta → evento `online` → `autoSync()` percorre a fila por matrícula e chama `syncFor()` sem credenciais (usa o token salvo).
4. Se o token expirou (72 h), o servidor responde "Autorização offline expirada"; o funcionário informa matrícula + PIN de novo, a fila sincroniza e um novo token de 72 h é emitido.
5. No Admin, a batida aparece em **Batidas** (origem `mobile_offline`/`kiosk_offline`) e em **Monitor offline** com o horário local correto.

## Identificação de aparelho e token

- `deviceId` (`ponto.js`) é gerado com `novoId()` (timestamp base36 + aleatório), persistido em
  `meta` (`device:<canal>`). É ele que aparece em `devices.client_device_id`.
- Quando o funcionário usa PIN online, o servidor emite um token aleatório de 32 bytes; o
  navegador guarda **só o hash SHA-256** no `device_tokens` e o token em texto só na IndexedDB
  do aparelho. Nas sincronizações seguintes o token em texto é enviado e comparado pelo hash.

## Diagrama de sequência (batida online mobile)

```
Funcionário   app.js/ponto.js      Worker          sync_punch_api → sync_punch
    │              │                 │                     │
    │ matr+pin     │                 │                     │
    ├─────────────▶│                 │                     │
    │              │ getCurrentPosition (alta precisão)    │
    │              │                 │                     │
    │              │ POST /api (record + credential)       │
    │              ├────────────────▶│                     │
    │              │                 │ RPC sync_punch_api  │
    │              │                 ├────────────────────▶│
    │              │                 │        valida PIN/token, geocerca, hash,
    │              │                 │        INSERT punches + audit_events,
    │              │                 │        lê settings.mensagem_funcionario
    │              │                 │◀────────────────────┤
    │              │◀────────────────┤ (ok, token, aviso)  │
    │ ok + aviso   │                 │                     │
    │◀─────────────┤                 │                     │
```
