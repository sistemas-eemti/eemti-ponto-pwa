# Checklist de testes — EEMTI Ponto

Estado da implantação: o Admin usa RPCs `security definer`; PWA Mobile/Quiosque usa IndexedDB + Service Worker; Worker Cloudflare chama `sync_punch_api`.

## 0. Pré-requisitos (uma vez por ambiente)

- [ ] Aplicar no SQL Editor do Supabase, em ordem:
  1. `20260813_011_admin_catalog_rpcs.sql`
  2. `20260813_012_admin_reports_rpcs.sql`
  3. `20260813_013_admin_holidays_rpcs.sql`
  4. `20260813_014_admin_punches_rpcs.sql`
  5. `20260813_015_admin_profiles_rpcs.sql`
  6. `20260813_016_admin_geofence_employee_fixes.sql`
  7. `20260813_017_admin_report_fixes.sql`
  8. `20260813_018_admin_schedule_break.sql`
  9. `20260813_019_admin_absences_reports.sql`
  10. `20260813_020_admin_outside_attendance.sql`
- [ ] Recarregar o Admin com Ctrl+F5 (força recarregar JS/CSS novos).

## 1. Login e segurança (Admin)

- [ ] Abrir `admin.html` sem estar logado: mostra a tela de login.
- [ ] E-mail/senha errados: mensagem de erro, sem acesso.
- [ ] Login com `sistemas.eemti@gmail.com`: entra e vai para "Visão geral".
- [ ] Recarregar a página já logado: permanece autenticado (sessão em localStorage).
- [ ] "Sair" encerra a sessão e volta para o login.
- [ ] Uma conta sem perfil admin vinculado não entra (mensagem "sem acesso administrativo").

## 2. Cadastros básicos (Admin)

- [ ] Departamentos: criar, editar, listar (coluna "Funcionários" atualiza), excluir.
- [ ] Cargos: criar, editar, listar, excluir.
- [ ] Jornadas: criar (nome, entrada, saída, **intervalo**, carga diária, tolerância), editar, excluir.
- [ ] Funcionário: cadastrar com matrícula, nome, PIN, departamento, cargo e jornada.
- [ ] **Editar funcionário**: clicar "Editar" preenche o formulário; salvar sem PIN mantém o PIN atual; alterar PIN troca o PIN.
- [ ] Ativar/inativar funcionário pela coluna "Ações".
- [ ] Geocercas: criar com nome, latitude, longitude, raio; listar; **inativar/ativar; excluir**.
- [ ] Feriados: criar (data, descrição, tipo), listar, excluir.
- [ ] Acessos: vincular outro e-mail; **criar a conta direto do Admin informando senha inicial**; listar; remover.
- [ ] Acessos: tentar inativar/alterar o próprio acesso → bloqueado.
- [ ] Ausências: registrar falta/atestado/férias/folga (data, tipo, abonada, motivo), editar, excluir, listar.

## 3. Mobile — online

- [ ] Abrir `mobile.html` no celular; mostrar relógio e data.
- [ ] Batida com matrícula + PIN corretos: mensagem "Batida registrada."
- [ ] Batida dentro da geocerca: sem aviso (ou "Dentro").
- [ ] Batida fora da geocerca: registrada com aviso "Fora da cerca" (e mensagem).
- [ ] PIN errado: mensagem de erro, sem registrar.
- [ ] Matrícula inexistente: mensagem de erro.
- [ ] Segunda batida imediata: "Batida repetida..." sem duplicar.

## 4. Mobile — offline

- [ ] Ativar modo avião no celular, abrir o app (ainda carrega).
- [ ] Bater o ponto offline: mensagem "Batida salva neste aparelho" e contador de pendentes.
- [ ] Desligar modo avião e tocar em "Sincronizar batidas pendentes": pendência some.
- [ ] No Admin → "Monitor offline": batida aparece com origem `mobile_offline` e data de sincronização.
- [ ] No Admin → "Batidas": registro presente e com status "Ativa".

## 5. Quiosque (tablet fixo da recepção)

- [ ] Abrir `quiosque.html`; layout maior.
- [ ] Bater ponto com PIN: registrado.
- [ ] Testar tecla Enter passando da matrícula para o PIN e registrando.
- [ ] Deixar aberto; confirmar sincronização automática (30s).
- [ ] Canal registrado como `kiosk` no Admin (origem `kiosk`).

## 6. Relatórios (Admin)

- [ ] Espelho de ponto: **lista TODAS as batidas do mês** (data, hora, entrada/saída previstas, **intervalo da jornada**, origem, dentro/fora da cerca).
- [ ] Resumo mensal: dias trabalhados, faltas, atrasos, horas trabalhadas/esperadas e saldo por funcionário + KPIs (funcionários, dias úteis, faltas, atrasos).
- [ ] Atrasos: período → KPIs (funcionários com atraso, total, minutos) + resumo por funcionário + lista com minutos de atraso.
- [ ] Faltas: período → KPIs (faltas, abonadas, não abonadas, funcionários) + resumo por funcionário + lista (automáticas e registradas).
- [ ] Assiduidade: escolher funcionário e período → dias úteis, dias trabalhados, faltas, atrasos, total trabalhado, esperado e saldo.
- [ ] Fora da cerca: período → KPIs + resumo por funcionário + lista de batidas fora (data, hora, origem, distância).
- [ ] Monitor offline: lista apenas batidas capturadas sem conexão, **com horário local correto (fuso Fortaleza)**.
- [ ] Dashboard: "Últimas batidas" com horário local correto.
- [ ] Batidas: listar por período; excluir uma batida com motivo; confirmar que aparece "Excluída".
- [ ] Exportar: "Exportar CSV" baixa arquivo com os dados da tabela atual.
- [ ] Imprimir/PDF: abre impressão mostrando somente o relatório (sem menu).

## 7. Integração / dados

- [ ] Batida do Mobile aparece no Dashboard (últimas batidas, contadores).
- [ ] Batida fora da geocerca aparece no contador "Fora da geocerca hoje".
- [ ] Funcionário inativo não bate ponto (tentar validar).
- [ ] Depois de excluir batida, relatório de espelho/resumo não a considera.

## 8. Regressão / versões de cache

- [ ] Sempre recarregar com Ctrl+F5 após publicar mudanças.
- [ ] Service Worker atualiza sozinho (caches antigos removidos no próximo load).

## 9. Produção

- [ ] Obter coordenadas exatas da escola (Camocim/CE) e ajustar a geocerca real.
- [ ] Cadastrar todos os funcionários e jornadas reais.
- [ ] Distribuir o PWA aos funcionários (ícone "Adicionar à tela inicial").
- [ ] Definir feriados nacionais/municipais/escolares.
- [ ] Validar com uma semana de uso real antes de desligar o sistema legado (Sheets/Apps Script).

## Observações

- PIN não fica salvo no aparelho: batidas offline de um aparelho novo precisam de PIN na 1ª sincronização manual; depois o token permite autossincronização.
- Horários e relatórios usam fuso `America/Fortaleza`.
- Nunca publicar `SUPABASE_SERVICE_ROLE_KEY` no repositório (fica apenas na variável do Worker).
