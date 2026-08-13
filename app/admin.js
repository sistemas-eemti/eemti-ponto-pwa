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
const pageTitles = { dashboard: 'Visão geral', employees: 'Funcionários', departments: 'Departamentos', positions: 'Cargos', schedules: 'Jornadas', geofences: 'Geocercas', espelho: 'Espelho de ponto', resumo: 'Resumo mensal', atrasos: 'Atrasos', faltas: 'Faltas', offline: 'Monitor offline' };

function message(text = '', error = false) { const el = $('app-message'); el.textContent = text; el.style.color = error ? 'var(--red)' : 'var(--green)'; }
function optionList(id, rows, label) { $(id).innerHTML = '<option value="">Nenhum</option>' + rows.map(row => `<option value="${row.id}">${escapeHtml(row[label])}</option>`).join(''); }
function escapeHtml(value) { const el = document.createElement('span'); el.textContent = value ?? ''; return el.innerHTML; }
function actionButtons(cells) { return cells.map(cell => `<button class="mini" type="button" onclick="${cell.fn}">${cell.label}</button>`).join(''); }
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
  $('recent-punches').innerHTML = data.recent.map(row => `<tr><td>${new Date(row.captured_at).toLocaleString('pt-BR')}</td><td>${escapeHtml(row.name || '-')} ${row.enrollment ? `<span class="muted">${escapeHtml(row.enrollment)}</span>` : ''}</td><td>${escapeHtml(row.origin)}</td><td>${row.inside_geofence === false ? '<span class="badge">Fora da cerca</span>' : 'Dentro / não verificado'}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">Nenhuma batida registrada.</td></tr>';
}

async function loadEmployees() {
  const [employees, options] = await Promise.all([supabase.rpc('admin_list_employees'), supabase.rpc('admin_employee_options')]);
  if (employees.error) throw employees.error; if (options.error) throw options.error;
  optionList('employee-department', options.data.departments, 'name'); optionList('employee-position', options.data.positions, 'name'); optionList('employee-schedule', options.data.schedules, 'name');
  $('employees-list').innerHTML = employees.data.map(row => `<tr><td>${escapeHtml(row.enrollment)}</td><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.department || '-')}</td><td><span class="badge">${row.active ? 'Ativo' : 'Inativo'}</span></td><td>${actionButtons([{ label: row.active ? 'Inativar' : 'Ativar', fn: `toggleEmployee('${escapeAttr(row.enrollment)}', ${!row.active})` }])}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhum funcionário cadastrado.</td></tr>';
}

