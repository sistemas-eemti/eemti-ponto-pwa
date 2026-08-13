# 01 — Visão geral

> Documento parte da documentação do sistema EEMTI Ponto.
> Índice: [README](../README.md) · [02 — Arquitetura](02_arquitetura.md) · [03 — Implantação](03_implantacao.md) · [04 — Banco de dados](04_banco_de_dados.md) · [05 — Funções RPC](05_funcoes_rpc.md) · [06 — Frontend](06_frontend.md) · [07 — Segurança](07_seguranca.md) · [08 — Operação](08_operacao.md)

## O que é

O **EEMTI Ponto** é o sistema de registro de ponto da escola. Antes, o sistema rodava em
Google Sheets + Apps Script; esta versão foi migrada para um trio de aplicações web (PWA)
hospedadas em GitHub Pages, com banco de dados no Supabase (PostgreSQL) e uma API de borda
no Cloudflare Worker.

## Quem usa

| Papel | Onde | O que faz |
|---|---|---|
| Funcionário | `mobile.html` no celular | Bate o ponto com matrícula + PIN; a localização é usada apenas no momento da batida; funciona sem internet. |
| Recepção | `quiosque.html` no tablet da portaria | Bate o ponto de quem chega (matrícula + PIN), com teclas de atalho (Enter) e sincronização automática. |
| Gestão | `admin.html` (sistemas.eemti@gmail.com) | Cadastros, manutenção de ponto, ajustes, relatórios, acessos e parâmetros. |

## As três aplicações

1. **Mobile** (`mobile.html` + `app/app.js` com `data-channel="mobile"`)
   - Exige localização: captura a posição com alta precisão (`enableHighAccuracy`,
     timeout 12 s, sem cache) e envia junto com a batida.
   - Offline-first: se não houver conexão, a batida é salva no IndexedDB (fila) e
     sincronizada quando a conexão voltar (evento `online`, botão de sincronização e
     sincronização automática no carregamento).
   - Mantém um "device id" persistente e um token offline de 72 h após o primeiro PIN,
     para autossincronizar as pendências sem pedir PIN de novo.

2. **Quiosque** (`quiosque.html` + `app/app.js` com `data-channel="kiosk"`)
   - Não exige localização (registra sem coordenadas).
   - Enter avança de matrícula para PIN e confirma a batida.
   - Sincronização automática a cada 30 s.

3. **Admin** (`admin.html` + `app/admin.js`)
   - Login com e-mail/senha do Supabase Auth; a sessão fica em `localStorage`
     (`eemti-admin-session`). Só entra quem tiver perfil `admin` ativo.
   - Fala direto com o Supabase via REST + RPCs `admin_*` (nunca usa `supabase-js`).
   - Botão "Atualizar" recarrega a página atual; todos os relatórios têm
     **Imprimir / PDF** (a impressão mostra só o relatório) e **Exportar CSV**.
   - Tema claro/escuro no login e no aplicativo.

## Páginas do Admin

| Menu | O que faz |
|---|---|
| Visão geral | KPIs (funcionários ativos, batidas hoje, fora da geocerca hoje, geocercas ativas) e últimas batidas. |
| Funcionários | CRUD: matrícula, nome, PIN, departamento, cargo, jornada; ativar/inativar. |
| Departamentos | CRUD com contagem de funcionários; impede exclusão com vínculos. |
| Cargos | CRUD com contagem de funcionários; impede exclusão com vínculos. |
| Jornadas | CRUD: entrada, saída, intervalo, carga diária, tolerância; impede exclusão com vínculos. |
| Geocercas | CRUD com latitude, longitude e raio; ativar/inativar; excluir. |
| Espelho de ponto | Todas as batidas do funcionário no mês, com previsto (entrada/saída/intervalo da jornada), origem e status da cerca. |
| Resumo mensal | KPIs, resumo por funcionário (trabalhado, esperado, saldo) e **tabela por departamento** (% cumprido). |
| Atrasos | Período → KPIs, resumo por funcionário e lista com minutos de atraso (respeita a tolerância). |
| Faltas | Período → KPIs (total, abonadas, não abonadas), resumo por funcionário e lista (faltas automáticas + registradas). |
| Assiduidade | Por funcionário e período: dias úteis, trabalhados, faltas, atrasos, saldo. |
| Fora da cerca | Período → KPIs, resumo por funcionário e lista de batidas fora da geocerca. |
| Ausências | Registro de falta/atestado/férias/folga, com abono e motivo; editar/excluir. |
| Ocorrências | Registro de ocorrências (advertência, elogio etc.), com quem registrou; editar/excluir. |
| Monitor offline | Batidas capturadas sem conexão, com horário local correto (fuso Fortaleza). |
| Batidas | Lista por período, com origem, offline, cerca, distância, status; exclusão com motivo (vira ajuste). |
| Manutenção de ponto | **Incluir batida manual** (origem `manual`, registrada em ajustes como `include`) e **batidas do funcionário** por período. |
| Feriados | CRUD de feriados (nacionais, municipais, escolares). |
| Motivos | CRUD de motivos (categorias: ajuste, falta, abono). |
| Acessos | Vincular e-mails, criar conta com senha inicial, listar/remover acessos (admin/operador); protege o próprio acesso. + **Trocar minha senha**. |
| Opções | Mensagem ao funcionário (aparece após cada batida no Mobile/Quiosque), tolerância padrão, e-mail de alerta. |

## Modelo de dados (resumo)

Tabelas principais: `employees`, `departments`, `positions`, `schedules`, `geofences`,
`devices`, `device_tokens`, `punches` (com cadeia de hash), `punch_adjustments`,
`absences`, `occurrences`, `holidays`, `reasons`, `settings`, `admin_profiles`,
`audit_events`.

Detalhes completos em [04 — Banco de dados](04_banco_de_dados.md).

## Convenções importantes

- **Fuso**: `America/Fortaleza`. Batidas são `timestamptz`; relatórios convertem sempre.
- **PIN**: guardado como hash bcrypt (`extensions.crypt`); nunca é retornado ao navegador.
- **Origem da batida**: `mobile`, `kiosk`, `mobile_offline`, `kiosk_offline`, `manual`.
- **Ajustes**: toda exclusão gera `punch_adjustments.kind='exclude'`; toda inclusão manual
  gera `kind='include'` — com autor e motivo.
- **Cadeia de hash** em `punches.previous_hash`/`hash` impede adulteração silenciosa das
  batidas; escritas são serializadas com advisory lock.

## Não faz parte (decisões da migração)

- **Campos extras do funcionário** (sexo, nascimento, salário, código de barras, endereço,
  CEP, telefones): não existiam no novo schema e não foram replicados.
- **Backup/auditoria no estilo Google Drive**: o Supabase tem backup nativo; não replicado.
- **Reset de senha de outro usuário**: exige a chave de serviço; os usuários trocam a própria
  senha pela página Acessos.
