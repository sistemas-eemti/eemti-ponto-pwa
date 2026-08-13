(() => {
const sessionKey = 'eemti-admin-session';
function savedSession() { try { return JSON.parse(localStorage.getItem(sessionKey)); } catch (_) { return null; } }
async function request(url, options = {}) {
  const response = await fetch(url, options);
  const data = await response.json().catch(() => null);
  return { data, error: response.ok ? null : data || { message: 'Falha na comunicação com o Supabase.' } };
}
const supabase = {
  auth: {
    async getSession() { return { data: { session: savedSession() } }; },
    async signInWithPassword({ email, password }) {
      const result = await request(`${window.ADMIN_CONFIG.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
        method: 'POST', headers: { apikey: window.ADMIN_CONFIG.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password })
      });
      if (!result.error) localStorage.setItem(sessionKey, JSON.stringify(result.data));
      return { error: result.error };
    },
    async signOut() { localStorage.removeItem(sessionKey); return { error: null }; }
  },
  async rpc(name, args = {}) {
    const session = savedSession();
    if (!session?.access_token) return { data: null, error: { message: 'Sessão expirada. Entre novamente.' } };
    return request(`${window.ADMIN_CONFIG.SUPABASE_URL}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { apikey: window.ADMIN_CONFIG.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args)
    });
  }
};
const $ = id => document.getElementById(id);
const pageTitles = { dashboard: 'Visão geral', employees: 'Funcionários', departments: 'Departamentos', positions: 'Cargos', schedules: 'Jornadas', geofences: 'Geocercas', espelho: 'Espelho de ponto', resumo: 'Resumo mensal', atrasos: 'Atrasos', faltas: 'Faltas', assiduidade: 'Assiduidade', 'fora-cerca': 'Fora da cerca', ausencias: 'Ausências', ocorrencias: 'Ocorrências', offline: 'Monitor offline', batidas: 'Batidas', manutencao: 'Manutenção de ponto', holidays: 'Feriados', motivos: 'Motivos', profiles: 'Acessos', opcoes: 'Opções' };

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  const label = theme === 'dark' ? 'Tema claro' : 'Tema escuro';
  $('theme').textContent = label;
  const loginTheme = $('login-theme'); if (loginTheme) loginTheme.textContent = label;
  try { localStorage.setItem('eemti-admin-theme', theme); } catch (_) {}
}
function toggleTheme() { applyTheme((document.documentElement.getAttribute('data-theme') || 'light') === 'dark' ? 'light' : 'dark'); }
(function () { let t = null; try { t = localStorage.getItem('eemti-admin-theme'); } catch (_) {} applyTheme(t === 'dark' ? 'dark' : 'light'); })();

function message(text = '', error = false) { const el = $('app-message'); el.textContent = text; el.style.color = error ? 'var(--red)' : 'var(--green)'; }
function optionList(id, rows, label) { $(id).innerHTML = '<option value="">Nenhum</option>' + rows.map(row => `<option value="${row.id}">${escapeHtml(row[label])}</option>`).join(''); }
function escapeHtml(value) { const el = document.createElement('span'); el.textContent = value ?? ''; return el.innerHTML; }
function actionButtons(cells) { return cells.map(cell => `<button class="mini" type="button" data-action="${cell.action}" data-id="${cell.id ?? ''}" data-name="${escapeAttr(cell.name ?? '')}" data-enrollment="${escapeAttr(cell.enrollment ?? '')}" data-active="${cell.active ?? ''}" data-date="${cell.date ?? ''}">${cell.label}</button>`).join(''); }
function timeOnly(value) { return value ? value.slice(0, 5) : ''; }
function todayRange() { const date = new Date(); date.setHours(0, 0, 0, 0); return date.toISOString(); }

async function requireAdmin() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return false;
  const { data: isAdmin, error } = await supabase.rpc('is_admin');
  if (error || !isAdmin) { await supabase.auth.signOut(); $('login-message').textContent = 'Esta conta não possui acesso administrativo.'; return false; }
  $('account-name').textContent = session.user.email;
  $('login-view').hidden = true; $('app-view').hidden = false;
  return true;
}

async function loadDashboard() {
  const { data, error } = await supabase.rpc('admin_dashboard'); if (error) throw error;
  $('total-employees').textContent = data.employees || 0; $('today-punches').textContent = data.punches || 0; $('outside-punches').textContent = data.outside || 0; $('active-geofences').textContent = data.geofences || 0;
  $('recent-punches').innerHTML = data.recent.map(row => `<tr><td>${escapeHtml(row.captured_at)}</td><td>${escapeHtml(row.name || '-')} ${row.enrollment ? `<span class="muted">${escapeHtml(row.enrollment)}</span>` : ''}</td><td>${escapeHtml(row.origin)}</td><td>${row.inside_geofence === false ? '<span class="badge">Fora da cerca</span>' : 'Dentro / não verificado'}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">Nenhuma batida registrada.</td></tr>';
}

async function loadEmployees() {
  const [employees, options] = await Promise.all([supabase.rpc('admin_list_employees'), supabase.rpc('admin_employee_options')]);
  if (employees.error) throw employees.error; if (options.error) throw options.error;
  optionList('employee-department', options.data.departments, 'name'); optionList('employee-position', options.data.positions, 'name'); optionList('employee-schedule', options.data.schedules, 'name');
  $('employees-list').dataset.rows = JSON.stringify(employees.data);
  $('employees-list').innerHTML = employees.data.map(row => `<tr><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.department || '-')}</td><td><span class="badge${row.active ? '' : ' off'}">${row.active ? 'Ativo' : 'Inativo'}</span></td><td>${actionButtons([{ label: 'Editar', action: 'edit-employee', enrollment: row.enrollment }, { label: row.active ? 'Inativar' : 'Ativar', action: 'toggle-employee', enrollment: row.enrollment, active: !row.active }])}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhum funcionário cadastrado.</td></tr>';
}

