# EEMTI Ponto — Sistema de Registro de Ponto

Sistema de ponto eletrônico da **EEMTI Monsenhor José Augusto da Silva** (Camocim/CE),
migrado do antigo Google Sheets + Apps Script para **PWA + Supabase + Cloudflare Worker**,
publicado em GitHub Pages.

| Aplicação | URL |
|---|---|
| Mobile (funcionários) | `https://sistemas-eemti.github.io/eemti-ponto-pwa/mobile.html` |
| Quiosque (recepção) | `https://sistemas-eemti.github.io/eemti-ponto-pwa/quiosque.html` |
| Admin (gestão) | `https://sistemas-eemti.github.io/eemti-ponto-pwa/admin.html` |
| API (Worker Cloudflare) | `https://eemti-ponto-api.sistemas-eemti.workers.dev/api` |

## Funcionalidades

- **Mobile**: batida com geolocalização (verificação de geocerca), funcionamento **offline**
  com fila no IndexedDB e sincronização automática, PIN criptografado, mensagem da escola
  exibida após cada batida.
- **Quiosque**: tablet fixo da recepção, layout maior, cadastro com Enter, sincronização
  automática a cada 30 s.
- **Admin**: 21 páginas — cadastros (funcionários, departamentos, cargos, jornadas,
  geocercas, feriados, motivos), manutenção de ponto (batida manual + ajustes), ocorrências,
  ausências, acessos, opções, e relatórios completos (espelho, resumo mensal com resumo por
  departamento, atrasos, faltas, assiduidade, fora da cerca, monitor offline, batidas) com
  exportação CSV e impressão/PDF, tema claro/escuro.

## Arquitetura (resumo)

```
PWA (GitHub Pages)
  Mobile / Quiosque  ──POST──▶  Cloudflare Worker  ──POST──▶  Supabase (RPC sync_punch_api)
  Admin              ────────────────────────────────▶  Supabase (REST + RPCs admin_*)
```

- **Mobile/Quiosque** não falam com o Supabase diretamente: passam pelo Worker, que guarda a
  `SERVICE_ROLE` fora do repositório e valida a origem (CORS).
- **Admin** fala direto com o Supabase usando a chave publicável (`publishable`) + token de
  sessão do usuário; **nunca** a `SERVICE_ROLE`.
- Toda a leitura/escrita administrativa é feita por **funções RPC `security definer`** que
  checam `is_admin()` — o cliente nunca faz `SELECT`/`UPDATE` direto nas tabelas.
- Fuso horário padrão: `America/Fortaleza`. Batidas são gravadas em `timestamptz` e exibidas
  sempre convertidas para esse fuso.

## Repositório

```
index.html                 redireciona para mobile.html
mobile.html / quiosque.html / admin.html   as três aplicações
app/config.js              URL pública do Worker (Mobile/Quiosque)
app/admin-config.js        URL + chave publicável do Supabase (Admin)
app/                       app.js, ponto.js, db.js, admin.js, styles.css, admin.css
sw.js / manifest.webmanifest   Service Worker e manifesto PWA
worker/                    Cloudflare Worker (wrangler.toml + src/index.js)
supabase/migrations/       22 arquivos SQL, na ordem 001 → 022
docs/                      documentação completa
CHECKLIST_TESTES.md        roteiro de testes de homologação
```

## Documentação

- [01 — Visão geral](docs/01_visao_geral.md)
- [02 — Arquitetura](docs/02_arquitetura.md)
- [03 — Implantação (Supabase + Worker + Pages)](docs/03_implantacao.md)
- [04 — Banco de dados (schema e migrations)](docs/04_banco_de_dados.md)
- [05 — Funções RPC](docs/05_funcoes_rpc.md)
- [06 — Frontend (Mobile, Quiosque e Admin)](docs/06_frontend.md)
- [07 — Segurança](docs/07_seguranca.md)
- [08 — Operação (dia a dia e problemas comuns)](docs/08_operacao.md)
- [Checklist de testes](CHECKLIST_TESTES.md)

## Implantação rápida

1. Crie o projeto no Supabase e aplique os migrations `supabase/migrations/` em ordem
   (001 → 022) no SQL Editor.
2. Crie a conta `sistemas.eemti@gmail.com` em **Authentication > Users** e rode o migration 007
   (ou cadastre o perfil admin manualmente).
3. Crie o Worker Cloudflare a partir de `worker/src/index.js` com as variáveis
   `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY`.
4. Atualize `app/config.js` (URL do Worker) e `app/admin-config.js` (URL e chave publicável
   do Supabase) se necessário.
5. Publique a branch `main` no GitHub Pages.

Passo a passo completo: [docs/03_implantacao.md](docs/03_implantacao.md).

## Segurança (não publique)

- `SUPABASE_SERVICE_ROLE_KEY` **nunca** deve ir para o repositório — fica apenas como variável
  do Worker (`SUPABASE_SERVICE_ROLE_KEY`).
- A chave `publicável` pode ficar no repositório (ela é feita para isso), mas não dá acesso
  administrativo: todo acesso é controlado por RLS + RPCs `security definer` + `is_admin()`.