async function loadDepartments() {
  const { data, error } = await supabase.rpc('admin_list_departments'); if (error) throw error;
  $('departments-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.employees || 0}</td><td>${actionButtons([{ label: 'Editar', fn: `editDepartment('${row.id}','${escapeAttr(row.name)}')` }, { label: 'Excluir', fn: `deleteDepartment('${row.id}')` }])}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">Nenhum departamento cadastrado.</td></tr>';
}

async function loadPositions() {
  const { data, error } = await supabase.rpc('admin_list_positions'); if (error) throw error;
  $('positions-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.employees || 0}</td><td>${actionButtons([{ label: 'Editar', fn: `editPosition('${row.id}','${escapeAttr(row.name)}')` }, { label: 'Excluir', fn: `deletePosition('${row.id}')` }])}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">Nenhum cargo cadastrado.</td></tr>';
}

async function loadSchedules() {
  const { data, error } = await supabase.rpc('admin_list_schedules'); if (error) throw error;
  $('schedules-list').dataset.rows = JSON.stringify(data);
  $('schedules-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.entry_time ? escapeHtml(timeOnly(row.entry_time)) : '-'}</td><td>${row.exit_time ? escapeHtml(timeOnly(row.exit_time)) : '-'}</td><td>${row.daily_minutes} min</td><td>${row.tolerance_minutes} min</td><td>${actionButtons([{ label: 'Editar', fn: `editSchedule('${row.id}')` }, { label: 'Excluir', fn: `deleteSchedule('${row.id}')` }])}</td></tr>`).join('') || '<tr><td colspan="6" class="muted">Nenhuma jornada cadastrada.</td></tr>';
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
  $('schedule-minutes').value = row.daily_minutes; $('schedule-tolerance').value = row.tolerance_minutes;
}

async function toggleEmployee(enrollment, active) {
  const { error } = await supabase.rpc('admin_set_employee_active', { p_enrollment: enrollment, p_active: active });
  if (error) { message(error.message, true); return; }
  message(active ? 'Funcionário ativado.' : 'Funcionário inativado.'); await loadEmployees();
}

async function saveDepartment(event) { event.preventDefault(); const { error } = await supabase.rpc('admin_save_department', { p_id: $('department-id').value || null, p_name: $('department-name').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Departamento salvo.'); await loadDepartments(); }
async function savePosition(event) { event.preventDefault(); const { error } = await supabase.rpc('admin_save_position', { p_id: $('position-id').value || null, p_name: $('position-name').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Cargo salvo.'); await loadPositions(); }
async function saveSchedule(event) { event.preventDefault(); const { error } = await supabase.rpc('admin_save_schedule', { p_id: $('schedule-id').value || null, p_name: $('schedule-name').value, p_entry_time: $('schedule-entry').value, p_exit_time: $('schedule-exit').value, p_daily_minutes: $('schedule-minutes').value, p_tolerance_minutes: $('schedule-tolerance').value }); if (error) { message(error.message, true); return; } event.target.reset(); message('Jornada salva.'); await loadSchedules(); }
async function deleteDepartment(id) { if (!confirm('Excluir este departamento?')) return; const { error } = await supabase.rpc('admin_delete_department', { p_id: id }); if (error) { message(error.message, true); return; } message('Departamento excluído.'); await loadDepartments(); }
async function deletePosition(id) { if (!confirm('Excluir este cargo?')) return; const { error } = await supabase.rpc('admin_delete_position', { p_id: id }); if (error) { message(error.message, true); return; } message('Cargo excluído.'); await loadPositions(); }
async function deleteSchedule(id) { if (!confirm('Excluir esta jornada?')) return; const { error } = await supabase.rpc('admin_delete_schedule', { p_id: id }); if (error) { message(error.message, true); return; } message('Jornada excluída.'); await loadSchedules(); }

async function loadGeofences() {
  const { data, error } = await supabase.rpc('admin_list_geofences'); if (error) throw error;
  $('geofences-list').innerHTML = data.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${row.latitude}, ${row.longitude}</td><td>${row.radius_meters} m</td><td><span class="badge">${row.active ? 'Ativa' : 'Inativa'}</span></td></tr>`).join('') || '<tr><td colspan="4" class="muted">Nenhuma geocerca cadastrada.</td></tr>';
}

async function loadPage(page) { message(); if (page === 'dashboard') await loadDashboard(); if (page === 'employees') await loadEmployees(); if (page === 'departments') await loadDepartments(); if (page === 'positions') await loadPositions(); if (page === 'schedules') await loadSchedules(); if (page === 'geofences') await loadGeofences(); if (page === 'espelho') await loadEspelho(); if (page === 'resumo') await loadResumo(); if (page === 'atrasos') await loadAtrasos(); if (page === 'faltas') await loadFaltas(); if (page === 'offline') await loadOffline(); }

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

async function runEspelho() {
  const { data, error } = await supabase.rpc('admin_espelho', { p_enrollment: $('espelho-employee').value, p_month: $('espelho-month').value + '-01' });
  if (error) { message(error.message, true); return; }
  const rows = data.rows || [];
  $('espelho-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.dia)}</td><td>${escapeHtml(row.entrada)}</td><td>${escapeHtml(row.saida || '-')}</td><td>${hours(row.minutos)}</td><td>${row.batidas}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Sem batidas no período.</td></tr>';
}

async function runResumo() {
  const { data, error } = await supabase.rpc('admin_resumo_mensal', { p_month: $('resumo-month').value + '-01' });
  if (error) { message(error.message, true); return; }
  const rows = data.rows || [];
  $('resumo-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.department || '-')}</td><td>${row.dias_trabalhados}</td><td>${row.faltas}</td><td>${row.atrasos}</td><td>${hours(row.minutos_trabalhados)}</td><td>${hours(row.minutos_esperados)}</td><td class="${row.saldo_minutos < 0 ? 'danger' : ''}">${hours(row.saldo_minutos)}</td></tr>`).join('') || '<tr><td colspan="8" class="muted">Sem funcionários ativos.</td></tr>';
}

async function runAtrasos() {
  const { data, error } = await supabase.rpc('admin_rel_atrasos', { p_start: $('atrasos-start').value, p_end: $('atrasos-end').value });
  if (error) { message(error.message, true); return; }
  const rows = data.rows || [];
  $('atrasos-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.previsto)}</td><td>${escapeHtml(row.dia)}</td><td>${escapeHtml(row.batida)}</td><td>${row.atraso_min} min</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhum atraso no período.</td></tr>';
}

async function runFaltas() {
  const { data, error } = await supabase.rpc('admin_rel_faltas', { p_start: $('faltas-start').value, p_end: $('faltas-end').value });
  if (error) { message(error.message, true); return; }
  const rows = data.rows || [];
  $('faltas-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.dia)}</td></tr>`).join('') || '<tr><td colspan="2" class="muted">Nenhuma falta no período.</td></tr>';
}

async function loadOffline() {
  const { data, error } = await supabase.rpc('admin_monitor_offline'); if (error) throw error;
  const rows = data.rows || [];
  $('offline-list').innerHTML = rows.map(row => `<tr><td>${escapeHtml(row.name)}</td><td>${escapeHtml(row.origin)}</td><td>${escapeHtml(shortDateTime(row.captured_at))}</td><td>${escapeHtml(shortDateTime(row.synced_at))}</td><td>${escapeHtml(row.client_record_id || '-')}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Nenhuma batida offline registrada.</td></tr>';
}

function hours(minutes) { const m = Math.abs(minutes || 0); return `${minutes < 0 ? '-' : ''}${String(Math.floor(m / 60)).padStart(2, '0')}:${String(Math.round(m % 60)).padStart(2, '0')}`; }
function shortDateTime(value) { if (!value) return '-'; return String(value).replace('T', ' ').slice(0, 16); }
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

requireAdmin().then(isAdmin => {
  if (isAdmin) return showPage('dashboard');
  $('login-message').textContent = 'Pronto para entrar.';
}).catch(error => { $('login-message').textContent = error.message || 'Não foi possível iniciar o Admin.'; });
})();