async function loadDepartments() {
  const { data, error } = await supabase.rpc('admin_list_departments'); if (error) throw error;
  $('departments-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.employees || 0}</td><td>${actionButtons([{ label: 'Editar', action: 'edit-department', id: row.id, name: row.name }, { label: 'Excluir', action: 'delete-department', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">Nenhum departamento cadastrado.</td></tr>';
}

async function loadPositions() {
  const { data, error } = await supabase.rpc('admin_list_positions'); if (error) throw error;
  $('positions-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.employees || 0}</td><td>${actionButtons([{ label: 'Editar', action: 'edit-position', id: row.id, name: row.name }, { label: 'Excluir', action: 'delete-position', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">Nenhum cargo cadastrado.</td></tr>';
}

async function loadSchedules() {
  const { data, error } = await supabase.rpc('admin_list_schedules'); if (error) throw error;
  $('schedules-list').dataset.rows = JSON.stringify(data);
  $('schedules-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.entry_time ? escapeHtml(timeOnly(row.entry_time)) : '-'}</td><td>${row.exit_time ? escapeHtml(timeOnly(row.exit_time)) : '-'}</td><td>${row.break_start ? `${escapeHtml(timeOnly(row.break_start))} - ${escapeHtml(timeOnly(row.break_end))}` : '-'}</td><td>${row.daily_minutes} min</td><td>${row.tolerance_minutes} min</td><td>${actionButtons([{ label: 'Editar', action: 'edit-schedule', id: row.id }, { label: 'Excluir', action: 'delete-schedule', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="7" class="muted">Nenhuma jornada cadastrada.</td></tr>';
}

function escapeAttr(value) { return escapeHtml(String(value ?? '').replace(/'/g, '\\')); }

function editDepartment(id, name) { $('department-id').value = id; $('department-name').value = name; }
function editPosition(id, name) { $('position-id').value = id; $('position-name').value = name; }
function editSchedule(id) {
  const rows = JSON.parse($('schedules-list').dataset.rows || '[]');
  const row = rows.find(item => item.id === id);
  if (!row) return;
  $('schedule-id').value = row.id; $('schedule-name').value = row.name;
  $('schedule-entry').value = timeOnly(row.entry_time); $('schedule-exit').value = timeOnly(row.exit_time);
  $('schedule-break-start').value = timeOnly(row.break_start); $('schedule-break-end').value = timeOnly(row.break_end);
  $('schedule-minutes').value = row.daily_minutes; $('schedule-tolerance').value = row.tolerance_minutes;
}

async function toggleEmployee(enrollment, active) {
  const { error } = await supabase.rpc('admin_set_employee_active', { p_enrollment: enrollment, p_active: active });
  if (error) { message(error.message, true); return; }
  message(active ? 'Funcionário ativado.' : 'Funcionário inativado.'); await loadEmployees();
}

function editEmployee(enrollment) {
  const rows = JSON.parse($('employees-list').dataset.rows || '[]');
  const row = rows.find(item => item.enrollment === enrollment);
  if (!row) return;
  $('employee-enrollment').value = row.enrollment;
  $('employee-name').value = row.name;
  $('employee-pin').value = '';
  $('employee-department').value = row.department_id || '';
  $('employee-position').value = row.position_id || '';
  $('employee-schedule').value = row.schedule_id || '';
  message('Editando funcionário. Deixe o PIN em branco para manter o atual.');
}

function clearEmployee() { const form = $('employee-form'); form.reset(); message(''); }

async function toggleGeofence(id, active) {
  const { error } = await supabase.rpc('admin_set_geofence_active', { p_id: id, p_active: active });
  if (error) { message(error.message, true); return; }
  message(active ? 'Geocerca ativada.' : 'Geocerca inativada.'); await loadGeofences();
}

async function deleteGeofence(id) {
  if (!confirm('Excluir esta geocerca?')) return;
  const { error } = await supabase.rpc('admin_delete_geofence', { p_id: id });
  if (error) { message(error.message, true); return; }
  message('Geocerca excluída.'); await loadGeofences();
}

async function saveDepartment(event) { event.preventDefault(); const { error } = await supabase.rpc('admin_save_department', { p_id: $('department-id').value || null, p_name: $('department-name').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Departamento salvo.'); await loadDepartments(); }
async function savePosition(event) { event.preventDefault(); const { error } = await supabase.rpc('admin_save_position', { p_id: $('position-id').value || null, p_name: $('position-name').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Cargo salvo.'); await loadPositions(); }
async function saveSchedule(event) { event.preventDefault(); const { error } = await supabase.rpc('admin_save_schedule', { p_id: $('schedule-id').value || null, p_name: $('schedule-name').value, p_entry_time: $('schedule-entry').value, p_exit_time: $('schedule-exit').value, p_break_start: $('schedule-break-start').value, p_break_end: $('schedule-break-end').value, p_daily_minutes: $('schedule-minutes').value, p_tolerance_minutes: $('schedule-tolerance').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Jornada salva.'); await loadSchedules(); }
async function deleteDepartment(id) { if (!confirm('Excluir este departamento?')) return; const { error } = await supabase.rpc('admin_delete_department', { p_id: id }); if (error) { message(error.message, true); return; } message('Departamento excluído.'); await loadDepartments(); }
async function deletePosition(id) { if (!confirm('Excluir este cargo?')) return; const { error } = await supabase.rpc('admin_delete_position', { p_id: id }); if (error) { message(error.message, true); return; } message('Cargo excluído.'); await loadPositions(); }
async function deleteSchedule(id) { if (!confirm('Excluir esta jornada?')) return; const { error } = await supabase.rpc('admin_delete_schedule', { p_id: id }); if (error) { message(error.message, true); return; } message('Jornada excluída.'); await loadSchedules(); }

async function loadGeofences() {
  const { data, error } = await supabase.rpc('admin_list_geofences'); if (error) throw error;
  $('geofences-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.latitude}, ${row.longitude}</td><td>${row.radius_meters} m</td><td><span class="badge${row.active ? '' : ' off'}">${row.active ? 'Ativa' : 'Inativa'}</span></td><td>${actionButtons([{ label: row.active ? 'Inativar' : 'Ativar', action: 'toggle-geofence', id: row.id, active: !row.active }, { label: 'Excluir', action: 'delete-geofence', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhuma geocerca cadastrada.</td></tr>';
}

async function loadPage(page) { message(); if (page === 'dashboard') await loadDashboard(); if (page === 'employees') await loadEmployees(); if (page === 'departments') await loadDepartments(); if (page === 'positions') await loadPositions(); if (page === 'schedules') await loadSchedules(); if (page === 'geofences') await loadGeofences(); if (page === 'espelho') await loadEspelho(); if (page === 'resumo') await loadResumo(); if (page === 'atrasos') await loadAtrasos(); if (page === 'faltas') await loadFaltas(); if (page === 'assiduidade') await loadAssiduidade(); if (page === 'fora-cerca') await loadForaCerca(); if (page === 'ausencias') await loadAbsences(); if (page === 'ocorrencias') await loadOccurrences(); if (page === 'offline') await loadOffline(); if (page === 'batidas') await loadBatidas(); if (page === 'manutencao') await loadManutencao(); if (page === 'holidays') await loadHolidays(); if (page === 'motivos') await loadReasons(); if (page === 'profiles') await loadProfiles(); if (page === 'opcoes') await loadSettings(); }

function monthInput(id) { const value = new Date().toISOString().slice(0, 7); $(id).value = value; return value; }
function todayInputs(startId, endId) { const end = new Date(); const start = new Date(end.getFullYear(), end.getMonth(), 1); $(endId).value = end.toISOString().slice(0, 10); $(startId).value = start.toISOString().slice(0, 10); }

async function loadEspelho() {
  const { data, error } = await supabase.rpc('admin_list_employees'); if (error) throw error;
  const select = $('espelho-employee');
  select.innerHTML = data.map(row => `<option value="${escapeAttr(row.enrollment)}">${escapeHtml(row.name)}</option>`).join('') || '<option value="">Nenhum funcionário</option>';
  monthInput('espelho-month');
}

function loadResumo() { monthInput('resumo-month'); }
function loadAtrasos() { todayInputs('atrasos-start', 'atrasos-end'); }
function loadFaltas() { todayInputs('faltas-start', 'faltas-end'); }

async function loadAssiduidade() {
  const { data, error } = await supabase.rpc('admin_list_employees'); if (error) throw error;
  const select = $('assiduidade-employee');
  select.innerHTML = data.map(row => `<option value="${escapeAttr(row.enrollment)}">${escapeHtml(row.name)}</option>`).join('') || '<option value="">Nenhum funcionário</option>';
  todayInputs('assiduidade-start', 'assiduidade-end');
}
function loadForaCerca() { todayInputs('fora-cerca-start', 'fora-cerca-end'); }

async function runEspelho() {
  const { data, error } = await supabase.rpc('admin_espelho', { p_enrollment: $('espelho-employee').value, p_month: $('espelho-month').value + '-01' });
  if (error) { message(error.message, true); return; }
  const rows = data.rows || [];
  $('espelho-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.dia)}</td><td>${escapeHtml(row.hora)}</td><td>${escapeHtml(row.entrada_prevista || '-')}</td><td>${escapeHtml(row.saida_prevista || '-')}</td><td>${escapeHtml(row.intervalo || '-')}</td><td>${escapeHtml(row.origin)}${row.captured_offline ? ' (offline)' : ''}</td><td>${escapeHtml(row.cerca)}</td></tr>`).join('') || '<tr><td colspan="7" class="muted">Sem batidas no período.</td></tr>';
}

async function runResumo() {
  const { data, error } = await supabase.rpc('admin_resumo_mensal', { p_month: $('resumo-month').value + '-01' });
  if (error) { message(error.message, true); return; }
  const rows = data.rows || [];
  renderKpis('resumo-kpis', [
    ['Funcionários ativos', rows.length],
    ['Dias úteis', data.dias_uteis || 0],
    ['Faltas', rows.reduce((sum, row) => sum + (row.faltas || 0), 0)],
    ['Atrasos', rows.reduce((sum, row) => sum + (row.atrasos || 0), 0)]
  ]);
  $('resumo-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.department || '-')}</td><td>${row.dias_trabalhados}</td><td>${row.faltas}</td><td>${row.atrasos}</td><td>${hours(row.minutos_trabalhados)}</td><td>${hours(row.minutos_esperados)}</td><td class="${row.saldo_minutos < 0 ? 'danger' : ''}">${hours(row.saldo_minutos)}</td></tr>`).join('') || '<tr><td colspan="8" class="muted">Sem funcionários ativos.</td></tr>';
  $('resumo-deptos-list').innerHTML = (data.departamentos || []).map(row => `<tr><td>${escapeHtml(row.nome)}</td><td>${row.funcionarios}</td><td>${hours(row.trabalhado_min)}</td><td>${hours(row.esperado_min)}</td><td>${row.esperado_min > 0 ? Math.round(row.trabalhado_min * 100 / row.esperado_min) + '%' : '—'}</td><td class="${row.saldo_min < 0 ? 'danger' : ''}">${hours(row.saldo_min)}</td></tr>`).join('') || '<tr><td colspan="6" class="muted">Sem departamentos.</td></tr>';
}

async function runAtrasos() {
  const { data, error } = await supabase.rpc('admin_rel_atrasos', { p_start: $('atrasos-start').value, p_end: $('atrasos-end').value });
  if (error) { message(error.message, true); return; }
  renderKpis('atrasos-kpis', [
    ['Funcionários com atraso', data.resumo?.funcionarios_com_atraso || 0],
    ['Total de atrasos', data.resumo?.total_atrasos || 0],
    ['Minutos perdidos', (data.resumo?.total_minutos || 0) + ' min']
  ]);
  $('atrasos-func-list').innerHTML = (data.por_funcionario || []).map(row => `<tr><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.department || '-')}</td><td>${row.atrasos}</td><td>${Math.round(row.minutos_atraso)} min</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhum atraso no período.</td></tr>';
  $('atrasos-list').innerHTML = (data.lista || []).map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.previsto)}</td><td>${escapeHtml(row.dia)}</td><td>${escapeHtml(row.batida)}</td><td>${row.atraso_min} min</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhum atraso no período.</td></tr>';
}

async function runFaltas() {
  const { data, error } = await supabase.rpc('admin_rel_faltas', { p_start: $('faltas-start').value, p_end: $('faltas-end').value });
  if (error) { message(error.message, true); return; }
  renderKpis('faltas-kpis', [
    ['Faltas', data.resumo?.total_faltas || 0],
    ['Abonadas', data.resumo?.abonadas || 0],
    ['Não abonadas', data.resumo?.nao_abonadas || 0],
    ['Funcionários', data.resumo?.funcionarios || 0]
  ]);
  $('faltas-func-list').innerHTML = (data.por_funcionario || []).map(row => `<tr><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${row.total}</td><td>${row.abonadas}</td><td class="${row.nao_abonadas > 0 ? 'danger' : ''}">${row.nao_abonadas}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhuma falta no período.</td></tr>';
  $('faltas-list').innerHTML = (data.lista || []).map(row => `<tr><td>${escapeHtml(row.dia)}</td><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.automatica ? 'Falta (automática)' : row.tipo)}</td><td>${row.excused ? '<span class="badge">Abonada</span>' : '<span class="badge off">Não abonada</span>'}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhuma falta no período.</td></tr>';
}

function renderKpis(containerId, items) {
  $(containerId).innerHTML = items.map(item => `<article><strong>${item[1]}</strong><span>${item[0]}</span></article>`).join('');
}

async function runAssiduidade() {
  const { data, error } = await supabase.rpc('admin_assiduidade', { p_enrollment: $('assiduidade-employee').value, p_start: $('assiduidade-start').value, p_end: $('assiduidade-end').value });
  if (error) { message(error.message, true); return; }
  const rows = [
    ['Funcionário', data.name], ['Matrícula', data.enrollment], ['Jornada', data.jornada || '-'],
    ['Dias úteis', data.dias_uteis], ['Dias trabalhados', data.dias_trabalhados], ['Faltas', data.faltas],
    ['Atrasos', data.atrasos], ['Total trabalhado', hours(data.total_min)],
    ['Esperado', hours(data.esperado_min)], ['Saldo', hours(data.saldo_min)]
  ];
  $('assiduidade-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row[0])}</td><td class="${row[0] === 'Saldo' && data.saldo_min < 0 ? 'danger' : ''}">${escapeHtml(row[1])}</td></tr>`).join('');
}

async function runForaCerca() {
  const { data, error } = await supabase.rpc('admin_rel_fora_cerca', { p_start: $('fora-cerca-start').value, p_end: $('fora-cerca-end').value });
  if (error) { message(error.message, true); return; }
  renderKpis('fora-cerca-kpis', [
    ['Batidas fora', data.resumo?.total_batidas || 0],
    ['Funcionários', data.resumo?.funcionarios_envolvidos || 0]
  ]);
  $('fora-cerca-func-list').innerHTML = (data.por_funcionario || []).map(row => `<tr><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${row.total}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">Nenhuma batida fora da cerca.</td></tr>';
  $('fora-cerca-list').innerHTML = (data.lista || []).map(row => `<tr><td>${escapeHtml(row.dia)}</td><td>${escapeHtml(row.hora)}</td><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.origin)}</td><td>${row.distance_meters != null ? Math.round(row.distance_meters) + ' m' : '-'}</td></tr>`).join('') || '<tr><td colspan="6" class="muted">Nenhuma batida fora da cerca.</td></tr>';
}

async function loadOffline() {
  const { data, error } = await supabase.rpc('admin_monitor_offline'); if (error) throw error;
  const rows = data.rows || [];
  $('offline-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.origin)}</td><td>${escapeHtml(row.captured_at)}</td><td>${escapeHtml(row.synced_at || '-')}</td><td>${escapeHtml(row.client_record_id || '-')}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhuma batida offline registrada.</td></tr>';
}

function hours(minutes) { const m = Math.abs(minutes || 0); return `${minutes < 0 ? '-' : ''}${String(Math.floor(m / 60)).padStart(2, '0')}:${String(Math.round(m % 60)).padStart(2, '0')}`; }

function loadBatidas() { todayInputs('batidas-start', 'batidas-end'); }

async function runBatidas() {
  const { data, error } = await supabase.rpc('admin_list_punches', { p_start: $('batidas-start').value, p_end: $('batidas-end').value });
  if (error) { message(error.message, true); return; }
  const rows = data.rows || [];
  $('batidas-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.captured_at)}</td><td>${escapeHtml(row.name)} (${escapeHtml(row.enrollment)})</td><td>${escapeHtml(row.origin)}</td><td>${row.captured_offline ? 'Sim' : 'Não'}</td><td>${row.inside_geofence === false ? 'Fora' : row.inside_geofence === true ? 'Dentro' : '-'}</td><td>${row.distance_meters != null ? `${row.distance_meters} m` : '-'}</td><td>${row.excluded ? '<span class="badge">Excluída</span>' : 'Ativa'}</td><td>${row.excluded ? '' : actionButtons([{ label: 'Excluir', action: 'delete-punch', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="8" class="muted">Nenhuma batida no período.</td></tr>';
}

async function deletePunch(id) {
  const reason = prompt('Motivo da exclusão desta batida:');
  if (!reason) return;
  const { error } = await supabase.rpc('admin_delete_punch', { p_id: id, p_reason: reason.trim() });
  if (error) { message(error.message, true); return; }
  message('Batida excluída.'); if ($('manutencao-page').classList.contains('active')) await runManutencao(); else await runBatidas();
}

function loadManutencao() {
  todayInputs('manut-start', 'manut-end');
  const now = new Date(); now.setMinutes(now.getMinutes() - now.getTimezoneOffset());
  $('manut-datetime').value = now.toISOString().slice(0, 16);
}

async function saveManualPunch() {
  const { data, error } = await supabase.rpc('admin_add_manual_punch', {
    p_enrollment: $('manut-enrollment').value.trim(),
    p_captured_at: $('manut-datetime').value ? new Date($('manut-datetime').value).toISOString() : null,
    p_reason: $('manut-reason').value.trim() || null
  });
  if (error) { message(error.message, true); return; }
  message(data?.message || 'Batida manual incluída.');
  $('manut-reason').value = ''; $('manut-enrollment').value = '';
  if ($('manut-enrollment-list').value.trim()) await runManutencao();
}

async function runManutencao() {
  const { data, error } = await supabase.rpc('admin_list_employee_punches', {
    p_enrollment: $('manut-enrollment-list').value.trim(),
    p_start: $('manut-start').value, p_end: $('manut-end').value
  });
  if (error) { message(error.message, true); return; }
  const rows = data.rows || [];
  $('manut-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.captured_at)}</td><td>${escapeHtml(row.name)} (${escapeHtml(row.enrollment)})</td><td>${escapeHtml(row.origin)}</td><td>${row.captured_offline ? 'Sim' : 'Não'}</td><td>${row.inside_geofence === false ? 'Fora' : row.inside_geofence === true ? 'Dentro' : '-'}</td><td>${row.distance_meters != null ? `${row.distance_meters} m` : '-'}</td><td>${row.excluded ? '<span class="badge">Excluída</span>' : 'Ativa'}</td><td>${row.excluded ? '' : actionButtons([{ label: 'Excluir', action: 'delete-punch', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="8" class="muted">Nenhuma batida para este funcionário no período.</td></tr>';
}

async function loadAbsences() {
  const end = new Date(); const start = new Date(end.getFullYear(), end.getMonth(), 1);
  const { data, error } = await supabase.rpc('admin_list_absences', { p_start: start.toISOString().slice(0, 10), p_end: end.toISOString().slice(0, 10) });
  if (error) throw error;
  const rows = data || [];
  $('absences-list').dataset.rows = JSON.stringify(rows);
  $('absences-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.absence_date)}</td><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.type)}</td><td>${row.excused ? '<span class="badge">Sim</span>' : '<span class="badge off">Não</span>'}</td><td>${escapeHtml(row.reason || '-')}</td><td>${actionButtons([{ label: 'Editar', action: 'edit-absence', id: row.id }, { label: 'Excluir', action: 'delete-absence', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="7" class="muted">Nenhuma ausência registrada no mês.</td></tr>';
}

function clearAbsence() { $('absence-form').reset(); $('absence-id').value = ''; message(''); }

function editAbsence(id) {
  const rows = JSON.parse($('absences-list').dataset.rows || '[]');
  const row = rows.find(item => item.id === id);
  if (!row) return;
  $('absence-id').value = row.id; $('absence-enrollment').value = row.enrollment;
  $('absence-date').value = row.absence_date.split('/').reverse().join('-');
  $('absence-type').value = row.type;
  $('absence-excused').checked = row.excused;
  $('absence-reason').value = row.reason || '';
  message('Editando ausência.');
}

async function saveAbsence(event) {
  event.preventDefault();
  const { error } = await supabase.rpc('admin_save_absence', {
    p_id: $('absence-id').value || null,
    p_enrollment: $('absence-enrollment').value.trim(),
    p_date: $('absence-date').value,
    p_type: $('absence-type').value,
    p_reason: $('absence-reason').value,
    p_excused: $('absence-excused').checked
  });
  if (error) { message(error.message, true); return; }
  clearAbsence(); message('Ausência salva.'); await loadAbsences();
}

async function deleteAbsence(id) {
  if (!confirm('Excluir esta ausência?')) return;
  const { error } = await supabase.rpc('admin_delete_absence', { p_id: id });
  if (error) { message(error.message, true); return; }
  message('Ausência excluída.'); await loadAbsences();
}

async function loadOccurrences() {
  const end = new Date(); const start = new Date(end.getFullYear(), end.getMonth() - 2, 1);
  const { data, error } = await supabase.rpc('admin_list_occurrences', { p_start: start.toISOString().slice(0, 10), p_end: end.toISOString().slice(0, 10) });
  if (error) throw error;
  const rows = data || [];
  $('occurrences-list').dataset.rows = JSON.stringify(rows);
  $('occurrences-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.occurrence_date)}</td><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.type)}</td><td>${escapeHtml(row.description)}</td><td>${escapeHtml(row.recorded_by || '-')}</td><td>${actionButtons([{ label: 'Editar', action: 'edit-occurrence', id: row.id }, { label: 'Excluir', action: 'delete-occurrence', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="7" class="muted">Nenhuma ocorrência registrada no período.</td></tr>';
}

function clearOccurrence() { $('occurrence-form').reset(); $('occurrence-id').value = ''; message(''); }

function editOccurrence(id) {
  const rows = JSON.parse($('occurrences-list').dataset.rows || '[]');
  const row = rows.find(item => item.id === id);
  if (!row) return;
  $('occurrence-id').value = row.id; $('occurrence-enrollment').value = row.enrollment;
  $('occurrence-date').value = row.occurrence_date.split('/').reverse().join('-');
  $('occurrence-type').value = row.type; $('occurrence-description').value = row.description;
  message('Editando ocorrência.');
}

async function saveOccurrence(event) {
  event.preventDefault();
  const { error } = await supabase.rpc('admin_save_occurrence', {
    p_id: $('occurrence-id').value || null,
    p_enrollment: $('occurrence-enrollment').value.trim(),
    p_date: $('occurrence-date').value,
    p_type: $('occurrence-type').value.trim(),
    p_description: $('occurrence-description').value.trim()
  });
  if (error) { message(error.message, true); return; }
  clearOccurrence(); message('Ocorrência salva.'); await loadOccurrences();
}

async function deleteOccurrence(id) {
  if (!confirm('Excluir esta ocorrência?')) return;
  const { error } = await supabase.rpc('admin_delete_occurrence', { p_id: id });
  if (error) { message(error.message, true); return; }
  message('Ocorrência excluída.'); await loadOccurrences();
}

async function loadReasons() {
  const { data, error } = await supabase.rpc('admin_list_reasons'); if (error) throw error;
  const rows = data || [];
  $('reasons-list').dataset.rows = JSON.stringify(rows);
  $('reasons-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.description)}</td><td>${escapeHtml(row.category)}</td><td><span class="badge${row.active ? '' : ' off'}">${row.active ? 'Ativo' : 'Inativo'}</span></td><td>${actionButtons([{ label: 'Editar', action: 'edit-reason', id: row.id }, { label: 'Excluir', action: 'delete-reason', id: row.id }])}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">Nenhum motivo cadastrado.</td></tr>';
}

function clearReason() { $('reason-form').reset(); $('reason-id').value = ''; $('reason-active').checked = true; message(''); }

function editReason(id) {
  const rows = JSON.parse($('reasons-list').dataset.rows || '[]');
  const row = rows.find(item => item.id === id);
  if (!row) return;
  $('reason-id').value = row.id; $('reason-description').value = row.description;
  $('reason-category').value = row.category; $('reason-active').checked = row.active;
  message('Editando motivo.');
}

async function saveReason(event) {
  event.preventDefault();
  const { error } = await supabase.rpc('admin_save_reason', {
    p_id: $('reason-id').value || null,
    p_description: $('reason-description').value.trim(),
    p_category: $('reason-category').value,
    p_active: $('reason-active').checked
  });
  if (error) { message(error.message, true); return; }
  clearReason(); message('Motivo salvo.'); await loadReasons();
}

async function deleteReason(id) {
  if (!confirm('Excluir este motivo?')) return;
  const { error } = await supabase.rpc('admin_delete_reason', { p_id: id });
  if (error) { message(error.message, true); return; }
  message('Motivo excluído.'); await loadReasons();
}

async function loadSettings() {
  const { data, error } = await supabase.rpc('admin_list_settings'); if (error) throw error;
  const rows = data || [];
  $('settings-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.key)}</td><td>${escapeHtml(row.value)}</td><td>${escapeHtml(row.updated_at || '-')}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">Nenhum parâmetro cadastrado.</td></tr>';
  rows.forEach(row => {
    if (row.key === 'mensagem_funcionario') $('setting-message').value = row.value;
    if (row.key === 'tolerancia_padrao') $('setting-tolerance').value = row.value;
    if (row.key === 'email_alertas') $('setting-alert-email').value = row.value;
  });
}

async function saveSetting(key, inputId) {
  const { error } = await supabase.rpc('admin_save_setting', { p_key: key, p_value: $(inputId).value.trim() });
  if (error) { message(error.message, true); return; }
  message('Parâmetro salvo.'); await loadSettings();
}

async function changePassword() {
  const password = $('password-new').value;
  if (!password || password.length < 6) { message('A nova senha deve ter ao menos 6 caracteres.', true); return; }
  if (password !== $('password-confirm').value) { message('As senhas não conferem.', true); return; }
  const session = savedSession();
  if (!session?.access_token) { message('Sessão expirada. Entre novamente.', true); return; }
  const result = await request(`${window.ADMIN_CONFIG.SUPABASE_URL}/auth/v1/user`, {
    method: 'PUT', headers: { apikey: window.ADMIN_CONFIG.SUPABASE_PUBLISHABLE_KEY, Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ password })
  });
  if (result.error) { message(result.error.msg || result.error.message || 'Não foi possível atualizar a senha.', true); return; }
  $('password-new').value = ''; $('password-confirm').value = '';
  message('Senha atualizada.');
}

async function loadHolidays() {
  const { data, error } = await supabase.rpc('admin_list_holidays'); if (error) throw error;
  const rows = data.rows || [];
  $('holidays-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.holiday_date)}</td><td>${escapeHtml(row.description)}</td><td>${escapeHtml(row.type)}</td><td>${actionButtons([{ label: 'Excluir', action: 'delete-holiday', date: row.holiday_date }])}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">Nenhum feriado cadastrado.</td></tr>';
}

async function saveHoliday(event) { event.preventDefault(); const { error } = await supabase.rpc('admin_save_holiday', { p_date: $('holiday-date').value, p_description: $('holiday-description').value, p_type: $('holiday-type').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Feriado salvo.'); await loadHolidays(); }
async function deleteHoliday(date) { if (!confirm('Excluir este feriado?')) return; const { error } = await supabase.rpc('admin_delete_holiday', { p_date: date }); if (error) { message(error.message, true); return; } message('Feriado excluído.'); await loadHolidays(); }

async function loadProfiles() {
  const { data, error } = await supabase.rpc('admin_list_profiles'); if (error) throw error;
  const rows = data.rows || [];
  $('profiles-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.email)}</td><td>${escapeHtml(row.display_name || '-')}</td><td>${escapeHtml(row.role === 'admin' ? 'Administrador' : 'Operador')}</td><td><span class="badge${row.active ? '' : ' off'}">${row.active ? 'Ativo' : 'Inativo'}</span></td><td>${actionButtons([{ label: 'Remover', action: 'delete-profile', id: row.user_id }])}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhum acesso vinculado.</td></tr>';
}

async function signUpAccount(email, password) {
  const result = await request(`${window.ADMIN_CONFIG.SUPABASE_URL}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: window.ADMIN_CONFIG.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  if (result.error && !JSON.stringify(result.error).toLowerCase().includes('already registered')) return result.error;
  return null;
}

async function saveProfile(event) {
  event.preventDefault();
  const email = $('profile-email').value.trim();
  const password = $('profile-password').value;
  if (password) {
    const signupError = await signUpAccount(email, password);
    if (signupError) { message(signupError.msg || signupError.message || 'Não foi possível criar a conta.', true); return; }
  }
  const { error } = await supabase.rpc('admin_save_profile', { p_user_email: email, p_role: $('profile-role').value, p_display_name: $('profile-name').value.trim(), p_active: $('profile-active').checked });
  if (error) { message(error.message, true); return; }
  event.target.reset(); $('profile-active').checked = true;
  message(password ? 'Conta criada e acesso salvo.' : 'Acesso salvo.');
  await loadProfiles();
}
async function deleteProfile(userId) { if (!confirm('Remover este acesso?')) return; const { error } = await supabase.rpc('admin_delete_profile', { p_user_id: userId }); if (error) { message(error.message, true); return; } message('Acesso removido.'); await loadProfiles(); }

function printReport() { window.print(); }
function exportTable(tableId, filename) {
  const table = $(tableId);
  const rows = Array.from(table.querySelectorAll('tr')).map(tr => Array.from(tr.children).map(cell => {
    const text = (cell.textContent || '').trim().replace(/"/g, '""');
    return /["\n,;]/.test(text) ? `"${text}"` : text;
  }).join(';'));
  const blob = new Blob(['\ufeff' + rows.join('\n')], { type: 'text/csv;charset=utf-8' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  link.click();
  URL.revokeObjectURL(link.href);
}
async function showPage(page) { document.querySelectorAll('.nav').forEach(el => el.classList.toggle('active', el.dataset.page === page)); document.querySelectorAll('.page').forEach(el => el.classList.toggle('active', el.id === `${page}-page`)); $('page-title').textContent = pageTitles[page]; await loadPage(page); }

async function login() {
  const button = $('login-button');
  $('login-message').textContent = '';
  if (!$('email').value.trim() || !$('password').value) { $('login-message').textContent = 'Informe e-mail e senha.'; return; }
  button.disabled = true;
  try {
    const { error } = await supabase.auth.signInWithPassword({ email: $('email').value.trim(), password: $('password').value });
    if (error) { $('login-message').textContent = 'E-mail ou senha inválidos.'; return; }
    if (await requireAdmin()) await showPage('dashboard');
  } catch (error) {
    $('login-message').textContent = error.message || 'Não foi possível entrar. Tente novamente.';
  } finally {
    button.disabled = false;
  }
}
$('login-form').addEventListener('submit', event => { event.preventDefault(); login(); });
$('login-button').addEventListener('click', login);
$('logout').addEventListener('click', async () => { await supabase.auth.signOut(); $('app-view').hidden = true; $('login-view').hidden = false; $('password').value = ''; });
$('refresh').addEventListener('click', () => loadPage(document.querySelector('.nav.active').dataset.page).catch(error => message(error.message, true)));
document.querySelectorAll('.nav').forEach(button => button.addEventListener('click', () => showPage(button.dataset.page).catch(error => message(error.message, true))));
$('employee-form').addEventListener('submit', async event => { event.preventDefault(); const { error } = await supabase.rpc('admin_save_employee', { p_enrollment: $('employee-enrollment').value, p_name: $('employee-name').value, p_pin: $('employee-pin').value, p_department_id: $('employee-department').value || null, p_position_id: $('employee-position').value || null, p_schedule_id: $('employee-schedule').value || null }); if (error) { message(error.message, true); return; } event.target.reset(); message('Funcionário salvo.'); await loadEmployees(); });
$('geofence-form').addEventListener('submit', async event => { event.preventDefault(); const { error } = await supabase.rpc('admin_create_geofence', { p_name: $('geofence-name').value.trim(), p_latitude: $('geofence-latitude').value, p_longitude: $('geofence-longitude').value, p_radius_meters: $('geofence-radius').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Geocerca salva.'); await loadGeofences(); });
$('department-form').addEventListener('submit', saveDepartment);
$('position-form').addEventListener('submit', savePosition);
$('schedule-form').addEventListener('submit', saveSchedule);
$('espelho-run').addEventListener('click', runEspelho);
$('resumo-run').addEventListener('click', runResumo);
$('atrasos-run').addEventListener('click', runAtrasos);
$('faltas-run').addEventListener('click', runFaltas);
$('assiduidade-run').addEventListener('click', runAssiduidade);
$('fora-cerca-run').addEventListener('click', runForaCerca);
$('batidas-run').addEventListener('click', runBatidas);
$('manut-save').addEventListener('click', saveManualPunch);
$('manut-run').addEventListener('click', runManutencao);
$('holiday-form').addEventListener('submit', saveHoliday);
$('profile-form').addEventListener('submit', saveProfile);
$('absence-form').addEventListener('submit', saveAbsence);
$('occurrence-form').addEventListener('submit', saveOccurrence);
$('reason-form').addEventListener('submit', saveReason);
$('save-message').addEventListener('click', () => saveSetting('mensagem_funcionario', 'setting-message'));
$('save-parameters').addEventListener('click', () => { saveSetting('tolerancia_padrao', 'setting-tolerance'); saveSetting('email_alertas', 'setting-alert-email'); });
$('password-change').addEventListener('click', changePassword);
$('theme').addEventListener('click', toggleTheme);
$('login-theme').addEventListener('click', toggleTheme);

const reportButtons = [
  ['espelho-print', 'espelho-table', 'espelho'], ['espelho-csv', 'espelho-table', 'espelho'],
  ['resumo-print', 'resumo-table', 'resumo'], ['resumo-csv', 'resumo-table', 'resumo'],
  ['atrasos-print', 'atrasos-table', 'atrasos'], ['atrasos-csv', 'atrasos-table', 'atrasos'],
  ['faltas-print', 'faltas-table', 'faltas'], ['faltas-csv', 'faltas-table', 'faltas'],
  ['assiduidade-print', 'assiduidade-table', 'assiduidade'], ['assiduidade-csv', 'assiduidade-table', 'assiduidade'],
  ['fora-cerca-print', 'fora-cerca-table', 'fora-cerca'], ['fora-cerca-csv', 'fora-cerca-table', 'fora-cerca'],
  ['offline-print', 'offline-table', 'offline'], ['offline-csv', 'offline-table', 'offline'],
  ['batidas-print', 'batidas-table', 'batidas'], ['batidas-csv', 'batidas-table', 'batidas'],
  ['manut-print', 'manut-table', 'manutencao'], ['manut-csv', 'manut-table', 'manutencao']
];
reportButtons.forEach(([id, tableId, name]) => {
  $(id).addEventListener('click', () => {
    if (id.endsWith('-print')) printReport();
    else exportTable(tableId, `${name}-${new Date().toISOString().slice(0, 10)}.csv`);
  });
});

document.body.addEventListener('click', event => {
  const btn = event.target.closest('[data-action]');
  if (!btn || btn.disabled) return;
  const d = btn.dataset;
  const route = {
    'edit-department': () => editDepartment(d.id, d.name),
    'delete-department': () => deleteDepartment(d.id),
    'edit-position': () => editPosition(d.id, d.name),
    'delete-position': () => deletePosition(d.id),
    'edit-schedule': () => editSchedule(d.id),
    'delete-schedule': () => deleteSchedule(d.id),
    'toggle-employee': () => toggleEmployee(d.enrollment, d.active === 'true'),
    'edit-employee': () => editEmployee(d.enrollment),
    'clear-employee': () => clearEmployee(),
    'toggle-geofence': () => toggleGeofence(d.id, d.active === 'true'),
    'delete-geofence': () => deleteGeofence(d.id),
    'delete-holiday': () => deleteHoliday(d.date),
    'delete-profile': () => deleteProfile(d.id),
    'delete-punch': () => deletePunch(d.id),
    'edit-absence': () => editAbsence(d.id),
    'delete-absence': () => deleteAbsence(d.id),
    'clear-absence': () => clearAbsence(),
    'edit-occurrence': () => editOccurrence(d.id),
    'delete-occurrence': () => deleteOccurrence(d.id),
    'clear-occurrence': () => clearOccurrence(),
    'edit-reason': () => editReason(d.id),
    'delete-reason': () => deleteReason(d.id),
    'clear-reason': () => clearReason()
  };
  const handler = route[btn.dataset.action];
  if (handler) Promise.resolve(handler()).catch(error => message(error.message, true));
});

requireAdmin().then(isAdmin => {
  if (isAdmin) return showPage('dashboard');
  $('login-message').textContent = '';
}).catch(error => { $('login-message').textContent = error.message || 'Não foi possível iniciar o Admin.'; });
})();
